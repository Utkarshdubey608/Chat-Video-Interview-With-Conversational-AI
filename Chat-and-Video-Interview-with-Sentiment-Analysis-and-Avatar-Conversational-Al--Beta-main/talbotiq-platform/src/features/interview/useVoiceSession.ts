import { useCallback, useEffect, useRef, useState } from 'react'
import { VoiceClient } from '@/lib/voiceClient'
import type { VoicePhase, VoiceCaption, TimeOfDay } from '@shared/types'

const localTimeOfDay = (): TimeOfDay => {
  const h = new Date().getHours()
  return h < 12 ? 'morning' : h < 18 ? 'afternoon' : 'evening'
}

/**
 * Drives a live voice interview: mic permission → WS to the backend relay →
 * Gemini Live audio round-trip. Exposes the call phase, live captions, and
 * mute/end controls. NB: there is deliberately no forced "Thinking…" delay —
 * voice is tuned for low latency; the phase is just an on-screen affordance.
 */
export function useVoiceSession(sessionId: string) {
  const [serverPhase, setServerPhase] = useState<VoicePhase>('connecting')
  const [audioPlaying, setAudioPlaying] = useState(false)
  const [captions, setCaptions] = useState<VoiceCaption[]>([])
  const [muted, setMuted] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [permissionDenied, setPermissionDenied] = useState(false)
  const [reconnecting, setReconnecting] = useState(false) // socket dropped, transparently retrying
  const [endedGraceful, setEndedGraceful] = useState(true) // false ⇒ interrupted, not a real finish
  const clientRef = useRef<VoiceClient | null>(null)
  const startedRef = useRef(false)
  const everSpokeRef = useRef(false) // agent audio has been audible at least once

  const start = useCallback(async () => {
    if (startedRef.current) return
    startedRef.current = true
    setError(null)
    const client = new VoiceClient(sessionId, {
      onPhase: setServerPhase,
      onAudioPlaying: (p) => { if (p) everSpokeRef.current = true; setAudioPlaying(p) },
      onCaption: (role, text, final) =>
        setCaptions((prev) => {
          // Update this speaker's most recent non-final line IN PLACE (streaming
          // partials and their final flush), so interleaved turns — e.g. an answer
          // finalizing after the next question started streaming — never duplicate
          // or reorder lines.
          for (let i = prev.length - 1; i >= 0; i--) {
            if (prev[i].role === role && !prev[i].final) {
              const next = [...prev]
              next[i] = { role, text, final }
              return next
            }
          }
          return [...prev, { role, text, final }]
        }),
      onReconnecting: (active) => setReconnecting(active),
      onEnded: (_reason, graceful) => { setReconnecting(false); setEndedGraceful(graceful !== false); setServerPhase('ended') },
      onError: (m) => setError(m),
    })
    clientRef.current = client
    try {
      await client.start(localTimeOfDay())
    } catch (e) {
      startedRef.current = false
      const err = e as DOMException
      if (err?.name === 'NotAllowedError' || err?.name === 'SecurityError') {
        setPermissionDenied(true)
        setError('Microphone access is required for a voice interview.')
      } else {
        setError(err?.message || 'Could not start the microphone.')
      }
      setServerPhase('error')
    }
  }, [sessionId])

  const toggleMute = useCallback(() => {
    setMuted((m) => { const next = !m; clientRef.current?.setMuted(next); return next })
  }, [])

  const end = useCallback(() => {
    clientRef.current?.end()
    setServerPhase('ended')
  }, [])

  // On unmount, tear down the mic/socket WITHOUT finalizing — only the explicit
  // End button (or the server's own wrap-up) ends the interview.
  useEffect(() => () => { clientRef.current?.dispose() }, [])

  // Ear-accurate phase: "speaking" only while agent audio is actually audible
  // (server phases lead local playback by the buffered duration). The moment the
  // audio drains, it's the candidate's turn — show "listening", never a stale
  // "speaking"/"one moment" that reads as lag.
  const phase: VoicePhase =
    serverPhase === 'connecting' || serverPhase === 'ended' || serverPhase === 'error'
      ? serverPhase
      : audioPlaying
        ? 'speaking'
        : serverPhase === 'greeting' && !everSpokeRef.current
          ? 'thinking' // greeting is still being generated — nothing audible yet
          : serverPhase === 'speaking' || serverPhase === 'greeting'
            ? 'listening'
            : serverPhase

  return { phase, captions, muted, error, permissionDenied, reconnecting, endedGraceful, start, toggleMute, end }
}
