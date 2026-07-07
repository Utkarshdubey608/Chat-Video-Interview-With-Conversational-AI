# Deployment — Google Cloud + Play Store

> **Status: scaffolding + guide.** These steps target production on Google Cloud
> and Android on the Play Store. They are **not run or tested in local dev** —
> they require your own GCP project, service accounts, and Android SDK. Local
> development stays exactly as-is: `npm run dev` (Vite + Express + JSON store).

## Target topology

```
┌─────────────────────────┐        ┌──────────────────────────────┐
│ Firebase Hosting (web)  │  /api  │ Cloud Run (Express API)      │
│ Capacitor APK (Android) │ ─────▶ │  · conversational turn loop  │
│  (the Vite SPA)         │  HTTPS │  · server-authoritative timers│
└─────────────────────────┘        │  · résumé parsing + scoring  │
                                     └───────┬──────────────┬───────┘
                                             │              │
                                      Firestore        Vertex AI (Gemini)
                                   (sessions/transcript,   via service account
                                    templates, reports)     — no key on device
                                             │
                                      Firebase Storage
                                    (résumés, video answers)
                                      Firebase Auth (recruiters + candidates)
```

## Why these pieces
- **Cloud Run** — the API scales to zero and runs the turn loop, authoritative timers, parsing, and scoring. Stateless containers.
- **Firestore** — because Cloud Run instances are ephemeral and horizontally scaled, session state (transcript, current index, phase start-times, drafts) **must not** live in server memory. Firestore makes server-authoritative timing + refresh-resume work across instances.
- **Vertex AI** — call Gemini with the Cloud Run service account (IAM), so **no API-key string ships to any device**. (An API key, if used instead, lives only as a Cloud Run secret — never `VITE_`-prefixed.)
- **Firebase Hosting + Capacitor** — one SPA build serves the web app and wraps into an Android AAB; Capacitor (not a TWA) gives the Video Avatar track reliable native camera/mic.

## Security rules (must hold)
- The LLM credential is **server-only**. Never in the client bundle, never in the APK, never in a response. Verify: `npm run build && grep -r "AIza\|GEMINI_API_KEY" dist/` → nothing.
- All Gemini calls (generation, turn loop, scoring, parsing) happen in the Cloud Run service.
- Env vars prefixed `VITE_` are **public** (inlined into the bundle). Only put non-secrets there (e.g. `VITE_API_BASE`).

---

## 1. Backend → Cloud Run
```bash
cd talbotiq-platform
gcloud config set project "$GOOGLE_CLOUD_PROJECT"
gcloud run deploy talbotiq-api \
  --source . \
  --dockerfile server/Dockerfile \
  --region "$VERTEX_LOCATION" \
  --allow-unauthenticated \
  --set-env-vars USE_VERTEX=true,GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT,VERTEX_LOCATION=$VERTEX_LOCATION
```
- Grant the Cloud Run service account the **Vertex AI User** role.
- If using an API key instead of Vertex: `gcloud secrets create gemini-key --data-file=-` then `--set-secrets GEMINI_API_KEY=gemini-key:latest` (never an env var in the image).

## 2. Swap the store → Firestore
The store is centralized in `server/store/db.ts` (Maps + JSON file). For production, implement the same surface against Firestore collections (`templates`, `questionSets`, `sessions`, `reports`) — e.g. `db.sessions.get/set` → `doc(...).get()/set()`. Everything else (routes, engine, scoring) is storage-agnostic and unchanged. Keep the in-memory/JSON impl for local dev behind an env switch.

## 3. LLM → Vertex AI
`server/services/gemini.ts` centralizes the client via `geminiClient()`. For Vertex, initialize `new GoogleGenAI({ vertexai: true, project: GOOGLE_CLOUD_PROJECT, location: VERTEX_LOCATION })` when `USE_VERTEX=true` (ADC from the Cloud Run service account); otherwise the existing API-key path. No prompts/schemas change.

## 4. Frontend → Firebase Hosting
```bash
npm run build            # → dist/
firebase init hosting    # public dir = dist, single-page app = yes
firebase deploy --only hosting
```
Add a Hosting rewrite so `/api/**` proxies to the Cloud Run service (or call it directly via `VITE_API_BASE`).

## 5. Android → Capacitor / Play Store
```bash
npm i -D @capacitor/cli && npm i @capacitor/core @capacitor/android
VITE_API_BASE="https://<cloud-run-url>" npm run build
npx cap add android && npx cap sync
npx cap open android     # build + sign the AAB in Android Studio → Play Console
```
See `capacitor.config.ts` (appId `com.talbotiq.interview`). Request camera/mic permissions for the Video Avatar track.

### Client base URL
For the native build, `src/lib/api.ts` must target the deployed API (there is no Vite proxy in the APK). Change `const BASE = '/api'` to `const BASE = (import.meta.env.VITE_API_BASE ?? '') + '/api'`. Web/dev leaves `VITE_API_BASE` blank so the proxy is used.

## 6. Auth & storage
- **Firebase Auth** — gate the recruiter app; issue candidate session links (optionally magic-link/token). Verify the ID token in the Cloud Run middleware.
- **Firebase Storage** — store uploaded résumés and (Video Avatar track) recorded answers; keep signed URLs server-side.

## Checklist
- [ ] Cloud Run deployed; `/api/health` returns `{ ok: true }`.
- [ ] Firestore holds sessions/templates/reports (survives instance restarts).
- [ ] Vertex AI (or secret-managed key) — `grep dist/` shows no key.
- [ ] Hosting serves the SPA; `/api` reaches Cloud Run.
- [ ] Signed AAB builds; camera/mic permissions declared.
