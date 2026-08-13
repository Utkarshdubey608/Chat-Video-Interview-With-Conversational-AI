# Video Interview Track

The **Video Interview** track is a one-way video mode where candidates answer interview questions on camera. Answers are captured as **live transcript text** (Deepgram), scored via Gemini, and analyzed for facial engagement via AWS Rekognition.

> ⚠️ **Corrected 12 Aug 2026.** This document previously stated that answer clips are recorded and uploaded to Firebase Storage. **They are not.** The live-transcription rework (`docs/superpowers/plans/2026-07-16-video-interview-live-rework.md`) removed video recording and upload from this track: the camera is a **preview only**, and the answer submitted to the server is the transcript text. See the docstring at `src/features/interview/screens/VideoStage.tsx:38-44` ("No video is recorded/uploaded") and note that `src/lib/storage.ts` is now used only by the **Two-way** track. Sections below that describe clip upload are retained for the Storage-rules walkthrough, which still applies to the Two-way recording. See `docs/DATA_STORAGE_AUDIT.md` for the verified end-to-end data map.

## Overview

- **Track type:** `video` (alongside `voice`, `video_avatar`, `chat`, `chatbot`)
- **Candidate flow:** Consent gate → 30-second prep countdown → answer phase opens and live transcription starts → candidate submits (or client pre-empts the server deadline) → transcript submitted as the answer → server advances
- **Recruiter view:** Report page with transcript, Gemini per-question scores, and AWS Rekognition facial analysis (engagement/emotion metrics). **No video playback for this track** — no clip exists.

## Pipeline

```
┌─ Candidate Interview ──────────────────────────────────────┐
│ 1. Consent gate (data collection, facial analysis)         │
│ 2. 30-second prep countdown (question visible, camera      │
│    preview live)                                           │
│ 3. Answer phase → live transcription starts off the shared │
│    stream's audio track (Deepgram relay). NO recording.    │
│ 4. Question advances automatically after time expires      │
│ 5. Client pre-emptive submit (~3s before the server        │
│    deadline) stops transcription                           │
│ 6. Server auto-submit if the client submit fails           │
│ 7. Submit answer (transcript text) → POST                  │
│    /api/sessions/:id/answers                               │
└────────────────────────────────────────────────────────────┘
                            ↓
┌─ Async Processing ─────────────────────────────────────────┐
│ (Off critical path)                                        │
│ • Deepgram Nova-3 speech-to-text via transcribeVideoUrl()  │
│   (server-side, deferred, fire-and-forget)                 │
│ • Gemini per-question scoring (resume context)             │
│ • AWS Rekognition facial analysis                          │
│   - Facial landmarks / engagement frames                   │
│   - Emotion metrics (HAPPY, CALM, CONFUSED, ANGRY)         │
│   - Aggregated per-question engagement score               │
└────────────────────────────────────────────────────────────┘
                            ↓
┌─ Recruiter Report ─────────────────────────────────────────┐
│ • Question + candidate answer (video playback)             │
│ • Transcript (from Deepgram, deferred load)                │
│ • Gemini score + reasoning                                 │
│ • Facial analysis panel (engagement graph, key frames)     │
└────────────────────────────────────────────────────────────┘
```

## Authentication & Authorization

- **Candidate:** Session-scoped; invitation ties `candidateEmailLower` to `interviews/{sessionId}` in Firestore.
- **Storage write:** Firebase Security Rules verify:
  - Request is authenticated (`request.auth != null`)
  - Email matches the `interviews/{sessionId}` doc's `candidateEmailLower` field (case-insensitive)
  - File size ≤ 50 MB
  - Content-type matches `video/*`
- **Recruiter:** Views entire session via `interviews/{sessionId}` Firestore doc and linked question/scoring data.

## Required Environment Variables

All keys are **server-side only** — the client receives only the public Firebase web config.

### Server-Side Keys (Express)

**Speech-to-Text (Deepgram Nova-3)**
```bash
DEEPGRAM_API_KEY=  # Video Interview STT via server-side pre-recorded transcribeVideoUrl(); also used by live avatar relay
```

**Gemini Scoring (AI Answer Analysis)**
```bash
GEMINI_API_KEY=           # Resume context, per-question scoring
GEMINI_MODEL=gemini-2.5-flash  # Optional; defaults as shown
```

**Facial Analysis (AWS Rekognition)**
```bash
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=us-east-2  # Must match your Rekognition bucket region
```

### Public Firebase Web Config (Compiled into Client Bundle)

```bash
VITE_FIREBASE_API_KEY=                    # Shared project talbotiq-9cc4e
VITE_FIREBASE_AUTH_DOMAIN=talbotiq-9cc4e.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=talbotiq-9cc4e
VITE_FIREBASE_STORAGE_BUCKET=talbotiq-9cc4e.firebasestorage.app  # Video clip storage
VITE_FIREBASE_MESSAGING_SENDER_ID=...
VITE_FIREBASE_APP_ID=...
```

See `.env.example` for the exact defaults.

## Firebase Storage Rules Deployment

### Rules File

The **`storage.rules`** file (at repo root) defines who can write video clips:

```
match /interviews/{sessionId}/{fileName} {
  allow write: if request.auth != null
               && firestore.get(/databases/(default)/documents/interviews/$(sessionId)).data.candidateEmailLower == request.auth.token.email.lower()
               && request.resource.size < 50 * 1024 * 1024
               && request.resource.contentType.matches('video/.*');
}
```

### Deploy

Firebase Storage rules **cannot be deployed via `npm run build`** — they are deployed separately using the Firebase CLI:

```bash
# When credentials are available (service account / Firebase CLI login):
firebase deploy --only storage
```

There is **no `firebase.json`** in this repo — each deployment environment manages its own config. To add it, see [Firebase CLI docs](https://firebase.google.com/docs/cli/setup).

### Verification

Storage rules **cannot be unit-tested locally**. Verify via:

1. **Firebase Console Rules Simulator:**
   - Go to Storage → Rules tab
   - Simulate a write request with:
     - Auth token: your candidate email
     - File size: 1 MB video
     - Path: `/interviews/{sessionId}/answer.webm`
     - Data: `{"contentType": "video/webm"}`
   - Confirm the rule allows the write

2. **Live deploy smoke test:**
   - Invite yourself as a candidate
   - Record and submit a question
   - Confirm the video appears in Storage without errors

## Capacitor Android

If building for Android via Capacitor, add the following **after** `npx cap add android`:

### AndroidManifest.xml Permissions

Edit `android/app/src/main/AndroidManifest.xml` and add:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-feature android:name="android.hardware.camera" android:required="false" />
```

**Note:** The `required="false"` allows the app to install on devices without a camera (though the Video Interview mode will not work without one).

### WebRTC / MediaRecorder Support

- **WebView:** Capacitor's WebView supports `getUserMedia()` and `MediaRecorder` on Android 7+ (API 24+).
- **Codec fallback:** The recorder hook (`useAnswerRecorder`) probes `MediaRecorder.isTypeSupported('video/webm')`:
  - If **supported:** uses `video/webm` (better compression, widely compatible).
  - If **unsupported:** falls back to `video/mp4` or browser default (some older Android versions).
  - **Test on your target device** — WebM support varies by manufacturer.

### Build Steps

```bash
npx cap add android
# ... edit AndroidManifest.xml ...
npx cap sync android
cd android
./gradlew assembleDebug   # or Release
```

## Known Considerations & Limitations

### Submit-vs-Deadline Race

The client pre-emptively submits ~3 seconds before the server auto-submit deadline. On a very slow upload (poor network), the server could auto-submit an empty answer before the client's clip lands, losing the video for that question. A follow-up could add a server-side "grace period" to hold advancement.

### Storage Cleanup

The source system (`talbotiq-avatar-server`) purges old interview media after 30 days. Video Interview does not yet have automatic cleanup — consider adding a Firebase Storage lifecycle rule or a scheduled Cloud Function as a follow-up.

### Two-Way / Live Interview

Not covered by the Video Interview track — that is a separate greenfield feature (not in the source). See the original design analysis for architectural notes.

## Debugging

### Client Upload Fails

Check browser console for:
- Firebase auth error → verify candidate email is in `interviews/{sessionId}.candidateEmailLower`
- Storage error → rules simulator (see above)
- Network error → check Content-Type header and file size

### Deepgram Transcription Hangs

Transcription is off the critical path (async). If a transcript doesn't appear:
- Check server logs for `[transcribe] failed` errors from `transcribeVideoUrl()`
- Verify `DEEPGRAM_API_KEY` is set and valid
- Audio duration must be ≥ 0.5 seconds

### Facial Analysis Missing

AWS Rekognition analysis is also deferred. If the `FacialAnalysisPanel` is empty:
- Check server logs for `[facial-frame]` Rekognition DetectFaces errors from `POST /api/sessions/:id/facial-frame`
- Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set
- Confirm bucket region matches `AWS_REGION`
- Facial capture is a graceful no-op / shows "not captured" when AWS is unconfigured

### Rules Simulator Rejects the Write

- Confirm `interviews/{sessionId}` Firestore doc exists
- Check `candidateEmailLower` field (must be lowercase, case-insensitive match against token email)
- Verify file MIME type is `video/*` (not `application/octet-stream`)
- Ensure file size < 50 MB

---

**Last updated:** 2026-07 (Task 8)
