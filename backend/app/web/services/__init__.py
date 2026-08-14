"""Service modules, mirroring `web_version/talbotiq-platform/server/services/`.

One module per Express service, same name, so the two trees diff side by side.

Six Express services are deliberately NOT ported — a shared equivalent already
exists in the kernel, and duplicating it would create two things to keep in sync:

    dailyServer.ts    -> app.providers.daily
    firebaseAdmin.ts  -> app.firebase
    rekognition.ts    -> app.providers.rekognition  (to be added)
    transcription.ts  -> app.providers.deepgram
    email.ts          -> app.mailer                 (after its generic-SMTP rewrite)
    users.ts          -> reads Firestore `users/{uid}` directly

`gemini.ts` and `tavusServer.ts` ARE ported, as thin wrappers adding web-only
behaviour (runtime key resolution, the candidate avatar payload) over the shared
provider clients.

Port the pure modules first, with their existing tests: `timing.ts`,
`voiceFlow.ts`, `signals.ts` and `videoTranscript.ts` are dependency-free state
machines and calculators, and they are the correctness core of the interview
engine. Get them green before wiring a single route.
"""
