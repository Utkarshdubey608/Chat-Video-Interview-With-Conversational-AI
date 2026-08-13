# Deploying TalbotIQ — Vercel (frontend) + Render (backend)

The SPA is static on Vercel. The Express API, including its WebSockets, runs on
Render. The SPA reaches the API directly via `VITE_API_BASE` — nothing proxies
through Vercel.

**Deploy Render first.** The frontend build needs the API's URL.

## Prerequisites

- A Render account on a **paid instance type**. The free tier has no Persistent
  Disks and idles out after 15 minutes (~50s cold start), which is unacceptable
  mid-interview.
- A Vercel account.
- A Firebase service-account JSON for project `talbotiq-9cc4e`
  (Firebase console → Project settings → Service accounts → Generate new private key).

## Step 1 — Deploy the API to Render

1. **New → Blueprint**, select this repository. Render reads `render.yaml` and
   proposes the `talbotiq-api` service with a 1 GB disk at `/var/data`.
2. Fill in the prompted env vars (see the table below). At minimum set the three
   `FIREBASE_*` values, or every auth-guarded endpoint returns 503.
   - `FIREBASE_PRIVATE_KEY` must be **one line** with newlines escaped as `\n`.
     Copy it from the service-account JSON exactly as it appears there.
3. Deploy, then confirm: `curl https://<your-service>.onrender.com/api/health`
   → `{"ok":true,...}`. The `auth` field is `true` once Firebase Admin is configured.
4. Copy the service URL — Step 2 needs it.

The Blueprint sets `autoDeploy: false`. Turn it on in the dashboard once you are
happy with manual deploys.

## Step 2 — Deploy the SPA to Vercel

1. **Add New → Project**, import this repository. `vercel.json` at the root sets
   the build command, install command, and output directory; leave the
   framework preset as **Other**.
2. Set the environment variables from the *Vercel* table below.
   `VITE_API_BASE` is the Render URL from Step 1, **with scheme, no trailing
   slash**: `https://talbotiq-api.onrender.com`.
3. Deploy, then open the site and confirm the browser devtools Network tab shows
   `/api/...` requests going to the Render host.

## Step 3 — Close the loop

1. **Restrict CORS.** In Render, set `CORS_ORIGINS` to the Vercel URL
   (e.g. `https://talbotiq.vercel.app`) and redeploy. Multiple origins are
   comma-separated. Leaving it blank allows every origin.
2. **Authorize the domain in Firebase.** Firebase console → Authentication →
   Settings → **Authorized domains** → add the Vercel domain. **Skip this and
   every login fails with `auth/unauthorized-domain`**, even though both
   deployments look healthy.
3. **Brevo webhook (only if you want delivery tracking).** Point it at
   `https://<render-url>/api/invites/brevo-webhook?token=<BREVO_WEBHOOK_SECRET>`.

## Environment variables

### Render (the API) — secrets live here

**Required for a working app**

| Var | Notes |
|---|---|
| `FIREBASE_PROJECT_ID` | `talbotiq-9cc4e` |
| `FIREBASE_CLIENT_EMAIL` | From the service-account JSON |
| `FIREBASE_PRIVATE_KEY` | One line, newlines as `\n`. Without these, auth-guarded endpoints return 503 |

**Set by the Blueprint — do not change**

| Var | Value |
|---|---|
| `NODE_ENV` | `production` |
| `DATA_DIR` | `/var/data` — the mounted disk. Changing it loses your data |
| `PORT` | Injected by Render |

**Per feature — absent, only that feature degrades**

| Var | Without it |
|---|---|
| `CORS_ORIGINS` | All origins allowed |
| `GEMINI_API_KEY` | AI question generation and scoring fall back to heuristics |
| `GEMINI_MODEL`, `GEMINI_LIVE_MODEL` | Defaults applied by the Blueprint |
| `DEEPGRAM_API_KEY` | No live speech-to-text |
| `HUME_API_KEY` | No voice prosody analysis |
| `TAVUS_API_KEY` | Deployment-wide fallback only; normally set in the Settings UI |
| `DAILY_API_KEY` | Two-way interview returns 503 |
| `DAILY_SUBDOMAIN` | Optional display convenience |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` | No Rekognition facial analysis |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `MAIL_FROM` | Invite email dry-runs (logs instead of sending) |
| `BREVO_API_KEY` | Recruiters type the sender manually instead of picking |
| `BREVO_WEBHOOK_SECRET` | No delivery tracking |
| `ADMIN_EMAILS` | No admin overlay for legacy sessions |

### Vercel (the SPA) — public values only

Everything here is compiled into the bundle and is readable by anyone. **Never
put a secret in a `VITE_` variable.**

| Var | Value |
|---|---|
| `VITE_API_BASE` | The Render URL, e.g. `https://talbotiq-api.onrender.com` (no trailing slash) |
| `VITE_FIREBASE_API_KEY` | From `.env.example` — public by design |
| `VITE_FIREBASE_AUTH_DOMAIN` | `talbotiq-9cc4e.firebaseapp.com` |
| `VITE_FIREBASE_PROJECT_ID` | `talbotiq-9cc4e` |
| `VITE_FIREBASE_STORAGE_BUCKET` | `talbotiq-9cc4e.firebasestorage.app` |
| `VITE_FIREBASE_MESSAGING_SENDER_ID` | `473028554722` |
| `VITE_FIREBASE_APP_ID` | `1:473028554722:web:152baa837fe77c7fb713bb` |

## Verifying a deployment

```bash
# API is up
curl https://<render-url>/api/health

# CORS allows the Vercel origin (expect access-control-allow-origin in the response)
curl -si -H "Origin: https://<vercel-domain>" https://<render-url>/api/health | grep -i access-control

# No secret leaked into the bundle — expect no output
npm run build && grep -r "GEMINI_API_KEY\|DEEPGRAM_API_KEY\|FIREBASE_PRIVATE_KEY" dist/
```

In the app itself: sign in (proves Firebase Auth + authorized domains), open a
Voice Track interview (proves the WebSocket reached Render), and create a
template then redeploy the Render service (proves the disk persisted it).

## Operational notes

- **The disk pins the service to one instance.** `server/store/db.ts` is a JSON
  file, not a database — two instances would overwrite each other. Do not enable
  horizontal scaling. Deploys briefly interrupt service.
- **Back up the data** by downloading `/var/data/db.json` from the Render shell
  before risky changes.
- **WebSocket origin is not filtered.** `CORS_ORIGINS` governs HTTP only; the
  `ws` upgrade path authenticates by Firebase ID token in the query string
  instead.
- To scale beyond one instance, migrate `server/store/db.ts` to Firestore —
  `firebase-admin` is already a dependency. See `docs/DEPLOYMENT.md`.
