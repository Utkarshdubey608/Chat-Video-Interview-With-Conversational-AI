/**
 * Renders the wordmark to an offscreen canvas and samples its opaque pixels
 * into `count` normalized target coordinates. The replica cloud lerps each tile
 * toward one of these points, so the tiles' positions spell the wordmark — the
 * text-sampled particle morph at the heart of the sequence.
 *
 * Returned coords are centered: x,y ∈ roughly [-0.5, 0.5] with +y up. The
 * caller scales them to the world-space letter plane.
 */
export function sampleText(text: string, count: number, width = 1024, height = 256): Float32Array {
  const out = new Float32Array(count * 2)

  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext('2d', { willReadFrequently: true })
  if (!ctx) {
    // No 2D context (extremely rare) — fall back to a flat line of points.
    for (let i = 0; i < count; i++) {
      out[i * 2] = (i / count - 0.5) * 0.9
      out[i * 2 + 1] = 0
    }
    return out
  }

  ctx.fillStyle = '#000'
  ctx.fillRect(0, 0, width, height)
  ctx.fillStyle = '#fff'
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  // Fit the wordmark to the canvas width with a heavy face.
  let fontPx = Math.floor(height * 0.7)
  ctx.font = `800 ${fontPx}px Syne, "Arial Black", Arial, sans-serif`
  while (ctx.measureText(text).width > width * 0.92 && fontPx > 12) {
    fontPx -= 4
    ctx.font = `800 ${fontPx}px Syne, "Arial Black", Arial, sans-serif`
  }
  ctx.fillText(text, width / 2, height / 2)

  const data = ctx.getImageData(0, 0, width, height).data

  // Collect bright (letter) pixels, subsampling the grid for speed.
  const bright: number[] = []
  const step = 2
  for (let y = 0; y < height; y += step) {
    for (let x = 0; x < width; x += step) {
      const idx = (y * width + x) * 4
      if (data[idx] > 128) {
        bright.push(x, y)
      }
    }
  }

  if (bright.length === 0) {
    for (let i = 0; i < count; i++) {
      out[i * 2] = (i / count - 0.5) * 0.9
      out[i * 2 + 1] = 0
    }
    return out
  }

  const pairs = bright.length / 2
  // Deterministic stride pick so targets spread evenly over the letterforms.
  const stride = Math.max(1, Math.floor(pairs / count))
  for (let i = 0; i < count; i++) {
    const p = ((i * stride) % pairs) * 2
    const px = bright[p]
    const py = bright[p + 1]
    // Tiny per-point jitter avoids visible sampling banding.
    const jx = (((i * 73) % 7) / 7 - 0.5) * (step / width)
    const jy = (((i * 37) % 7) / 7 - 0.5) * (step / height)
    out[i * 2] = px / width - 0.5 + jx
    out[i * 2 + 1] = 0.5 - py / height + jy
  }

  return out
}
