/**
 * useFaceLandmarker — on-device face tracking for the pre-flight framing aid.
 *
 * Lazy-loads MediaPipe FaceLandmarker (code-split: the heavy WASM/JS only
 * downloads on this screen), runs a throttled detect-for-video loop, samples
 * the face-region luma, and reports a FramingResult + the raw landmark sets
 * each detection. Everything runs on the device — nothing is uploaded.
 *
 * Resilience: GPU delegate falls back to CPU; a self-hosted model that 404s
 * falls back to the CDN; and if loading errors or times out, `status` becomes
 * 'unsupported' so the screen can drop to its guide-only manual path.
 */
import { useEffect, useRef, useState } from 'react'
import type { FaceLandmarker as FaceLandmarkerT } from '@mediapipe/tasks-vision'
import {
  WASM_BASE,
  MODEL_URL,
  MODEL_URL_FALLBACK,
  MAX_FACES,
  DETECT_INTERVAL_MS,
  MODEL_LOAD_TIMEOUT_MS,
} from './config'
import {
  computeFaceBox, evaluateFraming, type FramingResult, type Landmark, type Viewport,
} from './framing'

export type LandmarkerStatus = 'loading' | 'ready' | 'error' | 'unsupported'

/** MediaPipe's `Connection` shape (not exported by the package). */
export interface MeshConnection {
  start: number
  end: number
}

export interface FaceMesh {
  tesselation: MeshConnection[]
  contours: MeshConnection[]
}

interface Options {
  videoRef: React.RefObject<HTMLVideoElement>
  enabled: boolean
  /** Called on every (throttled) detection with the framing verdict + raw faces. */
  onResult: (result: FramingResult, faces: Landmark[][]) => void
}

/** Reject if a promise (model/runtime load) hasn't settled within `ms`. */
function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((_, reject) => setTimeout(() => reject(new Error(`${label} timed out`)), ms)),
  ])
}

/**
 * The visible crop of the camera frame (normalized) given how the <video> is
 * laid out with object-cover — so framing is judged against what's on screen.
 */
function visibleViewport(video: HTMLVideoElement): Viewport | undefined {
  const cw = video.clientWidth
  const ch = video.clientHeight
  const vw = video.videoWidth
  const vh = video.videoHeight
  if (!cw || !ch || !vw || !vh) return undefined // fall back to full frame
  const scale = Math.max(cw / vw, ch / vh)
  const width = Math.min(1, cw / (vw * scale))
  const height = Math.min(1, ch / (vh * scale))
  return { left: (1 - width) / 2, top: (1 - height) / 2, width, height }
}

export function useFaceLandmarker({ videoRef, enabled, onResult }: Options) {
  const [status, setStatus] = useState<LandmarkerStatus>('loading')
  const [error, setError] = useState<string | null>(null)
  const [mesh, setMesh] = useState<FaceMesh | null>(null)

  const landmarkerRef = useRef<FaceLandmarkerT | null>(null)
  const rafRef = useRef<number | null>(null)
  const lastDetectRef = useRef(0)
  const lastVideoTimeRef = useRef(-1)
  const lumaCanvasRef = useRef<HTMLCanvasElement | null>(null)
  const onResultRef = useRef(onResult)
  onResultRef.current = onResult

  // ── Load the model (once, while enabled) ────────────────────────────────
  useEffect(() => {
    if (!enabled) return
    let disposed = false

    ;(async () => {
      try {
        const vision = await import('@mediapipe/tasks-vision')
        const { FaceLandmarker, FilesetResolver } = vision
        const fileset = await withTimeout(
          FilesetResolver.forVisionTasks(WASM_BASE),
          MODEL_LOAD_TIMEOUT_MS,
          'Vision runtime',
        )
        if (disposed) return

        const build = (modelAssetPath: string, delegate: 'GPU' | 'CPU') =>
          FaceLandmarker.createFromOptions(fileset, {
            baseOptions: { modelAssetPath, delegate },
            runningMode: 'VIDEO',
            numFaces: MAX_FACES,
            minFaceDetectionConfidence: 0.5,
            minFacePresenceConfidence: 0.5,
            minTrackingConfidence: 0.5,
            outputFaceBlendshapes: false,
            outputFacialTransformationMatrixes: false,
          })

        // Try: local model on GPU → local on CPU → CDN model on GPU.
        let landmarker: FaceLandmarkerT | null = null
        const attempts: Array<[string, 'GPU' | 'CPU']> = [
          [MODEL_URL, 'GPU'],
          [MODEL_URL, 'CPU'],
          [MODEL_URL_FALLBACK, 'GPU'],
        ]
        let lastErr: unknown
        for (const [url, delegate] of attempts) {
          try {
            landmarker = await withTimeout(build(url, delegate), MODEL_LOAD_TIMEOUT_MS, 'Model')
            break
          } catch (e) {
            lastErr = e
          }
        }
        if (!landmarker) throw lastErr ?? new Error('FaceLandmarker unavailable')
        if (disposed) {
          landmarker.close()
          return
        }

        landmarkerRef.current = landmarker
        setMesh({
          tesselation: FaceLandmarker.FACE_LANDMARKS_TESSELATION as MeshConnection[],
          contours: [
            ...FaceLandmarker.FACE_LANDMARKS_FACE_OVAL,
            ...FaceLandmarker.FACE_LANDMARKS_LEFT_EYE,
            ...FaceLandmarker.FACE_LANDMARKS_RIGHT_EYE,
            ...FaceLandmarker.FACE_LANDMARKS_LEFT_EYEBROW,
            ...FaceLandmarker.FACE_LANDMARKS_RIGHT_EYEBROW,
            ...FaceLandmarker.FACE_LANDMARKS_LIPS,
            ...FaceLandmarker.FACE_LANDMARKS_LEFT_IRIS,
            ...FaceLandmarker.FACE_LANDMARKS_RIGHT_IRIS,
          ] as MeshConnection[],
        })
        setStatus('ready')
      } catch (e) {
        if (disposed) return
        console.warn('[facefit] FaceLandmarker load failed — using guide-only fallback', e)
        setError(e instanceof Error ? e.message : 'Face tracking unavailable')
        setStatus('unsupported')
      }
    })()

    return () => {
      disposed = true
      landmarkerRef.current?.close()
      landmarkerRef.current = null
    }
  }, [enabled])

  // ── Detection loop ──────────────────────────────────────────────────────
  useEffect(() => {
    if (!enabled || status !== 'ready') return

    const sampleLuma = (video: HTMLVideoElement, faces: Landmark[][]): number | null => {
      const vw = video.videoWidth
      const vh = video.videoHeight
      if (!vw || !vh) return null
      let canvas = lumaCanvasRef.current
      if (!canvas) {
        canvas = document.createElement('canvas')
        canvas.width = 32
        canvas.height = 32
        lumaCanvasRef.current = canvas
      }
      const ctx = canvas.getContext('2d', { willReadFrequently: true })
      if (!ctx) return null

      // Sample the face region when we have one, else the whole frame.
      const box = faces[0] ? computeFaceBox(faces[0]) : null
      const sx = box ? Math.max(0, (box.cx - box.w / 2) * vw) : 0
      const sy = box ? Math.max(0, (box.cy - box.h / 2) * vh) : 0
      const sw = box ? Math.min(vw - sx, box.w * vw) : vw
      const sh = box ? Math.min(vh - sy, box.h * vh) : vh
      if (sw <= 0 || sh <= 0) return null
      try {
        ctx.drawImage(video, sx, sy, sw, sh, 0, 0, 32, 32)
        const { data } = ctx.getImageData(0, 0, 32, 32)
        let sum = 0
        for (let i = 0; i < data.length; i += 4) {
          sum += 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]
        }
        return sum / (data.length / 4)
      } catch {
        return null // e.g. tainted canvas — skip lighting rather than crash
      }
    }

    const loop = () => {
      rafRef.current = requestAnimationFrame(loop)
      const video = videoRef.current
      const landmarker = landmarkerRef.current
      if (!video || !landmarker) return
      if (video.readyState < 2 || !video.videoWidth) return

      const now = performance.now()
      if (now - lastDetectRef.current < DETECT_INTERVAL_MS) return
      // Skip if the frame has not advanced (detectForVideo wants fresh frames).
      if (video.currentTime === lastVideoTimeRef.current) return
      lastDetectRef.current = now
      lastVideoTimeRef.current = video.currentTime

      let faces: Landmark[][] = []
      try {
        const res = landmarker.detectForVideo(video, now)
        faces = (res.faceLandmarks ?? []) as Landmark[][]
      } catch {
        return // transient detect error — try again next frame
      }
      const luma = sampleLuma(video, faces)
      onResultRef.current(evaluateFraming(faces, luma, undefined, visibleViewport(video)), faces)
    }

    rafRef.current = requestAnimationFrame(loop)
    return () => {
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current)
      rafRef.current = null
    }
  }, [enabled, status, videoRef])

  return { status, error, mesh }
}
