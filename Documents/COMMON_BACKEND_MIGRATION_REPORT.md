# Common Backend Migration — Gap Report

**Goal:** make `backend/` (FastAPI, Python) the single backend for web, mobile and desktop, retiring `web_version/talbotiq-platform/server/` (Express, TypeScript).

**Date:** 2026-08-13

---

## 1. Where we stand

| | Common backend (`backend/`) | Web server (`web_version/.../server/`) |
|---|---|---|
| Stack | FastAPI + Python | Express + TypeScript |
| Size | ~4,600 lines | ~10,300 lines |
| HTTP endpoints | 21 | ~90 |
| WebSocket endpoints | 0 | 3 |
| Data store | Firestore only (no local state) | In-memory Maps → JSON file on disk |
| Role checks | none (any signed-in user) | `requireRecruiter` / `requireAdmin` |
| Rate limiting | yes (per user) | none |
| Firebase project | `talbotiq-9cc4e` | `talbotiq-9cc4e` (same) |

**The good news:** both already use the same Firebase project, the same `interviews`
collection, and the same `users/{uid}.role` document for roles. The web server
already creates `interviews/{id}` docs for invites and pipelines. So the shared
spine exists — the gap is everything the web server keeps *outside* Firestore.

**The short version of the gap:** the common backend is a *stateless gateway*
(mail + AI proxy + tokens). The web server is a *full application server* that owns
the entire interview product: templates, question sets, the session engine,
pipelines, invites, analytics. None of that exists in the common backend.

---

## 2. Three decisions to make before writing code

These three shape everything else. Nothing below can be planned until they're settled.

### 2.1 Storage — JSON file must become Firestore

`server/store/db.ts` keeps nine collections in memory and snapshots them to
`DATA_DIR/db.json`:

`templates` · `questionSets` · `sessions` · `reports` · `users` · `inviteEmailTemplates` · `pipelines` · `pipelineCandidates` · `leads` · `settings`

This cannot back a shared backend — it's single-instance, disk-bound, and invisible
to the mobile app. All nine need to become Firestore collections in the common
backend, with a one-off import script for the existing `db.json`.

> Note: sessions and reports are the high-write ones (timing ticks, drafts,
> transcript appends). Plan the write pattern before porting — a naive
> document-per-tick will be slow and expensive.

### 2.2 Live audio — relay, or ephemeral token?

The two servers solve real-time audio in opposite ways:

- **Web server:** three server-side WebSocket relays.
  `/api/voice/:sessionId` (mic → Gemini Live, `services/voice.ts` + the
  `voiceFlow.ts` state machine), `/api/avatar/deepgram`, `/api/interview/deepgram`.
- **Common backend:** no WebSockets. It mints a short-lived Gemini Live token
  (`/api/rt/gemini-token`) with the whole session setup locked into it, and the
  device connects straight to Google. Deepgram is pre-recorded POST only.

**Recommendation: port the relays into FastAPI.** Reasons:
- The web Deepgram relay exists precisely because *this project's Deepgram key
  cannot mint short-lived tokens* (documented in `services/deepgramRelay.ts`), so
  a relay is required for live captions no matter what.
- The `voiceFlow.ts` end-of-interview state machine is tested server-side logic.
  Moving to the token model pushes it into the browser and loses that.

FastAPI supports WebSockets natively, so this is a port, not a redesign. Keep the
ephemeral-token route as well — mobile already uses it.

### 2.3 API keys — env-only, or recruiter-editable?

The common backend holds every key in `.env`, full stop. The web server lets a
recruiter type a Gemini key and a Tavus key into the Settings UI and stores them
server-side (`db.settings`), overriding env. Pick one:

- **Env-only (recommended):** simpler, safer, matches mobile. Drop the key-entry UI.
- **Keep runtime keys:** the common backend needs a settings store, key masking,
  and a per-request key-resolution order (as `services/gemini.ts` has today).

---

## 3. What the common backend is missing

Priority: **P1** = web can't run without it · **P2** = a whole feature is dark · **P3** = nice to have.

### P1 — Foundations

| # | Requirement | Today on web | Notes |
|---|---|---|---|
| 1 | **Role-based access control** | `middleware/auth.ts` — `requireRecruiter`, `requireAdmin`, role read from `users/{uid}.role`, `ADMIN_EMAILS` overlay | The common backend's `require_firebase_user` only proves *a* user. It never checks role. Every recruiter route is currently open to any signed-in candidate. **Fix this first — it's a live gap, not just a migration one.** |
| 2 | **Ownership guards** | `ownsSession`, `isAssignedCandidate`, `assertOwner`, `assertSessionParticipant` — cross-tenant reads return 404, not 403, so no existence leak | `app/interviews.py` has the equivalent for interviews; extend the same pattern to templates, question sets, pipelines, sessions, reports. |
| 3 | **WebSocket / media auth via `?token=`** | `contextFromUpgrade()` — browsers can't set headers on a WS handshake or a `<video>` tag | Needed for the ported relays and the face cache. |
| 4 | **Firestore-backed store for the 9 collections** | `store/db.ts` | See §2.1. |
| 5 | **Retire `require_api_key`** | n/a | A shared secret can't live in a browser bundle. Anything the web calls (`/api/emails/send`, `/api/templates`) must move to Firebase-token auth. |

### P2 — Missing features

| # | Feature | Web endpoints | What has to move |
|---|---|---|---|
| 6 | **Interview templates** | 5 | The `InterviewTemplate` model: role, seniority, timing config, KPI rubric + weights, branding, integrity config, adaptive config, voice, persona. Plus the seeded defaults (`store/defaults.ts`, `store/seed.ts`). |
| 7 | **Question sets** | 7 | Fixed questions, CRUD, duplicate, and generate-from-résumé (`POST /question-sets/generate`, multipart upload → Gemini). |
| 8 | **Session engine** | 30 | The largest single piece. `routes/sessions.ts` (1,144 lines) + `services/timing.ts` + `services/conversation.ts` (701 lines). Covers: create/claim, résumé upload + parse, system check, track selection, prep/answer phases, drafts, auto-submit on timeout, integrity events (tab-switch warnings), complete, the chat track (`/chat/*`, 6 endpoints), the avatar track (`/avatar/*`, 3), the video track (facial frames + summary), and the report view. |
| 9 | **Multi-round pipelines** | 10 | Pipeline CRUD, kanban board, round-1 invite, advance rules, not-advancing, move-back, audit trail, and the transition emails (advance / selected / rejection). |
| 10 | **Bulk invites** | 6 + 1 webhook | Extract candidates from CSV/XLSX/PDF/DOCX (`services/inviteExtract.ts`), create N `interviews` docs + send, logo upload to Firebase Storage, Brevo verified-sender list, test send, per-recipient retry, and the **public** Brevo delivery webhook (own `?token=` secret). |
| 11 | **Invite email templates** | 6 | Per-recruiter WYSIWYG templates, four kinds (invite/advance/selected/rejection), HTML allowlist sanitiser, shared renderer so the sent mail matches the client preview byte-for-byte. |
| 12 | **Analytics** | 1 | Aggregates over stored `ResultReport`s, filtered by track/template/role/date, scoped to the recruiter (admins see the tenant). |
| 13 | **Richer scoring model** | `services/scoring.ts` + `signals.ts` | The common backend's `app/evaluation.py` returns a flat `{overallScore, recommendation, summary, strengths, improvements, perQuestion[]}`. The web `ResultReport` also carries **KPI-rubric scores per question**, **weighted `kpiAverages`**, `SpeechMetrics` (word counts, fillers, vocabulary, response time), `SentimentSignals`, `manualReview`, and the `degraded` / `notEvaluated` flags. Without these the web Results and Analytics pages lose most of their content. **Keep the common backend's 202 + background-task pattern** — it's better than the web's fire-and-forget. |
| 14 | **Brevo email provider** | `services/email.ts`, `services/brevo.ts` | Common backend sends via Gmail SMTP / Gmail API. Web sends via Brevo SMTP relay and uses the Brevo REST API to list verified senders. Add Brevo as a third mailer mode; keep Gmail for mobile. |
| 15 | **Mimic Guide (in-app help)** | 3 | `/help/chat` (markdown assistant, 20-turn history, canned fallback KB), `/help/agent` (Autopilot decisions), `/help/tts` (Gemini Live synthesis for the ~55 languages with no browser voice). |
| 16 | **Avatar screening proxies** | 7 | `avatar/status` readiness, `avatar/deepgram/token`, Hume batch jobs (3 endpoints), `avatar/gemini-generate`, `avatar/analyze-face` (**AWS Rekognition — no AWS integration exists in the common backend at all**). |
| 17 | **Voice catalog + preview** | 2 | `GET /voices` catalog and `POST /voices/:id/sample` returning base64 PCM. The common backend has the preview *token* route instead — the web preview player expects audio bytes. |
| 18 | **Tavus write operations** | direct from browser | `src/services/tavus.ts` calls `tavusapi.com/v2` **directly from the browser** with a runtime-entered key, including `POST /replicas`, `POST /personas`, `POST /videos`. The common backend proxies reads + conversations only. Add write proxies. |

### P3 — Lower priority

| # | Feature | Notes |
|---|---|---|
| 19 | **Replica-preview face cache** | 2 endpoints. Downloads Tavus preview MP4s once to local disk, serves with immutable cache headers, host allowlist. A performance cache — a CDN or Firebase Storage is a cleaner home than server disk. |
| 20 | **Marketing leads** | 1 public endpoint. Demo requests from the marketing site, deliberately kept out of Firestore so no security rule change was needed. Small and self-contained. |
| 21 | **Server-held settings** | 8 endpoints. Only needed if §2.3 keeps runtime keys. |

---

## 4. Keep these — the common backend is ahead here

Don't lose them while porting. Each is a real improvement over the web server:

- **Per-user rate limiting** (`app/ratelimit.py`) — the web server has none, so one stolen ID token can burn the whole Gemini quota.
- **Provider error normalisation** — `ProviderNotConfigured` → 503, `UpstreamError` → mapped status, with the vendor body deliberately *not* forwarded. Routers need no try/except.
- **Gemini model allowlist** (`GEMINI_ALLOWED_MODELS`) — a client can't redirect spend onto an arbitrarily expensive model.
- **Locked Gemini Live setup** — the ephemeral token carries the entire `bidiGenerateContentSetup`, so a tampered client can't rewrite the interviewer's instructions.
- **Tavus `_LOCKED_PROPERTIES`** — the client can't override recording / S3 / assume-role config.
- **202 + background scoring** — avoids the gateway 504 that used to permanently fail evaluations.
- **Server-side résumé and evaluation writes** via the Admin SDK — because `firestore.rules` lets a candidate update their own interview doc, so a client-written score is a score the candidate chose.
- **Round criteria** read from `tests/{testId}/rounds/{roundId}` — the multi-round model the mobile app already uses.

---

## 5. Frontend changes required

### 5.1 Must fix — will break otherwise

**1. The auth interceptor doesn't match a cross-origin backend.**
`src/features/auth/AuthProvider.tsx:52`:

```ts
const isApi = url.startsWith('/api') || url.startsWith(`${window.location.origin}/api`)
```

With `VITE_API_BASE` set to an absolute URL, `httpBase()` returns
`https://api.example.com/api` — neither branch matches, so **no `Authorization`
header is attached at all**. Match against the configured API base instead.
*(Worth checking whether this already affects the current Vercel + Render deploy.)*

**2. Error shape mismatch.**
FastAPI returns `{"detail": "..."}`. `src/lib/api.ts:59` reads `data.error`, so every
error message degrades to `Request failed (400)`.
→ **Cheapest fix: add a FastAPI exception handler that emits both `error` and
`detail`.** Zero frontend churn, and mobile keeps working.

**3. Hardcoded relative `/api/...` calls that bypass `httpBase()`.**
These break against any non-same-origin backend:

| File | Path |
|---|---|
| `src/features/guide/MimicGuide.tsx:513` | `/api/help/chat` |
| `src/lib/guideSpeech.ts:258` | `/api/help/tts` |
| `src/services/hume.ts:108,125,134` | `/api/avatar/hume/*` |
| `src/services/geminiAnalysis.ts:325` | `/api/avatar/gemini-generate` |
| `src/pages/SettingsPage.tsx:68` | `/api/avatar/status` |
| `src/store/useAppStore.ts:111,222,230` | `/api/avatar/status`, `/api/avatar/analyze-face` |

→ Route all of them through `httpBase()`.

**4. Field-naming convention.**
Web types are camelCase throughout. The common backend is inconsistent —
`TwoWayJoinResponse` and the résumé models use camelCase aliases, but
`TemplateRead` (`is_html`, `owner_email`) and `SendResponse` (`template_id`,
`subject_preview`) are snake_case.
→ Standardise on camelCase aliases across **all** Pydantic models before the web
frontend touches them.

**5. Path renames.** Two-way, evaluate and résumé are keyed on `interviews/{id}` in
the common backend, but on `sessions/{id}` on web:

| Web | Common backend |
|---|---|
| `POST /api/sessions/:id/twoway/host` | `POST /api/interviews/{id}/twoway/host` |
| `POST /api/sessions/:id/twoway/join` | `POST /api/interviews/{id}/twoway/join` |
| `POST /api/sessions/:id/twoway/complete` | `POST /api/interviews/{id}/twoway/complete` |

→ Either update `src/lib/api.ts`, or mount the web paths as aliases on the common
backend during the cutover. **Aliases are safer** — they let you migrate one route
at a time.

### 5.2 Should fix

**6. Move Tavus off the browser.** `src/services/tavus.ts` holds a Tavus key in
memory and calls `tavusapi.com/v2` directly. Point it at the backend proxy and
delete the client-side key.

**7. Remove the direct Deepgram call.** `src/services/deepgram.ts:66` hits
`api.deepgram.com/v1/projects` from the browser to test the key. Replace with the
backend's readiness check — the client holds no keys, so it can't test them.

**8. Handle 429.** The common backend rate-limits; the frontend has no
`429` / `Retry-After` path. Add one to the `http()` helper in `src/lib/api.ts`.

**9. WebSocket client.** If §2.2 goes the relay route, `src/lib/voiceClient.ts` only
needs a path change. If it goes the token route, it needs a rewrite to connect to
Google directly and to carry the `voiceFlow` state machine.

---

## 6. Suggested order

Each phase should leave both apps working.

| Phase | Work | Why here |
|---|---|---|
| **0** | Fix the auth interceptor (5.1 #1) · add the `{error}` compatibility handler (5.1 #2) · normalise Pydantic aliases to camelCase (5.1 #4) · **add role-based access control to the common backend (P1 #1)** | Cheap, independent, and #1 closes a live security gap. |
| **1** | Firestore store for the 9 collections + import script for `db.json` | Everything else depends on it. |
| **2** | Templates, question sets, settings, voices | Small, self-contained CRUD. Good shakedown for the store. |
| **3** | Session engine + timing + conversation state machine | The big one. Port with its tests; expect this to dominate the schedule. |
| **4** | Richer scoring model (KPI rubric + speech + sentiment) on top of the existing 202/background path | Unblocks Results and Analytics. |
| **5** | Invites, invite-email templates, Brevo provider, delivery webhook | Depends on templates (phase 2). |
| **6** | Pipelines + board + transition emails | Depends on invites (phase 5). |
| **7** | Analytics | Depends on reports (phase 4). |
| **8** | WebSocket relays (voice + the two Deepgram relays) | Self-contained; can run in parallel with 3–7. |
| **9** | Avatar screening proxies (Hume, Rekognition, Tavus writes), Mimic Guide, face cache, leads | The remaining leaf features. |
| **10** | Point the web frontend fully at the common backend · delete `web_version/.../server/` | Cutover. |

---

## 7. Rough sizing

| Area | Web lines to port |
|---|---|
| Session engine (`routes/sessions.ts` + `conversation.ts` + `timing.ts`) | ~2,010 |
| Voice relay (`voice.ts` + `voiceFlow.ts` + `deepgramRelay.ts`) | ~945 |
| Invites (`invites.ts` + `interviewInvite.ts` + `inviteBridge.ts` + `inviteExtract.ts` + `inviteEmailRender.ts` + `inviteEmailTemplates.ts`) | ~1,150 |
| Pipelines | ~420 |
| Scoring + signals + analytics | ~600 |
| Mimic Guide (chat + prompt + TTS + autopilot) | ~625 |
| Avatar proxies + face cache + Rekognition | ~425 |
| Templates / question sets / settings / voices / store | ~640 |

**~6,800 lines of Express to re-express in FastAPI**, of which the session engine
and the voice relay are the two genuinely hard pieces. The rest is mostly
mechanical CRUD and proxying.

---

## 8. Open questions

1. **Sessions vs interviews — one model or two?** The web server keeps a local
   `InterviewSession` and *materialises* it from a Firestore `interviews/{id}` doc
   the first time a candidate opens their link (`services/inviteBridge.ts`). Once
   everything is on Firestore, is that bridge still needed, or do sessions and
   interviews merge into one document? Merging is cleaner but touches the mobile
   app's frozen schema.
2. **Does mobile need the web-only tracks?** `chat`, `chatbot`, and `video` exist
   only on web today; mobile uses `voice`, `video_avatar`, `two_way`, plus résumé
   rounds. If mobile will never use them, the session engine can stay
   web-shaped — but it should be a deliberate call, not an accident.
3. **Keep the Express server as a thin proxy during cutover?** It would let you
   migrate one route group at a time behind a stable frontend, at the cost of
   running two services for a while.
4. **Face cache — server disk, CDN, or Firebase Storage?** Local disk doesn't
   survive a multi-instance deploy.
5. **Do recruiters still enter their own API keys?** See §2.3. This decision alone
   adds or removes 8 endpoints plus a settings store.
