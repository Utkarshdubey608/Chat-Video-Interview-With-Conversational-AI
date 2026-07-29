import { useRef } from 'react'
import { Center, MeshTransmissionMaterial, Text3D } from '@react-three/drei'
import { useFrame } from '@react-three/fiber'
import * as THREE from 'three'

import type { HeroMaterialPreset, IntroTier } from '../constants'
import type { IntroState } from '../state'

const FONT_URL = '/fonts/helvetiker_bold.typeface.json'

const lerp = (a: number, b: number, t: number) => a + (b - a) * t

type HeroWordmarkProps = {
  state: IntroState
  text: string
  material: HeroMaterialPreset
  accentColor: string
  tier: IntroTier
}

/**
 * The photoreal centerpiece: extruded 3D "MIMIC AI" that slams in on the hit
 * and catches the sweeping key light. Default is polished chrome (a warm
 * platinum PBR metal lit by the HDRI env, tinted by the brand accent) — the
 * finish that reads most like a Marvel/Fortune-500 title. glass / brushed-metal
 * / emissive are swappable. `heroReveal` scales it in with a weighty settle and
 * ramps opacity (and, for glass, transmission).
 */
export function HeroWordmark({ state, text, material, accentColor, tier }: HeroWordmarkProps) {
  const group = useRef<THREE.Group>(null)
  const matRef = useRef<THREE.MeshPhysicalMaterial | THREE.MeshStandardMaterial | null>(null)
  const { heroReveal, heroGlow } = state.refs

  useFrame(() => {
    const g = group.current
    if (!g) return
    const reveal = heroReveal.value
    g.visible = reveal > 0.001

    const s = lerp(0.86, 1, reveal)
    g.scale.set(s, s, s)

    const mat = matRef.current
    if (!mat) return
    mat.transparent = reveal < 0.999
    mat.opacity = reveal
    const phys = mat as THREE.MeshPhysicalMaterial
    if (material === 'glass' && 'transmission' in mat) {
      phys.transmission = lerp(0.05, 1, reveal)
      phys.thickness = lerp(0.2, 1.5, reveal)
    }
    mat.emissiveIntensity = lerp(1.6, 0.28, reveal) + heroGlow.value * 0.4
  })

  return (
    <group ref={group} position={[0, 0.15, 0]} visible={false}>
      <Center>
        <Text3D
          font={FONT_URL}
          size={2}
          height={0.55}
          curveSegments={tier === 'high' ? 14 : 8}
          bevelEnabled
          bevelThickness={0.08}
          bevelSize={0.05}
          bevelOffset={0}
          bevelSegments={tier === 'high' ? 6 : 3}
          letterSpacing={-0.06}
        >
          {text}
          <HeroMaterial preset={material} accentColor={accentColor} tier={tier} matRef={matRef} />
        </Text3D>
      </Center>
    </group>
  )
}

type HeroMaterialProps = {
  preset: HeroMaterialPreset
  accentColor: string
  tier: IntroTier
  matRef: React.MutableRefObject<THREE.MeshPhysicalMaterial | THREE.MeshStandardMaterial | null>
}

function HeroMaterial({ preset, accentColor, tier, matRef }: HeroMaterialProps) {
  const setStd = (m: THREE.MeshStandardMaterial | null) => {
    matRef.current = m
  }
  const setPhys = (m: THREE.MeshPhysicalMaterial | null) => {
    matRef.current = m
  }

  switch (preset) {
    case 'glass':
      return (
        <MeshTransmissionMaterial
          ref={setPhys}
          samples={tier === 'high' ? 8 : 4}
          resolution={tier === 'high' ? 1024 : 512}
          transmission={1}
          thickness={1.5}
          roughness={0.06}
          ior={1.42}
          chromaticAberration={0.05}
          anisotropicBlur={0.12}
          distortion={0.1}
          distortionScale={0.35}
          temporalDistortion={0.1}
          clearcoat={1}
          clearcoatRoughness={0.1}
          iridescence={0.5}
          iridescenceIOR={1.3}
          iridescenceThicknessRange={[100, 420]}
          attenuationColor={accentColor}
          attenuationDistance={2.4}
          emissive={accentColor}
          emissiveIntensity={0.5}
          envMapIntensity={1.5}
        />
      )
    case 'brushed-metal':
      return (
        <meshStandardMaterial
          ref={setStd}
          color="#c9ccd2"
          metalness={1}
          roughness={0.36}
          envMapIntensity={1.3}
          emissive={accentColor}
          emissiveIntensity={0.25}
        />
      )
    case 'emissive':
      return (
        <meshStandardMaterial
          ref={setStd}
          color="#0a0a0b"
          metalness={0.4}
          roughness={0.28}
          emissive={accentColor}
          emissiveIntensity={2.4}
          envMapIntensity={1.2}
        />
      )
    case 'chrome':
    default:
      return (
        <meshStandardMaterial
          ref={setStd}
          color="#efe6d2"
          metalness={1}
          roughness={0.13}
          envMapIntensity={1.9}
          emissive={accentColor}
          emissiveIntensity={0.18}
        />
      )
  }
}
