import * as THREE from 'three'

import type { CachedFace } from './replicaFaceCache'

/** A packed atlas of REAL replica faces + its grid metadata. */
export type FaceAtlas = {
  texture: THREE.Texture
  grid: number
  cellUv: number
  /** Number of distinct faces packed (cells actually filled). */
  count: number
  /** Card aspect ratio (width / height) — matches the 4:3 stills. */
  aspect: number
  names: string[]
}

const CELL_W = 384
const CELL_H = 288 // 4:3, matches the extracted stills

/**
 * Packs real replica-face stills (from the IndexedDB cache) into a single sRGB
 * atlas texture — one texture → one draw call for the whole montage. Cells are
 * 4:3 (never stretched); mipmaps + max anisotropy keep them crisp at any
 * distance. Returns null when there are no cached faces (caller falls back to a
 * face-free treatment — never placeholders/cartoons).
 */
export async function buildFaceAtlas(faces: CachedFace[], maxGrid = 10): Promise<FaceAtlas | null> {
  if (!faces.length) return null

  const cap = maxGrid * maxGrid
  const chosen = faces.slice(0, cap)
  const grid = Math.max(2, Math.ceil(Math.sqrt(chosen.length)))

  const canvas = document.createElement('canvas')
  canvas.width = grid * CELL_W
  canvas.height = grid * CELL_H
  const ctx = canvas.getContext('2d')
  if (!ctx) return null
  ctx.imageSmoothingQuality = 'high'
  ctx.fillStyle = '#0a0b0d'
  ctx.fillRect(0, 0, canvas.width, canvas.height)

  const names: string[] = []
  for (let i = 0; i < chosen.length; i++) {
    const face = chosen[i]
    const x0 = (i % grid) * CELL_W
    const y0 = Math.floor(i / grid) * CELL_H
    let bmp: ImageBitmap | null = null
    try {
      bmp = await createImageBitmap(face.blob)
    } catch {
      bmp = null
    }
    if (bmp) {
      // Stills are already 4:3 → fill the 4:3 cell exactly (no distortion).
      ctx.drawImage(bmp, x0, y0, CELL_W, CELL_H)
      bmp.close?.()
    } else {
      ctx.fillStyle = '#15171b'
      ctx.fillRect(x0, y0, CELL_W, CELL_H)
    }
    names.push(face.name)
  }

  const texture = new THREE.CanvasTexture(canvas)
  texture.colorSpace = THREE.SRGBColorSpace
  texture.anisotropy = 16 // clamped to the GPU max by three
  // No mipmaps: at the grid hold the cards are only mildly minified, and
  // trilinear mip filtering visibly softens the faces. Bilinear on the full-res
  // atlas keeps them crisp/identifiable (the featured moment). Far rush cards
  // may shimmer slightly, but they're in fast motion.
  texture.minFilter = THREE.LinearFilter
  texture.magFilter = THREE.LinearFilter
  texture.generateMipmaps = false
  texture.flipY = false
  texture.needsUpdate = true

  return { texture, grid, cellUv: 1 / grid, count: chosen.length, aspect: CELL_W / CELL_H, names }
}
