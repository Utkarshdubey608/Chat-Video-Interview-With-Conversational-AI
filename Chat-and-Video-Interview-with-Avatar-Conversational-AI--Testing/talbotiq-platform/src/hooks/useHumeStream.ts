import { useEffect, useRef, useCallback } from 'react'
import { humeService } from '@/services/hume'
import { audioStore } from '@/services/audioStore'
import { useAppStore } from '@/store/useAppStore'
import type { EviUserMessage, EviInboundMessage } from '@/types/hume.types'

export function useHumeStream(enabled: boolean) {
  const store = useAppStore()
  const wsRef = useRef<WebSocket | null>(null)
  const recorderRef = useRef<MediaRecorder | null>(null)
  const processorRef = useRef<ScriptProcessorNode | null>(null)
  const audioCtxRef = useRef<AudioContext | null>(null)
  const streamRef = useRef<MediaStream | null>(null)

  const stop = useCallback(() => {
    wsRef.current?.close()
    wsRef.current = null
    recorderRef.current?.stop()
    recorderRef.current = null
    processorRef.current?.disconnect()
    processorRef.current = null
    audioCtxRef.current?.close()
    audioCtxRef.current = null
    streamRef.current?.getTracks().forEach(t => t.stop())
    streamRef.current = null
    store.setHumeStreamActive(false)
  }, [store])

  useEffect(() => {
    if (!enabled || !store.humeKey) return

    let cancelled = false

    async function start() {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
        if (cancelled) { stream.getTracks().forEach(t => t.stop()); return }
        streamRef.current = stream

        // ── MediaRecorder (WebM blob for batch API) ────────────────────
        const recorder = new MediaRecorder(stream, { mimeType: 'audio/webm;codecs=opus' })
        recorderRef.current = recorder
        audioStore.reset()
        recorder.ondataavailable = (e) => { if (e.data.size > 0) audioStore.push(e.data) }
        recorder.start(1000)

        // ── AudioContext → PCM → EVI WebSocket ────────────────────────
        const audioCtx = new AudioContext({ sampleRate: 16000 })
        audioCtxRef.current = audioCtx
        const source = audioCtx.createMediaStreamSource(stream)
        const processor = audioCtx.createScriptProcessor(4096, 1, 1)
        processorRef.current = processor
        source.connect(processor)
        processor.connect(audioCtx.destination)

        const ws = new WebSocket(humeService.buildEviUrl())
        wsRef.current = ws

        ws.onopen = () => {
          if (cancelled) { ws.close(); return }
          ws.send(JSON.stringify({
            type: 'session_settings',
            audio: { encoding: 'linear16', sample_rate: 16000, channels: 1 },
          }))
          store.setHumeStreamActive(true)
        }

        ws.onmessage = (ev) => {
          try {
            const msg = JSON.parse(ev.data) as EviInboundMessage
            if (msg.type === 'user_message') {
              const um = msg as EviUserMessage
              const emotions = um.models?.prosody?.predictions?.[0]?.emotions ?? []
              if (emotions.length) {
                store.setLiveEmotions(emotions)
              }
            }
          } catch { /* ignore malformed frames */ }
        }

        ws.onerror = () => {
          // Graceful degradation — turn off stream flag so InterviewPage falls back to jitter
          store.setHumeStreamActive(false)
        }

        ws.onclose = () => {
          if (!cancelled) store.setHumeStreamActive(false)
        }

        // Pipe PCM chunks to WebSocket
        processor.onaudioprocess = (e) => {
          if (ws.readyState !== WebSocket.OPEN) return
          const pcm = e.inputBuffer.getChannelData(0)
          const buf = new Int16Array(pcm.length)
          for (let i = 0; i < pcm.length; i++) {
            buf[i] = Math.max(-32768, Math.min(32767, pcm[i] * 32768))
          }
          const b64 = btoa(String.fromCharCode(...new Uint8Array(buf.buffer)))
          ws.send(JSON.stringify({ type: 'audio_input', data: b64 }))
        }
      } catch (err) {
        console.warn('[HumeStream] mic/ws error:', err)
        store.setHumeStreamActive(false)
      }
    }

    start()

    return () => {
      cancelled = true
      stop()
    }
  }, [enabled, store.humeKey]) // eslint-disable-line react-hooks/exhaustive-deps

  return { stop }
}
