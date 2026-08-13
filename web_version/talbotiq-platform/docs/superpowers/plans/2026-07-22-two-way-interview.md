# Two-Way Interview Mode — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a live recruiter↔candidate **Two-way Interview** as a new `TrackType: 'two_way'` in TalbotIQ — a real-time video call over **Daily** (server-minted short-lived rooms + tokens), recorded → **Firebase Storage** → **Deepgram** transcript → existing **Gemini** scorecard, plus an **interviewer manual rating/notes**. Native UI (reuses the `AvatarStage` dark live-room shell + `VoiceStage` controls) and the existing invite/session/report pipeline.

**Architecture:** The source (`talxi-integrated-final`) is a Django app doing raw WebRTC mesh + Socket.IO signaling + hardcoded TURN; we reimplement its *behavior* on TalbotIQ's stack using **Daily** (already a dependency, `@daily-co/daily-js`) so rooms/TURN/SFU/low-latency are managed and tokens are server-minted. The recruiter joins as **owner**, the candidate joins with a **non-owner + knocking** token (Daily waiting room = the source's lobby/admit). The call is **not** on TalbotIQ's timed engine (like the conversational tracks, `two_way` is exempt from `tick()`); scoring runs post-call on the recording, reusing the conversation scoring path.

**Tech stack:** Vite/React/TS, Express/tsx, `@daily-co/daily-js` (client), Daily REST API (server, `DAILY_API_KEY`), Firebase Storage, Deepgram (`transcription.ts`), Gemini (`scoreConversation`). Tests: `npx tsx <file>.test.ts`.

## Global Constraints

- **Keys server-side.** `DAILY_API_KEY` lives only on the server (`dailyServer.ts`); the client only ever receives a short-lived Daily **meeting token** + room URL. Never expose the API key.
- **Additive only.** New `TrackType` value `'two_way'`; new optional `InterviewSession.liveRoomName?`; a new optional manual-review shape on the report. Frozen — do NOT modify: `sessions`/`templates`/`question-sets` route contracts, Firestore `interviews` field names, existing `InterviewSession`/`ResultReport` fields, Tavus internals.
- **`two_way` is a conversation-style, non-timed track.** Add it to the `tick()` exemption (like `video_avatar`/`chatbot`), the `scoreConversation` OR-list, `isConversation`, and `computeSpeechMetrics` spoken set — NOT the per-question timed path.
- **Low latency.** No heavy CV/WebGL/facial analysis during the live call (facial is out of scope here; the prompt's avatar-lag warning). Warm the camera before join; send raw tracks (Daily handles this).
- **Interop.** Firestore `interviews.type` stays `'video'|'chat'`; `typeForMode('two_way')` → `'video'`; precise mode rides the additive `mode` field.
- **Gates:** `npm run build` AND `npx tsc -p server/tsconfig.json --noEmit` pass before each commit. (`npm run lint` is non-functional repo-wide — ignore.)
- Base: branch `feat/two-way-interview` off the current running copy's `feat/avatar-screening-migration`.

## File Structure

**New**
- `server/services/dailyServer.ts` — Daily REST client: create/get room, mint owner/candidate tokens, delete room.
- `server/services/dailyServer.test.ts` — `tsx` test for the pure token/room payload builders.
- `src/features/interview/screens/TwoWayStage.tsx` — candidate live-call screen (Daily call object, reuses `AvatarStage` shell + `VoiceStage` controls).
- `src/features/interview/useDailyCall.ts` — hook wrapping `@daily-co/daily-js` (join/leave, participants, tracks, knocking, recording via `MediaRecorder`).
- `src/features/recruiter/LiveInterviewPage.tsx` — recruiter host screen (join as owner, admit candidate, start/stop recording, end).
- `src/components/interview/DailyVideoTile.tsx` — renders one participant's video/audio track (shared by both screens).

**Modify**
- `shared/types.ts` — `TrackType` += `'two_way'`; `InterviewSession.liveRoomName?`; `ResultReport.manualReview?` (or a sibling); a `TwoWayJoinResponse` DTO.
- `server/routes/invites.ts` — `MODE_LABEL`/`typeForMode` recognise `'two_way'`.
- `server/services/inviteBridge.ts` — `trackForInvite` includes `'two_way'`; `synthTemplate` gives it a sane default.
- `server/routes/sessions.ts` — `/track` guard + `/mine` allowlist include `'two_way'`; new `/:id/twoway/host`, `/:id/twoway/join`, `/:id/twoway/complete`, `/:id/twoway/review` routes; report `isConversation` includes `'two_way'`.
- `server/services/scoring.ts` — `scoreSession` conversation OR-list includes `'two_way'`.
- `server/services/signals.ts` — `computeSpeechMetrics` spoken includes `'two_way'`.
- `server/services/timing.ts` — `tick()` exemption includes `'two_way'`.
- `server/index.ts` — (only if a Daily webhook is added; otherwise no change).
- `src/features/recruiter/InviteWizard.tsx` — "Two-way Interview" mode card.
- `src/features/recruiter/SessionsPage.tsx` — track label + a **"Join live interview"** action for `two_way` sessions (recruiter).
- `src/features/interview/TakeInterviewPage.tsx` — route `two_way` → `TwoWayStage`.
- `src/features/recruiter/ReportPage.tsx` — recording playback + manual-review panel for `two_way`.
- `src/lib/api.ts` — `twowayHost`/`twowayJoin`/`twowayComplete`/`twowayReview` methods.
- `.env.example`, `docs/VIDEO_INTERVIEW.md` (or a new `docs/TWO_WAY_INTERVIEW.md`).

---

## Task 1: `two_way` track recognized end-to-end (types + wiring + conversation routing)

Mirror the video-track recognition task: make `'two_way'` a first-class conversation-style, non-timed track.

**Files:** `shared/types.ts`; `server/routes/invites.ts`; `server/services/inviteBridge.ts`; `server/routes/sessions.ts` (`/track`, `/mine`, `isConversation`); `server/services/scoring.ts`; `server/services/signals.ts`; `server/services/timing.ts`; test `server/services/twoWayTrack.test.ts` (new).

**Interfaces:** Produces `TrackType` incl. `'two_way'`; `trackForInvite({mode:'two_way'})==='two_way'`; `typeForMode('two_way')==='video'`; `scoreSession`/`isConversation`/`computeSpeechMetrics` treat it as conversational; `tick()` exempts it.

- [ ] **Step 1: failing test** — `server/services/twoWayTrack.test.ts`: assert `tick()` returns `false`/no-mutation for a `two_way` in-progress session (exempt, like `video_avatar`), and `computeSpeechMetrics` treats a `two_way` session with a candidate transcript turn as `spoken`. Run → FAIL.
- [ ] **Step 2: implement** the additive edits (each mirrors the existing `video_avatar` handling exactly):
  - `shared/types.ts`: `export type TrackType = 'chat' | 'chatbot' | 'video_avatar' | 'voice' | 'video' | 'two_way'`. Add `liveRoomName?: string` to `InterviewSession` (after `tavusConversationId?`). Add `ResultReport.manualReview?: { rating: number; notes: string; by?: string; at: string }`. Add `export interface TwoWayJoinResponse { roomUrl: string; token: string; isOwner: boolean }`.
  - `server/services/timing.ts` `tick()`: `if (session.track === 'chatbot' || session.track === 'video_avatar' || session.track === 'two_way') return false`.
  - `server/services/scoring.ts:61`: add `|| session.track === 'two_way'` to the conversation OR-list.
  - `server/routes/sessions.ts` report `isConversation`: add `|| session.track === 'two_way'`.
  - `server/services/signals.ts` `spoken`: add `|| session.track === 'two_way'`.
  - `server/routes/invites.ts`: `MODE_LABEL.two_way = 'Two-way Interview'`; `typeForMode` returns `'video'` for `video_avatar`/`video`/`two_way`.
  - `server/services/inviteBridge.ts` `trackForInvite`: allow `'two_way'`.
  - `server/routes/sessions.ts` `/track` guard + `/mine` mode allowlist: add `'two_way'`.
- [ ] **Step 3: run test → PASS**; both gates.
- [ ] **Step 4: commit** `feat(twoway): recognise 'two_way' conversation track end-to-end`.

---

## Task 2: `dailyServer.ts` — rooms + short-lived tokens (server-side key)

**Files:** Create `server/services/dailyServer.ts`, `server/services/dailyServer.test.ts`.
**Interfaces:** Produces `ensureRoom(sessionId): Promise<{ name: string; url: string }>`, `mintToken({ roomName, isOwner, userName }): Promise<string>`, `deleteRoom(name): Promise<void>`, `dailyConfigured(): boolean`. Pure helper `buildRoomProperties(nowSec)` (tested).

- [ ] **Step 1: failing test** — `dailyServer.test.ts`: assert `buildRoomProperties(now)` returns `{ enable_knocking: true, exp: > now, eject_at_room_exp: true }` and a token-properties builder sets `is_owner`/`room_name`/`user_name`/`exp` correctly. Run → FAIL.
- [ ] **Step 2: implement** `server/services/dailyServer.ts`:
```ts
/**
 * Server-side Daily client for the Two-way Interview. The DAILY_API_KEY stays
 * here; the browser only ever receives a room URL + a short-lived meeting token
 * (mirrors tavusServer.ts's server-held-key pattern). Recruiter joins as owner;
 * candidate joins non-owner with knocking (Daily's waiting room = the source's
 * lobby/admit).
 */
const DAILY_BASE = 'https://api.daily.co/v1'
const ROOM_TTL_SEC = 4 * 60 * 60      // room self-expires 4h after creation
const TOKEN_TTL_SEC = 3 * 60 * 60     // token valid 3h

export function dailyConfigured(): boolean {
  return Boolean((process.env.DAILY_API_KEY ?? '').trim())
}
function key(): string {
  const k = (process.env.DAILY_API_KEY ?? '').trim()
  if (!k) throw new HttpError(503, 'The two-way interview is not configured — set DAILY_API_KEY on the server.')
  return k
}
async function daily<T>(path: string, init: RequestInit): Promise<T> {
  const res = await fetch(`${DAILY_BASE}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${key()}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) },
  })
  if (!res.ok) {
    const err = await res.json().catch(() => null) as { info?: string; error?: string } | null
    throw new HttpError(502, err?.info ?? err?.error ?? `Daily error (HTTP ${res.status})`)
  }
  return res.json() as Promise<T>
}

/** Room properties — knocking on so the recruiter (owner) admits the candidate. */
export function buildRoomProperties(nowSec: number): Record<string, unknown> {
  return { enable_knocking: true, enable_screenshare: true, eject_at_room_exp: true, exp: nowSec + ROOM_TTL_SEC, start_video_off: false, start_audio_off: false }
}

/** Idempotent: create the room if absent, else return the existing one. */
export async function ensureRoom(roomName: string): Promise<{ name: string; url: string }> {
  try {
    return await daily(`/rooms/${roomName}`, { method: 'GET' })
  } catch {
    const now = Math.floor(Date.now() / 1000)
    return await daily('/rooms', { method: 'POST', body: JSON.stringify({ name: roomName, privacy: 'private', properties: buildRoomProperties(now) }) })
  }
}

export async function mintToken(opts: { roomName: string; isOwner: boolean; userName: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const r = await daily<{ token: string }>('/meeting-tokens', { method: 'POST', body: JSON.stringify({
    properties: { room_name: opts.roomName, is_owner: opts.isOwner, user_name: opts.userName.slice(0, 60), exp: now + TOKEN_TTL_SEC, ...(opts.isOwner ? { enable_recording: 'cloud' } : {}) },
  }) })
  return r.token
}

export async function deleteRoom(roomName: string): Promise<void> {
  try { await daily(`/rooms/${roomName}`, { method: 'DELETE' }) } catch (err) { console.error('[twoway] room delete failed', roomName, err) }
}
```
(Import `HttpError` from `../util/ah`. Note: `now`/`Date.now()` here run on the server at request time — fine; the plan's tests pass a fixed `nowSec`.)
- [ ] **Step 3: run test → PASS**; server tsc gate.
- [ ] **Step 4: commit** `feat(twoway): Daily rooms + short-lived tokens (server-side key)`.

---

## Task 3: server routes — host / join / complete / review

**Files:** `server/routes/sessions.ts` (new routes); `src/lib/api.ts` (client methods).
**Interfaces:** `POST /:id/twoway/host` → `TwoWayJoinResponse` (owner); `POST /:id/twoway/join` → `TwoWayJoinResponse` (candidate, knocking); `POST /:id/twoway/complete { recordingUrl? }` → `{ ok }` (mark completed → transcribe+score); `POST /:id/twoway/review { rating, notes }` → `{ ok }` (recruiter).

- [ ] **Step 1: implement the routes** (place near the avatar routes; reuse `load`, `assertOwner`, `requireRecruiter`, `maybeScore`). Room name is deterministic per session: `room-${session.id}` stored on `session.liveRoomName`. `host` requires recruiter/owner; `join` requires the assigned candidate (participant). `complete`: if `recordingUrl` given, set it as the session's recording and, after transcription, score. Sketch:
```ts
// Recruiter joins as owner (admits the candidate via Daily knocking).
sessionsRouter.post('/:id/twoway/host', requireRecruiter, ah(async (req, res) => {
  const { session } = load(req); assertOwner(session, requireAuth(req))
  if (session.track !== 'two_way') throw new HttpError(400, 'Not a two-way interview')
  const roomName = session.liveRoomName ?? `room-${session.id}`
  const room = await ensureRoom(roomName); session.liveRoomName = roomName
  if (session.status === 'created' || session.status === 'system_check') { session.status = 'in_progress'; session.startedAt ??= new Date().toISOString() }
  db.scheduleSave()
  const token = await mintToken({ roomName, isOwner: true, userName: 'Interviewer' })
  res.json({ roomUrl: room.url, token, isOwner: true } satisfies TwoWayJoinResponse)
}))

// Candidate joins (non-owner, knocking → waits for the recruiter to admit).
sessionsRouter.post('/:id/twoway/join', ah(async (req, res) => {
  const { session } = load(req)   // load() enforces participant access
  if (session.track !== 'two_way') throw new HttpError(400, 'Not a two-way interview')
  if (!session.liveRoomName) throw new HttpError(409, 'The interviewer has not started this interview yet.')
  const room = await ensureRoom(session.liveRoomName)
  const token = await mintToken({ roomName: session.liveRoomName, isOwner: false, userName: session.candidate.name || 'Candidate' })
  res.json({ roomUrl: room.url, token, isOwner: false } satisfies TwoWayJoinResponse)
}))

// End the call → complete → (recording already uploaded) → transcribe + score.
sessionsRouter.post('/:id/twoway/complete', ah(async (req, res) => {
  const { session, template } = load(req)
  if (session.track !== 'two_way') throw new HttpError(400, 'Not a two-way interview')
  const recordingUrl = typeof req.body?.recordingUrl === 'string' ? req.body.recordingUrl : ''
  if (session.status !== 'completed') { session.status = 'completed'; session.completedAt = new Date().toISOString() }
  if (session.liveRoomName) { void deleteRoom(session.liveRoomName) }
  db.scheduleSave()
  if (recordingUrl) {
    // transcribe the recording → conversation turns → score (reuse transcription.ts)
    try {
      const text = await transcribeVideoUrl(recordingUrl)
      session.mode = session.mode ?? 'conversational'
      session.transcript = session.transcript ?? []
      session.transcript.push(
        { id: randomUUID(), role: 'interviewer', turnType: 'question', questionIndex: 0, content: 'Live two-way interview', createdAt: new Date().toISOString() },
        { id: randomUUID(), role: 'candidate', questionIndex: 0, content: text, createdAt: new Date().toISOString() },
      )
      ;(session as InterviewSession & { recordingUrl?: string }).recordingUrl = recordingUrl
      db.scheduleSave()
    } catch (err) { console.error('[twoway] transcription failed', session.id, err) }
  }
  maybeScore(session, template)
  res.json({ ok: true })
}))

// Recruiter manual rating/notes (dual path alongside the AI scorecard).
sessionsRouter.post('/:id/twoway/review', requireRecruiter, ah((req, res) => {
  const { session } = load(req); assertOwner(session, requireAuth(req))
  const rating = Math.max(0, Math.min(5, Number(req.body?.rating) || 0))
  const notes = String(req.body?.notes ?? '').slice(0, 4000)
  const report = db.reports.get(session.id)
  if (report) { report.manualReview = { rating, notes, by: requireAuth(req).email, at: new Date().toISOString() }; db.reports.set(session.id, report); db.scheduleSave() }
  res.json({ ok: true })
}))
```
(Imports: `ensureRoom`, `mintToken`, `deleteRoom` from `../services/dailyServer`; `transcribeVideoUrl` from `../services/transcription`; `randomUUID`. The report view already surfaces recording playback via `videoUrl`/a recording field — see Task 7. For the transcript, reuse `buildVideoTranscript`-style turns; a single (interviewer, candidate) pair over the whole call is acceptable v1 since it's one continuous conversation.)
- [ ] **Step 2: client `api.ts`** — add `twowayHost(id)`, `twowayJoin(id)`, `twowayComplete(id, recordingUrl?)`, `twowayReview(id, {rating,notes})`.
- [ ] **Step 3: gates + commit** `feat(twoway): host/join/complete/review session routes`.

---

## Task 4: `useDailyCall` hook + `DailyVideoTile`

**Files:** Create `src/features/interview/useDailyCall.ts`, `src/components/interview/DailyVideoTile.tsx`.
**Interfaces:** `useDailyCall()` → `{ join(url, token), leave(), participants, localParticipant, toggleMic, toggleCam, muted, camOff, startRecording(), stopRecording(): Promise<Blob|null>, waitingParticipants, admit(id), callState }`. `DailyVideoTile({ participant })` renders its video+audio tracks.

- [ ] **Step 1: implement `useDailyCall`** using `@daily-co/daily-js` `createCallObject()`:
  - `join`: `co = DailyIframe.createCallObject({ subscribeToTracksAutomatically: true }); await co.join({ url, token })`. Track `participants` from `participant-joined/updated/left` events; `waiting-participant-added/updated` → `waitingParticipants`; `admit(id)` → `co.updateWaitingParticipant(id, { grantRequestedAccess: true })`.
  - `toggleMic`/`toggleCam` → `co.setLocalAudio(!muted)` / `co.setLocalVideo(!camOff)`.
  - Recording (owner side, client `MediaRecorder`): build a `MediaStream` from the remote candidate participant's `video`+`audio` `persistentTrack`s (+ local audio), `new MediaRecorder(stream, {mimeType:'video/webm'})`; `startRecording()` starts it; `stopRecording()` stops and resolves the `Blob`.
  - `leave`: `co.leave(); co.destroy()`. Clean up on unmount.
- [ ] **Step 2: implement `DailyVideoTile`** — attach `participant.tracks.video.persistentTrack` to a `<video>` (styled with the `CameraRecorder`/`AvatarStage` frame: `aspect-video rounded-xl border border-border bg-neutral-900 object-cover`) + audio track; name label + mic-muted indicator.
- [ ] **Step 3: build gate + commit** `feat(twoway): Daily call hook + participant video tile`.
(No unit test — Daily/WebRTC needs a browser; verified in the Task 5/8 end-to-end run.)

---

## Task 5: candidate `TwoWayStage` + routing

**Files:** Create `src/features/interview/screens/TwoWayStage.tsx`; modify `src/features/interview/TakeInterviewPage.tsx`, `src/features/interview/screens/SystemCheck.tsx` (camera check for `two_way`).

- [ ] **Step 1: `TwoWayStage`** — reuse the `AvatarStage` full-screen dark room shell + `VoiceStage` circular control bar. Flow: `VideoSystemCheck`/consent → `sessionsApi.twowayJoin(id)` → `useDailyCall().join(roomUrl, token)` → show "Waiting for the interviewer to admit you…" until joined (Daily knocking) → render the interviewer tile (remote) big + self-preview (local) small → controls (mic/cam/leave). On leave → `sessionsApi.twowayComplete(id)` (no recordingUrl from the candidate) → Completion screen.
- [ ] **Step 2: route it** — `TakeInterviewPage.tsx`: `two_way` is conversational/full-screen (like `video_avatar`) — add `if (s.track === 'two_way' && (started || in_progress)) return <TwoWayStage .../>`; add `two_way` to the `conversational`/`fixedFormat`/`needsIntake` predicates as appropriate (skip the format picker; run a camera/mic system check).
- [ ] **Step 3: build gate; app-verify** (candidate lobby shows "waiting"); commit `feat(twoway): candidate live-call screen`.

---

## Task 6: recruiter `LiveInterviewPage` (host + admit + record + end)

**Files:** Create `src/features/recruiter/LiveInterviewPage.tsx`; modify `src/features/recruiter/SessionsPage.tsx` (a "Join live interview" action on `two_way` sessions), `src/App.tsx` (route, recruiter-guarded).

- [ ] **Step 1: `LiveInterviewPage`** — `sessionsApi.twowayHost(id)` → `useDailyCall().join(roomUrl, token)` (owner). Render candidate tile big + self small; controls: mic/cam/screen-share, **admit** waiting candidate (`waitingParticipants` → `admit(id)`), **Record** (start/stop → on stop, `uploadAnswerVideo`-style upload of the Blob to Firebase Storage → get URL), **End** → `stopRecording()` → upload → `sessionsApi.twowayComplete(id, recordingUrl)` → navigate to the report. Reuse the `AvatarStage` shell + `VoiceStage` controls; dark room.
- [ ] **Step 2: SessionsPage action + route** — for `two_way` sessions show **"Join live interview"** → `/live/:id`; register `RequireRecruiter` route in `App.tsx`.
- [ ] **Step 3: build gate; commit** `feat(twoway): recruiter live host page (admit/record/end)`.

---

## Task 7: recording → Firebase Storage + results (playback + scorecard)

**Files:** modify `src/features/recruiter/ReportPage.tsx`; reuse `src/lib/storage.ts` (`uploadAnswerVideo`, generalize the path). Ensure the report view surfaces the recording URL.

- [ ] **Step 1: recording upload** — in `LiveInterviewPage` end flow, upload the recorded `Blob` via a storage helper (`interviews/${sessionId}/two-way.webm`) → `recordingUrl`; pass to `twowayComplete`. (Generalize `uploadAnswerVideo` or add `uploadSessionRecording(sessionId, blob)`.)
- [ ] **Step 2: report** — `ReportPage` for `two_way`: it's `isConversation`, so transcript + speech + sentiment + the Gemini scorecard already render. Add a `<video controls src={recordingUrl}>` playback block (reuse the `CameraRecorder` frame styling) when the session has a recording; add `TRACK_LABEL.two_way = 'Two-way Interview'`.
- [ ] **Step 3: build gate; app-verify** (report shows recording + scorecard); commit `feat(twoway): recording→Storage + results playback`.

---

## Task 8: manual review UI + env/docs/Capacitor

**Files:** modify `src/features/recruiter/ReportPage.tsx` (manual-review panel); `.env.example`; `docs/TWO_WAY_INTERVIEW.md`.

- [ ] **Step 1: manual review** — a small "Interviewer review" card on `ReportPage` for `two_way`: star rating (0-5) + notes textarea → `sessionsApi.twowayReview(id, {rating, notes})`; render existing `report.manualReview` if present.
- [ ] **Step 2: env + docs** — `.env.example`: `DAILY_API_KEY=` (+ optional `DAILY_SUBDOMAIN=`) with a comment (server-side; mints rooms + short-lived tokens). `docs/TWO_WAY_INTERVIEW.md`: the flow, Daily setup (create a Daily account → API key; knocking waiting-room; cloud vs client recording), Firebase Storage prerequisite, and the Capacitor Android note (CAMERA + RECORD_AUDIO perms; Daily supports the webview).
- [ ] **Step 3: commit** `docs(twoway): env vars, Daily setup, Capacitor notes`.

---

## Verification (acceptance)
- "Two-way Interview" card in the selector; recruiter creates an invite; candidate opens `/take/:id` → lobby → admitted; recruiter joins `/live/:id` → live low-latency call (Daily); both see/hear each other.
- Recruiter records → recording lands in Firebase Storage; on end, Deepgram transcript → Gemini scorecard on the report; recording plays back; interviewer manual rating/notes save + show.
- Keys server-side (only short-lived Daily tokens reach the client); frozen modules untouched (git-diff); `two_way` is conversation-scored + non-timed; other tracks unaffected; both build gates green.

## Known considerations / follow-ups
- **Daily tier:** client `MediaRecorder` recording is tier-independent (chosen default). Daily **cloud recording** (`enable_recording: 'cloud'` on the owner token) is a paid-tier upgrade that offloads compositing/reliability — swap Task 6/7's client recorder for a Daily webhook → fetch → Storage if you move to it.
- **Scheduling:** v1 is "join now" (recruiter starts the room, candidate knocks). A scheduled start time (`scheduledAt`) + reminder emails is a follow-up.
- **Transcript granularity:** v1 stores one (interviewer, candidate) transcript pair for the whole call (Deepgram diarization could split speakers per-utterance later).
- **Capacitor:** verify Daily in the Android webview on device (permissions + `getUserMedia`).
