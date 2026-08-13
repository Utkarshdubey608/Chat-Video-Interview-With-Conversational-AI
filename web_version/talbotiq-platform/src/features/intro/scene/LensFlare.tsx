import { useMemo, useRef } from 'react'
import { useFrame } from '@react-three/fiber'
import * as THREE from 'three'

import type { ScalarRef } from '../contract'

function radialTexture(): THREE.CanvasTexture {
  const c = document.createElement('canvas')
  c.width = c.height = 128
  const ctx = c.getContext('2d')!
  const g = ctx.createRadialGradient(64, 64, 0, 64, 64, 64)
  g.addColorStop(0, 'rgba(255,255,255,1)')
  g.addColorStop(0.12, 'rgba(255,255,255,0.7)')
  g.addColorStop(0.4, 'rgba(255,255,255,0.12)')
  g.addColorStop(1, 'rgba(255,255,255,0)')
  ctx.fillStyle = g
  ctx.fillRect(0, 0, 128, 128)
  const t = new THREE.CanvasTexture(c)
  t.colorSpace = THREE.SRGBColorSpace
  return t
}

function streakTexture(): THREE.CanvasTexture {
  const c = document.createElement('canvas')
  c.width = 512
  c.height = 16
  const ctx = c.getContext('2d')!
  const g = ctx.createLinearGradient(0, 0, 512, 0)
  g.addColorStop(0, 'rgba(255,255,255,0)')
  g.addColorStop(0.5, 'rgba(255,255,255,1)')
  g.addColorStop(1, 'rgba(255,255,255,0)')
  ctx.fillStyle = g
  ctx.fillRect(0, 0, 512, 16)
  const t = new THREE.CanvasTexture(c)
  t.colorSpace = THREE.SRGBColorSpace
  return t
}

/**
 * A tasteful anamorphic lens flare anchored at the wordmark, driven by
 * `flare` (0..1). A soft core glow + a wide horizontal streak + a couple of
 * ghost discs, all additive and drawn on top — the cinematic accent on the hit.
 */
export function LensFlare({
  flare,
  accentColor,
  position = [0, 0.45, 0.4],
}: {
  flare: ScalarRef
  accentColor: string
  position?: [number, number, number]
}) {
  const group = useRef<THREE.Group>(null)
  const mats = useRef<THREE.MeshBasicMaterial[]>([])
  const glow = useMemo(radialTexture, [])
  const streak = useMemo(streakTexture, [])
  const color = useMemo(() => new THREE.Color(accentColor), [accentColor])
  const warm = useMemo(() => new THREE.Color('#fff3d8'), [])

  const register = (m: THREE.MeshBasicMaterial | null) => {
    if (m && !mats.current.includes(m)) mats.current.push(m)
  }

  useFrame(() => {
    const f = flare.value
    const g = group.current
    if (!g) return
    g.visible = f > 0.001
    for (const m of mats.current) m.opacity = f * (m.userData.base ?? 1)
    const s = 0.8 + f * 0.5
    g.scale.set(s, s, s)
  })

  return (
    <group ref={group} position={position} visible={false} renderOrder={20}>
      {/* Core glow */}
      <mesh>
        <planeGeometry args={[2.8, 2.8]} />
        <meshBasicMaterial
          ref={(m) => { if (m) { m.userData.base = 0.85; register(m) } }}
          map={glow}
          color={warm}
          transparent
          opacity={0}
          blending={THREE.AdditiveBlending}
          depthWrite={false}
          depthTest={false}
          toneMapped={false}
        />
      </mesh>
      {/* Anamorphic horizontal streak */}
      <mesh>
        <planeGeometry args={[22, 0.7]} />
        <meshBasicMaterial
          ref={(m) => { if (m) { m.userData.base = 0.8; register(m) } }}
          map={streak}
          color={color}
          transparent
          opacity={0}
          blending={THREE.AdditiveBlending}
          depthWrite={false}
          depthTest={false}
          toneMapped={false}
        />
      </mesh>
      {/* Ghost discs along the axis */}
      <mesh position={[4, -0.35, 0]}>
        <planeGeometry args={[0.8, 0.8]} />
        <meshBasicMaterial
          ref={(m) => { if (m) { m.userData.base = 0.45; register(m) } }}
          map={glow}
          color={color}
          transparent
          opacity={0}
          blending={THREE.AdditiveBlending}
          depthWrite={false}
          depthTest={false}
          toneMapped={false}
        />
      </mesh>
      <mesh position={[-5.5, 0.5, 0]}>
        <planeGeometry args={[1.3, 1.3]} />
        <meshBasicMaterial
          ref={(m) => { if (m) { m.userData.base = 0.35; register(m) } }}
          map={glow}
          color={warm}
          transparent
          opacity={0}
          blending={THREE.AdditiveBlending}
          depthWrite={false}
          depthTest={false}
          toneMapped={false}
        />
      </mesh>
    </group>
  )
}
