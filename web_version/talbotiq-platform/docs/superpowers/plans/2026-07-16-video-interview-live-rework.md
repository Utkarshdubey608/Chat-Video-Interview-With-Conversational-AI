# Video Interview Live-Transcript Rework — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Rework `TrackType: 'video'` so it stores NO video — camera + REC are aesthetic, each answer is transcribed live via Deepgram, and scoring/results are the same as the Voice interview (transcript + speech metrics + sentiment) plus the existing live AWS Rekognition facial analysis. Removes Firebase Storage from this mode.

**Architecture:** `video` keeps the timed per-question engine (`timing.ts` `tick()`) for FLOW, but each submitted answer's live transcript is appended to `session.transcript` as (interviewer question turn, candidate turn), so scoring/results route through the existing conversation path (`scoreConversation` + `computeSpeechMetrics` + sentiment). Live transcription reuses the avatar screening's Deepgram relay via a new candidate-authorized WS path; the one shared camera stream drives preview + transcription + facial. Facial (Task-7 live Rekognition) is unchanged.

**Tech stack:** Vite/React/TS, Express/tsx, Deepgram Nova-3 (live WS relay, server-side key), AWS Rekognition (existing), Firebase Auth/Firestore. Tests: `npx tsx <file>.test.ts`.

## Global Constraints

- **No persistence of raw media** — no video/audio blob, no Firebase Storage, no frames stored. Only derived data: `answerText` (transcript), `session.transcript` turns, `FacialSessionSummary`.
- **Keys server-side** — Deepgram key stays on the server (relay); only the public Firebase web config is client-side.
- **`video` stays on the timed engine** — do NOT add `'video'` to `timing.ts` `tick()`'s conversation exemption.
- **Additive/no-regression** — do not change behavior of `chat`/`chatbot`/`voice`/`video_avatar`. `session.transcript`/`mode`/`answerText` are existing optional fields.
- **Gates:** `npm run build` AND `npx tsc -p server/tsconfig.json --noEmit` both pass before each commit. (`npm run lint` is non-functional repo-wide — ignore.)
- Base state: branch off the current running copy's `feat/avatar-screening-migration` (has the shipped video mode + storage-timeout hotfix).

## File Structure

**Modify**
- `server/services/deepgramRelay.ts` — export `handle`; add `attachCandidateDeepgramRelay(server)` (authenticated, any role) on a new path.
- `server/index.ts` — mount the candidate relay.
- `src/features/interview/useAnswerRecorder.ts` — add live-transcript (shared stream → candidate relay); drop the blob `MediaRecorder` recording (REC becomes a UI flag).
- `src/features/interview/screens/VideoStage.tsx` — aesthetic REC, start/stop transcription per answer, submit the transcript (no upload); keep facial.
- `src/features/interview/useInterviewClock.ts` — video submit sends `answerText` (reuse `submit`); `submitVideo` removed or repurposed.
- `server/routes/sessions.ts` — `/answers` video branch: store `answerText`, append transcript turns; remove `videoUrl` + deferred pre-recorded transcription for video; simplify `maybeScore`. Report `isConversation` includes `'video'`.
- `server/services/scoring.ts` — `scoreSession` conversation OR-list includes `'video'`.
- `server/services/signals.ts` — `computeSpeechMetrics` `spoken` includes `'video'`.
- `src/features/recruiter/ReportPage.tsx` — (video now renders via the conversation path; drop the now-dead video-playback block / keep transcript display).
- `server/services/videoTrack.test.ts` — extend for the new behavior.

**No longer used by this mode (leave in tree):** `src/lib/storage.ts`, `storage.rules`, `server/services/transcription.ts`.

---

## Task 1: Candidate-authorized Deepgram live relay (server)

**Files:** Modify `server/services/deepgramRelay.ts`, `server/index.ts`.
**Interfaces:** Produces WS `GET (upgrade) /api/interview/deepgram?token=<idToken>` — authenticated (candidate or recruiter) → same Deepgram relay as `/api/avatar/deepgram`.

- [ ] **Step 1: Read `server/index.ts`** to see how `attachDeepgramRelay`/`attachVoiceWebSocket` are mounted (the `server.on('upgrade')` pattern) and where to add the new one.

- [ ] **Step 2: Export `handle` and add the candidate relay** in `server/services/deepgramRelay.ts`. Change `function handle(client: WebSocket)` to `export function handle(client: WebSocket)`. Add at the end:
```ts
/** Candidate-reachable Deepgram relay for the Video Interview (live transcription).
 *  Same relay as /api/avatar/deepgram but authorized for ANY authenticated user
 *  (the /api/avatar path is recruiter-only). Key stays server-side. */
export function attachCandidateDeepgramRelay(server: Server) {
  const wss = new WebSocketServer({ noServer: true })
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url ?? '', 'http://localhost')
    if (url.pathname !== '/api/interview/deepgram') return
    void (async () => {
      const auth = await contextFromUpgrade(req)
      if (!auth) {
        try { socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n') } catch { /* noop */ }
        socket.destroy()
        return
      }
      wss.handleUpgrade(req, socket, head, (ws) => handle(ws))
    })()
  })
}
```

- [ ] **Step 3: Mount it** in `server/index.ts` next to the existing `attachDeepgramRelay(server)` call: import `attachCandidateDeepgramRelay` and call `attachCandidateDeepgramRelay(server)`. (Multiple `server.on('upgrade')` handlers coexist — each ignores paths it doesn't own, matching the existing pattern.)

- [ ] **Step 4: Gates + commit.** `npm run build` and `npx tsc -p server/tsconfig.json --noEmit` pass. (No unit test — a WS relay isn't unit-testable here; verified by typecheck + the manual run in Task 6.)
```bash
git add server/services/deepgramRelay.ts server/index.ts
git commit -m "feat(video): candidate-authorized Deepgram live relay"
```

---

## Task 2: Live transcription in `useAnswerRecorder`; drop blob recording

**Files:** Modify `src/features/interview/useAnswerRecorder.ts`.
**Interfaces:** Produces `startTranscribing(): void`, `stopTranscribing(): Promise<string>`, `liveTranscript: string`, `transcriptConnected: boolean`; `recording` becomes a UI flag set by `startTranscribing`/`stopTranscribing`; removes blob `startRecording`/`stopRecording`.

- [ ] **Step 1: Read the current file** and `src/lib/firebase.ts` (`getIdTokenOrNull`).

- [ ] **Step 2: Replace the blob recorder with live transcription.** Remove `startRecording`/`stopRecording` (blob) and `chunksRef`. Add:
```ts
import { getIdTokenOrNull } from '@/lib/firebase'
// ...refs:
const wsRef = useRef<WebSocket | null>(null)
const audioRecRef = useRef<MediaRecorder | null>(null)
const transcriptRef = useRef('')            // accumulated finals for the current answer
const [liveTranscript, setLiveTranscript] = useState('')
const [transcriptConnected, setTranscriptConnected] = useState(false)

const startTranscribing = useCallback(() => {
  const stream = streamRef.current
  if (!stream || wsRef.current) return
  transcriptRef.current = ''
  setLiveTranscript('')
  setRecording(true)                         // drives the aesthetic REC dot
  void (async () => {
    const proto = location.protocol === 'https:' ? 'wss' : 'ws'
    const token = await getIdTokenOrNull()
    const ws = new WebSocket(`${proto}://${location.host}/api/interview/deepgram${token ? `?token=${encodeURIComponent(token)}` : ''}`)
    wsRef.current = ws
    ws.onopen = () => {
      setTranscriptConnected(true)
      const mime = MediaRecorder.isTypeSupported('audio/webm;codecs=opus') ? 'audio/webm;codecs=opus' : 'audio/webm'
      const audioStream = new MediaStream(stream.getAudioTracks())
      const rec = new MediaRecorder(audioStream, { mimeType: mime })
      audioRecRef.current = rec
      rec.ondataavailable = (e) => { if (e.data.size && ws.readyState === WebSocket.OPEN) ws.send(e.data) }
      rec.start(250)
    }
    ws.onmessage = (ev) => {
      try {
        const msg = JSON.parse(ev.data)
        if (msg.type !== 'Results') return
        const text = (msg.channel?.alternatives?.[0]?.transcript ?? '').trim()
        if (!text) return
        if (msg.is_final || msg.speech_final) {
          transcriptRef.current = (transcriptRef.current + ' ' + text).trim()
          setLiveTranscript(transcriptRef.current)
        }
      } catch { /* ignore malformed */ }
    }
    ws.onerror = () => setTranscriptConnected(false)
    ws.onclose = () => setTranscriptConnected(false)
  })()
}, [])

const stopTranscribing = useCallback((): Promise<string> => {
  setRecording(false)
  const rec = audioRecRef.current
  const ws = wsRef.current
  const finish = () => { try { ws?.close() } catch { /* noop */ }; wsRef.current = null; audioRecRef.current = null; return transcriptRef.current.trim() }
  return new Promise((resolve) => {
    if (!rec) { resolve(finish()); return }
    // Flush the final chunk, allow a short grace for Deepgram's last Results, then resolve.
    rec.onstop = () => setTimeout(() => resolve(finish()), 600)
    try { rec.stop() } catch { resolve(finish()) }
  })
}, [])
```
Add an unmount cleanup that closes the socket + recorder (mirror the existing stream/facial cleanup effects):
```ts
useEffect(() => () => { try { audioRecRef.current?.stop() } catch { /* noop */ }; wsRef.current?.close(); wsRef.current = null }, [])
```
Update the returned object: remove `startRecording`/`stopRecording`; add `startTranscribing, stopTranscribing, liveTranscript, transcriptConnected`. Keep `ready, recording, error, acquire, attachPreview, streamRef, startFacial, setFacialQuestion, stopFacial`.

- [ ] **Step 3: Gate + commit.** `npm run build` passes.
```bash
git add src/features/interview/useAnswerRecorder.ts
git commit -m "feat(video): live Deepgram transcription on the shared stream (no blob recording)"
```

---

## Task 3: VideoStage — aesthetic REC + submit the live transcript (no upload)

**Files:** Modify `src/features/interview/screens/VideoStage.tsx`, `src/features/interview/useInterviewClock.ts`.

- [ ] **Step 1: Read both files** (current post-hotfix state).

- [ ] **Step 2: `useInterviewClock`** — VideoStage will submit the transcript via the existing `submit(answerText)`. Confirm `submit` posts `{ questionId, answerText }`. If `submitVideo` is now unused after Task 3, remove it (and its export); otherwise leave it. (Do NOT break `QuestionStage`'s `onSubmit`.)

- [ ] **Step 3: Rework `VideoStage.doSubmit`** — remove the `uploadAnswerVideo` import and call. Start transcription when the answer phase opens; on submit, stop transcription and submit the transcript:
  - Replace the record-start effect (`rec.startRecording()`) with `rec.startTranscribing()`:
    ```tsx
    useEffect(() => { if (isAnswer && rec.ready && !rec.recording) rec.startTranscribing() }, [isAnswer, rec.ready, rec.recording])
    ```
  - Change `onSubmitVideo` prop to `onSubmitText: (answerText: string) => Promise<void>` wired in `TakeInterviewPage` to `clock.submit`.
  - `doSubmit`:
    ```tsx
    const doSubmit = async () => {
      if (submittingRef.current || !question) return
      submittingRef.current = true
      setUploading(true)                         // reuse as a brief "submitting" state
      try {
        const transcript = await rec.stopTranscribing()
        await onSubmitText(transcript)
      } catch (err) {
        console.error('[video] submit failed', err); setSubmitFailed(true)
      } finally {
        if (state.progress.current >= total) {
          try { const summary = rec.stopFacial(total); facialDoneRef.current = true; if (summary) await sessionsApi.facial(sessionId, summary) }
          catch (e) { console.error('[video] facial upload failed', e) }
        }
        setUploading(false); submittingRef.current = false
      }
    }
    ```
  - Change the overlay copy from "Uploading your answer…" to "Saving your answer…" (there's no upload now; it's a fast POST).
  - The REC dot already keys on `rec.recording` (now set by start/stopTranscribing) — keep it (aesthetic). Optionally show `rec.liveTranscript` as small muted caption text under the camera (nice-to-have; keep minimal).
  - Update `VideoInterview` (wrapper) prop pass-through: `onSubmitText` instead of `onSubmitVideo`.

- [ ] **Step 4: `TakeInterviewPage`** — update the `video` branch to pass `onSubmitText={clock.submit}` (drop `onSubmitVideo`/`clock.submitVideo`).

- [ ] **Step 5: Gate + commit.** `npm run build` passes.
```bash
git add src/features/interview/screens/VideoStage.tsx src/features/interview/useInterviewClock.ts src/features/interview/TakeInterviewPage.tsx
git commit -m "feat(video): submit live transcript, aesthetic REC, no upload"
```

---

## Task 4: Server `/answers` video branch → transcript turns; route scoring/results as conversation

**Files:** Modify `server/routes/sessions.ts`, `server/services/scoring.ts`, `server/services/signals.ts`; extend `server/services/videoTrack.test.ts`.

- [ ] **Step 1: Write the failing test** — extend `server/services/videoTrack.test.ts` with a case that calls a new exported helper `appendVideoTurns(session, question, now)` (or asserts `/answers` behavior via a pure helper) proving: after a video answer with `answerText`, `session.transcript` has an interviewer `question` turn + a candidate turn for the current index, and `scoreSession` routing for `video` is the conversation path. Since `/answers` is an Express handler, extract the turn-building into a small pure exported function `buildVideoTranscript(session, q, answerText, now)` in `sessions.ts` (or a tiny `server/services/videoTranscript.ts`) and test THAT. Assert:
  - `buildVideoTranscript` pushes 2 turns with correct `role`/`turnType`/`questionIndex`/`content`.
  - (routing) a `video` session with a candidate transcript turn is treated as conversational by `computeSpeechMetrics` (`spoken === true`).
Run: `npx tsx server/services/videoTrack.test.ts` → FAIL (helper/behavior missing).

- [ ] **Step 2: `/answers` video branch.** In `server/routes/sessions.ts`, in the `/answers` handler, REPLACE the current video block (videoUrl + deferred `transcribeVideoUrl` + `trackTranscription`) with:
```ts
q.answerText = typeof req.body?.answerText === 'string' ? req.body.answerText : q.draft ?? ''
if (session.track === 'video') {
  session.mode = session.mode ?? 'conversational'
  session.transcript = session.transcript ?? []
  const at = new Date().toISOString()
  session.transcript.push({ id: randomUUID(), role: 'interviewer', turnType: 'question', questionIndex: session.currentIndex, content: q.text, createdAt: at })
  session.transcript.push({ id: randomUUID(), role: 'candidate', questionIndex: session.currentIndex, content: q.answerText, createdAt: at })
}
```
Remove the `videoUrl` assignment, the `transcribeVideoUrl` call, and the `pendingTranscriptions`/`trackTranscription` machinery for video. In `maybeScore`, remove the `video` pending-transcription wait (revert to the simple fire-and-forget scoring for all tracks). Remove the now-unused `transcribeVideoUrl` import if nothing else uses it. Extract `buildVideoTranscript` per Step 1 for testability.

- [ ] **Step 3: Conversation routing.**
  - `server/services/scoring.ts:61` — add `'video'`: `if (session.track === 'chatbot' || session.track === 'video_avatar' || session.track === 'voice' || session.track === 'video')`.
  - `server/routes/sessions.ts` report `isConversation` (~:822) — add `|| session.track === 'video'`.
  - `server/services/signals.ts:48` — `const spoken = session.track === 'voice' || session.track === 'video_avatar' || session.track === 'video'`.
  - Do NOT touch `timing.ts` (video stays on the timed engine).

- [ ] **Step 4: Run the test** → PASS. Then both gates (`npm run build`, `npx tsc -p server/tsconfig.json --noEmit`).

- [ ] **Step 5: Commit.**
```bash
git add server/routes/sessions.ts server/services/scoring.ts server/services/signals.ts server/services/videoTrack.test.ts
git commit -m "feat(video): store live transcript as conversation turns; score/report as voice-style"
```

---

## Task 5: Report + cleanup, verify no storage, end-to-end

**Files:** Modify `src/features/recruiter/ReportPage.tsx` (if needed); verify.

- [ ] **Step 1: ReportPage** — with `video` now `isConversation`, the report renders the transcript panel + speech metrics + sentiment (existing conversation rendering) and the `FacialAnalysisPanel` (gate `session.track === 'video' && facial` already present). Confirm the per-question video-playback `<video>` block is NOT reached for `video` (the conversation report path uses `primaryQuestionGroups`, not the `videoUrl` accordion). If any `video`-specific `videoUrl` rendering remains reachable, remove it. Add `video` to `TRACK_LABEL` already exists — keep.

- [ ] **Step 2: Verify no Firebase Storage in the video path** — `grep -rn "uploadAnswerVideo\|firebase/storage" src/features/interview src/features/recruiter` returns nothing for the video flow (only the now-orphaned `src/lib/storage.ts` may reference `firebase/storage`, which is fine/unused).

- [ ] **Step 3: Gates.** `npm run build` + `npx tsc -p server/tsconfig.json --noEmit` pass; run all tsx tests (`inviteBridge`, `videoTrack`, `transcription`).

- [ ] **Step 4: Manual end-to-end (controller-run).** With the dev server running: create a `video` invite → as candidate, speak an answer → confirm: camera preview + REC dot, live transcript accumulates (check the Deepgram relay connects; no Firebase Storage network calls), **Submit advances quickly** (no "Uploading…" hang), report shows transcript + speech metrics + sentiment + facial panel, and nothing hits Firebase Storage. Confirm `db.json` shows the session's `transcript` populated and `answerText` set.

- [ ] **Step 5: Commit** any ReportPage change.
```bash
git add src/features/recruiter/ReportPage.tsx
git commit -m "chore(video): report renders voice-style transcript + facial; no video playback"
```

---

## Verification (acceptance)
- Video Interview: per-question, camera+REC aesthetic, **no video/audio/frames stored**, no Firebase Storage calls.
- Each answer transcribed live (Deepgram candidate relay); submit is a fast POST (no upload hang).
- Report = Voice-style (transcript + speech metrics + sentiment) **+** live-Rekognition facial panel.
- Other tracks unchanged; `video` still on the timed engine; both build gates + all tsx tests green.
