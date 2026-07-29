import { ContactShadows, MeshReflectorMaterial } from '@react-three/drei'

import { LAYOUT, PALETTE, type IntroTier } from '../constants'

/**
 * Studio grounding: a large, faintly reflective seamless floor a little below
 * the wordmark, plus soft contact shadows so the hero feels planted rather than
 * floating. Reflections are strong enough to catch the key/rim highlights but
 * dim enough to stay a "black studio". Skipped on the low tier (mobile) where a
 * reflector pass is not worth the fill cost.
 */
export function Floor({ tier }: { tier: IntroTier }) {
  const y = -LAYOUT.letterHalfHeight - 1.4

  return (
    <group position={[0, y, 0]}>
      <ContactShadows
        position={[0, 0.01, 0]}
        opacity={0.55}
        scale={40}
        blur={2.6}
        far={12}
        resolution={tier === 'high' ? 1024 : 512}
        color="#000000"
      />
      {tier !== 'low' ? (
        <mesh rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
          <planeGeometry args={[120, 120]} />
          <MeshReflectorMaterial
            resolution={tier === 'high' ? 1024 : 512}
            mixBlur={1}
            mixStrength={2.2}
            blur={[400, 100]}
            mirror={0.5}
            depthScale={1.1}
            minDepthThreshold={0.4}
            maxDepthThreshold={1.2}
            roughness={0.85}
            metalness={0.35}
            color={PALETTE.floor}
          />
        </mesh>
      ) : (
        <mesh rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
          <planeGeometry args={[120, 120]} />
          <meshStandardMaterial color={PALETTE.floor} roughness={0.9} metalness={0.2} />
        </mesh>
      )}
    </group>
  )
}
