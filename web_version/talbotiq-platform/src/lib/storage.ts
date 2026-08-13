import { getStorage, ref, uploadBytes, getDownloadURL, type FirebaseStorage } from 'firebase/storage'
import { firebaseAuth } from './firebase'

/**
 * Firebase Storage bootstrap. Reuses the initialised app from firebase.ts (via
 * firebaseAuth().app) so we don't double-init. The web config is public by
 * design; write access is enforced by storage.rules (scoped to the invited
 * candidate for the session, per the interviews/{sessionId} Firestore doc).
 *
 * Retry windows are bounded (default is 120s each) so a failed/unreachable
 * bucket surfaces as an error in seconds instead of leaving the candidate stuck
 * on "Uploading…". If uploads never succeed, confirm Firebase Storage is enabled
 * for the project and that VITE_FIREBASE_STORAGE_BUCKET matches the real bucket.
 */
const UPLOAD_RETRY_MS = 15_000
const OP_RETRY_MS = 15_000
const HARD_TIMEOUT_MS = 25_000

let storageInstance: FirebaseStorage | undefined
function storage(): FirebaseStorage {
  if (!storageInstance) {
    storageInstance = getStorage(firebaseAuth().app)
    storageInstance.maxUploadRetryTime = UPLOAD_RETRY_MS
    storageInstance.maxOperationRetryTime = OP_RETRY_MS
  }
  return storageInstance
}

/** Reject if `p` hasn't settled within `ms` — a hard cap so the submit flow can
 *  never hang indefinitely even if the SDK's own retry timer misbehaves. */
function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((_, reject) => setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms)),
  ])
}

/**
 * Upload one recorded answer clip and return its download URL. Path is namespaced
 * per session + question so re-records overwrite cleanly. The returned URL carries
 * a Storage access token, so the recruiter report can play it back without auth.
 * Throws (bounded by the timeouts above) rather than hanging when the bucket is
 * missing/unreachable — the caller surfaces the failure instead of spinning.
 */
export async function uploadAnswerVideo(sessionId: string, questionId: string, blob: Blob): Promise<string> {
  // Derive the extension from the recorded blob's MIME type (e.g. Safari records
  // video/mp4, Chrome/Firefox record video/webm) so playback matches the codec.
  const ext = (blob.type.split('/')[1] || 'webm').split(';')[0]
  const path = `interviews/${sessionId}/${questionId}.${ext}`
  const r = ref(storage(), path)
  await withTimeout(uploadBytes(r, blob, { contentType: blob.type || 'video/webm' }), HARD_TIMEOUT_MS, 'Video upload')
  return withTimeout(getDownloadURL(r), OP_RETRY_MS, 'Get download URL')
}
