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
      className="rounded-3xl border border-border bg-white p-8 shadow-lg sm:p-10"
    >
      <span
        className="inline-flex items-center rounded-full border px-3 py-1 text-[11px] font-bold uppercase tracking-[0.08em]"
        style={{ color: branding.accentColor, borderColor: branding.accentColor + '33', background: branding.accentColor + '11' }}
      >
        Welcome
      </span>
      <h1 className="mt-5 font-display text-3xl font-extrabold tracking-[-0.03em] text-balance text-neutral-900">
        {branding.welcomeMessage || `Welcome to your ${branding.companyName} interview.`}
      </h1>
      <p className="mt-3 leading-relaxed text-neutral-500">Here’s how it works before you begin:</p>

      <ul className="mt-8 space-y-4">
        {rules.map((r, i) => {
          const Icon = r.icon
          return (
            <li key={i} className="flex items-start gap-3.5">
              <span
                className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-xl"
                style={{ background: branding.accentColor + '14', color: branding.accentColor }}
              >
                <Icon size={17} strokeWidth={1.75} />
              </span>
              <span className="pt-1 text-[15px] leading-relaxed text-neutral-700">{r.text}</span>
            </li>
          )
        })}
      </ul>

      <div className="mt-9 border-t border-border pt-7">
        <button
          onClick={onContinue}
          className="inline-flex h-12 w-full items-center justify-center gap-2 rounded-full px-8 text-base font-semibold text-white shadow-sm transition-all duration-150 hover:-translate-y-px hover:shadow-md active:translate-y-0 sm:w-auto"
          style={{ background: branding.accentColor }}
        >
          Continue <ArrowRight size={18} />
        </button>
        <p className="mt-3.5 text-xs leading-relaxed text-neutral-400">
          Nothing starts yet — you’ll get a final ready check before the first question.
        </p>
      </div>
    </motion.div>
  )
}
