# Phase 0 results

Fill this in after running the spikes. **Phase 1 does not start until both questions
have a written answer** — the answers decide what Phase 2 and 3 actually build.

---

## Run 1 — 2026-08-02 — BLOCKED ON CREDENTIALS, no question answered

Neither spike reached its actual question. Both blockers are credential-side, not code.

**Gemini.** `GEMINI_API_KEY` is in the newer `AQ.` Google Cloud format (53 chars). It
fails on plain `GET /v1beta/models`, not just on `auth_tokens` — so the key is rejected
outright by `generativelanguage.googleapis.com` with `ACCESS_TOKEN_TYPE_UNSUPPORTED`.
This is a [widely reported issue with `AQ.`-prefixed keys](https://discuss.ai.google.dev/t/aq-key-401-access-token-type-unsupported-fully-configured-key-still-rejected/172852)
with no official fix as of late July 2026.
→ **Need a classic AI Studio key** (`AIza…`, 39 chars) from <https://aistudio.google.com/apikey>.
The keys the app uses today are already that format.

**Deepgram.** Key is **valid** — preflight lists the project fine. But `/v1/auth/grant`
returns 403 `Insufficient permissions`: minting requires a key with the **Member** role
or higher, and this one is scoped to usage only.
→ **Need a Member-role key** from the Deepgram console → Settings → API Keys.
Only the backend ever holds it; the app receives a short-lived JWT.

**Two script bugs found and fixed along the way**
1. Mint URL was `v1alpha/auth_tokens`; the REST path is **`v1beta/auth_tokens`**. The
   `api_version: 'v1alpha'` in Google's docs is an SDK setting, not the URL — and an
   unrecognised method path makes the gateway answer "expected OAuth 2" rather than 404,
   which reads exactly like a bad key.
2. The verdict printed `RELAY REQUIRED` when every case had *errored*. An error is not
   evidence that locking failed. Both scripts now preflight the key against a known-good
   endpoint and report `INCONCLUSIVE` unless a case actually reached the model.

---

## 0.1 — Gemini ephemeral token: does the systemInstruction lock hold?

`.venv/bin/python spikes/gemini_token_lock.py`

- Date run: **2026-08-02**
- Model: `models/gemini-2.5-flash-native-audio-preview-09-2025`
- Mint endpoint: **`https://generativelanguage.googleapis.com/v1beta/auth_tokens`** (`x-goog-api-key`)
- WS endpoint: **`wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained?access_token=<name>`**

| Case | Expected | Actual |
|---|---|---|
| A — control, unconstrained + client ASSISTANT | ASSISTANT | **ASSISTANT** ✅ |
| B — locked PIRATE, no client instruction | PIRATE | **PIRATE** ✅ |
| C — locked PIRATE vs conflicting client ASSISTANT | PIRATE | **PIRATE** ✅ |
| D — replay a `uses: 1` token | REJECTED | **REJECTED** ✅ |

### Verdict: **PROCEED DIRECT** — the lock holds against a hostile client.

A client that sends a conflicting `systemInstruction` is overridden: the model stayed in
the token's persona. The [reported bug](https://discuss.ai.google.dev/t/live-api-with-ephemeral-token-ignores-the-system-instruction/113346)
did **not** reproduce with the correct recipe.

### The correct wire format (NOT what the SDK docs show)

The SDK names `live_connect_constraints` and `lock_additional_fields` **do not exist on
the REST surface**. From the API discovery document, the real `AuthToken` message is:

```
name · expireTime · uses · newSessionExpireTime · fieldMask · bidiGenerateContentSetup · interactionId
```

Locking is done with `bidiGenerateContentSetup` + `fieldMask`:

| fieldMask | Effect |
|---|---|
| **empty** (omitted) | effective setup taken **entirely** from the token — **the client's setup frame is ignored** |
| non-empty | only the masked fields overwrite the client's setup |

**Use the empty-fieldMask form.** It is a full lock, strictly stronger than the
field-list approach the SDK docs describe.

```jsonc
POST https://generativelanguage.googleapis.com/v1beta/auth_tokens
x-goog-api-key: <server key>
{
  "uses": 1,
  "expireTime": "…",              // default 30 min
  "newSessionExpireTime": "…",    // default 60 s, max 20 h
  "bidiGenerateContentSetup": {   // no fieldMask ⇒ full lock
    "model": "models/gemini-2.5-flash-native-audio-preview-09-2025",
    "generationConfig": { "temperature": 0.7, "responseModalities": ["AUDIO"] },
    "systemInstruction": { "parts": [{ "text": "<built server-side>" }] },
    "sessionResumption": {},
    "outputAudioTranscription": {}
  }
}
```

### Consequences for Phase 2 — important

1. **No relay anywhere.** Candidate device connects straight to Gemini Live.
2. **The token must carry the ENTIRE setup.** Because the client's setup frame is
   discarded, everything `gemini_live_service._sendSetup` sends today has to move into
   the mint — including `speechConfig.voiceConfig.prebuiltVoiceConfig` (per-interview
   `interview.voiceName`) and `outputAudioTranscription`. Anything omitted is simply
   lost; the client cannot supply it.
3. **`uses` default is 1, and session resumption does not count as a use** — so a long
   interview that resumes stays within one token.
4. **`newSessionExpireTime` defaults to 60 s** (max 20 h) → mint on launch-tap, connect
   immediately.
5. Mint on **v1beta**, connect on **v1alpha/BidiGenerateContentConstrained**. Both
   versions expose the same `AuthToken` schema; the constrained WS service is v1alpha.

---

## 0.2 — Deepgram temporary token: does the web path work?

### Verdict: **NOT APPLICABLE — spike cancelled, no token needed.**

Superseded by a usage audit of the app rather than by running the spike. Deepgram has
**no live WebSocket usage at all**:

| Symbol | Status |
|---|---|
| `buildWsUrl()` | defined, **never called** — there is no live-captions path |
| `transcribeFromUrl` | never called |
| `testConnection()` | only the Settings "Test" button, which is being deleted |
| `setDeepgramConnected` / `deepgramConnected` | no callers — dead AppStore state |

The single real call site is
[results_page.dart:256](../../talbotiq_app/lib/features/interviews/candidate/results/results_page.dart#L256)
`transcribeFromFile`, which the code itself labels *"Fallback path (native only)"*:
post-interview transcription of a local `.wav`, skipped entirely when no key is set.
Primary transcripts come from Tavus (`?verbose=true`) and Gemini Live.

**Consequences**
- No WS relay, no subprotocol question, no Flutter-web problem.
- **No Member-role Deepgram key needed.** The earlier `403 Insufficient permissions` on
  `/v1/auth/grant` is moot — a usage-scoped key (what you have) is enough for
  `POST /v1/listen` behind the proxy.
- Phase 3 gets exactly one Deepgram route: `POST /api/deepgram/transcribe`.

Only revisit if live captions are ever wanted. For reference, the spike did confirm the
key is valid and can list the project; `/auth/grant` is the only thing it can't reach.

---

## Phase 5 soak — 2026-08-02

`PYTHONPATH=. .venv/bin/python spikes/soak.py` — every route against real vendors.

| Route | Result |
|---|---|
| `GET /health` | PASS — all four providers configured |
| `GET /api/tavus/replicas` | PASS — 90 replicas |
| `GET /api/tavus/personas` | PASS — 10 personas |
| `POST /api/tavus/conversations` | SKIP — starts a billable avatar session |
| `POST /api/gemini/generate` | PASS — key absent from response |
| `POST /api/rt/gemini-token` | PASS |
| `POST /api/deepgram/transcribe` | PASS — 64 KB accepted, 1 channel returned |
| `POST /api/hume/jobs` | **FAIL — upstream discontinued (see below)** |
| rate limiting | PASS — 429 after the live-token limit |

### Hume's Expression Measurement API is gone

Not a key problem and not our code. Every `/v0/batch/*` endpoint returns:

```
403 {"code":403, "message":"The Expression Measurement API has been
     discontinued and is no longer available."}
```

Hume [shut it down on 14 June 2026](https://dev.hume.ai/docs/expression-measurement/faq),
moving expression sensing into EVI (real-time conversational) instead. There is no
drop-in batch replacement from Hume; third parties (audEERING, Imentiv) offer
migrations.

**So the app's Hume prosody feature has been dead in production for ~7 weeks,
independently of this migration.** Our proxy behaved correctly — it surfaced the
vendor 403 as a 503 naming the provider.

Decision needed: delete the Hume integration, or swap in a replacement vendor.
Until then the three `/api/hume/*` routes proxy to a dead API.

### One production bug found and fixed

The shared `httpx.AsyncClient` cached connections belonging to whichever event
loop first used it. Under uvicorn there is one loop for the process lifetime so
it never surfaced, but any second loop hit `RuntimeError: Event loop is closed`.
`http_client()` now binds the pool to the running loop.
