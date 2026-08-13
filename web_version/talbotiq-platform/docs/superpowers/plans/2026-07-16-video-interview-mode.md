# Video Interview Mode — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-way, recorded **Video Interview** mode to TalbotIQ — a faithful port of the source `video-interview` (Django) project's only real feature — that plugs into TalbotIQ's existing mode/invite/session/scoring/results pipeline and design system as a new `TrackType`.

**Architecture:** A new `TrackType: 'video'` reuses TalbotIQ's existing **timed per-question engine** (`chat` track). Per question: 30s prep → the answer window auto-starts a `MediaRecorder` webcam recording → the candidate submits → the recorded clip is uploaded to **Firebase Storage** (client-side, authenticated) → its download URL is stored on the existing (already-threaded) `SubmitAnswerRequest.videoUrl` field → the server transcribes the clip's audio with **Deepgram** (pre-recorded, key stays server-side) into `answerText` → the existing **Gemini per-question scoring** runs unchanged. The recruiter report reuses `ReportPage` and adds a `<video>` playback block plus the existing **AWS Rekognition `FacialAnalysisPanel`**, fed by facial frames captured on the candidate's device during recording.

**Tech Stack:** Vite + React 18 + TypeScript (client), Express + `tsx` (server), Firebase Auth/Firestore + **Firebase Storage** (web SDK v12, modular), Deepgram Nova-3 (pre-recorded REST), Google Gemini (`@google/genai`), AWS Rekognition (`@aws-sdk/client-rekognition` via the existing proxy), `lucide-react`, Tailwind. Tests are standalone scripts run with `npx tsx <file>` (repo convention — there is **no** vitest/jest).

## Global Constraints

- **New mode value:** add `'video'` to `TrackType` (`shared/types.ts:9`). Do NOT reuse or rename `'video_avatar'` (that is the live Tavus avatar mode).
- **Reuse, do not rename, the existing `videoUrl` fields:** `SubmitAnswerRequest.videoUrl` (`shared/types.ts:392`), `SessionQuestion.videoUrl` (`:226`), `SessionReportQuestion.videoUrl` (`:434`). They are already threaded end-to-end.
- **Frozen — do NOT modify contracts:** the `sessions` / `templates` / `question-sets` route shapes, the Firestore `interviews` field names (`server/routes/invites.ts:106-125`), the `InterviewSession` / `ResultReport` existing field names, and all Tavus internals (`tavusServer.ts`, `AvatarStage.tsx`, `SetupPage` apply flow). Every change in this plan is **additive** (a new enum value, new optional fields, new files, new routes).
- **All third-party keys stay server-side:** `DEEPGRAM_API_KEY`, `GEMINI_API_KEY`, AWS creds (via the existing Rekognition proxy). The ONLY client-side credential is the **public** Firebase web config (already in `src/lib/firebase.ts`), used for authenticated Storage uploads.
- **Interop:** the Firestore `interviews.type` field stays `'video' | 'chat'`; the precise web mode rides on the additive `mode` field, exactly as the other modes do.
- **Timing matches the source:** reuse `DEFAULT_TIMING` (`server/store/defaults.ts:14` — prep 30s / answer 120s / warning 15s), which already equals the source's `PREP_SECS=30` / `MAX_SECONDS=120`.
- **Quality gates for every task:** `npm run build` (tsc + vite build) and `npm run lint` (eslint, `--max-warnings 0`) must pass before the task's commit.

---

## File Structure

**New files**
- `src/lib/storage.ts` — Firebase Storage upload helper (`uploadAnswerVideo`).
- `storage.rules` — Firebase Storage security rules (authenticated writes to `interviews/{sessionId}/…`).
- `server/services/transcription.ts` — Deepgram pre-recorded transcription of a video/audio URL.
- `server/services/transcription.test.ts` — `tsx` test for the Deepgram response parser.
- `server/services/videoTrack.test.ts` — `tsx` test proving the `video` track advances through the timed engine and routes to per-question scoring.
- `server/services/inviteBridge.test.ts` — `tsx` test for `trackForInvite`/`typeForMode` handling `'video'`.
- `src/features/interview/useAnswerRecorder.ts` — hook owning the shared camera stream + `MediaRecorder` (start/stop/getBlob) and optional Rekognition frame capture.
- `src/features/interview/screens/VideoStage.tsx` — the record → submit answer screen for the `video` track.
- `src/features/interview/screens/VideoIntro.tsx` — the "Before you begin" consent/checklist gate (ports the source `record.html` consent step) shown before recording.

**Modified files**
- `shared/types.ts` — add `'video'` to `TrackType`; add `facial?` to `SessionReportView`; add `facialSummary?` to `InterviewSession`.
- `server/routes/invites.ts` — `MODE_LABEL` + `typeForMode` recognise `'video'`.
- `server/services/inviteBridge.ts` — `trackForInvite` allowlist includes `'video'`.
- `server/routes/sessions.ts` — `/track` guard + `/mine` mode allowlist include `'video'`; `/answers` transcribes video answers; new `POST /:id/facial` route; report view includes `facial`.
- `src/features/recruiter/InviteWizard.tsx` — add the "Video Interview" mode card.
- `src/features/recruiter/SessionsPage.tsx` — add the `video` track badge label.
- `src/features/recruiter/ReportPage.tsx` — `TRACK_LABEL` + video playback block + `FacialAnalysisPanel`.
- `src/features/interview/TakeInterviewPage.tsx` — route the `video` track to `VideoStage`; skip the format picker for it.
- `src/features/interview/useInterviewClock.ts` — `submit` accepts an optional `videoUrl`.
- `src/lib/api.ts` — `submitAnswer` already carries `videoUrl` (no change); add `facial` client method.
- `.env.example` — document `DEEPGRAM_API_KEY` (if not present) + Firebase Storage bucket + AWS proxy for facial.
- `docs/AUTH.md` or a new `docs/VIDEO_INTERVIEW.md` — deploy/permission notes (Storage rules, Capacitor CAMERA/RECORD_AUDIO).

---

## Task 1: Recognise the `video` track server-side (types + engine wiring)

Make `'video'` a first-class track that the existing timed engine, invite bridge, and scoring already handle. No new runtime behaviour yet — just recognition so a `video` session can be created, advanced, and scored per-question.

**Files:**
- Modify: `shared/types.ts:9`
- Modify: `server/routes/invites.ts:34-35`
- Modify: `server/services/inviteBridge.ts:32`
- Modify: `server/routes/sessions.ts:200`, `server/routes/sessions.ts:791`
- Test: `server/services/inviteBridge.test.ts` (new), `server/services/videoTrack.test.ts` (new)

**Interfaces:**
- Produces: `TrackType` now includes `'video'`. `trackForInvite(data)` returns `'video'` when `data.mode === 'video'`. `typeForMode('video') === 'video'`. `MODE_LABEL.video === 'Video Interview'`.

- [ ] **Step 1: Write the failing test for the invite bridge**

Create `server/services/inviteBridge.test.ts`:

```ts
/**
 * Deterministic unit tests for the invite → track mapping. Run with:
 *   npx tsx server/services/inviteBridge.test.ts
 * No Firestore / network needed — trackForInvite/typeForMode are pure.
 */
import { __test } from './inviteBridge'
import { typeForMode } from '../routes/invites'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

console.log('\n=== invite → track mapping ===')
assert("mode 'video' → track 'video'", __test.trackForInvite({ mode: 'video' }) === 'video')
assert("mode 'chat' → track 'chat'", __test.trackForInvite({ mode: 'chat' }) === 'chat')
assert("no mode, type 'video' → 'video_avatar' (legacy fallback)", __test.trackForInvite({ type: 'video' }) === 'video_avatar')
assert("typeForMode('video') === 'video'", typeForMode('video') === 'video')
assert("typeForMode('chat') === 'chat'", typeForMode('chat') === 'chat')

console.log(`\n${failures === 0 ? '✅ ALL INVITE-BRIDGE TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx tsx server/services/inviteBridge.test.ts`
Expected: FAIL — `trackForInvite` is not exported (`__test` undefined) and `typeForMode` is not exported from `invites.ts`.

- [ ] **Step 3: Add `'video'` to the union**

In `shared/types.ts:9`, change:
```ts
export type TrackType = 'chat' | 'chatbot' | 'video_avatar' | 'voice'
```
to:
```ts
export type TrackType = 'chat' | 'chatbot' | 'video_avatar' | 'voice' | 'video'
```
And update the `videoUrl` comment at `shared/types.ts:226` from `// video avatar track` to `// video interview + video avatar tracks`.

- [ ] **Step 4: Export the mappings and add `'video'`**

In `server/routes/invites.ts:34`, change:
```ts
const typeForMode = (mode: TrackType): 'video' | 'chat' => (mode === 'video_avatar' ? 'video' : 'chat')
const MODE_LABEL: Record<string, string> = { chatbot: 'Chatbot', voice: 'Voice', video_avatar: 'Video Avatar', chat: 'Timed Q&A' }
```
to:
```ts
export const typeForMode = (mode: TrackType): 'video' | 'chat' =>
  (mode === 'video_avatar' || mode === 'video' ? 'video' : 'chat')
export const MODE_LABEL: Record<string, string> = {
  chatbot: 'Chatbot', voice: 'Voice', video_avatar: 'Video Avatar', chat: 'Timed Q&A', video: 'Video Interview',
}
```

In `server/services/inviteBridge.ts:30-34`, change:
```ts
function trackForInvite(data: Record<string, unknown>): TrackType {
  const mode = data.mode as string | undefined
  if (mode === 'chatbot' || mode === 'voice' || mode === 'video_avatar' || mode === 'chat') return mode
  return data.type === 'video' ? 'video_avatar' : 'chat' // fall back from the Flutter `type`
}
```
to:
```ts
function trackForInvite(data: Record<string, unknown>): TrackType {
  const mode = data.mode as string | undefined
  if (mode === 'chatbot' || mode === 'voice' || mode === 'video_avatar' || mode === 'chat' || mode === 'video') return mode
  return data.type === 'video' ? 'video_avatar' : 'chat' // fall back from the Flutter `type`
}

/** Test-only surface (pure helpers). */
export const __test = { trackForInvite }
```

- [ ] **Step 5: Add `'video'` to the two `sessions.ts` guards**

In `server/routes/sessions.ts:200`, change:
```ts
  if (track !== 'chat' && track !== 'chatbot' && track !== 'video_avatar' && track !== 'voice')
    throw new HttpError(400, 'Invalid track')
```
to:
```ts
  if (track !== 'chat' && track !== 'chatbot' && track !== 'video_avatar' && track !== 'voice' && track !== 'video')
    throw new HttpError(400, 'Invalid track')
```

In `server/routes/sessions.ts:790-793`, change:
```ts
      const mode = d.mode as string | undefined
      const track = (mode === 'chatbot' || mode === 'voice' || mode === 'video_avatar' || mode === 'chat')
        ? mode
        : d.type === 'video' ? 'video_avatar' as const : 'chat' as const
```
to:
```ts
      const mode = d.mode as string | undefined
      const track = (mode === 'chatbot' || mode === 'voice' || mode === 'video_avatar' || mode === 'chat' || mode === 'video')
        ? mode
        : d.type === 'video' ? 'video_avatar' as const : 'chat' as const
```

- [ ] **Step 6: Run the invite-bridge test to verify it passes**

Run: `npx tsx server/services/inviteBridge.test.ts`
Expected: PASS (all 5 assertions).

- [ ] **Step 7: Write the failing test for engine + scoring routing**

Create `server/services/videoTrack.test.ts`:

```ts
/**
 * The `video` track reuses the timed per-question engine (like `chat`) and the
 * per-question (non-conversational) scoring branch. Run with:
 *   npx tsx server/services/videoTrack.test.ts
 */
import { tick } from './timing'
import { heuristicReport } from './scoring'
import { DEFAULT_TIMING, DEFAULT_INTEGRITY, DEFAULT_BRANDING, defaultRubric } from '../store/defaults'
import type { InterviewSession, InterviewTemplate } from '../../shared/types'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

function makeTemplate(): InterviewTemplate {
  return {
    id: 't1', name: 'Video', role: 'Engineer', track: 'video', questionSource: 'fixed',
    timing: { ...DEFAULT_TIMING }, rubric: defaultRubric(),
    integrity: { ...DEFAULT_INTEGRITY }, branding: { ...DEFAULT_BRANDING },
    createdAt: 'now', updatedAt: 'now',
  }
}
function makeSession(startMsAgo: number): InterviewSession {
  const started = new Date(Date.now() - startMsAgo).toISOString()
  return {
    id: 's1', templateId: 't1', track: 'video',
    candidate: { name: 'A', email: 'a@x.com' }, status: 'in_progress',
    questions: [{ id: 'q1', text: 'Q1', autoSubmitted: false, prepStartedAt: started }],
    currentIndex: 0, createdAt: started, startedAt: started, integrityEvents: [], tabSwitchCount: 0,
  }
}

console.log('\n=== video track: timed engine applies ===')
{
  // prep started 31s ago (> 30s prep) → tick should open the answer phase.
  const s = makeSession(31_000)
  const changed = tick(s, makeTemplate())
  assert('tick mutates a video session (NOT exempt like chatbot/avatar)', changed === true)
  assert('answer phase opened after prep elapsed', Boolean(s.questions[0].answerStartedAt))
}

console.log('\n=== video track: per-question scoring shape ===')
{
  const s = makeSession(0)
  s.questions[0].answerText = 'I built distributed systems for six years handling high load.'
  s.questions[0].submittedAt = new Date().toISOString()
  s.status = 'completed'
  const report = heuristicReport(s, makeTemplate())
  assert('scored per-question by questionId (not q0 transcript group)', report.perQuestion[0].questionId === 'q1')
  assert('overall score is computed', typeof report.overallScore === 'number')
}

console.log(`\n${failures === 0 ? '✅ ALL VIDEO-TRACK TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 8: Run it to verify it passes (engine already supports `video`)**

Run: `npx tsx server/services/videoTrack.test.ts`
Expected: PASS. `timing.tick` (`server/services/timing.ts:49`) exempts only `chatbot`/`video_avatar`, so `video` gets the timed engine; `scoreSession` (`server/services/scoring.ts:61`) routes only `chatbot`/`video_avatar`/`voice` to conversation scoring, so `video` uses `heuristicReport`/`scoreWithGemini` per-question. If either test fails, that assumption is wrong — stop and reconcile before proceeding.

- [ ] **Step 9: Build, lint, commit**

Run: `npm run build && npm run lint`
Expected: both pass.
```bash
git add shared/types.ts server/routes/invites.ts server/services/inviteBridge.ts server/routes/sessions.ts server/services/inviteBridge.test.ts server/services/videoTrack.test.ts
git commit -m "feat(video): recognise the 'video' interview track server-side"
```

---

## Task 2: Add the "Video Interview" mode card + skip the candidate format picker

Surface the new mode in the recruiter invite wizard (existing card UI) and make the candidate flow skip the "Choose your format" screen for it (the mode is fixed by the invite, exactly like the conversational tracks).

**Files:**
- Modify: `src/features/recruiter/InviteWizard.tsx:5`, `:26`, `:29-34`
- Modify: `src/features/recruiter/SessionsPage.tsx` (track label map)
- Modify: `src/features/interview/TakeInterviewPage.tsx:124`, `:130`

**Interfaces:**
- Consumes: `TrackType` including `'video'` (Task 1).
- Produces: recruiters can pick "Video Interview" in Step 1; a `video` invite lands the candidate on Welcome (not TrackSelect).

- [ ] **Step 1: Add the recruiter mode card**

In `src/features/recruiter/InviteWizard.tsx:5`, add `Clapperboard` to the lucide import (keep the rest):
```ts
import { MessageSquare, Mic, Video, Clock, Clapperboard, ArrowLeft, Check, FileText, Layers, Plus, UploadCloud, Trash2, AlertTriangle, Loader2, CheckCircle2, Copy } from 'lucide-react'
```

In `src/features/recruiter/InviteWizard.tsx:26`, extend the `Mode` type:
```ts
type Mode = Extract<TrackType, 'chatbot' | 'voice' | 'video_avatar' | 'chat' | 'video'>
```

In `src/features/recruiter/InviteWizard.tsx:29-34`, add the card to the `MODES` array (after the `chat` entry):
```ts
const MODES: { value: Mode; label: string; blurb: string; icon: React.ReactNode }[] = [
  { value: 'chatbot',      label: 'Chatbot',      blurb: 'Conversational, typed — ChatGPT-style.',   icon: <MessageSquare size={20} /> },
  { value: 'voice',        label: 'Voice',        blurb: 'Live spoken AI interviewer (Gemini Live).', icon: <Mic size={20} /> },
  { value: 'video_avatar', label: 'Video Avatar', blurb: 'Conversational AI video avatar (Tavus).',   icon: <Video size={20} /> },
  { value: 'chat',         label: 'Timed Q&A',    blurb: '30s prep + timed answers (HireVue-style).', icon: <Clock size={20} /> },
  { value: 'video',        label: 'Video Interview', blurb: 'Candidate records webcam answers per question.', icon: <Clapperboard size={20} /> },
]
```
No gating is needed (unlike `video_avatar`, which requires an applied avatar) — the existing card click handler already just `setMode(m.value)` for non-avatar modes.

- [ ] **Step 2: Add the candidate list badge label**

In `src/features/recruiter/SessionsPage.tsx`, find the track-label map (grep for `video_avatar` — the agent located it near `:139`). Add a `video` sibling entry, e.g. within the existing `Record<string,string>` label map:
```ts
video: 'Video Interview',
```
(Match the exact key style already used for `video_avatar` in that file.)

- [ ] **Step 3: Skip the format picker for the `video` track**

In `src/features/interview/TakeInterviewPage.tsx:124`, change:
```ts
  const conversational = s.track === 'chatbot' || s.track === 'video_avatar' || s.track === 'voice'
```
to (add a `fixedFormat` flag that also covers `video` — the mode is fixed by the invite, so "Choose your format" should not appear, but `video` is NOT engine-driven so it must stay out of `conversational`):
```ts
  const conversational = s.track === 'chatbot' || s.track === 'video_avatar' || s.track === 'voice'
  // Video Interview's format is fixed by the invite too — skip "choose format",
  // but it runs on the timed engine (not the conversational full-screen engines).
  const fixedFormat = conversational || s.track === 'video'
```
Then at `src/features/interview/TakeInterviewPage.tsx:130`, change:
```ts
  const step: PreStep = conversational && preStep === 'track' ? 'welcome' : preStep
```
to:
```ts
  const step: PreStep = fixedFormat && preStep === 'track' ? 'welcome' : preStep
```
Leave the `SystemCheck` `onBegin` logic unchanged: `if (conversational) setChatbotStarted(true); else clock.begin()` — `video` is not `conversational`, so it correctly calls `clock.begin()` (the timed engine).

- [ ] **Step 4: Verify in the app**

Run: `npm run dev`
- As a recruiter, open **Invite candidates** (`/sessions/new`). Confirm a fifth card, **Video Interview**, renders with the film icon and selects like the others.
- Create an invite with mode = Video Interview for a candidate email you control; confirm the success screen lists an invite link.
- (Full candidate run happens in Task 5; here just confirm the card + invite creation and that no TypeScript/console errors appear.)

- [ ] **Step 5: Build, lint, commit**

Run: `npm run build && npm run lint`
```bash
git add src/features/recruiter/InviteWizard.tsx src/features/recruiter/SessionsPage.tsx src/features/interview/TakeInterviewPage.tsx
git commit -m "feat(video): add Video Interview mode card + skip format picker"
```

---

## Task 3: Firebase Storage upload helper + security rules

Wire Firebase Storage (configured but unused today) so the candidate browser can upload a recorded clip and get a download URL. The URL goes into the existing `videoUrl` field.

**Files:**
- Create: `src/lib/storage.ts`
- Create: `storage.rules`
- Modify: `docs` (deploy note — folded into Task 8)

**Interfaces:**
- Produces: `uploadAnswerVideo(sessionId: string, questionId: string, blob: Blob): Promise<string>` → resolves to a Firebase Storage **download URL** (tokenised; readable by the recruiter without auth).

- [ ] **Step 1: Create the Storage helper**

Create `src/lib/storage.ts`:
```ts
import { getStorage, ref, uploadBytes, getDownloadURL, type FirebaseStorage } from 'firebase/storage'
import { firebaseAuth } from './firebase'

/**
 * Firebase Storage bootstrap. Reuses the initialised app from firebase.ts (via
 * firebaseAuth().app) so we don't double-init. The web config is public by
 * design; write access is enforced by storage.rules (authenticated users only).
 */
let storageInstance: FirebaseStorage | undefined
function storage(): FirebaseStorage {
  if (!storageInstance) storageInstance = getStorage(firebaseAuth().app)
  return storageInstance
}

/**
 * Upload one recorded answer clip and return its download URL. Path is namespaced
 * per session + question so re-records overwrite cleanly. The returned URL carries
 * a Storage access token, so the recruiter report can play it back without auth.
 */
export async function uploadAnswerVideo(sessionId: string, questionId: string, blob: Blob): Promise<string> {
  const path = `interviews/${sessionId}/${questionId}.webm`
  const r = ref(storage(), path)
  await uploadBytes(r, blob, { contentType: blob.type || 'video/webm' })
  return getDownloadURL(r)
}
```

- [ ] **Step 2: Create the Storage security rules**

Create `storage.rules` at the repo root:
```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Interview answer clips: any authenticated user (candidate) may write to a
    // session folder; reads use the tokenised download URL (getDownloadURL), so
    // no broad read rule is granted. 50 MB / clip ceiling, video only.
    match /interviews/{sessionId}/{fileName} {
      allow write: if request.auth != null
                   && request.resource.size < 50 * 1024 * 1024
                   && request.resource.contentType.matches('video/.*');
      allow read: if request.auth != null;
    }
  }
}
```

- [ ] **Step 3: Type-check the helper**

Run: `npm run build`
Expected: passes. `firebase/storage` ships with the `firebase` package (v12) already in `package.json:33` — no new dependency.

- [ ] **Step 4: Commit**

(Deployment of `storage.rules` is a manual `firebase deploy --only storage` step documented in Task 8; do not deploy here.)
```bash
git add src/lib/storage.ts storage.rules
git commit -m "feat(video): add Firebase Storage upload helper + rules"
```

---

## Task 4: Deepgram pre-recorded transcription of video answers

Transcribe a recorded clip's audio server-side (Deepgram, key stays server-side) so the existing Gemini scoring has `answerText`. Triggered inside `/answers` only for the `video` track.

**Files:**
- Create: `server/services/transcription.ts`
- Create: `server/services/transcription.test.ts`
- Modify: `server/routes/sessions.ts:554`, `:571-576`

**Interfaces:**
- Produces: `transcribeVideoUrl(url: string): Promise<string>` → the transcript text (empty string on failure/no speech). `parseDeepgramTranscript(json: unknown): string` (pure, tested).

- [ ] **Step 1: Write the failing test for the response parser**

Create `server/services/transcription.test.ts`:
```ts
/**
 * Deterministic test for the Deepgram pre-recorded response parser. Run with:
 *   npx tsx server/services/transcription.test.ts
 * No network — we feed a canned Deepgram JSON shape.
 */
import { parseDeepgramTranscript } from './transcription'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

console.log('\n=== deepgram transcript parsing ===')
const ok = {
  results: { channels: [{ alternatives: [{ transcript: 'I built distributed systems.' }] }] },
}
assert('extracts the first alternative transcript', parseDeepgramTranscript(ok) === 'I built distributed systems.')
assert('empty channels → empty string', parseDeepgramTranscript({ results: { channels: [] } }) === '')
assert('garbage → empty string', parseDeepgramTranscript(null) === '' && parseDeepgramTranscript({}) === '')

console.log(`\n${failures === 0 ? '✅ ALL TRANSCRIPTION TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx tsx server/services/transcription.test.ts`
Expected: FAIL — module `./transcription` does not exist.

- [ ] **Step 3: Implement the transcription service**

Create `server/services/transcription.ts`:
```ts
/**
 * Deepgram pre-recorded transcription for the Video Interview track. The key
 * stays server-side (same key as the live relay in deepgramRelay.ts). We fetch
 * the uploaded clip by its Firebase Storage download URL and POST the bytes to
 * Deepgram's pre-recorded /v1/listen endpoint.
 */
const DG_URL = 'https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&punctuate=true&language=en-US'

/** Pure extractor — the first channel's first alternative transcript, or ''. */
export function parseDeepgramTranscript(json: unknown): string {
  const j = json as { results?: { channels?: Array<{ alternatives?: Array<{ transcript?: string }> }> } }
  const t = j?.results?.channels?.[0]?.alternatives?.[0]?.transcript
  return typeof t === 'string' ? t.trim() : ''
}

/** Transcribe a clip at `url`. Returns '' on any failure or when no key is set. */
export async function transcribeVideoUrl(url: string): Promise<string> {
  const key = (process.env.DEEPGRAM_API_KEY ?? '').trim()
  if (!key || !url) return ''
  const media = await fetch(url)
  if (!media.ok) throw new Error(`could not fetch clip (${media.status})`)
  const bytes = Buffer.from(await media.arrayBuffer())
  const res = await fetch(DG_URL, {
    method: 'POST',
    headers: { Authorization: `Token ${key}`, 'Content-Type': media.headers.get('content-type') || 'video/webm' },
    body: bytes,
  })
  if (!res.ok) throw new Error(`deepgram ${res.status}`)
  return parseDeepgramTranscript(await res.json())
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx tsx server/services/transcription.test.ts`
Expected: PASS (3 assertions).

- [ ] **Step 5: Wire transcription into `/answers` for the video track**

In `server/routes/sessions.ts:14-15` add the import (near the other service imports):
```ts
import { transcribeVideoUrl } from '../services/transcription'
```
In `server/routes/sessions.ts:554`, change the handler to async:
```ts
sessionsRouter.post('/:id/answers', ah(async (req, res) => {
```
In `server/routes/sessions.ts:571-576`, change:
```ts
  const now = new Date().toISOString()
  q.answerText =
    typeof req.body?.answerText === 'string' ? req.body.answerText : q.draft ?? ''
  if (req.body?.videoUrl) q.videoUrl = req.body.videoUrl
  q.submittedAt = now
  q.autoSubmitted = false
```
to:
```ts
  const now = new Date().toISOString()
  q.answerText =
    typeof req.body?.answerText === 'string' ? req.body.answerText : q.draft ?? ''
  if (req.body?.videoUrl) q.videoUrl = req.body.videoUrl
  // Video Interview: no typed text — transcribe the recorded clip (Deepgram,
  // key server-side) so the existing per-question Gemini scoring has content.
  if (session.track === 'video' && q.videoUrl && !q.answerText.trim()) {
    try { q.answerText = await transcribeVideoUrl(q.videoUrl) }
    catch (err) { console.error('[transcribe] failed for', session.id, q.id, err) }
  }
  q.submittedAt = now
  q.autoSubmitted = false
```

- [ ] **Step 6: Build, lint, run both server tests, commit**

Run: `npm run build && npm run lint && npx tsx server/services/transcription.test.ts`
```bash
git add server/services/transcription.ts server/services/transcription.test.ts server/routes/sessions.ts
git commit -m "feat(video): transcribe recorded answers with Deepgram in /answers"
```

---

## Task 5: The candidate Video Interview screen (record → upload → submit)

The core deliverable: a native-looking recording screen for the `video` track that ports the source's per-question record flow onto TalbotIQ's timed engine and design system.

**Files:**
- Create: `src/features/interview/useAnswerRecorder.ts`
- Create: `src/features/interview/screens/VideoIntro.tsx`
- Create: `src/features/interview/screens/VideoStage.tsx`
- Modify: `src/features/interview/useInterviewClock.ts:106-110`
- Modify: `src/features/interview/TakeInterviewPage.tsx` (route `video` → `VideoStage`)

**Interfaces:**
- Consumes: `uploadAnswerVideo` (Task 3); `clock.submit(answerText, videoUrl?)`.
- Produces: a working end-to-end candidate flow for the `video` track.

- [ ] **Step 1: Extend the clock's `submit` to carry a `videoUrl`**

In `src/features/interview/useInterviewClock.ts:106-110`, change:
```ts
  const submit = (answerText: string) => {
    const qid = state?.question?.id
    if (!qid) return Promise.resolve()
    return action(() => sessionsApi.submitAnswer(sessionId, { questionId: qid, answerText }))
  }
```
to:
```ts
  const submit = (answerText: string, videoUrl?: string) => {
    const qid = state?.question?.id
    if (!qid) return Promise.resolve()
    return action(() => sessionsApi.submitAnswer(sessionId, { questionId: qid, answerText, ...(videoUrl ? { videoUrl } : {}) }))
  }
```
(`QuestionStage`'s `onSubmit(text)` call is unaffected — the second arg is optional. `SubmitAnswerRequest.videoUrl` and `sessionsApi.submitAnswer` already accept it — no `api.ts`/types change.)

- [ ] **Step 2: Create the shared-stream recorder hook**

Create `src/features/interview/useAnswerRecorder.ts`:
```ts
import { useCallback, useEffect, useRef, useState } from 'react'

/**
 * Owns ONE camera+mic stream for the whole Video Interview and records the
 * current answer with MediaRecorder. One shared stream (not one per question)
 * so the camera LED comes on once and mobile webviews don't juggle two streams.
 * The same stream can be tapped for facial-frame capture (Task 7).
 */
export function useAnswerRecorder() {
  const streamRef = useRef<MediaStream | null>(null)
  const recorderRef = useRef<MediaRecorder | null>(null)
  const chunksRef = useRef<Blob[]>([])
  const [ready, setReady] = useState(false)
  const [recording, setRecording] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const acquire = useCallback(async () => {
    if (streamRef.current) return streamRef.current
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'user' }, audio: true })
      streamRef.current = stream
      setReady(true)
      return stream
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Camera/microphone access is required')
      throw e
    }
  }, [])

  const startRecording = useCallback(() => {
    const stream = streamRef.current
    if (!stream || recorderRef.current) return
    const mime = MediaRecorder.isTypeSupported('video/webm;codecs=vp8,opus') ? 'video/webm;codecs=vp8,opus' : 'video/webm'
    const rec = new MediaRecorder(stream, { mimeType: mime })
    chunksRef.current = []
    rec.ondataavailable = (e) => { if (e.data.size) chunksRef.current.push(e.data) }
    rec.start()
    recorderRef.current = rec
    setRecording(true)
  }, [])

  /** Stop and resolve the recorded clip (waits for the final dataavailable). */
  const stopRecording = useCallback((): Promise<Blob> => {
    return new Promise((resolve) => {
      const rec = recorderRef.current
      if (!rec) { resolve(new Blob([], { type: 'video/webm' })); return }
      rec.onstop = () => {
        const blob = new Blob(chunksRef.current, { type: 'video/webm' })
        recorderRef.current = null
        setRecording(false)
        resolve(blob)
      }
      rec.stop()
    })
  }, [])

  // Release the camera on unmount (once — the whole interview shares this stream).
  useEffect(() => () => { streamRef.current?.getTracks().forEach((t) => t.stop()) }, [])

  const attachPreview = useCallback((el: HTMLVideoElement | null) => {
    if (el && streamRef.current) el.srcObject = streamRef.current
  }, [])

  return { ready, recording, error, acquire, startRecording, stopRecording, attachPreview, streamRef }
}
```

- [ ] **Step 3: Create the consent gate (ports the source `record.html` "Before you begin")**

Create `src/features/interview/screens/VideoIntro.tsx`:
```tsx
import { useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { Camera, Mic, ShieldCheck, CheckCircle2 } from 'lucide-react'
import type { BrandingConfig } from '@shared/types'

interface Props {
  branding: BrandingConfig
  onBegin: () => void
  busy?: boolean
}

/** "Before you begin" consent + device checklist, ported from the source's
 *  record.html gate. Enabling "Begin" requires acknowledging AI analysis. */
export function VideoIntro({ branding, onBegin, busy }: Props) {
  const reduce = useReducedMotion()
  const [consent, setConsent] = useState(false)
  const checks = [
    { icon: Camera, label: 'Camera on', hint: 'Your webcam records each answer. Close other apps using the camera (Zoom, Teams, Meet).' },
    { icon: Mic, label: 'Microphone on', hint: 'Speak clearly — your spoken answer is transcribed and scored.' },
    { icon: ShieldCheck, label: 'Quiet, well-lit space', hint: 'You get 30s to prepare, then up to 2 minutes to answer each question.' },
  ]
  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="rounded-2xl border border-border bg-white p-8 shadow-sm"
    >
      <h1 className="text-2xl font-bold tracking-tight text-neutral-900">Video interview — before you begin</h1>
      <p className="mt-2 text-sm text-neutral-500">You’ll answer each question on camera. Here’s how it works.</p>
      <ul className="mt-6 space-y-3">
        {checks.map((c, i) => {
          const Icon = c.icon
          return (
            <li key={i} className="flex items-start gap-3 rounded-xl border border-border bg-neutral-50 p-4">
              <span className="mt-0.5 flex h-9 w-9 items-center justify-center rounded-lg" style={{ background: branding.accentColor + '14', color: branding.accentColor }}>
                <Icon size={18} />
              </span>
              <div>
                <p className="text-sm font-semibold text-neutral-800">{c.label}</p>
                <p className="mt-0.5 text-xs text-neutral-500">{c.hint}</p>
              </div>
            </li>
          )
        })}
      </ul>
      <label className="mt-6 flex cursor-pointer items-start gap-3 rounded-xl border border-border p-4">
        <input type="checkbox" checked={consent} onChange={(e) => setConsent(e.target.checked)}
          className="mt-0.5 h-4 w-4 rounded border-neutral-300" style={{ accentColor: branding.accentColor }} />
        <span className="text-sm font-medium text-neutral-700">
          I understand my responses are recorded and analysed by AI, and reviewed by a human recruiter.
        </span>
      </label>
      <button
        onClick={onBegin}
        disabled={!consent || busy}
        className="mt-6 inline-flex h-12 w-full items-center justify-center gap-2 rounded-lg text-base font-semibold text-white transition-all disabled:cursor-not-allowed disabled:opacity-50"
        style={{ background: branding.accentColor }}
      >
        <CheckCircle2 size={18} /> I consent — begin
      </button>
    </motion.div>
  )
}
```

- [ ] **Step 4: Create `VideoStage`**

Create `src/features/interview/screens/VideoStage.tsx`:
```tsx
import { useEffect, useRef, useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { AlertTriangle, Circle, Send, FastForward, Loader2, Camera } from 'lucide-react'
import { CircularCountdown } from '../components/CircularCountdown'
import { useAnswerRecorder } from '../useAnswerRecorder'
import { uploadAnswerVideo } from '@/lib/storage'
import type { CandidateSessionState } from '@shared/types'

interface Props {
  sessionId: string
  state: CandidateSessionState
  remaining: number
  secondsLeft: number
  busy: boolean
  onSkipPrep: () => void
  onSubmitVideo: (videoUrl: string) => Promise<void>
  onIntegrity?: (type: string) => void
}

/**
 * Video Interview answer screen. Runs on the shared timed engine: 30s prep
 * (camera preview live) → answer phase auto-starts recording → the candidate
 * submits (or a small client buffer before the server deadline auto-submits),
 * which stops recording, uploads the clip to Firebase Storage, and submits the
 * download URL. The server transcribes + scores it (Tasks 4/1).
 */
export function VideoStage({ sessionId, state, remaining, secondsLeft, busy, onSkipPrep, onSubmitVideo, onIntegrity }: Props) {
  const reduce = useReducedMotion()
  const { phase, timing, question, branding } = state
  const rec = useAnswerRecorder()
  const videoEl = useRef<HTMLVideoElement>(null)
  const [uploading, setUploading] = useState(false)
  const submittingRef = useRef(false)
  const isAnswer = phase === 'answer'
  const warning = isAnswer && secondsLeft <= timing.warningThresholdSeconds

  // Acquire the camera once, attach the live preview.
  useEffect(() => { void rec.acquire().catch(() => onIntegrity?.('camera_denied')) }, [rec, onIntegrity])
  useEffect(() => { if (rec.ready && videoEl.current) rec.attachPreview(videoEl.current) }, [rec, rec.ready])

  // Start recording when the answer phase opens.
  useEffect(() => { if (isAnswer && rec.ready && !rec.recording) rec.startRecording() }, [isAnswer, rec, rec.ready, rec.recording])

  const doSubmit = async () => {
    if (submittingRef.current || !question) return
    submittingRef.current = true
    setUploading(true)
    try {
      const blob = await rec.stopRecording()
      const url = await uploadAnswerVideo(sessionId, question.id, blob)
      await onSubmitVideo(url)
    } catch (err) {
      console.error('[video] submit failed', err)
    } finally {
      setUploading(false)
      submittingRef.current = false
    }
  }

  // Client-side pre-emptive submit ~3s before the server deadline so the clip is
  // uploaded before the engine's own empty auto-submit can advance the question.
  useEffect(() => {
    if (isAnswer && secondsLeft <= 3 && !submittingRef.current) void doSubmit()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isAnswer, secondsLeft])

  if (!question) return null

  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, x: 24 }}
      animate={{ opacity: 1, x: 0 }}
      exit={reduce ? undefined : { opacity: 0, x: -24 }}
      transition={{ duration: 0.25 }}
      className="space-y-6"
    >
      <div className="flex items-start justify-between gap-6">
        <div className="min-w-0">
          <span className={`text-xs font-bold uppercase tracking-widest ${isAnswer ? 'text-success' : 'text-neutral-400'}`}>
            {isAnswer ? 'Recording answer' : 'Preparation'}
          </span>
          <h2 className="mt-2 text-2xl font-bold leading-snug tracking-tight text-neutral-900">{question.text}</h2>
        </div>
        <div className="flex-shrink-0">
          <CircularCountdown
            remaining={remaining}
            total={state.totalPhaseSeconds}
            phase={phase ?? 'prep'}
            warningThreshold={timing.warningThresholdSeconds}
            accentColor={branding.accentColor}
          />
        </div>
      </div>

      {/* Camera stage */}
      <div className="relative aspect-video w-full overflow-hidden rounded-xl border border-border bg-neutral-900">
        <video ref={videoEl} autoPlay muted playsInline className="h-full w-full object-cover" />
        {rec.recording ? (
          <span className="absolute left-3 top-3 flex items-center gap-1.5 rounded-full bg-black/60 px-2.5 py-1 text-[11px] font-bold uppercase tracking-wider text-white">
            <Circle size={9} className="animate-pulse fill-red-500 text-red-500" /> Rec
          </span>
        ) : (
          <span className="absolute left-3 top-3 flex items-center gap-1.5 rounded-full bg-black/50 px-2.5 py-1 text-[11px] font-medium text-white/80">
            <Camera size={12} /> {rec.ready ? 'Preview' : 'Starting camera…'}
          </span>
        )}
        {!isAnswer && (
          <div className="absolute inset-0 flex items-center justify-center bg-black/40 text-center text-sm text-white/90">
            <span className="max-w-xs px-4">Read the question and get ready. Recording starts automatically when the answer timer begins.</span>
          </div>
        )}
        {uploading && (
          <div className="absolute inset-0 flex items-center justify-center gap-2 bg-black/60 text-sm font-medium text-white">
            <Loader2 size={18} className="animate-spin" /> Uploading your answer…
          </div>
        )}
      </div>

      {rec.error && (
        <div className="flex items-center gap-2 rounded-lg border border-danger-border bg-danger-bg px-3 py-2 text-sm font-medium text-danger">
          <AlertTriangle size={15} /> {rec.error}
        </div>
      )}
      {warning && !uploading && (
        <div className="flex items-center gap-2 rounded-lg border border-danger-border bg-danger-bg px-3 py-2 text-sm font-medium text-danger">
          <AlertTriangle size={15} /> {secondsLeft}s left — your answer submits automatically at zero.
        </div>
      )}

      <div className="flex items-center justify-between gap-3">
        <p className="text-xs text-neutral-400">
          {isAnswer ? 'You can’t return to this question once you continue.' : 'Read the question and gather your thoughts.'}
        </p>
        <div className="flex gap-2">
          {!isAnswer && timing.allowSkipPrep && (
            <button onClick={onSkipPrep} disabled={busy || !rec.ready}
              className="inline-flex h-10 items-center gap-2 rounded-lg border-2 px-4 text-sm font-semibold transition-all disabled:opacity-50"
              style={{ borderColor: branding.accentColor, color: branding.accentColor }}>
              <FastForward size={16} /> Start recording now
            </button>
          )}
          {isAnswer && timing.allowEarlySubmit && (
            <button onClick={() => void doSubmit()} disabled={busy || uploading}
              className="inline-flex h-10 items-center gap-2 rounded-lg px-5 text-sm font-semibold text-white transition-all disabled:opacity-50"
              style={{ background: branding.accentColor }}>
              <Send size={16} /> Submit &amp; continue
            </button>
          )}
        </div>
      </div>
    </motion.div>
  )
}
```

- [ ] **Step 5: Route the `video` track to `VideoStage`**

In `src/features/interview/TakeInterviewPage.tsx:13-16`, add the import (after the other screen imports):
```ts
import { VideoStage } from './screens/VideoStage'
```
In `src/features/interview/TakeInterviewPage.tsx:102-120`, change the in-progress render block from:
```tsx
  if (s.status === 'in_progress') {
    return (
      <InterviewShell branding={branding} progress={s.progress} live>
        <AnimatePresence mode="wait">
          <QuestionStage
            key={s.question?.id ?? 'q'}
            state={s}
            remaining={clock.remaining}
            secondsLeft={clock.secondsLeft}
            busy={clock.busy}
            onSkipPrep={clock.skipPrep}
            onSubmit={clock.submit}
            onSaveDraft={clock.saveDraft}
            onIntegrity={integrity.post}
          />
        </AnimatePresence>
      </InterviewShell>
    )
  }
```
to:
```tsx
  if (s.status === 'in_progress') {
    return (
      <InterviewShell branding={branding} progress={s.progress} live>
        <AnimatePresence mode="wait">
          {s.track === 'video' ? (
            <VideoStage
              key={s.question?.id ?? 'q'}
              sessionId={sessionId}
              state={s}
              remaining={clock.remaining}
              secondsLeft={clock.secondsLeft}
              busy={clock.busy}
              onSkipPrep={clock.skipPrep}
              onSubmitVideo={(url) => clock.submit('', url)}
              onIntegrity={integrity.post}
            />
          ) : (
            <QuestionStage
              key={s.question?.id ?? 'q'}
              state={s}
              remaining={clock.remaining}
              secondsLeft={clock.secondsLeft}
              busy={clock.busy}
              onSkipPrep={clock.skipPrep}
              onSubmit={clock.submit}
              onSaveDraft={clock.saveDraft}
              onIntegrity={integrity.post}
            />
          )}
        </AnimatePresence>
      </InterviewShell>
    )
  }
```
The `VideoIntro` consent gate is shown by adding it to the `SystemCheck` step for the video track — the simplest wiring is: for the `video` track, `SystemCheck` already renders the generic check (not `VideoSystemCheck`, which is `video_avatar`-only). Replace the generic check with `VideoIntro` for `video` by passing the track through (it already receives `track`). In `src/features/interview/screens/SystemCheck.tsx:18-20`, add above the existing `video_avatar` branch:
```tsx
  if (track === 'video') {
    return <VideoIntro branding={branding} onBegin={onBegin} busy={busy} />
  }
```
and import it at the top of `SystemCheck.tsx`:
```ts
import { VideoIntro } from './VideoIntro'
```

- [ ] **Step 6: Verify end-to-end in the app (candidate run)**

Run: `npm run dev`. Ensure `.env` has `GEMINI_API_KEY`, `DEEPGRAM_API_KEY`, and the `VITE_FIREBASE_*` values (incl. `VITE_FIREBASE_STORAGE_BUCKET`), and that Firebase Storage is enabled with `storage.rules` deployed (Task 8).
- Recruiter: create a Video Interview invite (Task 2) to an email you can sign in as.
- Candidate (that email): open the invite link → **Video interview — before you begin** consent gate → tick consent → **begin**. Camera preview appears; 30s prep countdown; recording auto-starts; speak an answer; **Submit & continue** → "Uploading your answer…" → advances to the next question. Repeat to completion.
- Confirm: the camera LED turns off at the end; no console errors; the recruiter's session list shows the session as completed and scoring runs.

- [ ] **Step 7: Build, lint, commit**

Run: `npm run build && npm run lint`
```bash
git add src/features/interview/useAnswerRecorder.ts src/features/interview/screens/VideoIntro.tsx src/features/interview/screens/VideoStage.tsx src/features/interview/useInterviewClock.ts src/features/interview/TakeInterviewPage.tsx src/features/interview/screens/SystemCheck.tsx
git commit -m "feat(video): candidate record→upload→submit Video Interview screen"
```

---

## Task 6: Recruiter results — video playback

Play the recorded clip back in the existing `ReportPage` per-question accordion. `videoUrl` already flows into `SessionReportQuestion.videoUrl` (`server/routes/sessions.ts:845`) — this task just renders it and adds the track label.

**Files:**
- Modify: `src/features/recruiter/ReportPage.tsx:23-28` (TRACK_LABEL), `:255-259` (per-question answer block)

**Interfaces:**
- Consumes: `SessionReportQuestion.videoUrl` (already populated for `video` sessions).

- [ ] **Step 1: Add the track label**

In `src/features/recruiter/ReportPage.tsx:23-28`, change:
```ts
const TRACK_LABEL: Record<string, string> = {
  chat: 'Timed Q&A',
  chatbot: 'Chatbot',
  voice: 'Voice',
  video_avatar: 'Video Avatar',
}
```
to:
```ts
const TRACK_LABEL: Record<string, string> = {
  chat: 'Timed Q&A',
  chatbot: 'Chatbot',
  voice: 'Voice',
  video_avatar: 'Video Avatar',
  video: 'Video Interview',
}
```

- [ ] **Step 2: Render the recorded clip in the per-question accordion**

In `src/features/recruiter/ReportPage.tsx:255-259`, change the answer block:
```tsx
                        <div>
                          <p className="text-xs font-semibold uppercase tracking-wide text-neutral-400">Answer</p>
                          <p className="mt-1 whitespace-pre-wrap text-sm text-neutral-700">{qq.answerText?.trim() || <span className="italic text-neutral-400">No answer provided.</span>}</p>
                        </div>
```
to:
```tsx
                        <div>
                          <p className="text-xs font-semibold uppercase tracking-wide text-neutral-400">
                            {qq.videoUrl ? 'Recorded answer' : 'Answer'}
                          </p>
                          {qq.videoUrl && (
                            <video
                              controls
                              src={qq.videoUrl}
                              className="mt-2 aspect-video w-full max-w-lg overflow-hidden rounded-xl border border-border bg-neutral-900"
                            />
                          )}
                          <p className="mt-2 whitespace-pre-wrap text-sm text-neutral-700">
                            {qq.answerText?.trim()
                              ? <><span className="text-xs font-semibold uppercase tracking-wide text-neutral-400">Transcript · </span>{qq.answerText}</>
                              : <span className="italic text-neutral-400">{qq.videoUrl ? 'No speech was transcribed for this clip.' : 'No answer provided.'}</span>}
                          </p>
                        </div>
```

- [ ] **Step 3: Verify in the app**

Open the completed Video Interview session's report (`/sessions/:id/report`). Each question's accordion shows a playable `<video>` of the recorded clip plus the Deepgram transcript, and KPI scores/feedback from Gemini. `PageHeader` shows "Video Interview" as the track.

- [ ] **Step 4: Build, lint, commit**

Run: `npm run build && npm run lint`
```bash
git add src/features/recruiter/ReportPage.tsx
git commit -m "feat(video): play back recorded answers in the recruiter report"
```

---

## Task 7: Facial / non-verbal analysis (reuse AWS Rekognition)

Capture facial frames on the candidate device during recording (shared stream), aggregate to a `FacialSessionSummary`, upload it to the server on completion, store it on the session, and render the existing `FacialAnalysisPanel` in the report. Ports the source's DeepFace step onto TalbotIQ's Rekognition path.

**Files:**
- Modify: `shared/types.ts` (add `facialSummary?` to `InterviewSession`; add `facial?` to `SessionReportView`)
- Modify: `server/routes/sessions.ts` (new `POST /:id/facial`; include `facial` in the report view)
- Modify: `src/lib/api.ts` (add `facial` method)
- Modify: `src/features/interview/useAnswerRecorder.ts` (tap the shared stream for Rekognition)
- Modify: `src/features/interview/screens/VideoStage.tsx` (start/stop facial capture; upload summary on the last submit)
- Modify: `src/features/recruiter/ReportPage.tsx` (render `FacialAnalysisPanel`)

**Interfaces:**
- Consumes: `RekognitionService` (`src/services/rekognitionService.ts` — `new RekognitionService(proxyUrl)`, `.startCapture(stream)`, `.setCurrentQuestion(idx)`, `.stopCapture()`), `aggregateFacialData(frames, questionCount)` (same file), `FacialAnalysisPanel` (`src/components/ats/FacialAnalysisPanel.tsx`), `useAppStore(s => s.awsProxyUrl)`.
- Produces: `sessionsApi.facial(id, summary)`; `session.facialSummary` stored; `SessionReportView.facial` returned.

- [ ] **Step 1: Add the additive fields**

In `shared/types.ts`, add to `InterviewSession` (after `tavusConversationId?` at `:294`):
```ts
  // Video Interview: AWS Rekognition facial summary captured on the candidate
  // device and uploaded on completion. Opaque JSON (client owns the shape).
  facialSummary?: Record<string, unknown>
```
And add to `SessionReportView` (after `speech?` at `:464`):
```ts
  /** AWS Rekognition facial analysis summary (video track). */
  facial?: Record<string, unknown>
```

- [ ] **Step 2: Add the server route + report inclusion**

In `server/routes/sessions.ts`, add a route (place it near the other candidate lifecycle routes, e.g. after `/answers`):
```ts
// Video Interview: candidate uploads the aggregated AWS Rekognition facial
// summary (computed client-side) on completion. Additive; stored opaquely.
sessionsRouter.post('/:id/facial', ah((req, res) => {
  const { session } = load(req)
  if (session.track !== 'video') throw new HttpError(400, 'This interview does not capture facial analysis')
  const summary = req.body?.summary
  if (summary && typeof summary === 'object') {
    session.facialSummary = summary as Record<string, unknown>
    db.scheduleSave()
  }
  res.json({ ok: true })
}))
```
In the report view (`server/routes/sessions.ts:850-879`), add `facial` to the returned `SessionReportView` object (after the `speech` spread near `:878`):
```ts
    // AWS Rekognition facial summary (video track).
    ...(session.facialSummary ? { facial: session.facialSummary } : {}),
```

- [ ] **Step 3: Add the client API method**

In `src/lib/api.ts`, add to the `sessionsApi` object (after `complete`):
```ts
  facial: (id: string, summary: unknown) =>
    http<{ ok: boolean }>(`/sessions/${id}/facial`, { method: 'POST', body: JSON.stringify({ summary }) }),
```

- [ ] **Step 4: Tap the shared stream for Rekognition in the recorder hook**

In `src/features/interview/useAnswerRecorder.ts`, add facial capture that reuses the SAME stream. Add imports at top:
```ts
import { RekognitionService } from '@/services/rekognitionService'
import { aggregateFacialData } from '@/services/rekognitionService'
import { useAppStore } from '@/store/useAppStore'
import type { FacialSessionSummary } from '@/types/rekognition.types'
```
Inside `useAnswerRecorder`, add a Rekognition ref + controls (place after the existing refs):
```ts
  const awsProxyUrl = useAppStore((s) => s.awsProxyUrl)
  const rekogRef = useRef<RekognitionService | null>(null)

  const startFacial = useCallback((questionCount: number) => {
    const stream = streamRef.current
    if (!stream || !awsProxyUrl || rekogRef.current) return
    const svc = new RekognitionService(awsProxyUrl)
    rekogRef.current = svc
    void svc.startCapture(stream)
    void questionCount
  }, [awsProxyUrl])

  const setFacialQuestion = useCallback((idx: number) => { rekogRef.current?.setCurrentQuestion(idx) }, [])

  const stopFacial = useCallback((questionCount: number): FacialSessionSummary | null => {
    const svc = rekogRef.current
    if (!svc) return null
    const frames = svc.stopCapture()
    rekogRef.current = null
    return frames.length ? aggregateFacialData(frames, questionCount) : null
  }, [])
```
Add `startFacial, setFacialQuestion, stopFacial` to the hook's return object. (Capture runs off the same `streamRef` stream — no second `getUserMedia`.)

- [ ] **Step 5: Wire facial capture into `VideoStage`**

In `src/features/interview/screens/VideoStage.tsx`:
- Add imports:
```ts
import { sessionsApi } from '@/lib/api'
```
- Add a `totalQuestions` from progress: `const total = state.progress.total`.
- Start facial capture once the camera is ready (after the preview effect):
```tsx
  useEffect(() => { if (rec.ready) rec.startFacial(total) }, [rec, rec.ready, total])
```
- Track the current question index for per-question facial bucketing:
```tsx
  useEffect(() => { rec.setFacialQuestion(Math.max(0, state.progress.current - 1)) }, [rec, state.progress.current])
```
- In `doSubmit`, when this is the LAST question (`state.progress.current >= total`), stop facial capture and upload the summary right after the answer submit:
```tsx
      await onSubmitVideo(url)
      if (state.progress.current >= total) {
        const summary = rec.stopFacial(total)
        if (summary) { try { await sessionsApi.facial(sessionId, summary) } catch { /* best-effort */ } }
      }
```
(If the recruiter/candidate device has no `awsProxyUrl`, `startFacial` is a no-op and `stopFacial` returns null — the mode still works, facial panel simply shows "Not Captured".)

- [ ] **Step 6: Render the facial panel in the report**

In `src/features/recruiter/ReportPage.tsx`:
- Import the panel + type:
```ts
import { FacialAnalysisPanel } from '@/components/ats/FacialAnalysisPanel'
import type { FacialSessionSummary } from '@/types/rekognition.types'
```
- Pull `facial` off the query data (change the destructure at `:90`):
```ts
  const { session, rubric, report, speech, facial } = q.data
```
- Render it just before `<SignalAnalytics .../>` at `:318`:
```tsx
          {session.track === 'video' && facial && (
            <FacialAnalysisPanel summary={facial as unknown as FacialSessionSummary} questionCount={session.questions.length} />
          )}
```

- [ ] **Step 7: Verify in the app**

Set the AWS Rekognition proxy URL in Settings (so `awsProxyUrl` is populated) and run a full Video Interview as the candidate. On the recruiter report, confirm the **Facial Analysis** card renders (attention/emotion bars, per-question breakdown). Without a proxy configured, confirm the mode still completes and the panel is simply absent (no errors).

- [ ] **Step 8: Build, lint, commit**

Run: `npm run build && npm run lint`
```bash
git add shared/types.ts server/routes/sessions.ts src/lib/api.ts src/features/interview/useAnswerRecorder.ts src/features/interview/screens/VideoStage.tsx src/features/recruiter/ReportPage.tsx
git commit -m "feat(video): capture + report AWS Rekognition facial analysis"
```

---

## Task 8: Env vars, Storage deploy, Capacitor permissions, docs

Document and configure the operational pieces so the mode runs in dev, in production, and (later) in the Android build.

**Files:**
- Modify: `.env.example`
- Create: `docs/VIDEO_INTERVIEW.md`
- Modify: `firebase.json` (Storage rules target) if present; otherwise document the manual deploy.

- [ ] **Step 1: Document env vars in `.env.example`**

Add (or confirm) these entries in `talbotiq-platform/.env.example`, each with a comment (no real values):
```
# Video Interview — speech-to-text of recorded answers (server-side; same key as the live relay)
DEEPGRAM_API_KEY=
# Firebase Storage bucket for recorded answer clips (public web config; already used for auth)
VITE_FIREBASE_STORAGE_BUCKET=
# AWS Rekognition proxy URL for facial analysis (optional; set in Settings or here)
# (AWS creds live on the proxy, never in the client)
```
(`GEMINI_API_KEY` is already documented; `DEEPGRAM_API_KEY` may already exist for the avatar relay — do not duplicate.)

- [ ] **Step 2: Wire the Storage rules into `firebase.json`**

If `firebase.json` exists, add a `storage` target:
```json
  "storage": { "rules": "storage.rules" }
```
Deploy note (run manually when credentials are available — NOT part of this task's commit):
```
firebase deploy --only storage
```

- [ ] **Step 3: Write `docs/VIDEO_INTERVIEW.md`**

Create `docs/VIDEO_INTERVIEW.md` documenting: the `video` track, the record→upload(Storage)→transcribe(Deepgram)→score(Gemini)→facial(Rekognition) pipeline, the env vars, the Storage rules deploy, and the **Capacitor Android** requirement: after `npx cap add android`, add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-feature android:name="android.hardware.camera" android:required="false" />
```
and note that WebRTC/`getUserMedia` + `MediaRecorder` work in the Capacitor WebView on Android 7+ (test `MediaRecorder` webm support on the target device; fall back to `video/mp4` if `video/webm` is unsupported — the recorder hook already probes `isTypeSupported`).

- [ ] **Step 4: Commit**

Run: `npm run build && npm run lint`
```bash
git add .env.example docs/VIDEO_INTERVIEW.md firebase.json
git commit -m "docs(video): env vars, Storage rules, Capacitor permissions"
```

---

## Verification (Phase 3 acceptance)

- [ ] **Video Interview** appears in the recruiter mode selector (native card UI) and in the candidate flow it goes consent gate → record per question → results.
- [ ] End-to-end: setup → invite → candidate records → clips in Firebase Storage → Deepgram transcript → Gemini scoring → recruiter report plays back video + shows transcript + KPIs + facial analysis.
- [ ] UI matches the design system (`InterviewShell`, `CircularCountdown`, `ReportPage`, `FacialAnalysisPanel`); architecture matches (same session/scoring/results pipeline, same auth/invite flow, Firebase Storage).
- [ ] Frozen modules untouched: `git diff main -- server/routes/templates.ts server/routes/questionSets.ts server/services/tavusServer.ts` is empty; the Firestore `interviews` field names in `invites.ts` are unchanged; all changes are additive.
- [ ] Keys server-side: `DEEPGRAM_API_KEY`, `GEMINI_API_KEY`, AWS creds never reach the client; only the public Firebase web config does.
- [ ] `npm run build` and `npm run lint` pass.

## Known considerations / follow-ups (out of v1 scope)

- **Submit-vs-deadline race:** the client pre-emptively submits ~3s before the server auto-submit. On a very slow upload the server could auto-submit an empty answer first (clip lost for that question). A follow-up could add a server-side "video answer grace" that holds advancement until the client's upload lands. Documented, not fixed in v1.
- **Two-way / live Interview** remains a separate greenfield phase (the source has no such feature) — see the original analysis. Not covered here.
- **Storage cleanup / retention:** the source purges media after 30 days (`purge_old_interview_media`). A follow-up could add a Storage lifecycle rule or a scheduled cleanup for `interviews/{sessionId}/…`.
