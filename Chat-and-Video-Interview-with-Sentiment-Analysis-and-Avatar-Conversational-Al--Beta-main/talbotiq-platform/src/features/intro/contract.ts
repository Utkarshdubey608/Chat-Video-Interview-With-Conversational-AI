import * as THREE from 'three'

/**
 * The animation contract for the MIMIC AI intro.
 *
 * Performance model (mirrors the reference cinematic in the CRM): GSAP tweens
 * plain mutable objects — `ScalarRef.value`, THREE.Vector3/Color fields — and a
 * single per-frame `useFrame` applies them to the camera / materials. Nothing
 * here is React state and nothing here is an R3F-owned object, so the whole film
 * plays at zero React re-renders.
 */

/** A single animatable scalar. GSAP mutates `.value`; the render loop reads it. */
export type ScalarRef = { value: number }

/** Convenience constructor for a {@link ScalarRef}. */
export const scalar = (value = 0): ScalarRef => ({ value })

/**
 * Camera proxy. The timeline tweens `position` / `lookAt` / `fov`; `CameraRig`
 * applies them each frame and layers a subtle handheld float + dutch on top.
 */
export type IntroCamProxy = {
  position: THREE.Vector3
  lookAt: THREE.Vector3
  fov: ScalarRef
  /** 0..1 handheld float / parallax intensity. */
  float: ScalarRef
  /** Dutch-roll, radians, applied after lookAt. */
  dutch: ScalarRef
}

/**
 * Post-processing proxy. `Effects` reads these every frame and writes them onto
 * the imperatively-constructed effect instances (no per-frame React work).
 */
export type IntroFxProxy = {
  /** Bloom intensity. */
  bloom: ScalarRef
  /** DOF focus distance in world units from the camera — drives the rack focus. */
  focusDistance: ScalarRef
  /** DOF bokeh scale (blur strength for out-of-focus regions). */
  bokeh: ScalarRef
  /** Chromatic-aberration offset (0 at rest; spikes on the resolve beat). */
  aberration: ScalarRef
}

/**
 * Scene-content proxy: the mutable signals every intro node reads to animate
 * itself. `world.time` is the film clock (scaled), consumed by idle drift.
 */
export type IntroRefs = {
  world: { time: ScalarRef; timeScale: ScalarRef }
  /** 0..1 rush progress — faces stream from far toward/past the camera. */
  rush: ScalarRef
  /** 0 = faces in the rush · 1 = faces have flown into the wordmark's letters. */
  morph: ScalarRef
  /** Overall face-card presence (opacity). Fades as the solid hero takes over. */
  cloud: ScalarRef
  /** 0..1 hero wordmark reveal — scale-in + material opacity/finish ramp. */
  heroReveal: ScalarRef
  /** Subtle emissive breathing on the hero once resolved. */
  heroGlow: ScalarRef
  /** 0..1 position of the sweeping key light across the wordmark (the light sweep). */
  lightSweep: ScalarRef
  /** 0..1 lens-flare intensity — spikes on the hit. */
  flare: ScalarRef
}

/**
 * The DOM-side bridge. The in-Canvas orchestrator calls these to drive the
 * React chrome that lives outside WebGL (tagline reveal, skip visibility, the
 * impact flash element, and the play-once handoff).
 */
export type IntroDomBridge = {
  /** The white flash overlay element, if mounted (nulled before/after). */
  flashEl: HTMLDivElement | null
  /** Fired as each named beat is reached. */
  onBeat: (beat: string) => void
  /** Fired once when the film completes (or is skipped to the end). */
  onDone: () => void
}

/** The DOM bridge plus the skip hook the orchestrator registers into. */
export type IntroBridge = IntroDomBridge & {
  registerSkip: (fn: () => void) => void
}
