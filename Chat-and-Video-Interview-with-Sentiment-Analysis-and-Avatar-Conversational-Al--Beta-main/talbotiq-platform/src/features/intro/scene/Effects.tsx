import { useRef, type Ref } from 'react'
import { useFrame } from '@react-three/fiber'
import { Bloom, DepthOfField, EffectComposer, Noise, SSAO, ToneMapping, Vignette } from '@react-three/postprocessing'
import { BlendFunction, type BloomEffect, type DepthOfFieldEffect, ToneMappingMode } from 'postprocessing'

import { DOF, POST, type IntroTier } from '../constants'
import type { IntroFxProxy } from '../contract'

/**
 * The filmic post stack — the second-biggest lever (after lighting) for the
 * "KeyShot" look. The renderer's own tone mapping is disabled upstream
 * (IntroCanvas mounts with `flat`), so HDR values (emissive glow, env
 * highlights) survive into Bloom; ACES filmic tone mapping is then applied
 * explicitly, then vignette + a whisper of film grain.
 *
 * Bloom + DOF are mutated every frame from the fx proxy with zero React
 * re-renders. DOF runs in *world-focus* mode, so the timeline's rack focus
 * (`fx.focusDistance` in world units) reads directly: the grid/cloud blurs
 * while the featured plane snaps sharp. SSAO + the normal pass are high-tier
 * only. (Chromatic aberration is intentionally omitted — even at zero offset it
 * fringed the crisp face cards.)
 */
export function Effects({ fx, tier }: { fx: IntroFxProxy; tier: IntroTier }) {
  // The postprocessing wrapper components type their `ref` as the effect
  // *constructor* rather than the instance (an upstream typing quirk); the
  // instance is what actually resolves at runtime, so we keep instance-typed
  // refs and cast only at the ref prop.
  const bloomRef = useRef<BloomEffect>(null)
  const dofRef = useRef<DepthOfFieldEffect>(null)

  useFrame(() => {
    const bloom = bloomRef.current
    if (bloom) bloom.intensity = fx.bloom.value

    const dof = dofRef.current
    if (dof) {
      dof.bokehScale = fx.bokeh.value
      dof.cocMaterial.worldFocusDistance = fx.focusDistance.value
    }
  })

  // EffectComposer types `children` strictly as JSX.Element[] (no falsy), so we
  // assemble the pass list imperatively to gate SSAO by tier.
  const passes: JSX.Element[] = []
  if (tier === 'high') {
    passes.push(
      <SSAO
        key="ssao"
        intensity={18}
        radius={0.12}
        luminanceInfluence={0.6}
        bias={0.03}
        worldDistanceThreshold={40}
        worldDistanceFalloff={8}
        worldProximityThreshold={6}
        worldProximityFalloff={2}
      />,
    )
  }
  passes.push(
    <DepthOfField
      key="dof"
      ref={dofRef}
      worldFocusDistance={DOF.rushFocus}
      worldFocusRange={tier === 'high' ? 15 : 18}
      bokehScale={DOF.rushBokeh}
    />,
    <Bloom
      key="bloom"
      ref={bloomRef as unknown as Ref<typeof BloomEffect>}
      mipmapBlur
      intensity={POST.bloomRest}
      luminanceThreshold={0.9}
      luminanceSmoothing={0.22}
      levels={tier === 'high' ? 7 : 5}
    />,
    <ToneMapping key="tone" mode={ToneMappingMode.ACES_FILMIC} />,
    <Vignette key="vig" offset={POST.vignette.offset} darkness={POST.vignette.darkness} eskil={false} />,
    <Noise key="noise" premultiply blendFunction={BlendFunction.SCREEN} opacity={POST.grain} />,
  )

  return (
    <EffectComposer multisampling={tier === 'high' ? 4 : 2} enableNormalPass={tier === 'high'}>
      {passes}
    </EffectComposer>
  )
}
