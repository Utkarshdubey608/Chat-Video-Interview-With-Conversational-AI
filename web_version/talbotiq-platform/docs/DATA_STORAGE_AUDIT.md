# Data Storage Audit & Migration Plan — TalbotIQ / MIMIC

**Date:** 12 August 2026 · **Method:** read-only code + config trace (no assumptions, no vendor docs)
**Status:** Audit is read-only. Two small hardening fixes have since shipped (below); **no migration has been performed** and no data has been moved or deleted.
**Branch audited:** `feat/mimic-marketing-site`

### Shipped since the audit (12 Aug 2026)

Both are cloud-independent items from the plan, verified by `npm test` (34 files), `tsc`, and a production build:

| Change | Files | Addresses |
|---|---|---|
| **`db.json` writes are now atomic** (temp file + `renameSync`) and **save failures are observable** via `db.saveHealth()`, surfaced on `/api/health` as `persistence` | [`server/store/db.ts`](../server/store/db.ts), [`server/index.ts`](../server/index.ts), new [`server/store/db.atomicsave.test.ts`](../server/store/db.atomicsave.test.ts) | The silent-data-loss mode described in Part 0. A crash or full disk can no longer truncate the snapshot, and a failing disk is now visible instead of silent. `/api/health` deliberately still returns **200** — see the comment there for why a data-integrity signal must not drive a liveness probe. |
| **`awsKey` / `anthropicKey` removed** from the client store entirely — fields, setters, and `localStorage` persistence | [`src/store/useAppStore.ts`](../src/store/useAppStore.ts) | Part of finding #4 / Phase 1. Both were **dead** (no consumer anywhere outside the store), so they were persisting secrets to `localStorage` for no functional reason. Confirmed absent from `dist/`. |

⚠️ **`tavusKey` is still client-side** — it has a real consumer ([`src/services/tavus.ts:19`](../src/services/tavus.ts#L19) calls `tavusapi.com` directly from the browser). Removing it requires the server proxy in Phase 1, so it is left in place with a `TODO(phase-1)` at the call site. Finding #4 is therefore **partially** addressed, not closed.

---

# Part 0 — Verdict up front

The platform runs on **two parallel databases that do not know about each other**, plus a **single JSON file on local disk** that holds nearly all interview data.

| # | Finding | Severity |
|---|---|---|
| 1 | All interview data lives in **one JSON file** rewritten wholesale on a 400 ms debounce | 🔴 Blocks scale |
| 2 | **Cannot run more than one server instance.** Two instances = two divergent `db.json` files, no shared state | 🔴 Blocks scale |
| 3 | **Tavus + Gemini API keys stored in plaintext** in that same JSON file | 🔴 Security |
| 4 | **Recruiter's Tavus API key sits in browser `localStorage`** and is sent browser→`tavusapi.com` directly | 🔴 Security |
| 5 | Templates and Question Sets have **no owner filter** — every recruiter sees every other recruiter's | 🔴 Tenancy |
| 6 | `db.settings` is **global, not per-recruiter** — one Tavus/Gemini key for the entire deployment | 🔴 Tenancy |
| 7 | Video recordings in Firebase Storage with **no retention or lifecycle rule** | 🟠 Compliance |
| 8 | Live voice-interview state is **in-process memory** — a restart mid-interview loses the session | 🟠 Reliability |
| 9 | Analytics recomputed by **full in-process scan of every report** on each request | 🟠 Scale |
| 10 | Storage download URLs are **tokenised and bypass `storage.rules`** — link-holder = access | 🟠 Security |

**The single most important structural fact:** `server/store/db.ts` is an in-memory `Map` set persisted by `fs.writeFileSync` of the entire snapshot. It is explicitly self-described as *"Not a production database."* Everything in Part 2 follows from replacing it.

### ✅ Deployment reality check — resolved from `render.yaml` (added 12 Aug 2026)

An earlier draft of this audit warned that deploys might be destroying `db.json`. **That alarm is false, and the config proves it.** [`render.yaml`](../../render.yaml) already does the right thing:

```yaml
plan: starter          # paid tier — free tier has NO persistent disks
disk:
  name: talbotiq-data
  mountPath: /var/data
  sizeGB: 1
envVars:
  - key: DATA_DIR
    value: /var/data
```

So `db.json` **does** survive deploys and restarts. Three qualifications remain:

1. **Only if the service was created from the blueprint.** If someone provisioned `talbotiq-api` by hand in the Render dashboard instead of via "New → Blueprint", `DATA_DIR` may be unset and the disk absent. This is the one thing still worth confirming in the console — but it is a narrow check, not an emergency.
2. 🔴 **The disk pins the service to ONE instance.** `render.yaml` says so in its own comment: *"a disk pins this service to a single instance — do not scale it out."* This is finding #2 confirmed at the infrastructure layer, and it means **horizontal scale requires leaving Render or dropping the disk** — a platform migration that Part 2 must schedule explicitly (see §2.3 Phase 0.5).
3. ⚠️ **The face-cache does NOT use `DATA_DIR`.** [`faceCache.ts:26`](../server/routes/faceCache.ts#L26) hardcodes `path.join(here, '..', 'data', 'face-cache')` — relative to the server module, *not* the mounted volume. So replica previews land on the **container's ephemeral layer** and are wiped on every deploy, while `db.json` persists. The "instant picker" benefit therefore resets each deploy, and the cache competes for container ephemeral storage rather than the 1 GB volume. Two different disks, one of them silently ephemeral.

**Why this matters beyond the correction:** `db.saveNow()` swallows write failures with a bare `console.error` ([db.ts:134](../server/store/db.ts#L134)). Any condition that makes the volume unwritable — full disk, permissions — produces **silent data loss**, not a crash. That failure mode is worth an alert regardless of which disk is involved.

---

# PART 1 — AUDIT

## 1.1 Architecture as it actually is

```
┌──────────────────────── BROWSER (SPA, Vercel) ─────────────────────────┐
│  localStorage "talbotiq-store" (zustand persist)                       │
│    ⚠️ tavusKey ⚠️ awsKey ⚠️ anthropicKey, webhookUrl,                  │
│       defaultReplicaId/PersonaId, questions, drafts                    │
│  Firebase Web SDK ──────────────► Firestore users/{uid} (role read)    │
│                     ──────────────► Storage interviews/{id}/two-way.webm│
│  ⚠️ direct call, key from localStorage ──► tavusapi.com (x-api-key)    │
└───────────────┬────────────────────────────────────────────────────────┘
                │ /api/* + Bearer ID token
┌───────────────▼──────────── EXPRESS API (Render, single instance) ─────┐
│                                                                        │
│  ┌── server/data/db.json ──────────── LOCAL DISK, SINGLE FILE ──────┐  │
│  │  templates · questionSets · sessions · reports · pipelines ·      │  │
│  │  pipelineCandidates · inviteEmailTemplates · leads · users(dead)  │  │
│  │  settings{ ⚠️ tavusApiKey, ⚠️ geminiApiKey, avatar{⚠️tavusKey} }  │  │
│  │  → sessions carry: transcript, resumeText, facialSummary,         │  │
│  │    recordingUrl, integrityEvents, manualReview                    │  │
│  │  PERSISTENCE: only if DATA_DIR → real disk. NOT shared. NOT       │  │
│  │  encrypted. Full-file rewrite, 400 ms debounce.                   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌── server/data/face-cache/*.mp4 ── LOCAL DISK, unbounded ─────────┐  │
│  │  Tavus replica preview MP4s, ≤150 MB each, never evicted          │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌── IN-PROCESS MEMORY (lost on restart, not shared) ───────────────┐  │
│  │  voice.ts    runtimes      live voice session state + transcript  │  │
│  │  avatar.ts   voiceJobs     Hume/Gemini prosody jobs, 1 h TTL      │  │
│  │  sessions.ts scoringInFlight, pendingQuestionGen                  │  │
│  │  mimicGuideTts cache(40), inFlight   ·  faceCache inflight        │  │
│  │  deepgramRelay per-socket queue  ·  gemini clients                │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└──┬──────────────┬──────────────────────────────────────────────────────┘
   │              │ Firebase Admin SDK (bypasses security rules)
   │              ▼
   │   ┌── FIRESTORE talbotiq-9cc4e (SHARED with Flutter app) ─────────┐
   │   │  users/{uid}            role — authority for authz            │
   │   │  interviews/{id}        invites, status, attemptsUsed,         │
   │   │                         result{}, resultPublished, invite{}    │
   │   │  recruiter_keys/{id}    ⚠️ ANY signed-in user may read (rules) │
   │   └────────────────────────────────────────────────────────────────┘
   │   ┌── FIREBASE STORAGE ───────────────────────────────────────────┐
   │   │  interviews/{sessionId}/two-way.webm   ⚠️ no lifecycle rule    │
   │   │  invite_email_logos/{uid}/{uuid}.ext   ⚠️ public tokenised URL │
   │   └────────────────────────────────────────────────────────────────┘
   ▼
THIRD PARTIES (data leaves the platform)
   Tavus     avatar media + transcript; FULL VIDEO if enableRecording=true
   Daily     WebRTC transport only — rooms exp 4 h, deleted on complete
   Deepgram  live audio stream + two-way recording bytes → transcript
   Hume      prosody audio (in-memory upload, never on disk)
   AWS Rekognition   per-frame base64 JPEG → face metadata (frames transient)
   Google Gemini     transcripts, résumé text, prosody audio, TTS
   Brevo     invite email delivery + webhook events
```

## 1.2 Master data inventory

Legend — **Persistence:** ✅ durable · ⚠️ conditional · ❌ ephemeral (lost on restart/redeploy) · 🔀 not shared across instances

| Data type | Written / read at | Exact store | Shape | Persists? | Sensitive |
|---|---|---|---|---|---|
| **Two-way: live session** | `dailyServer.ts:47-83` | Daily API (rooms + meeting tokens) | room name/URL, JWT token | Transport only — room `exp` 4 h, `deleteRoom` on complete | — |
| **Two-way: recording** | `LiveInterviewPage.tsx:130` → `storage.ts:45` | **Firebase Storage** `interviews/{sessionId}/two-way.webm` | WebM blob, recruiter-recorded client-side | ✅ **forever — no lifecycle rule** | 🔴 video+audio, both faces |
| **Two-way: recordingUrl** | `sessions.ts:635` | `db.json` → `session.recordingUrl` | tokenised HTTPS URL | ⚠️ | 🟠 bearer-equivalent |
| **Two-way: transcript** | `transcription.ts:29-39` | `db.json` → `session.transcript[]` | `{role, content, at, turnType}` | ⚠️ | 🟠 |
| **Two-way: manual review** | `session.manualReview` | `db.json` | `{rating, notes, by, at}` | ⚠️ | 🟠 |
| **Avatar (Tavus): media** | `AvatarStage.tsx` iframe | **Tavus infrastructure** — never touches our servers | video/audio stream | Tavus-side; **full video stored only if `enableRecording`** (`SetupPage.tsx:474`, default off) | 🔴 |
| **Avatar: transcript** | `tavusServer.ts:153` pull + `sessions.ts:424` live bridge | `db.json` → `session.transcript[]` | turn array | ⚠️ | 🟠 |
| **Avatar: conversation id** | `sessions.ts:363` | `db.json` → `session.tavusConversationId` | string | ⚠️ | — |
| **Facial analysis (Rekognition)** | frames `rekognitionService.ts:128` → `sessions.ts:791`; summary `sessions.ts:810` | frames **transient in memory** (`Image.Bytes`, never written); summary → `db.json` `session.facialSummary` | opaque `{perQuestion[]}` | frames ❌ / summary ⚠️ | 🔴 **biometric-derived** |
| **Prosody / EI (Hume)** | `avatar.ts:190-219` | audio: `multer.memoryStorage()` 25 MB, never on disk; job: **in-memory `voiceJobs`** 1 h TTL | `{begin,end,emotions[{name,score}]}` | ❌ **both** | 🔴 **biometric-derived** |
| **Gemini analysis / scores** | `sessions.ts` `maybeScore` | `db.json` → `db.reports` (keyed `sessionId`) | `ResultReport` — perQuestion, kpiAverages, overallScore, summary, strengths, improvements, recommendation, sentiment | ⚠️ | 🟠 |
| **Video track: webcam video** | `VideoStage.tsx:38-44` | **NOWHERE — never recorded or uploaded.** Camera is preview only; live audio → Deepgram → transcript text | — | n/a | — |
| **Video track: transcript** | `sessions.ts:764-770` | `db.json` → `session.transcript[]` | turns | ⚠️ | 🟠 |
| **Voice track: live state** | `voice.ts:202` `runtimes` | **in-process memory** — pending turns, timers, flow | `VoiceRuntime` | ❌ 🔀 **restart mid-interview = lost** | 🟠 |
| **Voice track: audio** | `voice.ts` WS → Gemini Live | streamed, **never stored** | PCM | n/a | — |
| **Voice/Chatbot: transcript** | `conversation.ts` → session | `db.json` → `session.transcript[]` | turns (cap 800) | ⚠️ | 🟠 |
| **Résumé: uploaded file** | `sessions.ts:225` multer memory | **discarded after parse** — PDF/DOCX/TXT never written | — | n/a | — |
| **Résumé: parsed text** | `resume.ts` → `sessions.ts:242` | `db.json` → `session.resumeText` (20 000 char cap) | plain text | ⚠️ | 🔴 **PII, plaintext** |
| **Question Sets** | `questionSets.ts:98` | `db.json` → `db.questionSets` | `{id,name,questions[]}` | ⚠️ | ⚠️ **no owner field — global** |
| **Templates** | `templates.ts:60` | `db.json` → `db.templates` | timing, rubric, integrity, branding, adaptive, voice | ⚠️ | ⚠️ **no owner filter — global** |
| **Sessions** | `sessions.ts` throughout | `db.json` → `db.sessions` | `InterviewSession` (see §1.3) | ⚠️ | 🔴 aggregates everything |
| **Interviews / invites** | `invites.ts:181`, `interviewInvite.ts:127` | **Firestore** `interviews/{id}` | role, candidateEmailLower, recruiterId, mode, screening, questions[], status, attemptsUsed, result{}, resultPublished, invite{} | ✅ | 🟠 candidate PII |
| **Invite links** | `invites.ts` | link = unguessable Firestore doc id, emailed | URL | ✅ (implicit) | 🟠 bearer-ish |
| **Pipelines / rounds** | `pipelines.ts:186,239,320` | `db.json` → `db.pipelines`, `db.pipelineCandidates` | rounds[], per-candidate progression | ⚠️ | 🟠 |
| **Analytics / KPI aggregates** | `analytics.ts:89-174` | **computed on demand, nothing stored** — full scan of `db.reports` per request | Maps built per call | ❌ by design | — |
| **Integrity events** | `sessions.ts:823-829` | `db.json` → `session.integrityEvents[]`, `tabSwitchCount` | `{type, at}` | ⚠️ | 🟠 behavioural |
| **Candidate emails (bulk extract)** | `inviteExtract.ts` → `invites.ts` | Firestore `interviews/{id}.candidateEmailLower` | email + name | ✅ | 🟠 |
| **Brevo config** | `.env` | env vars `SMTP_*`, `BREVO_API_KEY`, `BREVO_WEBHOOK_SECRET` | secrets | ✅ (env) | 🔴 |
| **Invite email templates** | `inviteEmailTemplates.ts:73,103` | `db.json` → `db.inviteEmailTemplates` | subject/body/branding, `recruiterId` owner | ⚠️ | ✅ **only genuine per-recruiter model in the app** |
| **Invite email logos** | `invites.ts:304-326` | **Firebase Storage** `invite_email_logos/{uid}/{uuid}.ext` via Admin SDK | image ≤2 MB | ✅ | ⚠️ **deliberately public** tokenised URL (email clients must load it) |
| **Email send logs** | `invites.ts:280-286`, `brevoWebhook.ts:73-90` | Firestore `interviews/{id}.invite` | `{status, attempts, sentAt, error}` | ✅ | — |
| **Marketing leads** | `leads.ts:46` | `db.json` → `db.leads[]` | name, email, hiresPerYear, source | ⚠️ | 🟠 PII, **public unauthenticated endpoint** |
| **Users / roles** | `firebaseAdmin.ts:128-135` | **Firestore** `users/{uid}.role` — sole authority | `{role, name}` | ✅ | — |
| **`db.users`** | `services/users.ts:41` read only | `db.json` — **never written; vestigial** | `AppUser` | ⚠️ dead | — |
| **Recruiter API keys (Flutter)** | `firestore.rules` | Firestore `recruiter_keys/{recruiterId}` | provider keys | ✅ | 🔴 **rules allow ANY signed-in user to read** |
| **Recruiter API keys (web)** | `settings.ts:66-91` | `db.json` → `db.settings.tavusApiKey`, `.geminiApiKey`, `.avatar.tavusKey` | plaintext strings | ⚠️ | 🔴 **plaintext, global, unencrypted** |
| **Client-held keys** | `useAppStore.ts:193-202` | **browser localStorage** | `tavusKey`, `awsKey`, `anthropicKey` | ✅ browser | 🔴 **`tavusKey` actively used browser→Tavus (`tavus.ts:19`)**; `awsKey`/`anthropicKey` persisted but no live consumer found — vestigial |
| **Server secrets** | `.env` | env vars | GEMINI, DEEPGRAM, HUME, AWS, DAILY, FIREBASE_PRIVATE_KEY, SMTP | ✅ (env) | 🔴 — no Secret Manager |
| **Firebase web config** | `.env` `VITE_*` | **client bundle** | apiKey, projectId, bucket… | ✅ | ✅ **public by design — correct, not a leak** |
| **Replica preview cache** | `faceCache.ts:45-69` | **local disk** `server/data/face-cache/*.mp4` | MP4 ≤150 MB each | ⚠️ 🔀 unbounded, never evicted | — (stock avatars, not candidates) |
| **Guide TTS cache** | `mimicGuideTts.ts:68-73` | in-memory, 40 entries | base64 audio | ❌ | — |
| **Job queue** | — | **none exists.** `voiceJobs` is a bare `Map`; no Pub/Sub, no Cloud Tasks, no Redis | — | ❌ | — |

## 1.3 The `db.json` snapshot — exact contents

From `Snapshot` in [`server/store/db.ts:52-63`](../server/store/db.ts#L52-L63):

```
templates[] · questionSets[] · sessions[] · reports[] · users[] ·
settings{} · inviteEmailTemplates[] · pipelines[] · pipelineCandidates[] · leads[]
```

Mechanics that matter for scale:

- **Load:** `fs.readFileSync` once at boot (`init()`), hydrated into `Map`s.
- **Save:** `scheduleSave()` → 400 ms debounce → `saveNow()` serialises **the entire snapshot** and `writeFileSync`s it. Cost grows linearly with total data; a large store means every small mutation rewrites megabytes.
- **Crash window:** up to 400 ms of accepted mutations are unflushed at any moment. A crash loses them silently — errors are `console.error`'d only (`db.ts:134`).
- **Location:** `DATA_DIR` env, else `server/data/`. The code comment is explicit: *"Container filesystems are ephemeral: without this the snapshot is lost on every deploy and restart."*
- **Concurrency:** no locking, no atomic rename (unlike `faceCache.ts`, which *does* write-then-rename). Two processes writing = last-write-wins corruption.

## 1.4 Explicitly flagged — local / ephemeral / not shared

| Item | Location | Lost on redeploy? | Shared across instances? |
|---|---|---|---|
| `db.json` — **all** app data | Render persistent disk `/var/data` | ✅ **No** — `DATA_DIR` is set correctly in `render.yaml` | ❌ **No** — and the disk *pins the service to 1 instance* |
| `face-cache/*.mp4` | container ephemeral layer — **ignores `DATA_DIR`** ([faceCache.ts:26](../server/routes/faceCache.ts#L26)) | **Yes** — wiped every deploy | ❌ No |
| `runtimes` — live voice sessions | memory | Yes — **mid-interview data loss** | ❌ No |
| `voiceJobs` — prosody jobs | memory | Yes — client gets `FAILED` "server restarted?" (`avatar.ts:229`) | ❌ No |
| `scoringInFlight`, `pendingQuestionGen` | memory | Yes — **dedup guards fail across instances → double scoring / double question generation** | ❌ No |
| `mimicGuideTts` cache | memory | Yes (benign, re-synthesises) | ❌ No |
| Analytics aggregates | recomputed per request | n/a | n/a — but **O(all reports) per call** |
| Browser `localStorage` | client | No | Per-device only |

**Consequence:** the app **cannot be horizontally scaled today.** Multiple instances would produce divergent `db.json` files, duplicate Gemini scoring calls, and voice sessions that break whenever the load balancer routes a candidate to a different instance.

## 1.5 Explicitly flagged — public / unencrypted / secrets in client

| Issue | Detail | Where |
|---|---|---|
| 🔴 **Tavus key in the browser** | Persisted to `localStorage` and sent as `x-api-key` in direct browser→`tavusapi.com` calls. Any XSS, any shared machine, any devtools read = key theft. | `useAppStore.ts:197`, `tavus.ts:9-19` |
| 🔴 **API keys in plaintext on disk** | `tavusApiKey`, `geminiApiKey`, `avatar.tavusKey` written into `db.json` as readable strings. Anyone with disk/backup/log access reads them. | `settings.ts:66-91`, `db.ts:133` |
| 🔴 **PII in plaintext on disk** | Résumé text, full transcripts, candidate names/emails in the same unencrypted file. | `db.ts` snapshot |
| 🔴 **`recruiter_keys` readable by any signed-in user** | `allow read: if isSignedIn()` — the rules file itself calls this *"App-side hiding, not cryptographic secrecy."* | `firestore.rules` |
| 🟠 **Tokenised Storage URLs bypass rules** | `getDownloadURL()` returns a token that grants access regardless of `storage.rules`. Whoever holds the link plays the recording. | `storage.ts:52`, `storage.rules:6-8` |
| 🟠 **No retention anywhere** | No lifecycle rule on Storage, no TTL on `db.json`. Recordings and transcripts accumulate indefinitely. | — |
| 🟠 **Public unauthenticated write** | `/api/leads` accepts POSTs from anyone (by design, for the marketing form) and appends to `db.json`. No rate limit found. | `index.ts:57`, `leads.ts:46` |
| ✅ **Firebase web config in the bundle is fine** | `VITE_FIREBASE_*` values are public identifiers, not secrets — correctly documented as such. | `.env.example` |
| ✅ **Candidate-facing keys correctly server-side** | Deepgram is minted as a 30 s token; Hume/Gemini/Rekognition/Daily/Tavus-for-candidates are all server-proxied. This part of the design is sound. | `avatar.ts:54-65`, `dailyServer.ts` |

## 1.6 Tenancy findings

The app is effectively **single-tenant while presenting as multi-tenant**:

| Model | Ownership | Cross-recruiter leak? |
|---|---|---|
| Templates | none | 🔴 **Yes** — `templates.ts:20` lists all |
| Question Sets | none | 🔴 **Yes** — `questionSets.ts:40` lists all |
| `db.settings` (Tavus/Gemini keys, avatar config) | global singleton | 🔴 **Yes** — one config for the whole deployment |
| Sessions | `recruiterId` | ✅ enforced |
| Pipelines | `owns()` | ✅ enforced |
| Invite email templates | `recruiterId`, server-stamped, immutable | ✅ enforced |

The `inviteEmailTemplates.ts:3` header states it is *"the ONLY genuine per-recruiter model in this app"* — the code agrees with this finding.

---

# PART 2 — MIGRATION PLAN (proposal only — not implemented)

## 2.1 Target architecture

```
SPA (Vercel) ── ID token ──► API (Cloud Run, N instances, stateless)
                                 │
   ┌─────────────────────────────┼──────────────────────────────┐
   ▼              ▼              ▼              ▼              ▼
FIRESTORE     CLOUD STORAGE   MEMORYSTORE    PUB/SUB +      BIGQUERY
structured    media, signed   cache, locks,  CLOUD TASKS    transcripts,
app data      URLs, lifecycle live state     async jobs     events, costs
tenant-keyed  CMEK + retention
                                 ▲
                          SECRET MANAGER
                    every provider key, server-only
```

Invariant: **no critical state on local disk or in one instance's memory.**

## 2.2 Migration table

| # | Data | Current | Target | Why | Retention / sensitivity | Approach |
|---|---|---|---|---|---|---|
| 1 | Provider API keys (Tavus, Gemini) | `db.json` plaintext + browser `localStorage` | **Secret Manager**, per-tenant secret versions | Keys in a JSON file and a browser are the sharpest edge here | Rotate on migrate — treat all current keys as compromised | Add `secrets.ts` resolver; remove `tavusKey` from `partialize`; route recruiter Setup/Replicas through the existing `/api/avatar/*` proxy pattern |
| 2 | `recruiter_keys` Firestore collection | any signed-in user can read | **Secret Manager**; tighten rule to owner-only | Rules self-describe as non-secret | Coordinate with the Flutter app — shared backend | Rule change first (cheap, reversible), then migrate values |
| 3 | Sessions | `db.json` | **Firestore** `tenants/{recruiterId}/sessions/{id}` | Core blocker — enables N instances | Define TTL (e.g. 12–24 mo); transcripts + `resumeText` are PII | Repository interface behind current `db.sessions` call sites; dual-write, verify, cut over |
| 4 | Reports / scores | `db.json` `db.reports` | **Firestore** `…/reports/{sessionId}` + **BigQuery** mirror for analytics | Firestore for live reads, BigQuery for aggregation | Same TTL as sessions | Same repository pattern; stream to BQ on write |
| 5 | Templates | `db.json`, **unowned** | **Firestore** `tenants/{recruiterId}/templates/{id}` | Fixes tenancy leak *and* durability together | — | ⚠️ Needs a **backfill owner decision** — see §2.5 |
| 6 | Question Sets | `db.json`, **unowned** | **Firestore**, tenant-keyed + optional shared library | Same | — | Same; consider an explicit `shared: true` flag for seed sets |
| 7 | Pipelines / candidates | `db.json` | **Firestore**, tenant-keyed | Durability + tenancy | — | Already has `owns()` — mechanical move |
| 8 | Invite email templates | `db.json` | **Firestore**, tenant-keyed | Durability | — | Cleanest migration — ownership model already correct |
| 9 | Marketing leads | `db.json` | **Firestore** `leads/{id}` (server-only writes) | Durability; add rate limiting | PII — define deletion policy | Keep endpoint public; add Cloud Armor / rate limit |
| 10 | `db.settings` | global singleton | **Firestore** `tenants/{id}/settings` + keys in Secret Manager | Removes the cross-tenant config leak | — | Per-recruiter split is a **behaviour change** — needs sign-off |
| 11 | Two-way recordings | Storage, no lifecycle | **Cloud Storage** + **lifecycle rule** + **signed URLs** (replace tokenised) + CMEK | Retention is both a compliance and a cost problem | 🔴 Biometric-adjacent. Set explicit retention (30–90 d suggested) | Add lifecycle rule **first** (no code change); swap `getDownloadURL` → server-minted signed URL |
| 12 | Résumé raw files | discarded | **Cloud Storage** `resumes/{tenant}/{sessionId}` *only if* raw retention is wanted | Currently fine — flagging as a decision, not a defect | If adopted: short TTL, encrypted | Only if product needs it. Otherwise **keep discarding** — the safest option |
| 13 | Résumé parsed text | `db.json` plaintext | **Firestore** field, or Storage if large | Durability | 🔴 PII — consider field-level encryption | Moves with sessions (#3) |
| 14 | Face-cache MP4s | local disk, unbounded | **Cloud Storage** + CDN, or **drop entirely** | Not durable, not shared, unbounded | Stock avatars — low sensitivity | Cheapest correct fix: serve Tavus CDN directly with a CDN in front; delete the local cache path |
| 15 | Live voice state (`runtimes`) | in-process memory | **Memorystore (Redis)** for turn state; keep WS pinned | Restart mid-interview currently loses the session | Short TTL (session length) | Hardest item — needs care. Interim: session affinity + graceful drain |
| 16 | Prosody jobs (`voiceJobs`) | in-memory Map, 1 h TTL | **Cloud Tasks / Pub/Sub** + job doc in Firestore | Survives restarts; enables retry | Audio stays transient — do not persist raw audio | Job doc + worker; client already polls, so the contract is unchanged |
| 17 | `scoringInFlight`, `pendingQuestionGen` | in-memory guards | **Redis distributed lock** | These guards **silently fail** across instances → duplicate Gemini spend | — | Required before scaling to N>1 |
| 18 | Guide TTS cache | in-memory 40 entries | **Memorystore**, or Storage with CDN | Cheap win, cuts duplicate Gemini spend | — | Low priority |
| 19 | Analytics | full in-process scan per request | **BigQuery** + scheduled rollups | O(all reports) per call will not hold | Aggregate/anonymised | Stream reports to BQ; repoint `/api/analytics` at rollup tables |
| 20 | Integrity events | `session.integrityEvents[]` | **BigQuery** events table | Append-only telemetry doesn't belong in the app record | Behavioural data — retention policy needed | Dual-write, then trim from session doc |
| 21 | Cost / provider-spend logs | none | **BigQuery** | No per-tenant AI cost visibility today | — | New capability, not a migration |
| 22 | Server env secrets | `.env` / Render env | **Secret Manager** + workload identity | Removes `FIREBASE_PRIVATE_KEY` from env | 🔴 | Do alongside #1 |

## 2.3 Phased order — lowest risk first

**Phase 0 — Stop the bleeding (no code changes, do today)**
1. ✅ **`DATA_DIR` is already correct** — verified in `render.yaml` (see the Deployment reality check in Part 0). The only residual check: confirm the live `talbotiq-api` service was created **from the blueprint**, not by hand.
2. Back up `db.json` off-box; schedule recurring backups. **Still required** — a persistent disk is not a backup, and write failures are silent.
3. **Rotate** the Tavus, Gemini, Deepgram, Hume, AWS and Daily keys — assume plaintext exposure.
4. Add a Firebase Storage **lifecycle rule** on `interviews/**` (console-only change).
5. Confirm Firestore/Storage **region** matches intended data residency. Note Render runs in `oregon` and `AWS_REGION` defaults to `us-east-2` — both US.
6. Add an **alert on `[db] save failed`** log lines. Silent data loss is the failure mode that a persistent disk does *not* protect against.

**Phase 0.5 — Platform decision (NEW — blocks Phase 4, must be decided before Phase 1)**
The audit's target architecture assumes **Cloud Run**, but the app deploys to **Render + Vercel** today (`render.yaml`, `vercel.json`). Render's persistent disk *pins the API to a single instance by design*, so **N>1 is unreachable on the current platform regardless of what Phase 4 does.** Either:
- **(a) Migrate the API to Cloud Run** — unlocks autoscaling, Workload Identity (removes `FIREBASE_PRIVATE_KEY` entirely, since [`firebaseAdmin.ts:43-45`](../server/services/firebaseAdmin.ts#L43-L45) already supports ADC), and native Secret Manager. Recommended, and it should happen *after* Phase 3 removes the disk dependency.
- **(b) Stay on Render** — then drop the disk once Firestore is the store, and use Render's own scaling. Secret Manager access then needs an explicit service-account key, which partly defeats Phase 1's purpose.

**Recommendation: (a), sequenced after Phase 3.** Phases 1–3 are platform-neutral and can ship on Render as-is.

**Phase 1 — Secrets (highest severity, self-contained)** → items 1, 2, 22
Remove the browser-held Tavus key; move all provider keys to Secret Manager. No data migration, so this is safe to ship independently.

**Phase 2 — Media hardening** → items 11, 14
Lifecycle + signed URLs + CMEK; retire the local face-cache. Small surface, immediate compliance benefit.

**Phase 3 — Structured data to Firestore** → items 3–10, 13
The big one. Introduce a repository interface behind today's `db.*` call sites so the frozen modules (sessions / templates / question sets) keep their current shape and **Firebase field names are preserved for Flutter interop**. Dual-write → shadow-read verification → cut over → decommission `db.json`. Resolves the tenancy leaks in the same pass.

**Phase 4 — Ephemeral state** → items 15–18
Redis + Cloud Tasks. **This is the gate for N>1 instances** — item 17 in particular, since duplicate scoring costs real money.

**Phase 5 — Analytics** → items 19–21
BigQuery streaming + rollups. Pure addition; no user-visible change.

## 2.4 Data residency & biometric considerations

- **Region pinning:** Firestore location is fixed at creation — verify `talbotiq-9cc4e` before committing. Storage buckets and Memorystore must be pinned to the same region.
- **Sub-processors outside the EU:** Tavus, Daily, Deepgram, Hume, AWS (`us-east-2` hardcoded default in `rekognition.ts:14`) and Google. Each needs a DPA and a transfer mechanism. **The AWS region default alone puts facial frames in Ohio.**
- **Biometric-derived data** (`facialSummary`, prosody scores) carries the heaviest obligations. Note that the frames and audio are already transient — good. The *derived summaries* are what persist.
- 🔴 **Cross-reference [EU_AI_ACT_COMPLIANCE.md](./EU_AI_ACT_COMPLIANCE.md):** the facial-expression and vocal-prosody **emotion** features appear to be **prohibited outright** for EU candidates under AI Act Art 5(1)(f) — not merely high-risk. **Do not invest in migrating those two pipelines until that product decision is made.** Items 16 and the `facialSummary` half of item 3 may be deletions rather than migrations.

## 2.5 Decisions — RESOLVED 12 Aug 2026

These were open when the audit was written. They are now decided and encoded in [`STORAGE_MIGRATION_PROMPT.md`](./STORAGE_MIGRATION_PROMPT.md), which is the executable artifact. Recorded here so the two documents don't diverge.

| # | Decision | Outcome | Implementation caveat |
|---|---|---|---|
| 1 | Templates / Question Sets backfill owner | **(c) seed shared + created owned** | ⚠️ No `createdBy` field exists, so existing non-seed rows go to the `ADMIN_EMAILS` uid; "created owned" applies only post-migration |
| 2 | `db.settings` per-recruiter split | **Yes, per-recruiter** | 🔴 Must copy the global Tavus key onto the relying recruiter(s) before cutover, or `avatarConfigured()` 503s every candidate avatar interview |
| 3 | Retention | recordings **30 d** · transcripts **12 mo** · résumé text **6 mo** · leads **24 mo** · integrity events **90 d** | 🔴 **Placeholders, not findings** — no regulator-endorsed basis; implement as configuration, not constants |
| 4 | Raw résumé files | **Keep discarding** | Already the behaviour — no work |
| 5 | Firestore vs Cloud SQL | **Firestore** | Interop with the existing `interviews` collection wins over relational fit |
| 6 | Emotion features | **Migrate behind flag + region gate, pending legal** | 🔴 Flag default **OFF**, gate **default-deny at session creation**. A flag does not cure processing already done — the prohibition has been live since 2 Feb 2025 |

**Still genuinely open** (added by the deployment-config review, not part of the original six):

- **Platform.** Render→Cloud Run is required for N>1 (§2.3 Phase 0.5) and is not yet scheduled for execution.
- **Firestore document layout.** The 1 MiB limit vs ≤800 transcript turns + 20 k chars of résumé text needs a subcollection decision *before* the repository interface is written.
- **The legal answer on emotion features.** Needs privacy counsel; the flag is a holding position, not a resolution.

---

## Guardrails honoured

- ✅ Phase 1 was **read-only**. No edits, no migrations, no deletions.
- ✅ No changes to frozen modules (sessions / templates / question sets), migrated interview internals, or auth/invite-link logic. Phase 2 **proposes** storage changes only.
- ✅ Plan preserves Firebase field names for Flutter interop (`candidateEmailLower`, `recruiterId`, `resultPublished`, `invite`, `result.detail`).
- ✅ Plan keeps all provider keys server-side and **removes** the one that is currently client-side.
- ⏸️ **Awaiting your approval before any code changes.**
