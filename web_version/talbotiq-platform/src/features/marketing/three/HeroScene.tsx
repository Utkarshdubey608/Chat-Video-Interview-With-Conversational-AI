import { useMemo, useRef } from 'react'
import { Canvas, useFrame, useThree } from '@react-three/fiber'
import { EffectComposer, Bloom } from '@react-three/postprocessing'
import * as THREE from 'three'

/**
 * The marketing hero's WebGL layer — a slowly drifting field of interview
 * "cards" that the scroll position pushes through.
 *
 * Deliberately self-contained rather than reusing src/features/intro's canvas:
 * that scene is driven by a timeline bridge and a face atlas built for a
 * one-shot title sequence, and threading scroll progress through it would mean
 * changing a working piece of the product. This shares its visual language —
 * same violet palette, same studio-lit depth, same restraint — without touching it.
 *
 * Everything here is instanced (one draw call for the whole field) and the
 * canvas is capped at DPR 1.5, because a hero that costs a phone its frame rate
 * is not a premium hero.
 */

/**
 * Palette for a *saturated* ground.
 *
 * The first three attempts at this scene sat over a near-white page, where
 * violet at low opacity can only resolve to pink or mud — that is a fact about
 * the colour, not a tuning problem. On the brand gradient field these light
 * tints read as glow instead, which is what the palette was built for.
 */
const LILAC = new THREE.Color('#E4D8FB')
const MINT = new THREE.Color('#8FE3D0')
const WHITE = new THREE.Color('#FFFFFF')

type Quality = 'high' | 'med'

/** The card field. Instanced; colour lerps violet→magenta with depth, with a
 *  few mint cards seeded through it as the "scored" ones. */
/**
 * Soft-edged alpha mask, generated once on a 2D canvas.
 *
 * Without it the cards are hard-edged rectangles that read as paper cut-outs
 * pasted over the page. Feathering the edges turns the same geometry into
 * atmosphere — the thing that actually creates a sense of depth here.
 */
function useSoftMask() {
  return useMemo(() => {
    const s = 128
    const c = document.createElement('canvas')
    c.width = c.height = s
    const ctx = c.getContext('2d')!
    const g = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2)
    g.addColorStop(0, 'rgba(255,255,255,1)')
    g.addColorStop(0.55, 'rgba(255,255,255,0.85)')
    g.addColorStop(1, 'rgba(255,255,255,0)')
    ctx.fillStyle = g
    ctx.fillRect(0, 0, s, s)
    const tex = new THREE.CanvasTexture(c)
    tex.colorSpace = THREE.NoColorSpace
    return tex
  }, [])
}

function CardField({ count, scrollRef }: { count: number; scrollRef: React.MutableRefObject<number> }) {
  const mesh = useRef<THREE.InstancedMesh>(null)
  const dummy = useMemo(() => new THREE.Object3D(), [])
  const softMask = useSoftMask()

  const seeds = useMemo(() => {
    // Deterministic layout — no Math.random, so the scene is identical on every
    // load and across reloads. A hero that reshuffles looks accidental.
    //
    // The field is deliberately pushed right and back. The hero's composition
    // was already resolved — headline left, product frame right — so a scene
    // spread across the whole width does not add depth, it adds debris behind
    // the words. This sits in the margin the layout already had.
    const out: { x: number; y: number; z: number; rx: number; ry: number; drift: number; mint: boolean }[] = []
    for (let i = 0; i < count; i++) {
      const g = i * 0.6180339887498949 // golden-ratio stride → even, non-gridded spread
      const a = (g % 1) * Math.PI * 2
      const r = 2.4 + ((i * 0.37) % 1) * 5.2
      out.push({
        x: Math.cos(a) * r * 2.1,          // full width — this band has no side column to protect
        y: Math.sin(a) * r * 0.72,
        z: -6 - ((i * 0.813) % 1) * 20,
        rx: ((i * 0.271) % 1 - 0.5) * 0.35,
        ry: ((i * 0.611) % 1 - 0.5) * 0.7,
        drift: 0.12 + ((i * 0.145) % 1) * 0.24,  // slower — calm, not confetti
        mint: i % 9 === 0,
      })
    }
    return out
  }, [count])

  useFrame((state) => {
    const m = mesh.current
    if (!m) return
    const t = state.clock.elapsedTime
    const scroll = scrollRef.current // 0 → 1 across the hero

    for (let i = 0; i < seeds.length; i++) {
      const s = seeds[i]
      // Scroll pulls the field toward the camera and slightly apart.
      const z = s.z + scroll * 22
      const spread = 1 + scroll * 0.35
      dummy.position.set(s.x * spread, s.y * spread + Math.sin(t * s.drift + i) * 0.09, z)
      dummy.rotation.set(s.rx + Math.sin(t * 0.18 + i) * 0.05, s.ry + t * 0.03 * s.drift, 0)
      const near = THREE.MathUtils.clamp((z + 26) / 26, 0, 1)
      const sc = 0.9 + near * 1.5   // fewer, larger cards read as depth; many small ones read as noise
      dummy.scale.set(sc * 1.45, sc, 1)
      dummy.updateMatrix()
      m.setMatrixAt(i, dummy.matrix)

      // Unlit colour. A standard material lit by warm keys over a pale page
      // desaturates violet into brown — the first version of this scene looked
      // like mud. Basic material keeps the brand hue exactly as specified, and
      // depth is carried by scale and opacity instead of shading.
      // Near cards brighten toward white; a ninth of them are mint — the
      // "scored" ones, the same signal the product uses for a completed result.
      const c = s.mint ? MINT : LILAC.clone().lerp(WHITE, near * 0.7)
      m.setColorAt(i, c)
    }
    m.instanceMatrix.needsUpdate = true
    if (m.instanceColor) m.instanceColor.needsUpdate = true
  })

  return (
    <instancedMesh ref={mesh} args={[undefined, undefined, count]}>
      <planeGeometry args={[1, 0.68]} />
      {/* Additive over the gradient field: the cards add light rather than
          paint over it, so they glow instead of sitting on top as decals. */}
      <meshBasicMaterial
        alphaMap={softMask}
        side={THREE.DoubleSide}
        transparent
        opacity={0.5}
        blending={THREE.AdditiveBlending}
        depthWrite={false}
        toneMapped={false}
      />
    </instancedMesh>
  )
}

/** Camera easing. Scroll dollies in and tilts fractionally — no rolls, no
 *  swoops; the restraint is the point. */
function Rig({ scrollRef }: { scrollRef: React.MutableRefObject<number> }) {
  const { camera } = useThree()
  useFrame((_, delta) => {
    const s = scrollRef.current
    const targetZ = 15 - s * 4.5
    const targetY = 0.35 + s * 0.8
    const k = 1 - Math.pow(0.001, delta) // frame-rate-independent damping
    camera.position.z += (targetZ - camera.position.z) * k
    camera.position.y += (targetY - camera.position.y) * k
    camera.lookAt(0, 0, -6)
  })
  return null
}

export default function HeroScene({ quality, scrollRef }: { quality: Quality; scrollRef: React.MutableRefObject<number> }) {
  // Sparse on purpose. 150 cards read as confetti; ~40 large, slow, translucent
  // ones read as depth behind a page that already had a finished composition.
  const count = quality === 'high' ? 42 : 24
  return (
    <Canvas
      dpr={[1, quality === 'high' ? 1.5 : 1]}
      gl={{ antialias: quality === 'high', powerPreference: 'high-performance', alpha: true }}
      camera={{ position: [0, 0.35, 15], fov: 38 }}
      // The scene is decorative; the headline beside it carries the meaning.
      aria-hidden="true"
      style={{ pointerEvents: 'none' }}
      onCreated={({ gl }) => { gl.toneMapping = THREE.ACESFilmicToneMapping; gl.toneMappingExposure = 1.05 }}
    >
      {/* The cards are unlit, so the scene needs no light rig at all. */}
      <CardField count={count} scrollRef={scrollRef} />
      <Rig scrollRef={scrollRef} />
      {/* Bloom only, and gently. Vignette darkened the corners of a page whose
          ground is near-white, and the chromatic aberration read as a display
          fault rather than an effect — both removed. */}
      {quality === 'high' && (
        <EffectComposer enableNormalPass={false}>
          <Bloom intensity={0.28} luminanceThreshold={0.62} luminanceSmoothing={0.9} mipmapBlur />
        </EffectComposer>
      )}
    </Canvas>
  )
}
