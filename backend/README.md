# TalbotIQ Backend

A small **FastAPI** service with two jobs:

1. **Mailer** — email a list of candidates using a template. No SQL database, no
   queue; custom templates live in the **same Firebase project as the mobile
   app** (`talbotiq-9cc4e`, Firestore collection `email_templates`).
2. **AI gateway** — hold every third-party credential (Gemini, Tavus, Deepgram)
   so the mobile app holds none. See [AI providers](#ai-providers).

## Endpoints

Interactive docs at `/docs`.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/templates?owner_email=…` | Templates this recruiter can pick: built-ins + their own. |
| `POST` | `/api/templates` | Save a custom template; returns its `id`. |
| `POST` | `/api/emails/send` | Send to a list of candidates using a template id. |
| `POST` | `/api/rt/gemini-token` | Mint a locked Gemini Live token for an assigned interview. |
| `*` | `/api/tavus/*` | Avatar replicas, personas and conversations. |
| `POST` | `/api/gemini/generate` | One `generateContent` call (scoring, question generation, …). |
| `POST` | `/api/deepgram/transcribe` | Transcribe recorded audio. |
| `GET` | `/health` | Status, sending readiness, and which AI providers are configured. |

Custom templates are **owned by the email that created them** (`owner_email`,
stored lowercased). A recruiter only ever sees the built-ins plus their own, and
cannot send with someone else's template id (404).

### `GET /api/templates?owner_email=…`

Omit `owner_email` and you get the built-ins only.

```jsonc
{
  "templates": [
    { "id": "builtin:interview_invite", "name": "Interview invite",
      "subject": "…", "body": "…", "is_html": true,
      "source": "builtin", "is_default": true },
    { "id": "0dU51aGWqkkhse1r4zGi", "name": "Round 2 invite",
      "source": "custom", "owner_email": "vaishnavi@talbotiq.com", … }
  ],
  "default_template_id": "builtin:interview_invite",
  "variables": { "candidate_name": "…", "interview_link": "…", … },
  "warning": null   // set if Firestore is unreachable — built-ins still returned
}
```

Built-ins ship in code (`app/templating.py`): `interview_invite`,
`interview_reminder`, `result_published`, `plain_invite`.

### `POST /api/templates`

```jsonc
{
  "name": "Round 2 invite",
  "description": "Our wording for the second round",   // optional
  "subject": "{{ company }} — round 2 for {{ candidate_name }}",
  "body": "<h2>Hi {{ candidate_name }}</h2>…",
  "is_html": true,                                      // optional, default true
  "owner_email": "vaishnavi@talbotiq.com",              // required — who owns it
  "recruiter_id": "firebase-uid"                        // optional, for traceability
}
```

→ `201` with the saved template, including the `id` to pass to `/send`.

### `POST /api/emails/send`

```jsonc
{
  "template_id": "0dU51aGWqkkhse1r4zGi",   // omit → default_template_id is used
  "owner_email": "vaishnavi@talbotiq.com", // who is sending (ownership check)
  "shared_context": {                       // variables shared by everyone
    "interview_title": "Senior Flutter Engineer",
    "recruiter_name": "Vaishnavi",
    "company": "TalbotIQ"
  },
  "recipients": [
    { "email": "ada@example.com", "name": "Ada",
      "context": { "interview_link": "https://talbotiq.app/i/abc" } },
    { "email": "grace@example.com",
      "context": { "interview_link": "https://talbotiq.app/i/def" } }
  ]
}
```

`subject` / `body` / `is_html` may also be sent inline to override the template
for this one call. Response:

```jsonc
{
  "total": 2, "sent": 2, "failed": 0,
  "template_id": "0dU51aGWqkkhse1r4zGi",
  "provider": "smtp",
  "subject_preview": "TalbotIQ — round 2 for Ada",
  "results": [ { "email": "ada@example.com", "status": "sent", "error": null }, … ]
}
```

One bad address fails only its own row; the rest still go out.
`SEND_CONCURRENCY` recipients are delivered in parallel.

## Template variables

`{{ variable }}` placeholders (plain substitution — no code execution, so
recruiter-authored templates can't run anything server-side). Unknown
placeholders render empty.

`candidate_name`, `candidate_email`, `interview_title`, `interview_link`,
`recruiter_name`, `company`, `deadline` — plus anything else you put in
`shared_context` / a recipient's `context`.

Precedence per recipient: `shared_context` < recipient `context` <
`candidate_name` / `candidate_email` (always the candidate's own).

## Quick start

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # DRY_RUN=true — emails are logged, not sent
uvicorn app.main:app --reload # http://localhost:8000  (docs at /docs)
```

`GET /health` tells you what mode you're in:

```json
{"status":"ok","provider":"dry_run","sending_ready":true,"hint":null,
 "firebase_project":"talbotiq-9cc4e"}
```

## Sending for real

Set `DRY_RUN=false` and pick one mode:

**A — Gmail App Password (simplest).** With 2-Step Verification on, create one at
[myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords):

```env
DRY_RUN=false
EMAIL_USER=hr@yourdomain.com
EMAIL_APP_PASSWORD=abcd efgh ijkl mnop
```

**B — Gmail API (OAuth refresh token).** Use where outbound SMTP is blocked
(e.g. some PaaS hosts). Enable the Gmail API, create an OAuth **Desktop** client,
authorise the `gmail.send` scope once, and capture a refresh token:

```env
DRY_RUN=false
EMAIL_USER=hr@yourdomain.com
GMAIL_CLIENT_ID=…
GMAIL_CLIENT_SECRET=…
GMAIL_REFRESH_TOKEN=…
```

Mode B wins when all three `GMAIL_*` values are set. If neither is configured,
`/send` returns **503** with a hint instead of silently failing.

## Firebase (custom templates)

Built-ins and sending work with no Firebase setup. To save custom templates,
give the service a **service account** for the mobile app's project:

1. Firebase console → ⚙ **Project settings → Service accounts → Generate new
   private key** — this downloads a JSON file.
2. Point the service at it:

```env
FIREBASE_PROJECT_ID=talbotiq-9cc4e
FIREBASE_CREDENTIALS_FILE=./serviceAccount.json
# or, as a single env var on Render/Cloud Run:
# FIREBASE_CREDENTIALS_JSON={"type":"service_account", …}
```

Keep that JSON out of git (`.gitignore` already covers `.env`). The Admin SDK
bypasses Firestore security rules, so templates need no rule changes — the app
talks to this API, not to the collection directly.

Local testing without a service account:

```bash
firebase emulators:start --only firestore --project talbotiq-9cc4e
FIRESTORE_EMULATOR_HOST=localhost:8080 uvicorn app.main:app --reload
```

## AI providers

Every vendor credential lives **only** in this service's environment. The mobile
app never receives one: it either calls a proxy route here, or connects straight
to Gemini Live using a short-lived token minted here from `GEMINI_API_KEY`.

```bash
GEMINI_API_KEY=AIza…      # AI Studio key — https://aistudio.google.com/apikey
TAVUS_API_KEY=
DEEPGRAM_API_KEY=
```

Any left blank makes that feature answer **503** with a message naming the env
var to set, rather than failing later with a confusing vendor error. `GET /health`
reports which are configured under `providers` — that is the authoritative
availability check, replacing the app's old per-key "Test Connection" buttons.

> **Gemini keys:** use an AI Studio key (starts with `AIza`). Newer `AQ.`-prefixed
> Google Cloud keys are rejected by `generativelanguage.googleapis.com` and will
> not work.

### `POST /api/rt/gemini-token`

Returns a short-lived token the app uses to open **one** Gemini Live voice
session, connecting straight to Google — this service is never in the audio path.

```jsonc
// request — an interview id and nothing else
{ "interview_id": "abc123" }

// response
{ "token": "auth_tokens/…", "wsUrl": "wss://…BidiGenerateContentConstrained",
  "model": "models/…", "expiresAt": "…Z", "connectBy": "…Z" }
```

The model, voice and interviewer system instruction are resolved from the
interview document and **locked into the token**, so a tampered client cannot
change the session it is about to open. Connect with
`{wsUrl}?access_token={token}` before `connectBy` (default 120s).

Callers must be the assigned candidate (matched on `candidateEmailLower`) or the
owning recruiter; the interview must be inside its access window and have
attempts left. `409` means it cannot start right now, `403` means it is not
yours.

> **Do not add a `fieldMask` when minting.** Omitting it is what makes Google
> ignore the client's setup frame entirely. See `app/providers/gemini.py` and
> re-run `spikes/gemini_token_lock.py` before changing that.

### The AI proxy

| Method | Path | Replaces |
| --- | --- | --- |
| `GET` | `/api/tavus/replicas` | custom + stock, merged and de-duplicated |
| `GET` | `/api/tavus/personas` | |
| `POST` | `/api/tavus/conversations` | returns the Daily URL the device joins |
| `GET` | `/api/tavus/conversations/{id}` | status |
| `GET` | `/api/tavus/conversations/{id}/verbose` | status + server-side transcript |
| `POST` | `/api/tavus/conversations/{id}/end` | ends the call, keeps the transcript |
| `POST` | `/api/tavus/conversations/{id}/interactions` | `{"text": "…"}` — overwrite live context |
| `POST` | `/api/gemini/generate` | every `generateContent` caller |
| `POST` | `/api/deepgram/transcribe` | audio as the raw body, `?model=&language=` |

**One Gemini route, not one per purpose.** All eight callers in the app hit the
same upstream endpoint and differ only in their prompt, so the client still
builds `contents`; this service supplies the key and the model. The prompts are
not secrets — the credential was the thing that had to move — and porting them
to Python would duplicate a lot of logic across two languages for no security
gain. Where the prompt *is* the security boundary (the voice interviewer's
instruction) it does live server-side; see `app/voice.py`.

What the caller cannot control: the model, the upstream host, and payload size
(64 MB audio, 12 MB Gemini).

> **Hume was removed.** Its Expression Measurement (batch prosody) API was
> discontinued by Hume on 14 June 2026 and every endpoint now returns 403. The
> integration could not work, so it is gone rather than left as a dead path.

## Auth

Two schemes, by route:

| Routes | Scheme |
| --- | --- |
| `/api/templates`, `/api/emails/*` | `X-API-Key` — the shared secret in `API_KEY`. Empty disables the check (dev only). |
| AI proxy + token minting | `Authorization: Bearer <Firebase ID token>` |

The AI routes spend real money and can mint credentials, so they need to know
*which user* is calling — not merely that the caller holds a secret. A shared
secret compiled into the app bundle would be an unrotatable shipped credential;
an ID token is per-user, short-lived and revocable.

## Rate limits

Authentication proves a caller is a real user; it does not bound what one user
can spend. The billable routes are limited per user:

| Bucket | Routes | Default |
| --- | --- | --- |
| `live-token` | `POST /api/rt/gemini-token` | 10 / min |
| `gemini-generate` | `POST /api/gemini/generate` | 30 / min |
| `media` | Tavus conversation create, Deepgram transcribe | 20 / min |

Read-only polling (conversation status) is **not** limited — it costs
nothing and needs to stay responsive. Buckets are separate so a burst of scoring
cannot stop a candidate from starting their interview. Exceeding a limit returns
`429` with `Retry-After`, and the request never reaches the vendor.

Counters are **in-process**: they reset on restart and are not shared between
workers, so N workers allow roughly N x the configured limit. That is deliberate
— it needs no extra infrastructure and stops the cases that actually hurt (a
retry loop, a script with a stolen ID token). If exact limits are ever needed,
swap the store in `app/ratelimit.py`; the routes do not change.

## Tavus conversation defaults

Recording destination and session timeouts are org infrastructure, set here rather
than in the app:

```bash
TAVUS_ENABLE_RECORDING=false
TAVUS_RECORDING_S3_BUCKET=
TAVUS_RECORDING_S3_REGION=
TAVUS_AWS_ASSUME_ROLE_ARN=
```

The app sends only what is genuinely per-interview (replica, persona, context,
duration, language); this service merges the rest in at create time. The four
recording fields are **locked** — a caller that supplied them would be able to
point the org's AWS assume-role at a bucket it controls, so they are dropped from
the request body rather than passed through.

## Known limits of this design

Worth knowing before relying on it:

* **Any signed-in user can read or end any Tavus conversation, given its id.**
  Ids are opaque and unguessable, and the app has no conversation→interview
  mapping to check ownership against. Binding them would
  be a feature, not a hardening pass. The token route is different: it *is*
  ownership-checked, because there the caller names the interview.
* **`POST /api/gemini/generate` accepts caller-built prompts.** Any signed-in
  user can spend Gemini quota within their rate limit. The model and upstream
  are fixed server-side; the prompt is not.
* **CORS defaults to `*`.** Credentialed CORS is disabled whenever origins are a
  wildcard, so this is safe for bearer-token auth, but set `CORS_ORIGINS` to your
  real origins in production anyway.

## Tests

```bash
pip install pytest
pytest
```

Runs in `DRY_RUN` with Firestore stubbed — no network, no credentials.

## Layout

```
app/
  main.py             FastAPI app, /health, provider error handlers
  config.py           env-driven settings (the only reader of os.environ)
  security.py         X-API-Key + Firebase ID-token auth
  mailer.py           delivery: smtp | gmail_api | dry_run
  firebase.py         lazy Admin SDK / Firestore client (optional)
  templating.py       {{ }} renderer + the built-in templates
  templates_store.py  built-ins + Firestore CRUD
  interviews.py       reads the interviews collection + who may launch one
  voice.py            interviewer personas, system instruction, Live setup
  providers/          one module per vendor; the only holders of API keys
    base.py           shared httpx client, ProviderNotConfigured, UpstreamError
    gemini.py         ephemeral Live tokens + generateContent
    tavus.py          replicas, personas, conversations
    deepgram.py       pre-recorded transcription
  routers/templates.py  GET/POST /api/templates
  routers/emails.py     POST /api/emails/send
  routers/realtime.py   POST /api/rt/gemini-token
  routers/ai.py         the vendor proxy routes
```

Dependencies point one way: `routers → providers → config`. A provider module
never imports a router, and nothing outside `config.py` reads `os.environ`.
