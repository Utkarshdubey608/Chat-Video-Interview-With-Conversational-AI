import { initializeApp, type FirebaseApp } from 'firebase/app'
import { getAuth, type Auth } from 'firebase/auth'
import { getFirestore, type Firestore } from 'firebase/firestore'

/**
 * Firebase Web SDK bootstrap (client identity + the users/{uid} role doc).
 *
 * These config values are PUBLIC by design — they identify the Firebase project
 * (`talbotiq-9cc4e`), they are not secrets. Access control lives in the deployed
 * Firestore security rules and in the backend (which verifies the ID token on
 * every /api request). No server key or third-party credential is in this bundle.
 *
 * The role model mirrors the Flutter app EXACTLY so the two clients interoperate
 * on the same Firestore documents: a user's role is stored on `users/{uid}.role`
 * (written at sign-up), read live via onSnapshot, and defaults to `candidate`
 * when the doc is missing. See docs/AUTH.md.
 */
const config = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
}

/** True when the minimum Firebase config is present. When false the app shows a
 *  "sign-in isn't configured" notice instead of the login screen. */
export const firebaseConfigured = Boolean(config.apiKey && config.projectId && config.appId)

let app: FirebaseApp | undefined
let authInstance: Auth | undefined
let dbInstance: Firestore | undefined

function ensureApp(): FirebaseApp {
  if (!firebaseConfigured) throw new Error('Firebase is not configured — set the VITE_FIREBASE_* env vars.')
  if (!app) app = initializeApp(config)
  return app
}

export function firebaseAuth(): Auth {
  if (!authInstance) authInstance = getAuth(ensureApp())
  return authInstance
}

/** Cloud Firestore handle — used to read/write the users/{uid} role doc. */
export function firestore(): Firestore {
  if (!dbInstance) dbInstance = getFirestore(ensureApp())
  return dbInstance
}

/** Current Firebase ID token, or null when signed out / unconfigured. Attached to
 *  every /api request (and to WebSocket handshakes via a ?token= query param) so
 *  the backend can verify identity and enforce role + ownership. */
export async function getIdTokenOrNull(): Promise<string | null> {
  if (!firebaseConfigured) return null
  const user = firebaseAuth().currentUser
  return user ? user.getIdToken() : null
}
