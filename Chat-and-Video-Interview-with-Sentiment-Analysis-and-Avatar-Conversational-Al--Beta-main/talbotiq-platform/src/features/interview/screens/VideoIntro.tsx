import { useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { Camera, Mic, ShieldCheck, CheckCircle2 } from 'lucide-react'
import type { BrandingConfig } from '@shared/types'

interface Props {
  branding: BrandingConfig
  onBegin: () => void
  busy?: boolean
}

/** "Before you begin" consent + device checklist, ported from the source's
 *  record.html gate. Enabling "Begin" requires acknowledging AI analysis. */
export function VideoIntro({ branding, onBegin, busy }: Props) {
  const reduce = useReducedMotion()
  const [consent, setConsent] = useState(false)
  const checks = [
    { icon: Camera, label: 'Camera on', hint: 'Your webcam records each answer. Close other apps using the camera (Zoom, Teams, Meet).' },
    { icon: Mic, label: 'Microphone on', hint: 'Speak clearly — your spoken answer is transcribed and scored.' },
    { icon: ShieldCheck, label: 'Quiet, well-lit space', hint: 'You get 30s to prepare, then up to 2 minutes to answer each question.' },
  ]
  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="rounded-2xl border border-border bg-white p-8 shadow-sm"
    >
      <h1 className="text-2xl font-bold tracking-tight text-neutral-900">Video interview — before you begin</h1>
      <p className="mt-2 text-sm text-neutral-500">You’ll answer each question on camera. Here’s how it works.</p>
      <ul className="mt-6 space-y-3">
        {checks.map((c, i) => {
          const Icon = c.icon
          return (
            <li key={i} className="flex items-start gap-3 rounded-xl border border-border bg-neutral-50 p-4">
              <span className="mt-0.5 flex h-9 w-9 items-center justify-center rounded-lg" style={{ background: branding.accentColor + '14', color: branding.accentColor }}>
                <Icon size={18} />
              </span>
              <div>
                <p className="text-sm font-semibold text-neutral-800">{c.label}</p>
                <p className="mt-0.5 text-xs text-neutral-500">{c.hint}</p>
              </div>
            </li>
          )
        })}
      </ul>
      <label className="mt-6 flex cursor-pointer items-start gap-3 rounded-xl border border-border p-4">
        <input type="checkbox" checked={consent} onChange={(e) => setConsent(e.target.checked)}
          className="mt-0.5 h-4 w-4 rounded border-neutral-300" style={{ accentColor: branding.accentColor }} />
        <span className="text-sm font-medium text-neutral-700">
          I understand my responses are recorded and analysed by AI, and reviewed by a human recruiter.
        </span>
      </label>
      <button
        onClick={onBegin}
        disabled={!consent || busy}
        className="mt-6 inline-flex h-12 w-full items-center justify-center gap-2 rounded-lg text-base font-semibold text-white transition-all disabled:cursor-not-allowed disabled:opacity-50"
        style={{ background: branding.accentColor }}
      >
        <CheckCircle2 size={18} /> I consent — begin
      </button>
    </motion.div>
  )
}
