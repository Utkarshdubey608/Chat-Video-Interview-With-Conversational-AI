# Video Interview → Live-Transcript Rework — Design

**Date:** 2026-07-16
**Status:** Approved (design), pending implementation plan

## Goal

Rework the existing one-way **Video Interview** (`TrackType: 'video'`) so it **stores no video**. The camera stays on with a REC indicator **purely for aesthetics**; the candidate **speaks** each answer and it is **transcribed live** (Deepgram), exactly like the AI-avatar screening. Scoring and results become the **same as the Voice interview** (transcript + speech metrics + sentiment + conversation-style per-question breakdown), **plus** the existing **live AWS Rekognition facial analysis** (which already stores only aggregated metrics, never video/frames). This removes the Firebase Storage dependency entirely — and with it the current stuck-"Uploading…" bug.

## Motivation

The shipped Video Interview recorded a clip per question → uploaded to Firebase Storage → server transcribed the clip (Deepgram pre-recorded) → per-question scoring. Firebase Storage was never enabled for the project, so uploads hung and every answer was lost. The product owner decided the video itself has no value here — only the transcript (and live facial signals) matter. Dropping storage removes the failure mode and matches the Voice interview's proven analytics path.

## Non-goals

- No video/audio/frame persistence of any kind (only derived analysis: transcript text, speech metrics, sentiment, aggregated facial summary).
- No change to the other tracks (`chat`, `chatbot`, `voice`, `video_avatar`).
- No AI interviewer/avatar — questions are fixed and read by the candidate.
- Two-way / live interview remains out of scope (separate greenfield).

## Architecture

The `video` track keeps the **timed per-question engine** (`server/services/timing.ts` `tick()` — prep/answer/submit per question) for FLOW, but produces **conversation-style transcript data** for analytics. It is a hybrid: timed engine for UX, conversation path for scoring/results.

### Candidate flow (unchanged UX)
1. Consent gate (`VideoIntro`) → per question: 30s prep (question shown, camera preview live) → answer window opens.
2. When the answer window opens: camera shows a **REC** dot (aesthetic only) and **live transcription starts** — the shared mic stream is sent to Deepgram via a candidate-authorized relay; interim + final transcript accumulate for this answer. Live facial capture runs in parallel (unchanged).
3. Candidate clicks **Submit & continue** (or the client auto-submits ~3s before the deadline): live transcription for this answer stops, and the accumulated transcript is submitted as the answer text (`answerText`). **No upload, no blob, no videoUrl.**
4. Repeat to the last question; on the last submit, facial capture stops and its aggregated summary uploads (unchanged).

### Single shared stream
`useAnswerRecorder` owns ONE `getUserMedia({video, audio})` stream for the whole interview and now drives three consumers off it, with **no video/audio persistence**:
- **Preview** — attached to the `<video>` element.
- **Live transcript** — a `MediaRecorder(audioOnly)` (or the stream's audio track) streams WebM/Opus chunks to the candidate Deepgram relay; results accumulate into the current answer's transcript.
- **Facial** — `RekognitionService` grabs frames → candidate-authorized `/api/sessions/:id/facial-frame` → aggregated summary (unchanged, Task 7).

The `MediaRecorder` that previously produced an upload **blob is removed**. The REC indicator is a UI flag tied to the answer phase, not a real recording.

### Candidate-authorized Deepgram relay (server)
The existing relay (`server/services/deepgramRelay.ts`, WS `/api/avatar/deepgram`) is **recruiter-only** (`auth.role !== 'recruiter'` → 401). Add a **candidate-reachable** relay path (e.g. `/api/interview/deepgram`) that authorizes **any authenticated user** (via `contextFromUpgrade`), reusing the same relay `handle()` (browser WebM/Opus → Deepgram Nova-3 with the server-side key → Results JSON back). Mount it in `server/index.ts` alongside the existing WS relays. The Deepgram key stays server-side.

### Client transcript hook
Add live-transcript handling to `useAnswerRecorder` (so it uses the SHARED stream — no second `getUserMedia`): `startTranscribing()` opens the WS to the candidate relay and streams the stream's audio; incoming `Results` with `is_final`/`speech_final` append to an accumulated transcript ref; `stopTranscribing()` closes the socket and returns the accumulated text; expose `liveTranscript` (interim, for optional on-screen display) and `transcriptConnected`. Degrades gracefully: if Deepgram isn't configured or the socket fails, the answer submits with whatever text accumulated (possibly empty).

### Submit → conversation transcript (server)
`POST /sessions/:id/answers` for the `video` track:
- Store `q.answerText = req.body.answerText` (the live transcript).
- **Remove** the `videoUrl` handling and the deferred server-side pre-recorded transcription for video (Task 4) — transcription is now client-live.
- **Build the conversation transcript** so analytics match voice: append to `session.transcript` an interviewer `question` turn (`turnType: 'question'`, `questionIndex: currentIndex`, `content: q.text`) and a candidate turn (`questionIndex: currentIndex`, `content: q.answerText`); set `session.mode = 'conversational'` if unset. (`session.transcript`/`mode` are existing optional conversation fields — additive for video.)

### Scoring & results = Voice
Add `'video'` to the conversation branches so it uses the identical path as voice/avatar:
- `server/services/scoring.ts` `scoreSession` → conversation OR-list (`chatbot|video_avatar|voice|video`) → `scoreConversation` (transcript-grouped via `primaryQuestionGroups`).
- `server/routes/sessions.ts` report `isConversation` → include `'video'` → transcript panel + `computeSpeechMetrics` + sentiment; per-question view synthesised from the transcript (no `videoUrl`).
- `server/services/signals.ts` `computeSpeechMetrics` `spoken` flag → include `'video'` (it is spoken). Sentiment (`analyzeSentiment`) is transcript-based → automatic.
- `server/services/timing.ts` `tick()` — **do NOT** add `'video'` to the exemption; it stays on the timed per-question engine.

### Facial analysis — unchanged
Live AWS Rekognition capture (Task 7) stays exactly as-is: frames → candidate-authorized `/api/sessions/:id/facial-frame` (analyzed in-flight, nothing stored) → aggregated `FacialSessionSummary` uploaded on the last question → `FacialAnalysisPanel` in the report. This is the "same AWS as the avatar, live, no storage" the owner confirmed.

### Results page
`ReportPage` for `video`: voice-style transcript + speech metrics + sentiment (already rendered for `isConversation`) **plus** the `FacialAnalysisPanel` (already gated on `session.track === 'video' && facial`). Remove the `<video>` playback block for `video` (nothing is stored) — the per-question "Recorded answer"/"Transcript" block reverts to a plain transcript display.

## What is removed

- `uploadAnswerVideo` usage; the Firebase Storage upload path in the submit flow; `SubmitAnswerRequest.videoUrl` usage for video (field may remain for `video_avatar` legacy but is unused by `video`).
- `src/lib/storage.ts` + `storage.rules` become unused by this mode (leave in tree or delete; no longer required).
- Server-side pre-recorded transcription for video (`transcribeVideoUrl` call in `/answers` + the `pendingTranscriptions`/`maybeScore` video deferral). `transcription.ts` may remain unused.
- The `MediaRecorder` blob recording in `useAnswerRecorder`; the video-playback `<video>` block in `ReportPage` for video.

## Interfaces (key)

- `useAnswerRecorder`: adds `startTranscribing(sessionId): void`, `stopTranscribing(): Promise<string>`, `liveTranscript: string`, `transcriptConnected: boolean`; drops `startRecording`/`stopRecording` blob semantics (REC becomes a UI flag). Keeps `acquire`, `attachPreview`, `startFacial`/`setFacialQuestion`/`stopFacial`.
- Server WS: `GET (upgrade) /api/interview/deepgram?token=<idToken>` — authenticated (candidate or recruiter) Deepgram relay.
- `/answers` (video): request `{ questionId, answerText }` (the live transcript); no `videoUrl`.

## Error handling / degradation

- Deepgram not configured / relay fails → the answer still submits with whatever transcript accumulated (may be empty → that question scored as no/low answer, like a silent voice answer). No hang (the submit is a normal fast `/answers` POST — no upload).
- Mic denied → `useAnswerRecorder.acquire` sets `error`; the candidate sees the existing camera/mic error; transcription simply produces nothing.
- Facial degradation unchanged (no AWS creds → "not captured" panel; interview still completes).

## Testing / verification

- `tsx` unit test: `/answers` for `video` populates `session.transcript` with the (question, answer) turns and sets `answerText`; `scoreSession` routes `video` to `scoreConversation`; `computeSpeechMetrics` treats `video` as spoken. (Extend the existing `videoTrack.test.ts`.)
- Build gates: `npm run build` + `npx tsc -p server/tsconfig.json --noEmit`.
- Manual (app): run a `video` invite → speak answers → confirm live transcript accumulates, no upload/network to Storage, submit advances immediately, report shows transcript + speech metrics + sentiment + facial panel, and nothing is written to Firebase Storage.

## Risks

- **Live-transcript accuracy/latency** depends on Deepgram + mic; acceptable (same as the avatar screening).
- **Auto-submit race** is far smaller now — the submit is a plain `/answers` POST (no upload), so it comfortably beats the deadline; the existing pre-emptive submit at `secondsLeft ≤ 3` stays as a backstop.
- **Empty transcript** if the candidate is silent or Deepgram is down → scored as no answer (honest; matches voice).
