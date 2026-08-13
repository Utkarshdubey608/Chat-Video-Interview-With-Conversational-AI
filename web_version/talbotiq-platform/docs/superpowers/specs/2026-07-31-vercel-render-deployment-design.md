# Vercel + Render deployment — design

**Date:** 2026-07-31
**Goal:** Hand the deployment team a repository they can deploy immediately: the SPA on Vercel, the Express API on Render, with no code archaeology required.

## Problem

The app runs today only as a single-origin dev setup: Vite on :3001 proxies `/api`
(HTTP and WebSocket) to Express on :8787. Three things prevent a split deployment.

1. **The client assumes same-origin.** `src/lib/api.ts` uses `const BASE = '/api'`,
   `src/lib/faceCache.ts` uses `/api/avatar/face-cache`, and four call sites build
   WebSocket URLs from `location.host`. On Vercel these resolve to the Vercel
   domain, where no API exists.
2. **The store is a JSON file on local disk.** `server/store/db.ts` writes
   `server/data/db.json`. Render's container filesystem is ephemeral, so every
   deploy and every restart discards templates, question sets, sessions, reports,
   pipelines, marketing leads, and saved settings (including the Tavus key).
3. **The Dockerfile targets Cloud Run**, and its `.dockerignore` sits in a
   directory Docker never reads.

## Constraints

- Local `npm run dev` must keep working unchanged. Developers should not need
  Vercel or Render to run the app.
- Secrets stay server-side. Only `VITE_`-prefixed values may enter the bundle,
  and those are public by definition.
- No hard-coded hostnames. The team supplies domains at deploy time.
- Minimal blast radius: routes, interview engine, and scoring stay untouched.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Persistence | Render Persistent Disk + `DATA_DIR` override | ~10-line change, keeps the proven JSON store, survives deploys. A Firestore migration was rejected for this pass as too large a behaviour-regression risk across every route. |
| Frontend → backend | Client calls Render directly via `VITE_API_BASE` | Vercel rewrites cannot proxy WebSockets, and impose a 4.5 MB body limit that would break résumé and logo uploads. |
| Domains | Fully env-configurable | No hostnames in git; custom domains later need no code change. |
| Server runtime | Keep `tsx` running TypeScript directly | Matches what runs today. Adding a server compile step is new, unproven build surface for no deployment benefit. `tsx` is promoted from a stray Docker layer to a real dependency. |
| SPA hosting | Static only, no Vercel functions | The API is entirely on Render. Vercel serves assets and the SPA fallback. |

### Rejected: proxy `/api` through Vercel rewrites

Attractive because it needs zero client changes, but it breaks the Voice Track,
the Deepgram relays, and the live interview transcription — Vercel rewrites do
not carry WebSocket upgrades. Splitting HTTP through a proxy while WebSockets go
direct would leave two inconsistent mechanisms and still cap uploads at 4.5 MB.

## Architecture

```
Vercel (static SPA)                     Render (Docker web service)
  root: talbotiq-platform/                root: talbotiq-platform/
  build: npm run build → dist/            dockerfile: server/Dockerfile
                                          health: /api/health
  VITE_API_BASE ───── HTTPS /api ───────▶ Express
                ───── WSS /api/voice ───▶   ├── Persistent Disk → /var/data
                                            └── Gemini, Tavus, Daily,
                                                Deepgram, Hume, AWS, Brevo
```

## Components

### `src/lib/apiOrigin.ts` (new)

The single place that knows where the backend lives.

- `httpBase(): string` — returns `${VITE_API_BASE}/api`, or `/api` when
  `VITE_API_BASE` is blank.
- `wsUrl(path: string): string` — returns a `ws://`/`wss://` URL against
  `VITE_API_BASE`'s host, or `location.host` when blank. Scheme follows the
  target's protocol, not the page's, so an `https://` API base yields `wss://`.

A blank `VITE_API_BASE` reproduces today's same-origin behaviour exactly, which
is what keeps the Vite dev proxy working.

### Client call sites (6 edits)

`api.ts` and `faceCache.ts` swap their literal bases for `httpBase()`.
`voiceClient.ts`, `useAudioAnalysis.ts`, `useDeepgramTranscript.ts`, and
`useAnswerRecorder.ts` swap `${proto}://${location.host}` for `wsUrl(...)`.

### `server/store/db.ts`

`DATA_DIR` env var overrides the hard-coded `server/data` path. Unset, behaviour
is identical to today. On Render it points at the mounted disk. The directory is
created if absent so a fresh disk seeds cleanly on first boot.

### `server/index.ts`

`CORS_ORIGINS` — comma-separated allowlist. Blank preserves the current
allow-all, so nothing breaks if the team forgets it; setting it locks the API to
the Vercel origin.

### Deployment files

- **`render.yaml`** (repo root) — Blueprint: Docker service, `talbotiq-platform`
  root, `/api/health` check, 1 GB disk mounted at `/var/data`, `DATA_DIR`
  preset. Every secret declared `sync: false` so Render prompts for values and
  none are committed.
- **`vercel.json`** — SPA fallback rewrite so deep links (`/login`, candidate
  invite URLs) do not 404; long-lived cache headers for hashed assets; basic
  security headers.
- **`server/Dockerfile`** — rewritten: pinned `node:20-slim`, `npm ci` without
  the `|| npm install` fallback that currently hides lockfile drift, non-root
  user, `PORT` honoured.
- **`talbotiq-platform/.dockerignore`** — moved from `server/.dockerignore`,
  which Docker never reads (it only honours the file at the build-context root).
  Today the entire `node_modules` tree ships as build context.
- **`package.json`** — `"engines": { "node": "20.x" }` so both platforms agree on
  a Node version; `tsx` moved to `dependencies`.

## Environment variables

Split three ways in the runbook, because most integrations degrade to a 503
rather than crashing — the team needs to know which gaps are fatal.

**Required for a working app**
`VITE_API_BASE` (Vercel), the six `VITE_FIREBASE_*` values (Vercel, public),
and `FIREBASE_PROJECT_ID` / `FIREBASE_CLIENT_EMAIL` / `FIREBASE_PRIVATE_KEY`
(Render — without these every auth-guarded endpoint returns 503).

**Required per feature** — absent, that feature alone fails:
`GEMINI_API_KEY` (AI questions/scoring; falls back to heuristics),
`DEEPGRAM_API_KEY` (live transcription), `DAILY_API_KEY` (two-way interview,
503 without), `TAVUS_API_KEY` (avatar fallback; normally set in the Settings
UI), `HUME_API_KEY`, `AWS_*` (Rekognition), `SMTP_*` + `MAIL_FROM` (invite
email; dry-runs without).

**Deployment-specific** — `DATA_DIR`, `CORS_ORIGINS`, `PORT` (Render sets it).

## Manual steps the code cannot do

These belong in the runbook because they are console actions, and each one
fails silently or confusingly if missed:

- Add the Vercel domain to **Firebase Auth → Authorized domains**, or every
  login fails with `auth/unauthorized-domain`.
- Choose a paid Render instance. The free tier has no persistent disks and
  idles out after 15 minutes, producing ~50 s cold starts mid-interview.
- Point the Brevo webhook at the Render URL if delivery tracking is wanted.

## Verification

Automated in this repo:
- `npm run build` passes (`tsc` + `vite build`).
- Server boots and `GET /api/health` returns `{ ok: true }`.
- No secret material in `dist/` — grep for `AIza`, `GEMINI_API_KEY`, and the
  other key patterns.
- A blank `VITE_API_BASE` still produces same-origin URLs (dev-proxy parity).

**Not verifiable here:** the Docker image cannot be built or run — Docker is not
installed in this environment. The Dockerfile is therefore kept conservative and
must get one real build on Render before the team treats it as proven.

## Out of scope

Firestore migration, CI/CD pipelines, the Capacitor/Play Store path, autoscaling
(the disk pins the service to one instance), and any interview-feature change.
