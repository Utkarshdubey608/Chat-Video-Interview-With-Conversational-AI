/**
 * Face-Fit pre-flight — tunable configuration.
 *
 * Everything the "fit your face to frame" screen keys off lives here so the
 * thresholds, hold timings, and auto-vs-manual start behaviour are trivial to
 * tune without touching the detection or UI code.
 *
 * NOTE: this screen is a purely client-side FRAMING AID. It never uploads
 * landmarks and it is NOT the facial analysis — AWS Rekognition still runs
 * server-side on the recorded video, unchanged. Keep the two separate.
 */

/* ── MediaPipe assets ──────────────────────────────────────────────────────
 * The FaceLandmarker needs two things: the WASM runtime (the "fileset") and
 * the `.task` model. Defaults below "just work" online:
 *   - WASM  → jsDelivr CDN, pinned to the installed package version.
 *   - MODEL → self-hosted from /public (committed), so the most likely
 *             CSP/availability failure point does not depend on a third party.
 *
 * For a fully offline / Capacitor (Play Store) build, vendor the WASM too and
 * point WASM_BASE at it — see public/mediapipe/README.md. If any asset fails to
 * load, the screen falls back to a guide-only oval + manual "I'm ready" confirm
 * (it never hard-blocks the candidate).
 */
export const MEDIAPIPE_VERSION = '0.10.35'
export const WASM_BASE =
  import.meta.env?.VITE_FACEFIT_WASM_BASE ||
  `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MEDIAPIPE_VERSION}/wasm`
/** Self-hosted model (see public/mediapipe/). Override with VITE_FACEFIT_MODEL_URL. */
export const MODEL_URL =
  import.meta.env?.VITE_FACEFIT_MODEL_URL || '/mediapipe/face_landmarker.task'
/** Last-resort CDN model if the self-hosted one 404s. */
export const MODEL_URL_FALLBACK =
  'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task'

/* ── Detection loop ────────────────────────────────────────────────────────*/
/** Detect at most this often (ms). ~55ms ≈ 18fps — smooth but light on mobile. */
export const DETECT_INTERVAL_MS = 55
/** Detect up to N faces so we can flag "more than one person in frame". */
export const MAX_FACES = 2
/** If the model has not loaded within this long, drop to the guide-only fallback. */
export const MODEL_LOAD_TIMEOUT_MS = 12_000

/* ── Framing thresholds (all in normalized 0–1 frame space) ────────────────*/
export const FRAMING = {
  /** Face centre must sit within ±tolerance of the frame centre (0.5). */
  centerToleranceX: 0.15,
  centerToleranceY: 0.16,
  /** Face-box width as a fraction of frame width — the "distance" sweet spot. */
  distanceMin: 0.30,
  distanceMax: 0.62,
  /** Max head rotation from frontal, in degrees. Yaw + roll are the reliable
   *  "facing the camera" signals; pitch is a coarse landmark proxy so it's kept
   *  lenient (it only trips on clear looking-up/down). */
  maxYawDeg: 16,
  maxPitchDeg: 22,
  maxRollDeg: 14,
  /** Frontal nose-tip position between the eye line (0) and mouth line (1).
   *  The nose tip sits below the midpoint on a real frontal face, so this is
   *  ~0.62, not 0.5. Tune per replica/camera if needed. */
  pitchNeutralRatio: 0.62,
  /** Optional lighting check on the mean luma of the face region (0–255). */
  lightingEnabled: true,
  lumaMin: 55,
  lumaMax: 232,
} as const

/* ── Lock-in gating ────────────────────────────────────────────────────────*/
/** All checks must hold continuously this long before we "lock". */
export const HOLD_MS = 1600
/**
 * After lock-in:
 *   AUTO_START true  → show "Perfect — you're all set" then auto-proceed.
 *   AUTO_START false → enable a "Start interview" button (candidate clicks).
 * Manual start also engages fullscreen from a real user gesture; auto-start's
 * fullscreen request is best-effort (browsers may ignore it without a gesture).
 */
export const AUTO_START = true
/** Success-beat length before auto-proceed. Kept short: the camera is released
 *  AT lock, so this countdown already covers the device-release buffer — every
 *  extra ms here is dead air between the candidate and their interviewer. */
export const AUTO_START_COUNTDOWN_MS = 900
/**
 * Pause after releasing our camera/mic before handing off to Tavus. The camera
 * device (esp. exclusive-access webcams on Windows) needs a moment to free up,
 * or the Tavus/Daily call loses the race and joins with the camera OFF.
 */
export const HANDOFF_RELEASE_MS = 500

/* ── Presentation ──────────────────────────────────────────────────────────*/
/** Mirror the preview like a selfie camera (feels natural to the candidate). */
export const MIRROR = true
/** After this long with no successful lock, surface a "having trouble?" skip. */
export const STUCK_HINT_AFTER_MS = 25_000

export type FramingConfig = typeof FRAMING
