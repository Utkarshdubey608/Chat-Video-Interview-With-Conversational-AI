import { useEffect, useRef, useState } from 'react'
import { Circle, Video } from 'lucide-react'

interface Props {
  active: boolean // true during the answer phase
  accentColor: string
}

/**
 * Video Avatar track — SCAFFOLD.
 *
 * Reuses the shared timing engine (prep/answer/auto-submit) and the same
 * submit/advance pipeline as the chat track. Recording is captured locally
 * via MediaRecorder; the avatar voice and upload are intentionally stubbed.
 *
 * TODO(video-avatar):
 *   - Speak the question via avatar TTS when the prep phase opens. This can
 *     plug into the repo's existing Tavus integration (src/services/tavus.ts)
 *     instead of a placeholder.
 *   - Upload the recorded Blob to storage and pass the resulting URL into the
 *     submit-answer call (SubmitAnswerRequest.videoUrl) so the recruiter view
 *     can play it back.
 */
export function CameraRecorder({ active, accentColor }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const recorderRef = useRef<MediaRecorder | null>(null)
  const chunks = useRef<Blob[]>([])
  const [recording, setRecording] = useState(false)

  // Live preview for the whole stage.
  useEffect(() => {
    let cancelled = false
    navigator.mediaDevices
      .getUserMedia({ video: true, audio: true })
      .then((stream) => {
        if (cancelled) { stream.getTracks().forEach((t) => t.stop()); return }
        streamRef.current = stream
        if (videoRef.current) videoRef.current.srcObject = stream
      })
      .catch(() => {})
    return () => {
      cancelled = true
      streamRef.current?.getTracks().forEach((t) => t.stop())
    }
  }, [])

  // Record only during the answer phase.
  useEffect(() => {
    const stream = streamRef.current
    if (!stream) return
    if (active && !recorderRef.current) {
      try {
        const rec = new MediaRecorder(stream)
        chunks.current = []
        rec.ondataavailable = (e) => e.data.size && chunks.current.push(e.data)
        rec.start()
        recorderRef.current = rec
        setRecording(true)
      } catch {
        /* recording unsupported — scaffold continues without it */
      }
    }
    if (!active && recorderRef.current) {
      recorderRef.current.stop()
      recorderRef.current = null
      setRecording(false)
      // TODO(video-avatar): upload Blob(chunks) and attach the URL on submit.
    }
  }, [active])

  return (
    <div className="relative aspect-video w-full overflow-hidden rounded-xl border border-border bg-neutral-900">
      <video ref={videoRef} autoPlay muted playsInline className="h-full w-full object-cover" />
      {recording ? (
        <span className="absolute left-3 top-3 flex items-center gap-1.5 rounded-full bg-black/60 px-2.5 py-1 text-[11px] font-bold uppercase tracking-wider text-white">
          <Circle size={9} className="animate-pulse fill-red-500 text-red-500" /> Rec
        </span>
      ) : (
        <span className="absolute left-3 top-3 flex items-center gap-1.5 rounded-full bg-black/50 px-2.5 py-1 text-[11px] font-medium text-white/80">
          <Video size={12} /> Preview
        </span>
      )}
      {!active && (
        <div className="absolute inset-0 flex items-center justify-center bg-black/40 text-center text-sm text-white/90">
          <span className="max-w-xs px-4">
            The avatar will ask the question during preparation. Recording starts automatically when the
            answer timer begins.
          </span>
        </div>
      )}
      <span className="absolute bottom-2 right-3 text-[10px] text-white/40" style={{ color: accentColor }}>
        scaffold
      </span>
    </div>
  )
}
