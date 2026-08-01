# TalbotIQ Mailer Backend

A small **FastAPI** service that emails a list of candidates using a template.
No SQL database, no queue — custom templates are stored in the **same Firebase
project as the mobile app** (`talbotiq-9cc4e`, Firestore collection
`email_templates`).

## Endpoints

Interactive docs at `/docs`.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/templates?owner_email=…` | Templates this recruiter can pick: built-ins + their own. |
| `POST` | `/api/templates` | Save a custom template; returns its `id`. |
| `POST` | `/api/emails/send` | Send to a list of candidates using a template id. |
| `GET` | `/health` | Status + whether sending is actually configured. |

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

## Auth

If `API_KEY` is set, every `/api/*` call must send it as `X-API-Key`. Empty
disables the check (dev only). `app/security.py` is where Firebase ID-token
verification would slot in.

## Tests

```bash
pip install pytest
pytest
```

Runs in `DRY_RUN` with Firestore stubbed — no network, no credentials.

## Layout

```
app/
  main.py             FastAPI app + /health
  config.py           env-driven settings
  security.py         X-API-Key check
  mailer.py           delivery: smtp | gmail_api | dry_run
  firebase.py         lazy Firestore client (optional)
  templating.py       {{ }} renderer + the built-in templates
  templates_store.py  built-ins + Firestore CRUD
  routers/templates.py  GET/POST /api/templates
  routers/emails.py     POST /api/emails/send
```
