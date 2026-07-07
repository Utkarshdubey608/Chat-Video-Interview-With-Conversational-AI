import { useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { Wifi, Volume2, ShieldCheck, CheckCircle2 } from 'lucide-react'
import type { BrandingConfig, TrackType } from '@shared/types'
import { VideoSystemCheck } from './VideoSystemCheck'

interface Props {
  branding: BrandingConfig
  track: TrackType
  onBegin: () => void
  busy?: boolean
}

export function SystemCheck({ branding, track, onBegin, busy }: Props) {
  const reduce = useReducedMotion()
  const [ready, setReady] = useState(false)

  if (track === 'video_avatar') {
    return <VideoSystemCheck branding={branding} onBegin={onBegin} busy={busy} />
  }

  const checks = [
    { icon: Wifi, label: 'Stable internet connection', hint: 'A dropped connection won’t lose your progress, but a steady one is best.' },
    { icon: Volume2, label: 'Quiet, distraction-free space', hint: 'You won’t be able to pause once a question begins.' },
    { icon: ShieldCheck, label: 'Ready to focus', hint: 'Set aside enough uninterrupted time to finish in one sitting.' },
  ]

  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="rounded-2xl border border-border bg-white p-8 shadow-sm"
    >
      <h1 className="text-2xl font-bold tracking-tight text-neutral-900">Quick system check</h1>
      <p className="mt-2 text-sm text-neutral-500">Make sure you’re set up before you start.</p>

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

      <label className="mt-6 flex cursor-pointer items-center gap-3 rounded-xl border border-border p-4">
        <input
          type="checkbox"
          checked={ready}
          onChange={(e) => setReady(e.target.checked)}
          className="h-4 w-4 rounded border-neutral-300"
          style={{ accentColor: branding.accentColor }}
        />
        <span className="text-sm font-medium text-neutral-700">
          I understand the rules and I’m ready to begin.
        </span>
      </label>

      <button
        onClick={onBegin}
        disabled={!ready || busy}
        className="mt-6 inline-flex h-12 w-full items-center justify-center gap-2 rounded-lg text-base font-semibold text-white transition-all disabled:cursor-not-allowed disabled:opacity-50"
        style={{ background: branding.accentColor }}
      >
        <CheckCircle2 size={18} /> I’m ready, begin
      </button>
    </motion.div>
  )
}
