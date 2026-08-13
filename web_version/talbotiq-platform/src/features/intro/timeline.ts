import { gsap } from 'gsap'

import { BEATS, CAMERA, DOF, POST, type BeatLabel } from './constants'
import type { IntroDomBridge } from './contract'
import type { IntroState } from './state'

const LABELS: readonly BeatLabel[] = ['rush', 'converge', 'hit', 'tagline', 'settle']

export type IntroTimelineCtx = { state: IntroState; dom: IntroDomBridge }

/**
 * The single master timeline for the film. Created paused; the orchestrator
 * plays it. Every tween targets the shared mutable proxies (Vector3 fields /
 * ScalarRef.value) — never React state, never R3F-owned objects — so the rig
 * applies them per frame at zero re-render cost.
 *
 * rush (faces stream the camera) → converge (faces fly into the letters) →
 * hit (polished-metal wordmark slams in: light sweep + lens flare + bloom
 * spike) → tagline → settle → end.
 */
export function buildIntroTimeline({ state, dom }: IntroTimelineCtx): gsap.core.Timeline {
  const { cam, fx, refs } = state

  // --- Frame-zero state (also makes StrictMode rebuilds restart cleanly).
  cam.position.set(...CAMERA.rush.position)
  cam.lookAt.set(...CAMERA.rush.lookAt)
  cam.fov.value = CAMERA.rush.fov
  cam.float.value = 0
  cam.dutch.value = 0
  fx.bloom.value = POST.bloomRest
  fx.focusDistance.value = DOF.rushFocus
  fx.bokeh.value = DOF.rushBokeh
  fx.aberration.value = POST.aberrationRest
  refs.world.time.value = 0
  refs.world.timeScale.value = 1
  refs.rush.value = 0
  refs.morph.value = 0
  refs.cloud.value = 1
  refs.heroReveal.value = 0
  refs.heroGlow.value = 0
  refs.lightSweep.value = 0
  refs.flare.value = 0

  const tl = gsap.timeline({ paused: true })

  for (const label of LABELS) {
    tl.addLabel(label, BEATS[label])
    tl.call(() => dom.onBeat(label), undefined, BEATS[label])
  }

  // ---- [rush 0 → ~1.8] real faces rush in and SETTLE into the tidy grid wall,
  //      then hold ~0.4s (crisp, readable HD) before the converge.
  tl.to(refs.rush, { value: 1, duration: 1.85, ease: 'power2.out' }, BEATS.rush)
  tl.to(cam.float, { value: 0.4, duration: 1.4, ease: 'sine.out' }, BEATS.rush)
  tl.to(cam.position, { z: 15.5, duration: 2.2, ease: 'sine.inOut' }, BEATS.rush)

  // ---- [converge 2.2 → 3.8] faces fly into the letterforms; camera reframes; rack focus.
  tl.to(refs.morph, { value: 1, duration: 1.5, ease: 'power2.inOut' }, BEATS.converge)
  tl.to(
    cam.position,
    { x: CAMERA.hero.position[0], y: CAMERA.hero.position[1], z: CAMERA.hero.position[2], duration: 1.6, ease: 'power2.inOut' },
    BEATS.converge,
  )
  tl.to(
    cam.lookAt,
    { x: CAMERA.hero.lookAt[0], y: CAMERA.hero.lookAt[1], z: CAMERA.hero.lookAt[2], duration: 1.6, ease: 'power2.inOut' },
    BEATS.converge,
  )
  tl.to(cam.fov, { value: CAMERA.hero.fov, duration: 1.6, ease: 'power2.inOut' }, BEATS.converge)
  tl.to(cam.float, { value: 0.22, duration: 1.4, ease: 'sine.inOut' }, BEATS.converge)
  tl.to(fx.focusDistance, { value: DOF.heroFocus, duration: 1.2, ease: 'power2.inOut' }, BEATS.converge + 0.2)
  tl.to(fx.bokeh, { value: DOF.heroBokeh, duration: 1.2, ease: 'power2.inOut' }, BEATS.converge + 0.2)

  // ---- [hit 3.8 → 4.7] THE HIT: wordmark slams in, light sweep, lens flare, bloom spike.
  tl.to(refs.cloud, { value: 0.14, duration: 0.8, ease: 'power2.in' }, BEATS.hit - 0.25)
  tl.to(refs.heroReveal, { value: 1, duration: 0.7, ease: 'back.out(1.5)' }, BEATS.hit)
  tl.fromTo(refs.lightSweep, { value: 0 }, { value: 1, duration: 1.1, ease: 'power2.inOut' }, BEATS.hit)
  // Bloom + flare punch, then settle.
  tl.to(fx.bloom, { value: POST.bloomHit, duration: 0.18, ease: 'power2.out' }, BEATS.hit)
  tl.to(fx.bloom, { value: POST.bloomRest * 1.3, duration: 0.9, ease: 'power2.inOut' }, BEATS.hit + 0.18)
  tl.fromTo(refs.flare, { value: 0 }, { value: 1, duration: 0.16, ease: 'power2.out' }, BEATS.hit)
  tl.to(refs.flare, { value: 0.18, duration: 0.9, ease: 'power2.out' }, BEATS.hit + 0.16)
  tl.fromTo(fx.aberration, { value: POST.aberrationSpike }, { value: POST.aberrationRest, duration: 0.7, ease: 'power2.out' }, BEATS.hit)

  // ---- [tagline 4.7 → 5.7] tagline resolves (DOM); flare eases out.
  tl.to(refs.flare, { value: 0, duration: 0.8, ease: 'sine.out' }, BEATS.tagline)

  // ---- [settle 5.7 → 6.6] gentle settle, then hand off.
  tl.to(
    cam.position,
    { x: CAMERA.settle.position[0], y: CAMERA.settle.position[1], z: CAMERA.settle.position[2], duration: 0.9, ease: 'sine.inOut' },
    BEATS.settle,
  )
  tl.to(cam.fov, { value: CAMERA.settle.fov, duration: 0.9, ease: 'sine.inOut' }, BEATS.settle)
  tl.to(cam.float, { value: 0.14, duration: 0.9, ease: 'sine.inOut' }, BEATS.settle)

  tl.call(dom.onDone, undefined, BEATS.end)

  return tl
}
