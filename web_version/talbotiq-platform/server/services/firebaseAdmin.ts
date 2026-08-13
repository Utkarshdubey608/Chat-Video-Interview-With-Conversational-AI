import { initializeApp, cert, applicationDefault, getApps, type App } from 'firebase-admin/app'
import { getAuth, type Auth, type DecodedIdToken } from 'firebase-admin/auth'
import { getFirestore, type Firestore } from 'firebase-admin/firestore'
import { getStorage, type Storage } from 'firebase-admin/storage'
import { HttpError } from '../util/ah'
import type { UserRole } from '../../shared/types'

/**
 * Firebase Admin SDK bootstrap.
 *
 * This is the SERVER's authority for identity: it verifies the ID tokens the
 * client sends on every request, and reads the caller's role from the SAME
 * Firestore doc the client uses (`users/{uid}.role`) — so the two clients (this
 * web app and the Flutter app) stay in lock-step on roles. It is initialised
 * LAZILY and never throws at import time, so the rest of the app (templates,
 * interviews, scoring) still boots for local dev even when Firebase credentials
 * are absent — auth-guarded endpoints simply return 503 until it's configured.
 * See docs/AUTH.md.
 *
 * Credentials, in priority order:
 *   1. FIREBASE_PROJECT_ID + FIREBASE_CLIENT_EMAIL + FIREBASE_PRIVATE_KEY
 *      (a service-account, split across env vars — good for Cloud Run / CI).
 *   2. GOOGLE_APPLICATION_CREDENTIALS / Application Default Credentials
 *      (a key file path, or the ambient service account on GCP).
 */

let cached: { app: App; auth: Auth } | null = null
let firestoreCache: Firestore | null = null
let bucketCache: ReturnType<Storage['bucket']> | null = null
let initTried = false
let initError: string | null = null

function buildCredential() {
  const projectId = (process.env.FIREBASE_PROJECT_ID ?? '').trim()
  const clientEmail = (process.env.FIREBASE_CLIENT_EMAIL ?? '').trim()
  // Env-encoded PEM keys keep their newlines as the literal characters "\n".
  const privateKey = (process.env.FIREBASE_PRIVATE_KEY ?? '').replace(/\\n/g, '\n').trim()

  if (projectId && clientEmail && privateKey) {
    return { credential: cert({ projectId, clientEmail, privateKey }), projectId }
  }
  // Fall back to ADC (GOOGLE_APPLICATION_CREDENTIALS or the ambient GCP identity).
  if ((process.env.GOOGLE_APPLICATION_CREDENTIALS ?? '').trim() || (process.env.GOOGLE_CLOUD_PROJECT ?? '').trim()) {
    return { credential: applicationDefault(), projectId: (process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT || '').trim() || undefined }
  }
  return null
}

function ensureInit(): void {
  if (cached || initTried) return
  initTried = true
  try {
    const existing = getApps()
    if (existing.length) {
      cached = { app: existing[0], auth: getAuth(existing[0]) }
      return
    }
    const cred = buildCredential()
    if (!cred) {
      initError = 'no credentials found (set FIREBASE_PROJECT_ID/CLIENT_EMAIL/PRIVATE_KEY or GOOGLE_APPLICATION_CREDENTIALS)'
      return
    }
    const app = initializeApp({ credential: cred.credential, projectId: cred.projectId })
    cached = { app, auth: getAuth(app) }
    console.log('[auth] Firebase Admin initialised' + (cred.projectId ? ` (project ${cred.projectId})` : ''))
  } catch (err) {
    initError = err instanceof Error ? err.message : String(err)
    console.error('[auth] Firebase Admin init failed:', initError)
  }
}

/** True when the Admin SDK is ready to verify tokens / set claims. */
export function authConfigured(): boolean {
  ensureInit()
  return cached !== null
}

/** The Admin Auth instance, or a 503 if Firebase isn't configured. */
export function adminAuth(): Auth {
  ensureInit()
  if (!cached) throw new HttpError(503, `Authentication is not configured on the server (${initError ?? 'unknown reason'})`)
  return cached.auth
}

/** Verify a client ID token. Throws HttpError(401) on any invalid/expired token. */
export async function verifyIdToken(idToken: string): Promise<DecodedIdToken> {
  try {
    return await adminAuth().verifyIdToken(idToken, true)
  } catch (err) {
    if (err instanceof HttpError) throw err // 503 (unconfigured) — surface as-is
    throw new HttpError(401, 'Invalid or expired authentication token')
  }
}

/** Admin Firestore handle, or a 503 if Firebase isn't configured. */
export function adminFirestore(): Firestore {
  ensureInit()
  if (!cached) throw new HttpError(503, `Authentication is not configured on the server (${initError ?? 'unknown reason'})`)
  if (!firestoreCache) firestoreCache = getFirestore(cached.app)
  return firestoreCache
}

/** The configured Storage bucket name (server var, else the client-facing one). */
export function storageBucketName(): string {
  return (process.env.FIREBASE_STORAGE_BUCKET || process.env.VITE_FIREBASE_STORAGE_BUCKET || '').trim()
}

/**
 * Admin Storage bucket handle, or a 503/500 if not configured. Admin writes bypass
 * Storage security rules — used to host recruiter-uploaded invite-email logos and
 * return a public, tokenised download URL that email clients can load.
 */
export function adminBucket(): ReturnType<Storage['bucket']> {
  ensureInit()
  if (!cached) throw new HttpError(503, `Storage is not configured on the server (${initError ?? 'unknown reason'})`)
  const name = storageBucketName()
  if (!name) throw new HttpError(500, 'Storage bucket not configured (set FIREBASE_STORAGE_BUCKET or VITE_FIREBASE_STORAGE_BUCKET)')
  if (!bucketCache) bucketCache = getStorage(cached.app).bucket(name)
  return bucketCache
}

/**
 * Read the role recorded on `users/{uid}` — the SAME document the Flutter app and
 * the web client write at sign-up. This is the single source of truth for the
 * role (no custom claims). A missing or unreadable doc resolves to `candidate`
 * (least privilege), matching the client's AuthGate default.
 */
export async function getUserRole(uid: string): Promise<UserRole> {
  try {
    const snap = await adminFirestore().collection('users').doc(uid).get()
    return snap.get('role') === 'recruiter' ? 'recruiter' : 'candidate'
  } catch {
    return 'candidate'
  }
}
