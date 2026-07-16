# TalbotIQ Mailer Backend

A standalone **FastAPI** service that sends interview-invite emails to selected
candidates and stores recruiter-customised email templates. Called by the
Flutter app when a recruiter creates an exam with *"Notify candidates"* enabled.

## Queue-based architecture

Email delivery is **asynchronous and durable** so the API stays responsive and
many recruiters can send at once:

```
POST /api/emails/send
      │  render one email per candidate, persist as jobs (status=queued)
      │  return 202 { batch_id, queued } immediately  ◀── never blocks on SMTP/Gmail
      ▼
  email_jobs (queue table, durable)
      │  workers atomically claim the oldest due job (queued → processing)
      ▼
  worker pool (N async workers, started in the app lifespan)
      │  send via Gmail API off the event loop (asyncio.to_thread)
      ├── success → status=sent
      └── failure → retry with exponential backoff, then status=failed
```

- **Responsive:** the request only writes rows and nudges the workers; delivery
  happens in the background.
- **Concurrent & fair:** `WORKER_CONCURRENCY` workers process the global queue in
  FIFO order, so multiple recruiters' batches interleave.
- **Reliable:** jobs are persisted, retried with backoff (`JOB_MAX_ATTEMPTS`),
  and any job left `processing` by a crash is recovered to `queued` on startup
  (at-least-once delivery).
- **No external broker:** the queue is a DB table (SQLite by default). Point
  `DATABASE_URL` at Postgres to share one queue across multiple app/worker
  processes — the guarded atomic claim is safe there too.

## Quick start

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # DRY_RUN=true — emails are logged, not sent
uvicorn app.main:app --reload # http://localhost:8000  (docs at /docs)
```

## Gmail API setup (one time)

DRY_RUN mode needs no credentials. To send for real:

1. In Google Cloud Console, enable the **Gmail API**.
2. Create an **OAuth client ID** (type: Desktop app). Note the client id/secret.
3. Authorise the `https://www.googleapis.com/auth/gmail.send` scope once for the
   sending account and capture a **refresh token** (e.g. via the OAuth
   Playground with your own client, or a short local script).
4. Put `EMAIL_USER`, `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`,
   `GMAIL_REFRESH_TOKEN` in `.env` and set `DRY_RUN=false`.

This mirrors the OAuth refresh-token flow and works on hosts like Render where
outbound SMTP is often blocked.

## Auth

If `API_KEY` is set, every `/api/*` call must send it as `X-API-Key`. Empty
disables the check (dev). `app/security.py` is where Firebase ID-token
verification would slot in for production.

## Endpoints

Interactive docs at `/docs`.

### Emails
| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/api/emails/send` | Enqueue an invite per recipient; returns `202 {batch_id, queued}`. |
| `GET` | `/api/emails/batches/{id}` | Batch progress: queued/processing/sent/failed + per-job status. |

`POST /api/emails/send` body:

```jsonc
{
  "recruiter_id": "firebase-uid",
  "template_id": 3,               // optional: use a saved template…
  "subject": "…", "body": "…",    // …or supply inline (inline wins)
  "is_html": true,
  "shared_context": { "interview_title": "Senior Flutter Engineer",
                      "recruiter_name": "Vaishnavi", "company": "TalbotIQ" },
  "recipients": [
    { "email": "a@x.com", "name": "Ada",
      "context": { "interview_link": "talbotiq://interview/abc123" } }
  ]
}
```

### Templates
| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/templates/defaults` | Built-in starter subject/body + supported variables. |
| `GET` | `/api/templates?recruiter_id=…` | List a recruiter's saved templates. |
| `POST` | `/api/templates` | Save a new template. |
| `PUT` | `/api/templates/{id}` | Update a template. |
| `DELETE` | `/api/templates/{id}` | Delete a template. |

## Template variables

`{{ variable }}` placeholders (plain substitution — no code execution):
`candidate_name`, `candidate_email`, `interview_title`, `interview_link`,
`recruiter_name`, `company`. Unknown placeholders render empty.

## Running workers separately (optional scale-out)

By default workers run inside the API process. To scale delivery independently,
set `WORKER_CONCURRENCY=0` on the API instances and run one or more dedicated
worker processes against the same `DATABASE_URL` (a small runner that calls
`QueueManager.start()`), or migrate the queue to Celery/RQ + Redis — the job
model and repository are the natural seam for that.

## Tests

```bash
pip install pytest
pytest
```

Runs entirely in `DRY_RUN` with an in-memory DB — no network, no Gmail creds.
