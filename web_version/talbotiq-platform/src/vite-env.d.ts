/// <reference types="vite/client" />

interface ImportMetaEnv {
  // Firebase Web SDK config (public by design — these are NOT secrets; access is
  // controlled by Firebase security rules + the backend, not by hiding these).
  readonly VITE_FIREBASE_API_KEY?: string
  readonly VITE_FIREBASE_AUTH_DOMAIN?: string
  readonly VITE_FIREBASE_PROJECT_ID?: string
  readonly VITE_FIREBASE_STORAGE_BUCKET?: string
  readonly VITE_FIREBASE_MESSAGING_SENDER_ID?: string
  readonly VITE_FIREBASE_APP_ID?: string
  // API base URL for the native (Capacitor) build; blank in web/dev (Vite proxy).
  readonly VITE_API_BASE?: string
  // Face-Fit pre-flight (client-side framing aid) — override MediaPipe asset
  // locations for offline / Capacitor builds. See public/mediapipe/README.md.
  readonly VITE_FACEFIT_WASM_BASE?: string
  readonly VITE_FACEFIT_MODEL_URL?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
