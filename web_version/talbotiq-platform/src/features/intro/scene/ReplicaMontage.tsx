import { useEffect, useMemo } from 'react'
import { useFrame } from '@react-three/fiber'
import * as THREE from 'three'

import { LAYOUT, type IntroTier } from '../constants'
import type { IntroState } from '../state'
import type { FaceAtlas } from '../lib/faceAtlas'
import { sampleText } from '../lib/textSample'

const VERT = /* glsl */ `
  attribute vec3 aLane;
  attribute vec3 aGrid;
  attribute vec3 aTarget;
  attribute float aSeed;
  attribute vec2 aCell;
  attribute float aScale;
  uniform float uRush;
  uniform float uMorph;
  uniform float uCellUv;
  varying vec2 vAtlasUv;
  varying vec2 vCardUv;
  void main() {
    // Rush IN: from a deep-field scatter, decelerating into a tidy grid wall.
    float rushE = smoothstep(0.0, 1.0, uRush);
    vec3 rushPos = mix(aLane, aGrid, rushE);

    // Converge: per-card staggered flight from the grid into the letterforms.
    float mLocal = clamp((uMorph - aSeed * 0.35) / 0.65, 0.0, 1.0);
    mLocal = mLocal * mLocal * (3.0 - 2.0 * mLocal);
    vec3 pos = mix(rushPos, aTarget, mLocal);

    // Flat, front-facing (screen-aligned) card — no tilt/foreshortening.
    vec4 mv = modelViewMatrix * vec4(pos, 1.0);
    float sc = aScale * mix(1.0, 0.42, mLocal);

    // Gentle radial motion cue ONLY while a card is still flying in; it fully
    // eases off once it settles into the grid, so the HD face stays crisp.
    float speed = (1.0 - rushE) * (1.0 - mLocal) * 0.45;
    vec2 dir = length(mv.xy) > 0.0001 ? normalize(mv.xy) : vec2(0.0, 1.0);
    vec2 q = position.xy;
    q += dir * dot(q, dir) * speed;
    mv.xy += q * sc;

    gl_Position = projectionMatrix * mv;
    vAtlasUv = vec2((aCell.x + uv.x), (aCell.y + 1.0 - uv.y)) * uCellUv;
    vCardUv = uv;
  }
`

const FRAG = /* glsl */ `
  uniform sampler2D uAtlas;
  uniform float uHasAtlas;
  uniform float uCloud;
  uniform float uAspect;
  uniform vec3 uAccent;
  varying vec2 vAtlasUv;
  varying vec2 vCardUv;
  void main() {
    // Rounded-rect frame via SDF (aspect-corrected so corners are even).
    vec2 p = (vCardUv - 0.5);
    p.x *= uAspect;
    vec2 halfe = vec2(0.5 * uAspect, 0.5);
    float radius = 0.075;
    float margin = 0.045;
    vec2 d = abs(p) - (halfe - margin - radius);
    float sdf = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;

    float aa = 0.006;
    float faceMask = 1.0 - smoothstep(-aa, aa, sdf);          // inside the frame
    float ring = 1.0 - smoothstep(0.0, 0.022, abs(sdf));       // border band
    float shadow = (1.0 - smoothstep(0.0, 0.11, max(sdf, 0.0))) * (1.0 - faceMask);

    vec3 faceCol;
    if (uHasAtlas > 0.5) {
      faceCol = texture2D(uAtlas, vAtlasUv).rgb;
    } else {
      float r = length(vCardUv - 0.5);
      faceCol = uAccent * clamp(1.25 - r * 1.7, 0.0, 1.4);
    }
    // Crisp premium border (soft warm → accent), kept subtle so bloom doesn't halo it.
    vec3 borderCol = mix(vec3(0.82), uAccent, 0.5);
    vec3 col = mix(faceCol, borderCol, ring * 0.4);

    float alpha = (faceMask + shadow * 0.5) * uCloud;
    if (alpha < 0.01) discard;
    // Shadow region is black (a soft drop shadow); face region shows the card.
    gl_FragColor = vec4(col * faceMask, alpha);
  }
`

type ReplicaMontageProps = {
  state: IntroState
  tier: IntroTier
  tileCount: number
  heroText: string
  accentColor: string
  atlas: FaceAtlas | null
}

/**
 * The flip-through: REAL replica faces (one InstancedBufferGeometry → one draw
 * call, textured from the cached-face atlas) rush in from deep space and settle
 * into a tidy, FRONT-FACING grid of crisp HD 4:3 framed cards (a brief readable
 * hold), then fly into the wordmark's letterforms before the solid hero takes
 * over. Cards are screen-aligned (no tilt/skew), correct-aspect (cover-cropped,
 * never stretched), rounded with a border + soft drop shadow. With no cached
 * faces yet, cards fall back to accent shards — never placeholder faces.
 */
export function ReplicaMontage({ state, tileCount, heroText, accentColor, atlas }: ReplicaMontageProps) {
  const mesh = useMemo(() => {
    const count = tileCount
    const aspect = atlas?.aspect ?? LAYOUT.cardAspect
    const targets = sampleText(heroText, count)

    // Tidy grid wall: columns/rows chosen to fill the ~16:9 wall evenly.
    const cols = Math.max(1, Math.round(Math.sqrt((count * LAYOUT.gridHalfW) / (LAYOUT.gridHalfH * aspect))))
    const rows = Math.ceil(count / cols)
    const cellW = (2 * LAYOUT.gridHalfW) / cols
    const cellH = (2 * LAYOUT.gridHalfH) / rows
    const cardH = Math.min(cellH, cellW / aspect) * 0.9

    const lanes = new Float32Array(count * 3)
    const grids = new Float32Array(count * 3)
    const tgts = new Float32Array(count * 3)
    const seeds = new Float32Array(count)
    const cells = new Float32Array(count * 2)
    const scales = new Float32Array(count)

    let s = 0x1234abcd
    const rng = () => {
      s = (Math.imul(s ^ (s >>> 15), 1 | s) + 0x6d2b79f5) | 0
      return ((s >>> 0) % 100000) / 100000
    }

    const faceCells = atlas?.count ?? 1
    const grid = atlas?.grid ?? 1
    for (let i = 0; i < count; i++) {
      // Deep-field scatter start.
      lanes[i * 3] = (rng() * 2 - 1) * LAYOUT.rushSpreadX
      lanes[i * 3 + 1] = (rng() * 2 - 1) * LAYOUT.rushSpreadY
      lanes[i * 3 + 2] = LAYOUT.rushZFar + rng() * (LAYOUT.rushZNear - LAYOUT.rushZFar)

      // Tidy grid slot (front-facing wall).
      const col = i % cols
      const row = Math.floor(i / cols)
      grids[i * 3] = -LAYOUT.gridHalfW + (col + 0.5) * cellW
      grids[i * 3 + 1] = LAYOUT.gridCenterY + LAYOUT.gridHalfH - (row + 0.5) * cellH
      grids[i * 3 + 2] = LAYOUT.gridZ + (rng() - 0.5) * 0.15

      // Letter target (pixel-sampled).
      tgts[i * 3] = targets[i * 2] * (2 * LAYOUT.letterHalfWidth)
      tgts[i * 3 + 1] = 0.15 + targets[i * 2 + 1] * (2 * LAYOUT.letterHalfHeight)
      tgts[i * 3 + 2] = (rng() - 0.5) * 0.6

      seeds[i] = rng()
      const cell = i % faceCells
      cells[i * 2] = cell % grid
      cells[i * 2 + 1] = Math.floor(cell / grid)
      scales[i] = cardH
    }

    const base = new THREE.PlaneGeometry(aspect, 1)
    const geo = new THREE.InstancedBufferGeometry()
    geo.index = base.index
    geo.setAttribute('position', base.attributes.position)
    geo.setAttribute('uv', base.attributes.uv)
    geo.instanceCount = count
    geo.setAttribute('aLane', new THREE.InstancedBufferAttribute(lanes, 3))
    geo.setAttribute('aGrid', new THREE.InstancedBufferAttribute(grids, 3))
    geo.setAttribute('aTarget', new THREE.InstancedBufferAttribute(tgts, 3))
    geo.setAttribute('aSeed', new THREE.InstancedBufferAttribute(seeds, 1))
    geo.setAttribute('aCell', new THREE.InstancedBufferAttribute(cells, 2))
    geo.setAttribute('aScale', new THREE.InstancedBufferAttribute(scales, 1))
    base.dispose()

    const white = new THREE.DataTexture(new Uint8Array([255, 255, 255, 255]), 1, 1)
    white.needsUpdate = true

    const mat = new THREE.ShaderMaterial({
      vertexShader: VERT,
      fragmentShader: FRAG,
      transparent: true,
      depthWrite: false,
      depthTest: true,
      blending: atlas ? THREE.NormalBlending : THREE.AdditiveBlending,
      uniforms: {
        uAtlas: { value: atlas?.texture ?? white },
        uHasAtlas: { value: atlas ? 1 : 0 },
        uCellUv: { value: atlas?.cellUv ?? 1 },
        uAspect: { value: aspect },
        uRush: { value: 0 },
        uMorph: { value: 0 },
        uCloud: { value: 1 },
        uAccent: { value: new THREE.Color(accentColor) },
      },
    })

    const m = new THREE.Mesh(geo, mat)
    m.frustumCulled = false
    m.renderOrder = -1
    return m
  }, [tileCount, heroText, accentColor, atlas])

  useEffect(() => {
    return () => {
      mesh.geometry.dispose()
      ;(mesh.material as THREE.Material).dispose()
    }
  }, [mesh])

  useFrame(() => {
    const u = (mesh.material as THREE.ShaderMaterial).uniforms
    u.uRush.value = state.refs.rush.value
    u.uMorph.value = state.refs.morph.value
    u.uCloud.value = state.refs.cloud.value
  })

  return <primitive object={mesh} />
}
