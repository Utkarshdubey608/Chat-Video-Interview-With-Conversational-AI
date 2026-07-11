import type { CapacitorConfig } from '@capacitor/cli'

/**
 * Capacitor config for the Play Store (Android) build of the TalbotIQ SPA.
 * SCAFFOLD — not wired into local dev. See docs/DEPLOYMENT.md for the full flow.
 *
 * Setup (run in talbotiq-platform/):
 *   npm i -D @capacitor/cli && npm i @capacitor/core @capacitor/android
 *   npm run build                       # produces dist/ (webDir below)
 *   npx cap add android
 *   npx cap sync
 *   npx cap open android                # build/sign the AAB in Android Studio
 *
 * IMPORTANT: the app must call the deployed Cloud Run API over HTTPS in the
 * native build (there is no Vite dev proxy in the APK). Set VITE_API_BASE at
 * build time and have src/lib/api.ts use it (see DEPLOYMENT.md §Client base URL).
 * The Gemini/Vertex credential lives ONLY on Cloud Run — never in the APK.
 */
const config: CapacitorConfig = {
  appId: 'com.talbotiq.interview',
  appName: 'TalbotIQ',
  webDir: 'dist',
  server: {
    androidScheme: 'https',
  },
}

export default config
