/**
 * Framing checks — the "what makes results accurate" logic.
 *
 * Pure functions only (no MediaPipe / DOM imports) so this is trivially
 * testable and cheap to run every frame. Input is normalized landmarks
 * (0–1 in frame space) plus an optional pre-sampled face-region luma; output
 * is a per-check boolean set and the single most relevant hint to surface.
 *
 * Coordinates are in the RAW (un-mirrored) camera space. Centering/distance/
 * pose checks are all mirror-invariant, so the selfie-mirror preview does not
 * affect them.
 */
import { FRAMING, type FramingConfig } from './config'

export interface Landmark {
  x: number
  y: number
  z?: number
}

/** Canonical MediaPipe FaceMesh indices we key off (subject-relative). */
const IDX = {
  noseTip: 1,
  eyeOuterA: 33, // one eye's outer corner
  eyeOuterB: 263, // the other eye's outer corner
  mouthCornerA: 61,
  mouthCornerB: 291,
} as const

/** Approx degrees-per-unit conversions for the landmark-based pose proxies. */
const YAW_DEG_PER_UNIT = 90 // nose horizontal offset (as fraction of inter-eye) → deg
const PITCH_DEG_PER_UNIT = 120 // nose vertical position deviation → deg

export type HintId =
  | 'no_face'
  | 'multiple'
  | 'move_closer'
  | 'move_back'
  | 'center'
  | 'frontal'
  | 'lighting'
  | 'hold'

export interface FaceBox {
  cx: number
  cy: number
  w: number
  h: number
}

/**
 * The portion of the raw camera frame that is actually visible on screen, in
 * normalized (0–1) camera coords. With object-cover, part of the frame is
 * cropped off; centering/distance must be judged against what the candidate
 * sees, not the full sensor frame. Defaults to the whole frame.
 */
export interface Viewport {
  left: number
  top: number
  width: number
  height: number
}

const FULL_VIEWPORT: Viewport = { left: 0, top: 0, width: 1, height: 1 }

export interface Pose {
  yaw: number
  pitch: number
  roll: number
}

export interface FramingChecks {
  present: boolean
  single: boolean
  centered: boolean
  distanceOk: boolean
  frontal: boolean
  lightingOk: boolean
}

export interface FramingResult {
  checks: FramingChecks
  /** True only when every (enabled) check passes. */
  allGood: boolean
  /** The single instruction to show right now. */
  hint: HintId
  faceBox: FaceBox | null
  pose: Pose | null
  faceCount: number
}

const HINT_TEXT: Record<HintId, string> = {
  no_face: 'Position your face inside the frame',
  multiple: 'Make sure only you are in the frame',
  move_closer: 'Move a little closer',
  move_back: 'Move back a bit',
  center: 'Center your face in the frame',
  frontal: 'Look straight ahead at the camera',
  lighting: 'Find brighter, even lighting',
  hold: 'Perfect — hold steady',
}

export function hintText(id: HintId): string {
  return HINT_TEXT[id]
}

/** Axis-aligned bounding box (normalized) around a set of landmarks. */
export function computeFaceBox(landmarks: Landmark[]): FaceBox | null {
  if (!landmarks.length) return null
  let minX = 1
  let minY = 1
  let maxX = 0
  let maxY = 0
  for (const p of landmarks) {
    if (p.x < minX) minX = p.x
    if (p.y < minY) minY = p.y
    if (p.x > maxX) maxX = p.x
    if (p.y > maxY) maxY = p.y
  }
  return { cx: (minX + maxX) / 2, cy: (minY + maxY) / 2, w: maxX - minX, h: maxY - minY }
}

/**
 * Head pose from landmark symmetry (mirror-invariant, no matrix-convention
 * pitfalls). Roll comes from the eye line; yaw from the nose's horizontal
 * offset between the eyes; pitch from the nose's vertical position between the
 * eye line and the mouth. Values are approximate degrees — good enough for a
 * lenient "roughly frontal" gate, and the thresholds are tunable.
 */
export function computePose(landmarks: Landmark[], cfg: FramingConfig = FRAMING): Pose | null {
  const eyeA = landmarks[IDX.eyeOuterA]
  const eyeB = landmarks[IDX.eyeOuterB]
  const nose = landmarks[IDX.noseTip]
  const mouthA = landmarks[IDX.mouthCornerA]
  const mouthB = landmarks[IDX.mouthCornerB]
  if (!eyeA || !eyeB || !nose || !mouthA || !mouthB) return null

  // Roll: tilt of the inter-eye line.
  const roll = Math.abs((Math.atan2(eyeB.y - eyeA.y, eyeB.x - eyeA.x) * 180) / Math.PI)
  const rollNorm = roll > 90 ? 180 - roll : roll // fold to [0, 90]

  const eyeMidX = (eyeA.x + eyeB.x) / 2
  const eyeMidY = (eyeA.y + eyeB.y) / 2
  const interEye = Math.hypot(eyeB.x - eyeA.x, eyeB.y - eyeA.y) || 1e-6

  // Yaw: how far the nose sits off the eye midpoint, scaled by eye spacing.
  const yaw = Math.abs(((nose.x - eyeMidX) / interEye) * YAW_DEG_PER_UNIT)

  // Pitch: nose's vertical position between eye line (0) and mouth line (1);
  // ~0.5 is frontal. Deviations map to up/down tilt.
  const mouthY = (mouthA.y + mouthB.y) / 2
  const eyeToMouth = mouthY - eyeMidY || 1e-6
  const pitchRatio = (nose.y - eyeMidY) / eyeToMouth
  const pitch = Math.abs((pitchRatio - cfg.pitchNeutralRatio) * PITCH_DEG_PER_UNIT)

  return { yaw, pitch, roll: rollNorm }
}

/**
 * Evaluate all framing checks and pick the single most relevant hint.
 *
 * Centering and distance are judged in VISIBLE space (via `viewport`) so they
 * match what the candidate sees under object-cover, not the full sensor frame.
 *
 * @param faces     landmark sets, one per detected face (raw camera space)
 * @param luma      mean luma (0–255) of the face region, or null if unsampled
 * @param cfg       tunable thresholds
 * @param viewport  visible crop of the frame (normalized); defaults to full
 */
export function evaluateFraming(
  faces: Landmark[][],
  luma: number | null,
  cfg: FramingConfig = FRAMING,
  viewport: Viewport = FULL_VIEWPORT,
): FramingResult {
  const faceCount = faces.length
  const present = faceCount >= 1
  const single = faceCount === 1
  const primary = faces[0] ?? []

  const faceBox = present ? computeFaceBox(primary) : null
  const pose = present ? computePose(primary, cfg) : null

  // Face box mapped into visible (on-screen) space.
  const cxVis = faceBox ? (faceBox.cx - viewport.left) / viewport.width : 0.5
  const cyVis = faceBox ? (faceBox.cy - viewport.top) / viewport.height : 0.5
  const wVis = faceBox ? faceBox.w / viewport.width : 0
  const centered = !!faceBox &&
    Math.abs(cxVis - 0.5) <= cfg.centerToleranceX &&
    Math.abs(cyVis - 0.5) <= cfg.centerToleranceY

  const tooClose = !!faceBox && wVis > cfg.distanceMax
  const tooFar = !!faceBox && wVis < cfg.distanceMin
  const distanceOk = !!faceBox && !tooClose && !tooFar

  const frontal = !!pose &&
    pose.yaw <= cfg.maxYawDeg &&
    pose.pitch <= cfg.maxPitchDeg &&
    pose.roll <= cfg.maxRollDeg

  const lightingOk = !cfg.lightingEnabled || luma === null ||
    (luma >= cfg.lumaMin && luma <= cfg.lumaMax)

  const checks: FramingChecks = { present, single, centered, distanceOk, frontal, lightingOk }

  // Single-hint priority: the biggest blocker first, so the candidate always
  // gets one clear instruction rather than a wall of nags.
  let hint: HintId = 'hold'
  if (!present) hint = 'no_face'
  else if (!single) hint = 'multiple'
  else if (tooFar) hint = 'move_closer'
  else if (tooClose) hint = 'move_back'
  else if (!centered) hint = 'center'
  else if (!frontal) hint = 'frontal'
  else if (!lightingOk) hint = 'lighting'

  const allGood = present && single && centered && distanceOk && frontal && lightingOk

  return { checks, allGood, hint, faceBox, pose, faceCount }
}
