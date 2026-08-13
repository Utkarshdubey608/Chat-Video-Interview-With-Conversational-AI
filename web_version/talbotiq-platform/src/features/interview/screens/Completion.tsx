import { motion, useReducedMotion } from 'framer-motion'
import { Check, ShieldCheck } from 'lucide-react'
import type { BrandingConfig } from '@shared/types'

export function Completion({ branding }: { branding: BrandingConfig }) {
  const reduce = useReducedMotion()
  const accent = branding.accentColor

  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, scale: 0.98 }}
      animate={{ opacity: 1, scale: 1 }}
      className="rounded-3xl border border-border bg-white p-10 text-center shadow-lg sm:p-12"
    >
      {/* Accent tick plate — a solid disc seated in a faint accent halo. */}
      <span
        className="mx-auto flex h-20 w-20 items-center justify-center rounded-full"
        style={{ background: accent + '0F' }}
      >
        <span
          className="flex h-14 w-14 items-center justify-center rounded-full text-white"
          style={{ background: accent }}
        >
          <Check size={28} strokeWidth={3} />
        </span>
      </span>

      <h1 className="mt-6 font-display text-3xl font-extrabold tracking-[-0.03em] text-neutral-900">
        All done — thank you.
      </h1>
      <p className="mx-auto mt-3 max-w-md text-balance leading-relaxed text-neutral-500">
        Your responses have been submitted to the {branding.companyName} team. There’s nothing more you
        need to do — you can safely close this window.
      </p>

      <div className="mt-8 border-t border-border pt-5">
        <p className="mx-auto flex max-w-sm items-start justify-center gap-2 text-left text-xs leading-relaxed text-neutral-400">
          <ShieldCheck size={14} strokeWidth={1.75} className="mt-0.5 flex-shrink-0" />
          <span>Your answers are reviewed by the hiring team. Scores aren’t shown to candidates.</span>
        </p>
      </div>
    </motion.div>
  )
}
