import { useEffect, useRef, useState, useCallback } from 'react'
import toast from 'react-hot-toast'
import { humeService } from '@/services/hume'
import { audioStore } from '@/services/audioStore'
import { deepgramService, countFillers, calcWpm } from '@/services/deepgram'
import { createAudioCapture, type AudioCapture } from '@/services/audioCapture'
import { useAppStore } from '@/store/useAppStore'
import type { EviUserMessage, EviInboundMessage } from '@/types/hume.types'

// Safe base64 for Int16 PCM — avoids spread stack-overflow on large buffers
function pcmToBase64(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf)
  let binary = ''
  const len = bytes.byteLength
  for (let i = 0; i < len; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary)
}

/**
 * Single-mic unified audio analysis hook.
 *
 * Opens ONE getUserMedia stream (echoCancellation / noiseSuppression / autoGainControl OFF)
 * and routes it through an AudioWorklet ('pcm-processor') that runs on a dedicated audio
 * thread. Every Int16 PCM chunk fans out to:
 *  - Deepgram Nova-3 WebSocket (raw linear16 PCM) — real-time transcription
 *  - Hume EVI WebSocket (base64 PCM)              — real-time prosody emotions
 * A MediaRecorder on the same stream produces the WebM blob for the Hume batch job.
 *
 * Public contract is unchanged: { interimText, dgConnected, sealAndGetBlob }.
 */
export function useAudioAnalysis(enabled: boolean) {
  const store = useAppStore()
  const [interimText, setInterimText] = useState('')
  const [dgConnected, setDgConnected] = useState(false)

  // Refs — survive React re-renders
  const captureRef       = useRef<AudioCapture | null>(null)
  const dgWsRef          = useRef<WebSocket | null>(null)
  const eviWsRef         = useRef<WebSocket | null>(null)
  const totalFillersRef  = useRef(0)
  // Deepgram WebM chunks captured before the socket opens are buffered here so the
  // FIRST chunk (which carries the WebM/Opus header) is never lost — without it Deepgram
  // cannot decode the stream and returns no transcript.
  const dgQueueRef       = useRef<Blob[]>([])

  // Called by InterviewPage before navigating to Results.
  // Flushes the final MediaRecorder chunk and seals audioStore.
  const sealAndGetBlob = useCallback(async (): Promise<Blob | null> => {
    try {
      await captureRef.current?.flushRecording()
    } catch { /* fall through to seal whatever we have */ }
    audioStore.seal()
    return audioStore.blob
  }, [])

  useEffect(() => {
    if (!enabled) return

    // Prefer store keys; fall back to service keys (set by onRehydrateStorage from env vars)
    const humeKey = store.humeKey  || humeService.getKey()
    const dgKey   = store.deepgramKey || deepgramService.getKey()

    if (!humeKey && !dgKey) return

    let cancelled = false
    totalFillersRef.current = 0
    dgQueueRef.current = []

    async function start() {
      // ── Hume EVI WebSocket — real-time prosody emotions ────────────────
      if (humeKey) {
        humeService.setKey(humeKey)
        try {
          const eviWs = new WebSocket(humeService.buildEviUrl())
          eviWsRef.current = eviWs

          eviWs.onopen = () => {
            if (cancelled) { eviWs.close(); return }
            eviWs.send(JSON.stringify({
              type: 'session_settings',
              audio: { encoding: 'linear16', sample_rate: 16000, channels: 1 },
            }))
            store.setHumeStreamActive(true)
          }

          eviWs.onmessage = (ev) => {
            try {
              const msg = JSON.parse(ev.data) as EviInboundMessage
              if (msg.type === 'user_message') {
                const um = msg as EviUserMessage
                const emotions = um.models?.prosody?.predictions?.[0]?.emotions ?? []
                if (emotions.length) store.setLiveEmotions(emotions)
              }
            } catch { /* ignore malformed */ }
          }

          eviWs.onerror = () => store.setHumeStreamActive(false)
          eviWs.onclose = () => { if (!cancelled) store.setHumeStreamActive(false) }
        } catch (eviErr) {
          console.warn('[AudioAnalysis] EVI failed (batch recording still active):', eviErr)
        }
      }

      // ── Deepgram WebSocket — real-time transcription ─────────────────────
      if (dgKey) {
        deepgramService.setKey(dgKey)
        try {
          // Auth via Sec-WebSocket-Protocol subprotocol (Deepgram SDK approach)
          // — avoids browsers stripping ?token= query params.
          const dgWs = new WebSocket(deepgramService.buildWsUrl(), ['token', deepgramService.getTrimmedKey()])
          dgWs.binaryType = 'arraybuffer'
          dgWsRef.current = dgWs

          dgWs.onopen = () => {
            if (cancelled) { dgWs.close(); return }
            setDgConnected(true)
            store.setDeepgramConnected(true)
            // Flush buffered chunks IN ORDER — the first one carries the WebM header.
            const queued = dgQueueRef.current
            dgQueueRef.current = []
            for (const b of queued) {
              if (dgWs.readyState === WebSocket.OPEN) dgWs.send(b)
            }
            console.log(`[DG] WebSocket OPEN — flushed ${queued.length} buffered chunk(s)`)
            toast.success('Deepgram Nova-3 live — transcribing', { id: 'dg-live', duration: 3000 })
          }

          dgWs.onmessage = (ev) => {
            try {
              const msg = JSON.parse(ev.data)

              if (msg.type === 'Results') {
                const text = (msg.channel?.alternatives?.[0]?.transcript ?? '').trim()
                console.log(`[DG] Results — is_final=${msg.is_final} speech_final=${msg.speech_final} text="${text}"`)
                if (!text) return

                // Commit on ANY finalized segment (is_final), not only clean speech
                // endpoints (speech_final). With noiseSuppression off, ambient noise keeps
                // the VAD active so speech_final rarely fires — committing on is_final
                // guarantees every finalized utterance is recorded. Interim (is_final=false)
                // results just drive the live "typing" indicator.
                if (msg.is_final) {
                  // Finalized segment — commit to transcript store
                  setInterimText('')
                  const fillers = countFillers(text)
                  totalFillersRef.current += fillers

                  const entry = {
                    role: 'candidate' as const,
                    text,
                    timestamp: Date.now(),
                    questionIdx: useAppStore.getState().currentQuestionIdx,
                  }
                  store.pushTranscriptEntry(entry)
                  console.log(`[DG] ✓ committed transcript entry: "${text}"`)

                  const allEntries = [...useAppStore.getState().sessionTranscript, entry]
                  const wpm = calcWpm(allEntries)
                  const currentWpm = useAppStore.getState().metrics.wpm
                  store.updateMetrics({
                    wpm: wpm > 0 ? wpm : currentWpm,
                    fillers: totalFillersRef.current,
                  })
                } else {
                  // Interim or stable-but-incomplete — show as typing indicator
                  setInterimText(text)
                }
              }

              if (msg.type === 'UtteranceEnd') {
                setInterimText('')
              }
            } catch { /* ignore malformed */ }
          }

          let dgErrorShown = false
          dgWs.onerror = (e) => {
            console.error('[AudioAnalysis] Deepgram WS error:', e)
            setDgConnected(false)
            store.setDeepgramConnected(false)
            // Don't toast here — wait for onclose to get the exact code
          }
          dgWs.onclose = (ev) => {
            if (!cancelled) {
              setDgConnected(false)
              store.setDeepgramConnected(false)
              if (!dgErrorShown && ev.code !== 1000) {
                dgErrorShown = true
                const detail = ev.reason ? ` — ${ev.reason}` : ''
                const hint = ev.code === 1006
                  ? 'Deepgram auth failed — verify key in Settings'
                  : ev.code === 1008
                  ? 'Deepgram rejected key — invalid credentials'
                  : `Deepgram closed (${ev.code})${detail} — check key in Settings`
                console.warn('[AudioAnalysis] Deepgram WS closed:', ev.code, ev.reason)
                toast.error(hint, { id: 'dg-error', duration: 6000 })
              }
            }
          }
        } catch (dgErr) {
          console.error('[AudioAnalysis] Deepgram init failed:', dgErr)
          toast.error('Deepgram failed to initialise', { id: 'dg-init', duration: 4000 })
        }
      }

      // ── Single mic → AudioWorklet → fan-out to both sockets + batch recorder ──
      try {
        audioStore.reset()
        const capture = createAudioCapture({
          sampleRate: 16000,
          recorderTimeslice: 1000,
          deepgramTimeslice: 250,
          // Deepgram gets WebM/Opus chunks from a MediaRecorder (independent of the
          // AudioContext) — the reliable transport that works even if the worklet is
          // suspended. URL omits `encoding`, so Deepgram auto-detects the Opus container.
          onDeepgramChunk: (blob: Blob) => {
            const dg = dgWsRef.current
            if (dg && dg.readyState === WebSocket.OPEN) {
              dg.send(blob)
            } else {
              // Socket still connecting — buffer (preserves the header chunk).
              dgQueueRef.current.push(blob)
            }
          },
          // Hume EVI gets real-time base64 PCM from the AudioWorklet (best-effort).
          onPCMChunk: (chunk: ArrayBuffer) => {
            const evi = eviWsRef.current
            if (evi && evi.readyState === WebSocket.OPEN) {
              evi.send(JSON.stringify({ type: 'audio_input', data: pcmToBase64(chunk) }))
            }
          },
          onRecordingChunk: (blob: Blob) => { audioStore.push(blob) },
        })
        captureRef.current = capture
        await capture.start()
        if (cancelled) { capture.stop(); captureRef.current = null }
      } catch (err: any) {
        console.error('[AudioAnalysis] audio capture failed:', err)
        const msg = err?.name === 'NotAllowedError'
          ? 'Mic access denied — allow microphone to enable AI analysis'
          : 'Microphone unavailable — AI analysis disabled'
        toast.error(msg, { id: 'mic-error', duration: 6000 })
      }
    }

    start()

    return () => {
      cancelled = true
      setDgConnected(false)
      setInterimText('')
      store.setDeepgramConnected(false)
      store.setHumeStreamActive(false)

      captureRef.current?.stop()
      captureRef.current = null

      dgQueueRef.current = []
      dgWsRef.current?.close()
      dgWsRef.current = null
      eviWsRef.current?.close()
      eviWsRef.current = null
    }
  }, [enabled, store.humeKey, store.deepgramKey]) // eslint-disable-line react-hooks/exhaustive-deps

  return { interimText, dgConnected, sealAndGetBlob }
}
