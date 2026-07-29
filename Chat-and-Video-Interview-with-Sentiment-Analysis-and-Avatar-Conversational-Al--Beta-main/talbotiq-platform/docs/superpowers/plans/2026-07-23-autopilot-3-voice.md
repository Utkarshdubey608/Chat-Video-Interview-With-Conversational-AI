# Mimic Guide Autopilot — Plan 3: Voice + One-shot (final v1 slice)

**Date:** 2026-07-23 · **Branch:** `feat/avatar-screening-migration`

**Goal:** Complete the v1 vision — the recruiter can drive the guided setup flow hands-free by **voice** (as well as typed). Most of Plan 3's scope already works after Plan 2 and is reused rather than rebuilt:

- **Voice OUTPUT (speak each prompt):** already works — the existing auto-speak effect (`MimicGuide.tsx`) speaks every appended assistant message via `speakSmart`, honoring the language selector. Autopilot's `res.say` is appended as an assistant message, so it is already spoken. No change.
- **One-shot:** already works — the runner loops (cap 8) so a single utterance ("set up a video interview for Senior Backend Engineer") fills mode → role → … across iterations. Plan 3 adds a small prompt nudge to make the model reliably extract EVERY provided field before asking.
- **Correct / go-back / take-over:** already work — "no, make it Voice" is just the next utterance (model re-emits `selectMode`); `setup.backStep` is a registered action ("go back"); take-over is inherent (the wizard is fully usable manually — Autopilot is additive).
- **Interrupt:** already works — `cancelSpeech()`/`stopSpeakRef` stop TTS; toggling the mic stops listening.

So Plan 3 is two small, reviewable changes.

## Changes

### Change 1 — One-shot prompt nudge (server, TDD)
`server/services/autopilotAgent.ts` → `buildAutopilotPrompt`: add one instruction so the model extracts all fields the user already gave in a single utterance and asks only for what's missing. Add a test assertion in `autopilotAgent.test.ts` that the prompt contains the one-shot guidance.

### Change 2 — Mic auto-submit in Autopilot mode (client)
`src/features/guide/MimicGuide.tsx` → `toggleMic`'s `onResult`: when Autopilot is ON, auto-submit the final transcript through `submitComposer(transcript)` (hands-free, per the "take answers by my mic automatically" ask) instead of only appending to the draft. Guide-mode (Autopilot OFF) mic behavior is unchanged (dictate-into-draft). Use refs (`autopilotRef`, `submitComposerRef`) so the recognition callback always sees the latest state (no stale closure). The transcript still appears as the user turn (visible/correctable via the next utterance).

## Constraints
Additive; guide-OFF mic + all existing behavior unchanged; reuse `startSpeechRecognition`/`speakSmart`; whitelist + confirm-before-side-effect unchanged (voice answers flow through the same executor/confirm card). Keys server-side.

## Gates
`npx tsx server/services/autopilotAgent.test.ts` (incl. new one-shot assertion); `npm run build`; `npx tsc -p server/tsconfig.json --noEmit`. Manual: with a mic in Chrome/Edge, toggle Autopilot, click the mic, speak "set up a video interview for Senior Backend Engineer", confirm it fills the wizard and speaks its prompts; a spoken "create the invites" surfaces the read-back confirm card (no send without Confirm).

## Follow-ups (post-v1)
Live interim transcript with an edit-before-act window (needs `interimResults` on a per-call basis so the shared guide mic is unaffected); continuous hands-free listening; server-persisted audit; widen the registry to Templates/Question-Sets/Results/Pipelines/CSV.
