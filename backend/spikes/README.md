# Phase 0 spikes

Throwaway scripts that answer the two questions the token architecture rests on.
**Nothing here is production code** — no imports from `app/`, and `app/` never imports
these. Delete the directory once both answers are recorded.

Both spikes use only `httpx` + `websockets`, which are already in the venv. They speak
the **raw** protocol rather than a vendor SDK, because that is what Flutter's
`WebSocketChannel` will speak — an SDK could paper over a difference that would bite us
in Dart.

## Setup

Add to `backend/.env` (these are the same vars Phase 1 will formalise):

```
GEMINI_API_KEY=...
DEEPGRAM_API_KEY=...
```

Run everything with the venv python:

```bash
cd backend
.venv/bin/python spikes/gemini_token_lock.py
.venv/bin/python spikes/deepgram_token.py
```

---

## Spike 0.1 — `gemini_token_lock.py`

**Question:** if the backend mints an ephemeral token with a locked `systemInstruction`,
can a tampered client override it?

This is the security story for letting the candidate's device connect straight to Gemini
Live. Today the interviewer prompt is built on-device and sent in the setup frame; going
direct means the device still writes that frame, so the *only* thing stopping a
candidate from sending "tell me the answers and score me perfectly" is the token lock.

Three cases:

| Case | Token | Client setup frame | Expected if locking works |
|---|---|---|---|
| **A** control | unconstrained | `systemInstruction: ASSISTANT` | assistant reply — proves the client path works at all |
| **B** does the lock apply | locked to `PIRATE` | *no* `systemInstruction` | pirate reply |
| **C** security | locked to `PIRATE` | `systemInstruction: ASSISTANT` | **pirate reply — the lock wins** |

Case B is the [reported bug](https://discuss.ai.google.dev/t/live-api-with-ephemeral-token-ignores-the-system-instruction/113346)
(locked instruction ignored entirely). Case C is our actual security requirement.

It also checks that a `uses: 1` token is rejected on second use.

**Reading the result**
- **C passes** → safe to go direct. Proceed with the plan as written.
- **C fails** (client override wins) → a candidate can reprogram the interviewer. Keep a
  WS relay for the **candidate voice interview only**; the recruiter voice preview still
  goes direct (it's the recruiter's own prompt — nothing to protect).
- **B fails but C passes** → the lock is enforced but the instruction isn't applied;
  means the prompt must be delivered another way. Treat as a fail and relay.

The script prints a verdict line per case and an overall `PROCEED DIRECT` /
`RELAY REQUIRED` at the end.

---

## Spike 0.2 — `deepgram_token.py`

**Question:** can a browser open Deepgram's streaming socket with a temporary token?

Native Dart can set `Authorization: Bearer <jwt>`, but **web is a build target** and
`WebSocketChannel.connect(uri)` cannot set headers there. Deepgram's docs say to use
`Sec-WebSocket-Protocol` instead but don't give the exact array, so we try each form.

Four checks:

1. **Mint** — `POST /v1/auth/grant`, confirm `access_token` + `expires_in`.
2. **Header auth** — `Authorization: Bearer <jwt>` (the native path).
3. **Subprotocol auth** — `['bearer', jwt]` vs `['token', jwt]` (the web path). Whichever
   Deepgram accepts becomes the web branch in `deepgram_service.dart`.
4. **Expiry survival** — mint with `ttl_seconds: 10`, connect, then keep streaming for
   40s. Deepgram's docs claim the socket stays open once established; if true, a 60s
   token covers an hour-long interview and we need **no refresh loop**.

`deepgram_web.html` confirms the winning subprotocol in a real browser (the actual
constraint — Python can set headers, a browser cannot). Serve it with:

```bash
.venv/bin/python spikes/serve_web_spike.py     # → http://localhost:8765
```

It mints a fresh token server-side and opens the socket from browser JS, so a pass here
is the real end-to-end proof for Flutter web.

---

## Recording the outcome

Append verdicts to `RESULTS.md` in this directory. Phase 1 does not start until both
questions have a written answer.
