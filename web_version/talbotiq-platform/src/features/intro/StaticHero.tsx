import { useEffect } from 'react'
import { motion, useReducedMotion } from 'framer-motion'

import { PALETTE, type IntroConfig } from './constants'

type StaticHeroProps = {
  config: Required<Pick<IntroConfig, 'tagline' | 'heroText' | 'accentColor'>>
  onDone: () => void
  /**
   * Optional pre-rendered cinematic (MP4/WebM). When supplied, constrained
   * devices get the full guaranteed-quality film as video instead of the CSS
   * hero. Produce it offline and drop it in public/intro/ — see the plan.
   */
  videoSrc?: string
  /** How long the static hero holds before handing off (ms). */
  holdMs?: number
}

/**
 * The no-WebGL / reduced-motion / low-power fallback: a premium lit wordmark +
 * tagline (or the pre-rendered video, if provided). No Canvas is ever mounted.
 * Holds briefly, then hands off to the app.
 */
export function StaticHero({ config, onDone, videoSrc, holdMs = 2600 }: StaticHeroProps) {
  const reduced = useReducedMotion()

  useEffect(() => {
    if (videoSrc) return // video drives onDone via onEnded
    const id = window.setTimeout(onDone, reduced ? Math.min(holdMs, 1800) : holdMs)
    return () => window.clearTimeout(id)
  }, [onDone, videoSrc, reduced, holdMs])

  if (videoSrc) {
    return (
      <div className="absolute inset-0 flex items-center justify-center bg-black">
        <video
          src={videoSrc}
          autoPlay
          muted
          playsInline
          onEnded={onDone}
          onError={onDone}
          className="h-full w-full object-cover"
        />
      </div>
    )
  }

  const ease = [0.22, 1, 0.36, 1] as const

  return (
    <div
      className="absolute inset-0 flex flex-col items-center justify-center overflow-hidden"
      style={{ background: `radial-gradient(120% 90% at 50% 42%, #14161a 0%, ${PALETTE.void} 62%)` }}
    >
      {/* Accent bloom behind the wordmark. */}
      <div
        aria-hidden
        className="pointer-events-none absolute left-1/2 top-[42%] h-[420px] w-[720px] max-w-[90vw] -translate-x-1/2 -translate-y-1/2 rounded-full opacity-40 blur-3xl"
        style={{ background: `radial-gradient(circle, ${config.accentColor}55 0%, transparent 68%)` }}
      />
      <motion.h1
        initial={{ opacity: 0, y: 18, filter: 'blur(12px)' }}
        animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
        transition={{ duration: reduced ? 0.4 : 1.0, ease }}
        className="relative px-6 text-center font-head font-extrabold tracking-tight"
        style={{
          fontSize: 'clamp(2.75rem, 12vw, 8rem)',
          lineHeight: 1,
          fontFamily: 'Syne, Inter, system-ui, sans-serif',
          backgroundImage: `linear-gradient(180deg, #ffffff 0%, ${config.accentColor} 58%, #b8860b 100%)`,
          WebkitBackgroundClip: 'text',
          backgroundClip: 'text',
          color: 'transparent',
          filter: `drop-shadow(0 6px 40px ${config.accentColor}66)`,
        }}
      >
        {config.heroText}
      </motion.h1>
      <motion.p
        initial={{ opacity: 0, y: 14 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: reduced ? 0.4 : 0.9, ease, delay: reduced ? 0.15 : 0.55 }}
        className="relative mt-6 px-6 text-center"
        style={{
          fontFamily: 'DM Sans, Inter, system-ui, sans-serif',
          color: '#c7ccd4',
          fontSize: 'clamp(0.9rem, 2.6vw, 1.35rem)',
          letterSpacing: '0.18em',
          textTransform: 'uppercase',
        }}
      >
        {config.tagline}
      </motion.p>
    </div>
  )
}
