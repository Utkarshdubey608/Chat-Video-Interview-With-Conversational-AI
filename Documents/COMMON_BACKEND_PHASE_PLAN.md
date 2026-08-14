# Common Backend — Phase Plan

**Goal:** one backend (`backend/`, FastAPI) serving web, mobile and desktop.
The web server's routes are ported verbatim under an `/api/web/*` prefix, and its
local JSON store is replaced by Firestore.

**Date:** 2026-08-13

---

## Decisions locked

| Decision | Choice |
|---|---|
| Approach | Full port, TypeScript → Python |
| URL namespace | All ported web routes mount under **`/api/web/*`** |
| Code layout | `backend/app/web_routes/` package |
| Storage | Firestore replaces the local JSON store |
| Route/field shapes | **Unchanged** — ported verbatim |
| Flutter changes | **Zero** |
| Web frontend changes | **One PR, at the start** (Phase 1) |

### Why `/api/web/*`

`/api/templates` means two different things today — email templates on the common
backend (called by `mailer_service.dart:108`), interview templates on web. The
prefix dissolves that clash without renaming anything, and prevents every future
one. All 13 other web prefixes were checked and are free.

### Frozen contracts

1. **Nothing under `/api/…` (outside `/api/web/`) changes.** Not the path, request
   shape, response shape, field names, or auth. That is the mobile/desktop contract.
2. **Ported routes keep their exact paths, shapes and field names**, just re-prefixed.
   The web frontend must not need a second PR.
3. **Ownership checks are NOT optional.** Role gating is deliberately dropped for
   now (see *Parked*), but every route keeps its ownership check —
   `recruiterId == uid` for recruiters, `candidateEmailLower == email` for
   candidates, and cross-tenant reads returning **404, not 403**, so the response
   never reveals that another recruiter's record exists.

> ⚠️ **Do not confuse the two.** `app/interviews.py` already has a function named
> `require_recruiter(interview, uid=…)` which is an **ownership** check, not a role
> check. Dropping role gating must not remove ownership gating — without it, one
> recruiter can read another's sessions, candidates and reports.

---

## Why storage moves first

Router-by-router cutover only works if both servers read the same data. They
don't today, and the coupling is not localised:

| Module | Reads |
|---|---|
| `avatar.ts`, `gemini.ts`, `tavusServer.ts` | `db.settings` |
| `invites.ts` | `db.questionSets` |
| `pipelines.ts` | `db.questionSets`, `db.reports`, `db.sessions` |
| `sessions.ts` | `db.questionSets`, `db.reports`, `db.sessions`, `db.settings`, `db.templates` |
| `voice.ts` (WS) | `db.questionSets`, `db.reports`, `db.sessions`, `db.templates` |
| `analytics.ts` | `db.reports`, `db.sessions`, `db.templates` |
| `conversation.ts` | `db.questionSets` |
| `inviteBridge.ts` | `db.sessions`, `db.templates` |
| `leads.ts` | `db.leads` *(the only standalone one)* |

`db.settings` holds the runtime API keys and is read by the **shared** `gemini.ts`
client, so nearly every AI route depends on it. If FastAPI reads Firestore while
Express still reads `db.json`, a session started on one can't find its template on
the other.

**So Phase 2 swaps the storage inside Express, in TypeScript, keeping the same
synchronous in-memory API.** Both servers then point at one database and routes can
move one group at a time, each independently verifiable and reversible.

**Fallback if Phase 2 is skipped:** all 89 routes must cut over in a single
big-bang switch, with no incremental verification. Not recommended, but it is the
only alternative.

---

## Phases

### Phase 0 — Express serves `/api/web/*` too

*Goal: make the new URL shape real before anything else moves.*

Mount every router twice in `server/index.ts` — once at its current path, once
under `/api/web`. Both sets live simultaneously, so nothing breaks.

Then widen the three WebSocket path matchers to accept either prefix:

| File | Line | Change |
|---|---|---|
| `server/services/voice.ts` | 624 | `/^\/api\/voice\/([^/]+)$/` → `/^\/api(?:\/web)?\/voice\/([^/]+)$/` |
| `server/services/deepgramRelay.ts` | 69 | `!== '/api/avatar/deepgram'` → accept both |
| `server/services/deepgramRelay.ts` | 89 | `!== '/api/interview/deepgram'` → accept both |

**Size:** ~13 router lines + 3 one-line edits.
**Done when:** every endpoint answers identically on both prefixes.
**Risk:** very low — purely additive.

---

### Phase 1 — The single web frontend PR

*Goal: all frontend work, once, tested against the known-good Express server.*

This is the **only** frontend change in the project. It ships against Express
(Phase 0), so it is verified before any Python exists. After this, cutover is a
`VITE_API_BASE` change.

**See `WEB_FRONTEND_MIGRATION_TASKS.md` for the line-by-line version.** Summary:

1. **`src/lib/apiOrigin.ts:26`** — `` `${base}/api` `` → `` `${base}/api/web` `` (and `'/api'` → `'/api/web'`).
2. **`src/features/auth/AuthProvider.tsx:52`** — the interceptor matches only `/api`
   and same-origin, so against a different host **no `Authorization` header is
   attached at all**. Match the configured API base instead. *Blocking — and
   possibly already broken in the current Vercel + Render deploy.*
3. **Four WebSocket literals** → `/api/web/…`:
   `voiceClient.ts:81` · `useDeepgramTranscript.ts:39` · `useAudioAnalysis.ts:76` · `useAnswerRecorder.ts:53`
4. **Seven hardcoded relative `/api/…` fetches** → route through `httpBase()`:
   `MimicGuide.tsx:513` · `guideSpeech.ts:258` · `hume.ts:108,125,134` ·
   `geminiAnalysis.ts:325` · `SettingsPage.tsx:68` · `useAppStore.ts:111,222,230` ·
   `useAnswerRecorder.ts:130`
5. **429 / `Retry-After` handling** in the `http()` helper (`src/lib/api.ts:52`) —
   the common backend rate-limits and the frontend currently has no path for it.

**Done when:** the app runs fully against `/api/web/*` on Express.
**Risk:** low, and it is the highest-value item in the plan — everything after it
is invisible to the frontend.

---

### Phase 2 — Firestore inside Express *(pivotal)*

*Goal: one database, shared by both servers.*

Replace `server/store/db.ts`'s JSON-snapshot persistence with Firestore while
**keeping its synchronous in-memory API unchanged** — `db.sessions.get(id)` still
returns an object, handlers still mutate it and call `db.scheduleSave()`. No call
site changes.

**Design: write-through cache.**
- On boot, load each collection into the existing `Map`s.
- Reads stay in-memory and synchronous (so `sessions.ts`, `conversation.ts` and
  `timing.ts` need no async refactor — this is what keeps the port mechanical).
- `scheduleSave()` becomes a debounced per-document Firestore write instead of a
  whole-file snapshot.
- Keep `saveHealth()` and the `/api/health` persistence block.

**Constraint:** single instance, or sticky routing, until consolidation. That is
already true today, so it is not a regression.

**Also in this phase:** the one-off `db.json` → Firestore import for the deployed
Render disk. Local dev has no `server/data/` yet, so this only matters in
production.

**Done when:** Express runs with `DATA_DIR` unused and survives a restart with all
data intact.
**Risk:** highest in the plan. `web_sessions` is the high-write collection
(timing ticks, draft saves, transcript appends) — measure write volume here.

---

### Phase 3 — FastAPI skeleton

*Goal: somewhere for ported routes to land.*

- `backend/app/web_routes/` package, one module per Express router.
- Mount in `create_app()` under `/api/web`.
- **Python store layer** over the same Firestore collections as Phase 2.
- Auth: reuse `require_firebase_user`, plus a `?token=` variant for WebSocket
  upgrades and `<video>` tags (ports `contextFromUpgrade` from `middleware/auth.ts`).
- **Error-shape shim:** FastAPI returns `{"detail": …}`; the web client reads
  `data.error` (`api.ts:59`). Add a handler emitting **both** keys. Additive, so
  mobile is unaffected.
- Port `/api/web/health`.

**Done when:** `/api/web/health` answers from FastAPI and the store layer round-trips
a document.
**Risk:** low.

---

### Phase 4 — Cut over the light routers

| Router | Routes |
|---|---|
| `help` (chat, agent, tts) | 3 |
| `avatar` (status, deepgram/token, hume ×3, gemini-generate, analyze-face) | 7 |
| `voices` (catalog, sample) | 2 |
| `faceCache` | 1 |
| `leads` (public) | 1 |
| `auth/me` | 1 |

**15 routes.** Little or no shared state — `avatar` reads only `settings`, `leads` is
standalone, and `auth/me` reads Firestore `users/{uid}` directly.

Route these prefixes to FastAPI at the reverse proxy; everything else stays on
Express.

**New deps:** `boto3` (Rekognition — no AWS integration exists today).
**Done when:** Mimic Guide, the avatar screening panels and the voice preview all
work against FastAPI.
**Risk:** low. Proves the skeleton with no data risk.

---

### Phase 5 — CRUD routers

| Router | Routes |
|---|---|
| `templates` (interview templates) | 5 |
| `question-sets` | 7 |
| `settings` | 8 |
| `invite-email-templates` | 6 |

**26 routes.** First real use of the store layer. Includes porting the seeded
defaults (`store/defaults.ts`, `store/seed.ts`) and the HTML allowlist sanitiser.

**New deps:** `nh3` or `bleach` (replaces `sanitize-html`).
**Done when:** a template created on FastAPI is visible to an Express-served session.
**Risk:** medium — this is where the two servers first share mutable data.

---

### Phase 6 — Invites and pipelines

| Router | Routes |
|---|---|
| `invites` (extract, create, logo, senders, test, retry) | 6 |
| `invites/brevo-webhook` (**public**, own `?token=` secret) | 1 |
| `pipelines` | 10 |

**17 routes.** Carries the email stack: Brevo SMTP delivery, the verified-sender
list, per-candidate rendering, the shared renderer so sent mail matches the client
preview, invite send-status stamping, and candidate extraction from
CSV/XLSX/PDF/DOCX.

**New deps:** `pypdf` (pdf-parse), `python-docx` (mammoth), `openpyxl` (xlsx).
**Done when:** a bulk invite sends, its Brevo webhook lands, and a pipeline
advances a candidate to round 2.
**Risk:** medium. Delivery is externally observable — verify against a real inbox.

---

### Phase 7 — The session engine

| Router | Routes |
|---|---|
| `sessions` (+ chat, avatar, video, two-way sub-tracks) | 30 |
| `analytics` | 1 |

**31 routes, and the bulk of the work.** Ports `routes/sessions.ts` (1,144 lines),
`services/conversation.ts` (701), `services/timing.ts` (165), plus `scoring.ts`,
`signals.ts`, `videoTranscript.ts` and `inviteBridge.ts`.

Port the **pure** modules first and with their tests — `timing.ts`, `voiceFlow.ts`,
`signals.ts` and `videoTranscript.ts` are dependency-free state machines and
calculators with existing unit tests. They are the correctness core; get them
green before wiring any route.

**Done when:** every track completes end to end and produces a report identical to
Express's for the same inputs.
**Risk:** highest after Phase 2. Budget accordingly — this is the phase that
decides the schedule.

---

### Phase 8 — WebSocket relays

| Relay | Path |
|---|---|
| Voice → Gemini Live | `/api/web/voice/{sessionId}` |
| Avatar transcription → Deepgram | `/api/web/avatar/deepgram` |
| Candidate transcription → Deepgram | `/api/web/interview/deepgram` |

Ports `services/voice.ts` (638), `voiceFlow.ts` (207) and `deepgramRelay.ts` (100).
FastAPI supports WebSockets natively.

The relays stay relays rather than moving to ephemeral tokens: this project's
Deepgram key cannot mint short-lived tokens (`Insufficient permissions` on
`/v1/auth/grant`, documented in `deepgramRelay.ts`), so a relay is required either
way, and keeping voice relayed preserves the tested server-side `voiceFlow` machine.

**Done when:** a full voice interview runs against FastAPI with live captions.
**Risk:** medium-high — long-lived connections, backpressure, and reconnects.

---

### Phase 9 — Decommission

- Route **all** `/api/web/*` to FastAPI at the proxy.
- Delete `web_version/talbotiq-platform/server/`.
- Drop the duplicate `/api/…` mounts added in Phase 0.
- Remove `DATA_DIR` and the Render persistent disk.
- Delete the dead `recruiter_keys` Firestore collection (see *Cleanup*).

---

## Firestore layout

Web collections take a `web_` prefix, mirroring the URL prefix. No clash with
mobile's `interviews`, `tests/{id}/rounds/{id}` or `email_templates`, and trivially
consolidatable later.

| JSON store | Firestore collection | Key | Notes |
|---|---|---|---|
| `templates` | `web_templates` | `id` | seeded on first boot |
| `questionSets` | `web_question_sets` | `id` | seeded on first boot |
| `sessions` | `web_sessions` | `id` | **high write** |
| `reports` | `web_reports` | `sessionId` | |
| `inviteEmailTemplates` | `web_invite_email_templates` | `id` | per recruiter |
| `pipelines` | `web_pipelines` | `id` | per recruiter |
| `pipelineCandidates` | `web_pipeline_candidates` | `id` | per recruiter |
| `leads` | `web_leads` | auto | append-only, public writes |
| `settings` | `web_settings` | single doc `global` | holds runtime API keys |
| `users` | — | — | **dropped**, see below |

**Two things do not migrate:**

- **`users`** — the JSON store only mirrors Firestore `users/{uid}`, which both
  clients already read (`firebaseAdmin.getUserRole`, and Flutter at
  `auth_service.dart:86`). Read it directly; delete the mirror.
- **`sessions` stays separate from `interviews`** — the existing
  materialise-on-claim bridge (`inviteBridge.ts`) is preserved exactly. No merge.

**Security:** `firestore.rules` uses explicit per-collection matches with no
catch-all, and Firestore defaults to deny — so the new `web_*` collections are
already client-inaccessible and are written only by the Admin SDK. Verify no
permissive rule is added for them.

---

## Rate limits

Applied to ported routes that call a vendor. Made exact **and** raised in the same
change — doing either alone is wrong in both directions.

| Setting | Now | New | Why |
|---|---|---|---|
| `RATE_LIMIT_WINDOW_SECONDS` | 60 | 60 | unchanged |
| `RATE_LIMIT_LIVE_TOKEN` | 10 | **20** | one launch needs 1; web adds voice previews |
| `RATE_LIMIT_GENERATE` | 30 | **90** | web adds adaptive questions + scoring + sentiment per session, plus recruiter question-set generation |
| `RATE_LIMIT_MEDIA` | 20 | **60** | transcription + avatar start + Deepgram tokens + voice samples + résumé uploads |
| `RATE_LIMIT_FACE` | — | **60** *(new)* | facial capture fires every 8 s (`rekognitionService.ts:26`) = 7.5/min; 8× headroom still catches a hot loop |
| `RATE_LIMIT_CHAT` | — | **30** *(new)* | help chat + TTS; a human can't exceed ~10/min |

**Rule:** the session engine's cheap routes — state polls, draft saves, timing
ticks, integrity events, track selection — hit Firestore, not a vendor, and must
**not** go in any AI bucket. Bounding those belongs at the gateway. Putting them in
`generate` would throttle real interviews.

Today's in-process counters mean N workers allow N× the configured limit, so the
effective ceiling is already far looser than the numbers suggest. When the limiter
becomes exact (shared store), these raised values keep roughly today's real
headroom. `ratelimit.py` already documents that the dependency surface stays the
same, so this is a swap of `_LIMITER`, not a redesign.

---

## New Python dependencies

| Purpose | TypeScript | Python |
|---|---|---|
| PDF text | `pdf-parse` | `pypdf` |
| DOCX text | `mammoth` | `python-docx` |
| CSV/Excel | `xlsx` | `openpyxl` |
| HTML sanitiser | `sanitize-html` | `nh3` (or `bleach`) |
| AWS Rekognition | `@aws-sdk/client-rekognition` | `boto3` |
| SMTP | `nodemailer` | stdlib `smtplib` *(already used)* |
| WebSockets | `ws` | FastAPI native |

---

## Mail

The common backend's mailer is **Gmail-shaped, not SMTP-shaped**: `_send_smtp` logs
in as `settings.email_user` and `_build_message` hardcodes `From` to the same
address. Brevo needs them separate — the login is `…@smtp-brevo.com`, the From must
be the verified domain.

Rewrite `app/mailer.py` as a generic SMTP sender, adding: separate `SMTP_USER` /
`MAIL_FROM`, a per-send `from` override, `replyTo`, custom headers
(`X-Mailin-custom` carries the interview id — **without it Brevo delivery webhooks
cannot be correlated back to a recipient**), a returned `messageId`, and an auto
text alternative derived from the HTML.

**`/api/emails/send` stays byte-identical.** Default `smtp_user` → `email_user` and
`mail_from` → `formataddr(from_name, email_user)` when unset, so existing Gmail
deploys keep working with no env change. `provider()` gains `"brevo"`, which is safe
— Flutter's only check is `provider == 'dry_run'` (`send_report.dart:47`).

**Zero Flutter changes.** Two things to note: mobile's outbound mail will start
going through Brevo once the env vars are set (different sender domain and
deliverability profile), and `DRY_RUN` currently defaults to `true` in
`config.py` — the deploy must set it `false` or nothing sends.

---

## Two constraints that would break Flutter

1. **If role checks are ever added, read Firestore `users/{uid}.role`, not the
   custom claim.** `security.py`'s `AuthedUser.role` reads `claims["role"]`, and its
   own docstring says that is *"Absent for most users — role lives in Firestore
   today."* Flutter confirms it (`auth_service.dart:86`). A claim-based guard would
   403 **every recruiter on both platforms.**
2. **`/health`'s `providers` map is parsed generically** — Flutter maps every entry
   to a bool (`backend_client.dart:233`). **Adding** keys is safe; renaming or
   removing one silently disables a feature on mobile.

---

## Parked

Deliberately deferred to a later consolidation pass. Recorded so none of it is lost.

| Item | Note |
|---|---|
| **Role enforcement** | Accepted gap: any signed-in candidate can call recruiter endpoints. Ownership checks still apply, so no cross-tenant data access. |
| `ADMIN_EMAILS` overlay | Goes with role gating — an admin recruiter no longer sees other recruiters' sessions or unclaimed legacy sessions. Backend-only behaviour change. |
| Web's recruiter key-entry UI | Contradicts the mobile model (keys server-side, `keyOverrides` is dead in Flutter). Keep `/api/web/settings` for now; remove when consolidating. |
| Browser-held Tavus key | `src/services/tavus.ts` calls `tavusapi.com/v2` directly for replica/persona/video creation. |
| Direct `api.deepgram.com` call | `src/services/deepgram.ts:66` tests the key from the browser. |
| camelCase naming | `/api/templates` and `/api/emails/send` stay snake_case. If ever renamed, **dual-emit** — Flutter parses with silent defaults (`is_html ?? true`), so a rename degrades quietly instead of erroring. |
| Duplicate implementations | Two-way, Gemini generate, Tavus and Deepgram now exist twice (`/api/…` and `/api/web/…`). Both call the same provider clients internally. |
| Path ambiguity | `/api/web/*` is a transitional namespace, not a permanent one. |

### Cleanup

`firestore.rules:74` exposes a `recruiter_keys/{recruiterId}` collection with
`allow read: if isSignedIn()` — any signed-in user can read any recruiter's
document. Nothing in the web frontend, web server, or Flutter app references it;
it appears vestigial from the pre-server-side-keys era. Confirm and delete.

---

## Summary

| Phase | Work | Routes | Risk |
|---|---|---|---|
| 0 | Express serves `/api/web/*` too | — | very low |
| 1 | **The single web frontend PR** | — | low |
| 2 | **Firestore inside Express** | — | **highest** |
| 3 | FastAPI skeleton | 1 | low |
| 4 | help · avatar · voices · faceCache · leads · auth/me | 15 | low |
| 5 | templates · question-sets · settings · invite-email-templates | 26 | medium |
| 6 | invites · brevo-webhook · pipelines | 17 | medium |
| 7 | **session engine · analytics** | 31 | **high** |
| 8 | WebSocket relays | 3 WS | medium-high |
| 9 | Decommission Express | — | low |

Phases 0–1 are cheap and unlock everything. Phase 2 is the one that must be right.
Phase 7 is the one that will take the time.
