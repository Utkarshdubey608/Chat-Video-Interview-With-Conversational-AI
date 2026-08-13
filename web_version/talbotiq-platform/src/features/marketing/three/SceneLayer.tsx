import { lazy, Suspense, useEffect, useRef, useState } from 'react'
import { detectTier, supportsWebgl } from '@/features/intro/tier'

const HeroScene = lazy(() => import('./HeroScene'))

/**
 * Capability gate for the marketing site's WebGL layer.
 *
 * The scene chunk (three.js + postprocessing, ~240 KB gzipped) is only ever
 * fetched when all of these hold:
 *   · the browser can actually create a WebGL context
 *   · the device is not a software renderer / low tier
 *   · the visitor has not asked for reduced motion
 *   · the host section is on screen
 *
 * Anything else leaves the section exactly as designed — the gradient band is a
 * finished piece of work on its own, not a placeholder waiting for 3D. The page
 * is 212 KB without this; nobody who cannot benefit from the scene pays for it.
 *
 * Scroll progress is written to a ref rather than React state — a re-render per
 * scroll frame is exactly the jank this is meant to avoid.
 */
export function SceneLayer() {
  const hostRef = useRef<HTMLDivElement>(null)
  const scrollRef = useRef(0)
  const [quality, setQuality] = useState<'high' | 'med' | null>(null)

  useEffect(() => {
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    if (reduced || !supportsWebgl()) return
    const tier = detectTier()
    if (tier === 'low') return

    // Only mount once the hero is actually in view.
    const host = hostRef.current
    if (!host) return
    const io = new IntersectionObserver(
      (entries) => { if (entries.some((e) => e.isIntersecting)) { setQuality(tier === 'high' ? 'high' : 'med'); io.disconnect() } },
      { rootMargin: '200px' },
    )
    io.observe(host)
    return () => io.disconnect()
  }, [])

  useEffect(() => {
    if (!quality) return
    let frame = 0
    const onScroll = () => {
      if (frame) return
      frame = requestAnimationFrame(() => {
        frame = 0
        const host = hostRef.current
        if (!host) return
        const r = host.getBoundingClientRect()
        const span = r.height + window.innerHeight
        scrollRef.current = Math.min(1, Math.max(0, (window.innerHeight - r.top) / span))
      })
    }
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => { window.removeEventListener('scroll', onScroll); if (frame) cancelAnimationFrame(frame) }
  }, [quality])

  return (
    <div ref={hostRef} className="mm-scene-layer" aria-hidden="true">
      {quality && (
        <Suspense fallback={null}>
          <HeroScene quality={quality} scrollRef={scrollRef} />
        </Suspense>
      )}
    </div>
  )
}
