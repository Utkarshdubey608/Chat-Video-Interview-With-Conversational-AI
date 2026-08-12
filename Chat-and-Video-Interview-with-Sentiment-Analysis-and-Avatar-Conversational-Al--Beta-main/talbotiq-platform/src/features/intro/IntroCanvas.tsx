import { Suspense, useMemo } from 'react'
import { Canvas, useFrame } from '@react-three/fiber'
import * as THREE from 'three'

import { CAMERA, COUNTS, DOF, PALETTE, POST, type IntroTier, type IntroConfig } from './constants'
import type { IntroBridge, ScalarRef } from './contract'
import { IntroExperience } from './IntroExperience'
import { createIntroState, type IntroState } from './state'
import type { FaceAtlas } from './lib/faceAtlas'
import { CameraRig } from './scene/CameraRig'
import { Effects } from './scene/Effects'
import { Floor } from './scene/Floor'
import { HeroWordmark } from './scene/HeroWordmark'
import { LensFlare } from './scene/LensFlare'
import { ReplicaMontage } from './scene/ReplicaMontage'
import { StudioEnvironment } from './scene/StudioEnvironment'

const MAX_DELTA = 1 / 30

type IntroCanvasProps = {
  bridge: IntroBridge
  tier: IntroTier
  config: Required<Pick<IntroConfig, 'tagline' | 'heroText' | 'heroMaterial' | 'accentColor'>> &
    Pick<IntroConfig, 'tileCount'>
  /** Packed real replica faces (null → face-free abstract shards). */
  atlas: FaceAtlas | null
  /** 'play' runs the film; 'preview' parks a static resolved hero shot. */
  mode?: 'play' | 'preview'
  onReady?: () => void
}

/**
 * The WebGL surface: an ACES-filmic, sRGB-managed <Canvas> that owns the shared
 * animation state and mounts the studio environment, floor, the real-face
 * montage, the hero wordmark, the lens flare + sweeping key light, the post
 * stack and the camera rig. `flat` disables the renderer's tone mapping so the
 * Effects composer can apply ACES after Bloom (HDR-correct).
 */
export function IntroCanvas({ bridge, tier, config, atlas, mode = 'play', onReady }: IntroCanvasProps) {
  const state = useMemo(() => createIntroState(), [])
  const dpr = COUNTS[tier].dpr
  const tileCount = config.tileCount ?? COUNTS[tier].tiles

  return (
    <Canvas
      flat
      shadows
      dpr={[1, dpr]}
      gl={{ antialias: true, powerPreference: 'high-performance', alpha: false, stencil: false }}
      camera={{ position: [...CAMERA.rush.position], fov: CAMERA.rush.fov, near: 0.1, far: 200 }}
      onCreated={() => onReady?.()}
    >
      <color attach="background" args={[PALETTE.void]} />
      <fog attach="fog" args={[PALETTE.void, 22, 70]} />

      <Suspense fallback={null}>
        <StudioEnvironment accentColor={config.accentColor} />
        <Floor tier={tier} />
        <ReplicaMontage
          state={state}
          tier={tier}
          tileCount={tileCount}
          heroText={config.heroText}
          accentColor={config.accentColor}
          atlas={atlas}
        />
        <HeroWordmark
          state={state}
          text={config.heroText}
          material={config.heroMaterial}
          accentColor={config.accentColor}
          tier={tier}
        />
        <LensFlare flare={state.refs.flare} accentColor={config.accentColor} />
      </Suspense>

      <SweepLight sweep={state.refs.lightSweep} accentColor={config.accentColor} />
      <CameraRig cam={state.cam} time={state.refs.world.time} />
      <Effects fx={state.fx} tier={tier} />

      {mode === 'preview' ? <PreviewDriver state={state} /> : <IntroExperience state={state} bridge={bridge} />}
    </Canvas>
  )
}

/** A warm key light that travels across the wordmark during the hit — its
 *  reflection is the "light sweep" on the polished metal. */
function SweepLight({ sweep, accentColor }: { sweep: ScalarRef; accentColor: string }) {
  const ref = useMemo(() => new THREE.SpotLight(new THREE.Color('#fff3d8'), 0, 60, 0.5, 1, 2), [])
  useFrame(() => {
    ref.position.set(-14 + sweep.value * 28, 5, 7)
    ref.target.position.set(0, 0.2, 0)
    ref.target.updateMatrixWorld()
    // Bright only mid-sweep so it reads as a pass, not a static light.
    const s = sweep.value
    ref.intensity = Math.sin(Math.min(Math.max(s, 0), 1) * Math.PI) * 900
    ref.color.set(s < 0.5 ? '#fff3d8' : accentColor)
  })
  return (
    <>
      <primitive object={ref} />
      <primitive object={ref.target} />
    </>
  )
}

/**
 * Temporary parked-pose driver (preview mode): frames the resolved hero shot
 * (camera at hero pose, faces assembled + faded, wordmark revealed, focus on the
 * letter plane) and breathes the glow, advancing the clock so float stays alive.
 */
function PreviewDriver({ state }: { state: IntroState }) {
  const { cam, fx, refs } = state

  useMemo(() => {
    cam.position.set(...CAMERA.hero.position)
    cam.lookAt.set(...CAMERA.hero.lookAt)
    cam.fov.value = CAMERA.hero.fov
    cam.float.value = 0.25
    fx.focusDistance.value = DOF.heroFocus
    fx.bokeh.value = DOF.heroBokeh
    fx.bloom.value = POST.bloomRest * 1.3
    refs.rush.value = 1
    refs.morph.value = 1
    refs.cloud.value = 0.16
    refs.heroReveal.value = 1
    refs.lightSweep.value = 0.55
    refs.flare.value = 0.12
  }, [cam, fx, refs])

  useFrame((_, delta) => {
    refs.world.time.value += Math.min(delta, MAX_DELTA)
    refs.heroGlow.value = 0.5 + 0.5 * Math.sin(refs.world.time.value * 0.9)
  })

  return null
}
