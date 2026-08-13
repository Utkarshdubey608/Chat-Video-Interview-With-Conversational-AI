import type { IntroTier } from './constants'

const SOFTWARE_RENDERER = /swiftshader|llvmpipe|software|basic render/i
const MOBILE_UA = /android|iphone|ipad|ipod|mobile/i

/** True if this browser can create a WebGL context at all. */
export function supportsWebgl(): boolean {
  try {
    const canvas = document.createElement('canvas')
    return Boolean(canvas.getContext('webgl2') ?? canvas.getContext('webgl'))
  } catch {
    return false
  }
}

/**
 * Device-capability heuristic for the cinematic intro. Returns "low" for
 * software renderers or when WebGL is unavailable; "med" for mobile / low-core
 * machines; "high" otherwise. The caller maps "low" (and reduced-motion) to the
 * non-WebGL static hero.
 */
export function detectTier(): IntroTier {
  if (typeof window === 'undefined' || typeof navigator === 'undefined') {
    return 'low'
  }
  try {
    const canvas = document.createElement('canvas')
    const gl = canvas.getContext('webgl2') ?? canvas.getContext('webgl')
    if (!gl) {
      return 'low'
    }
    const info = gl.getExtension('WEBGL_debug_renderer_info')
    if (info) {
      const renderer = String(gl.getParameter(info.UNMASKED_RENDERER_WEBGL))
      if (SOFTWARE_RENDERER.test(renderer)) {
        return 'low'
      }
    }
  } catch {
    return 'low'
  }

  const cores = navigator.hardwareConcurrency ?? 8
  const deviceMemory = (navigator as Navigator & { deviceMemory?: number }).deviceMemory ?? 8
  if (MOBILE_UA.test(navigator.userAgent) || cores <= 4 || deviceMemory <= 4) {
    return 'med'
  }
  return 'high'
}
