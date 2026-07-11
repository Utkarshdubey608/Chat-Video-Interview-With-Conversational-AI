import { useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { MessageSquareText, Video } from 'lucide-react'
import { cn } from '@/components/ui'
import type { BrandingConfig, TrackType } from '@shared/types'

interface Props {
  branding: BrandingConfig
  defaultTrack: TrackType
  onChoose: (track: TrackType) => void
  busy?: boolean
}

const TRACKS: { id: TrackType; title: string; blurb: string; icon: typeof Video; tag?: string }[] = [
  { id: 'chat', title: 'Chat Interview', blurb: 'Answer each question by typing. Calm, focused, and fully keyboard-friendly.', icon: MessageSquareText },
  { id: 'video_avatar', title: 'Video Avatar', blurb: 'An AI avatar asks each question and you respond on camera.', icon: Video, tag: 'Preview' },
]

export function TrackSelect({ branding, defaultTrack, onChoose, busy }: Props) {
  const reduce = useReducedMotion()
  const [selected, setSelected] = useState<TrackType>(defaultTrack)

  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="text-center"
    >
      <span
        className="inline-flex rounded-full border px-3 py-1 text-xs font-semibold"
        style={{ color: branding.accentColor, borderColor: branding.accentColor + '55', background: branding.accentColor + '11' }}
      >
        {branding.companyName} Interview
      </span>
      <h1 className="mt-4 text-4xl font-bold tracking-tight text-neutral-900">Choose your format</h1>
      <p className="mx-auto mt-2 max-w-md text-neutral-500">
        Both formats ask the same questions and are timed identically. Pick whichever feels most comfortable.
      </p>

      <div className="mt-8 grid gap-4 sm:grid-cols-2">
        {TRACKS.map((t) => {
          const Icon = t.icon
          const active = selected === t.id
          return (
            <button
              key={t.id}
              onClick={() => setSelected(t.id)}
              aria-pressed={active}
              className={cn(
                'group relative rounded-2xl border-2 bg-white p-6 text-left transition-all duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2',
                active ? 'shadow-md' : 'border-border hover:border-neutral-300',
              )}
              style={active ? { borderColor: branding.accentColor } : undefined}
            >
              {t.tag && (
                <span className="absolute right-4 top-4 rounded-full bg-amber-50 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-amber-700">
                  {t.tag}
                </span>
              )}
              <span
                className="flex h-11 w-11 items-center justify-center rounded-xl text-white"
                style={{ background: active ? branding.accentColor : '#94a3b8' }}
              >
                <Icon size={20} />
              </span>
              <h3 className="mt-4 text-lg font-bold text-neutral-900">{t.title}</h3>
              <p className="mt-1 text-sm leading-relaxed text-neutral-500">{t.blurb}</p>
            </button>
          )
        })}
      </div>

      <button
        onClick={() => onChoose(selected)}
        disabled={busy}
        className="mt-8 inline-flex h-12 items-center justify-center rounded-lg px-8 text-base font-semibold text-white transition-all disabled:opacity-50"
        style={{ background: branding.accentColor }}
      >
        Continue
      </button>
    </motion.div>
  )
}
