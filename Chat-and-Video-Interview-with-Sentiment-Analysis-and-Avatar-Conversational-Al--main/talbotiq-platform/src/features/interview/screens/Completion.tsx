import { motion, useReducedMotion } from 'framer-motion'
import { CheckCircle2 } from 'lucide-react'
import type { BrandingConfig } from '@shared/types'

export function Completion({ branding }: { branding: BrandingConfig }) {
  const reduce = useReducedMotion()
  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, scale: 0.96 }}
      animate={{ opacity: 1, scale: 1 }}
      className="rounded-2xl border border-border bg-white p-10 text-center shadow-sm"
    >
      <span
        className="mx-auto flex h-16 w-16 items-center justify-center rounded-full"
        style={{ background: branding.accentColor + '14', color: branding.accentColor }}
      >
        <CheckCircle2 size={32} />
      </span>
      <h1 className="mt-5 text-3xl font-bold tracking-tight text-neutral-900">All done — thank you!</h1>
      <p className="mx-auto mt-3 max-w-md text-neutral-500">
        Your responses have been submitted to the {branding.companyName} team. There’s nothing more you
        need to do — you can safely close this window.
      </p>
      <p className="mt-6 text-xs text-neutral-400">
        Results are reviewed by the hiring team; scores aren’t shown to candidates.
      </p>
    </motion.div>
  )
}
