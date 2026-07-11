import { useEffect, useRef, useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { Camera, Mic, CheckCircle2, AlertTriangle } from 'lucide-react'
import type { BrandingConfig } from '@shared/types'

interface Props {
  branding: BrandingConfig
  onBegin: () => void
  busy?: boolean
}

/** Camera + mic permission and preview for the Video Avatar track. */
export function VideoSystemCheck({ branding, onBegin, busy }: Props) {
  const reduce = useReducedMotion()
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const [status, setStatus] = useState<'idle' | 'granted' | 'denied'>('idle')

  const request = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true })
      streamRef.current = stream
      if (videoRef.current) videoRef.current.srcObject = stream
      setStatus('granted')
    } catch {
      setStatus('denied')
    }
  }

  useEffect(() => {
    return () => streamRef.current?.getTracks().forEach((t) => t.stop())
  }, [])

  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="rounded-2xl border border-border bg-white p-8 shadow-sm"
    >
      <h1 className="text-2xl font-bold tracking-tight text-neutral-900">Camera &amp; microphone check</h1>
      <p className="mt-2 text-sm text-neutral-500">
        The AI avatar will ask each question aloud. We need access to your camera and mic to record your answers.
      </p>

      <div className="mt-6 aspect-video w-full overflow-hidden rounded-xl border border-border bg-neutral-900">
        <video ref={videoRef} autoPlay muted playsInline className="h-full w-full object-cover" />
      </div>

      {status === 'idle' && (
        <button
          onClick={request}
          className="mt-5 inline-flex h-11 w-full items-center justify-center gap-2 rounded-lg border-2 font-semibold transition-all"
          style={{ borderColor: branding.accentColor, color: branding.accentColor }}
        >
          <Camera size={18} /> Enable camera &amp; microphone
        </button>
      )}

      {status === 'denied' && (
        <div className="mt-5 flex items-start gap-2 rounded-lg border border-danger-border bg-danger-bg p-3 text-sm text-danger">
          <AlertTriangle size={16} className="mt-0.5 flex-shrink-0" />
          <span>Permission was blocked. Enable camera &amp; mic access in your browser, then retry.</span>
        </div>
      )}

      {status === 'granted' && (
        <div className="mt-5 flex items-center gap-4 text-sm font-medium text-success">
          <span className="flex items-center gap-1.5"><Camera size={15} /> Camera ready</span>
          <span className="flex items-center gap-1.5"><Mic size={15} /> Mic ready</span>
        </div>
      )}

      <button
        onClick={onBegin}
        disabled={status !== 'granted' || busy}
        className="mt-6 inline-flex h-12 w-full items-center justify-center gap-2 rounded-lg text-base font-semibold text-white transition-all disabled:cursor-not-allowed disabled:opacity-50"
        style={{ background: branding.accentColor }}
      >
        <CheckCircle2 size={18} /> I’m ready, begin
      </button>
    </motion.div>
  )
}
