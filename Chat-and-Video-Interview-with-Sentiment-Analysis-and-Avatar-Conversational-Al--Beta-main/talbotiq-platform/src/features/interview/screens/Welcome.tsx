import { motion, useReducedMotion } from 'framer-motion'
import { Clock, EyeOff, Lock, ArrowRight } from 'lucide-react'
import type { BrandingConfig, PublicTimingView } from '@shared/types'

interface Props {
  branding: BrandingConfig
  timing: PublicTimingView
  onContinue: () => void
}

export function Welcome({ branding, timing, onContinue }: Props) {
  const reduce = useReducedMotion()
  const rules = [
    { icon: Clock, text: `Each question gives you ${timing.prepSeconds}s to prepare, then ${Math.round(timing.answerSeconds / 60) || 1} min${timing.answerSeconds >= 120 ? 's' : ''} to answer.` },
    { icon: Lock, text: 'Your answer auto-submits when the timer ends — you cannot go back or edit earlier answers.' },
    { icon: EyeOff, text: 'Questions appear one at a time. Upcoming questions stay hidden until it’s their turn.' },
  ]

  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="rounded-2xl border border-border bg-white p-8 shadow-sm"
    >
      <span
        className="inline-flex rounded-full px-3 py-1 text-xs font-semibold"
        style={{ color: branding.accentColor, background: branding.accentColor + '11' }}
      >
        Welcome
      </span>
      <h1 className="mt-4 text-3xl font-bold tracking-tight text-neutral-900">
        {branding.welcomeMessage || `Welcome to your ${branding.companyName} interview.`}
      </h1>
      <p className="mt-3 text-neutral-500">Here’s how it works before you begin:</p>

      <ul className="mt-6 space-y-4">
        {rules.map((r, i) => {
          const Icon = r.icon
          return (
            <li key={i} className="flex items-start gap-3">
              <span
                className="mt-0.5 flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-lg"
                style={{ background: branding.accentColor + '14', color: branding.accentColor }}
              >
                <Icon size={16} />
              </span>
              <span className="text-sm leading-relaxed text-neutral-700">{r.text}</span>
            </li>
          )
        })}
      </ul>

      <button
        onClick={onContinue}
        className="mt-8 inline-flex h-12 w-full items-center justify-center gap-2 rounded-lg text-base font-semibold text-white transition-all sm:w-auto sm:px-8"
        style={{ background: branding.accentColor }}
      >
        Continue <ArrowRight size={18} />
      </button>
    </motion.div>
  )
}
