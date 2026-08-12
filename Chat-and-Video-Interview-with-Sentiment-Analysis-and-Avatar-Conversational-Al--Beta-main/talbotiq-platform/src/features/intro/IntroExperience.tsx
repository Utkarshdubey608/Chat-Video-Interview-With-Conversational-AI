import { useEffect } from 'react'
import { useFrame } from '@react-three/fiber'

import { BEATS, SKIP_TWEEN, type BeatLabel } from './constants'
import type { IntroBridge } from './contract'
import type { IntroState } from './state'
import { buildIntroTimeline } from './timeline'

const MAX_DELTA = 1 / 30
const SCRUB_LABELS: readonly BeatLabel[] = ['rush', 'converge', 'hit', 'tagline', 'settle']

/** Reads ?introT=<seconds> once — a dev scrub for parking the playhead. */
function readScrubTime(): number | null {
  const raw = new URLSearchParams(window.location.search).get('introT')
  if (raw === null) return null
  const t = Number.parseFloat(raw)
  return Number.isFinite(t) ? Math.min(Math.max(t, 0), BEATS.end) : null
}

/**
 * The in-Canvas orchestrator: builds and plays the master timeline against the
 * shared proxies, advances the film clock (used by idle drift / handheld float)
 * and derives the hero's emissive breathing from its reveal. Registers the skip
 * hook (fast-forward to the handoff) and pauses with the tab.
 */
export function IntroExperience({ state, bridge }: { state: IntroState; bridge: IntroBridge }) {
  useEffect(() => {
    let skipped = false

    const tl = buildIntroTimeline({ state, dom: bridge })

    const scrub = readScrubTime()
    if (scrub !== null) {
      tl.pause(scrub)
      state.refs.world.time.value = scrub
      for (const label of SCRUB_LABELS) {
        if (BEATS[label] <= scrub) bridge.onBeat(label)
      }
      if (scrub >= BEATS.end - 0.05) bridge.onDone()
    } else {
      tl.play(0)
    }

    bridge.registerSkip(() => {
      if (skipped || scrub !== null) return
      skipped = true
      tl.tweenTo(BEATS.end, { duration: SKIP_TWEEN, ease: 'power2.inOut' })
    })

    const onVisibility = () => {
      if (skipped || scrub !== null) return
      if (document.hidden) tl.pause()
      else tl.play()
    }
    document.addEventListener('visibilitychange', onVisibility)

    return () => {
      document.removeEventListener('visibilitychange', onVisibility)
      tl.kill()
    }
  }, [state, bridge])

  useFrame((_, delta) => {
    const { refs } = state
    refs.world.time.value += Math.min(delta, MAX_DELTA) * refs.world.timeScale.value
    const t = refs.world.time.value
    refs.heroGlow.value = refs.heroReveal.value * (0.6 + 0.4 * Math.sin(t * 0.9))
  })

  return null
}
