# Migration Runbook — the human steps, in order

**For:** the actions an agent cannot do for you — console clicks, credentials, key rotation, legal, spending money.
**Companion docs:** [`DATA_STORAGE_AUDIT.md`](./DATA_STORAGE_AUDIT.md) (what's where) · [`STORAGE_MIGRATION_PROMPT.md`](./STORAGE_MIGRATION_PROMPT.md) (what Cursor executes) · [`EU_AI_ACT_COMPLIANCE.md`](./EU_AI_ACT_COMPLIANCE.md) (the legal gate)

---

## If you do only three things this week

1. **Rotate every provider key** (Step 2) — they've been sitting in a plaintext file and one is in browsers.
2. **Add the Storage lifecycle rule** (Step 3) — recordings currently accumulate forever. ⚠️ Read the prefix warning; a blanket rule breaks sent emails.
3. **Point an alert at `persistence.ok === false`** (Step 4) — the code now reports failing disk writes; nothing is listening yet.

Everything else can wait weeks. These three cannot.

---

## Do you actually need all five phases?

Be honest about current scale before spending money.

| Phase | Do it when | Monthly cost |
|---|---|---|
| **0 — Console hygiene** | **Now.** Free. | £0 |
| **1 — Secrets** | **Now.** Keys are exposed today. | ~£0 (Secret Manager is pennies) |
| **2 — Media retention** | **Now.** Compliance + storage cost both grow daily. | Saves money |
| **3 — Firestore** | Before you hold real candidate data at volume, **or** before you need a 2nd instance. This is the scaling unlock. | £low, usage-based |
| **4 — Redis + queues** | Only when you actually run N>1. | **£40–70+/mo floor** (Memorystee has no free tier) |
| **5 — BigQuery** | Only when analytics gets slow or you need per-tenant cost data. | £low until volume |

**Phases 4–5 are premature if you don't have traffic yet.** A single Cloud Run instance on Firestore will carry a real pilot comfortably. Don't pay for Memorystore before you need it.

---

## Step 0 — Review and commit what already changed (15 min)

Four files changed and four are new. Your branch has unrelated work in progress, so review this diff on its own.

```bash
cd "path/to/Virtual - Copy - Copy - Copy"

# The code changes — read these before committing
git diff talbotiq-platform/server/store/db.ts \
         talbotiq-platform/server/index.ts \
         talbotiq-platform/src/store/useAppStore.ts

# Verify for yourself
cd talbotiq-platform && npm test    # expect: 34 files pass
```

What you're approving:
- `db.ts` — atomic writes (temp + rename) and `saveHealth()`
- `index.ts` — `/api/health` now returns a `persistence` block
- `useAppStore.ts` — dead `awsKey`/`anthropicKey` deleted; `tavusKey` left with a `TODO(phase-1)`
- `db.atomicsave.test.ts` — new test
- `docs/` — audit, compliance report, migration prompt, this runbook, plus a correction to `VIDEO_INTERVIEW.md`

Commit on a dedicated branch so it can be reviewed and reverted independently:

```bash
git checkout -b fix/storage-hardening
git add talbotiq-platform/server/store/db.ts talbotiq-platform/server/index.ts \
        talbotiq-platform/src/store/useAppStore.ts \
        talbotiq-platform/server/store/db.atomicsave.test.ts \
        talbotiq-platform/docs/
git commit   # describe: atomic db.json writes + persistence health + drop dead client keys
```

---

## Step 1 — Confirm the Render service (10 min)

`render.yaml` is correct. What's unconfirmed is whether the **live service** was created from it.

1. Render dashboard → `talbotiq-api` → **Environment** → confirm `DATA_DIR = /var/data` is present.
2. → **Disks** → confirm a disk named `talbotiq-data` is mounted at `/var/data`.

**If either is missing**, the service was hand-provisioned and your data *is* being lost on deploy. Fix: add the env var and the disk, then redeploy. (Adding a disk requires a paid instance type — the free tier has no disks.)

3. Take a backup regardless — a disk is not a backup:

```bash
# Render dashboard → talbotiq-api → Shell
cat /var/data/db.json > /tmp/db-backup.json
# then download it, or from your machine:
#   render ssh talbotiq-api 'cat /var/data/db.json' > db-backup-$(date +%F).json
```

Schedule this. Weekly minimum, daily once you have real candidates.

---

## Step 2 — Rotate every provider key (45 min) ⚠️ highest priority

Assume all are compromised: they've been in plaintext in `db.json`, and the Tavus key has been in browsers.

Do these in order per provider — **create new → update Render → verify → revoke old** — so you never have a window with no working key.

| Provider | Where | Notes |
|---|---|---|
| **Tavus** | tavus.io → API Keys | Also clear it from the recruiter Settings UI, which writes it into `db.json` |
| **Google Gemini** | AI Studio → API Keys | Or move to Vertex AI + service account (see `USE_VERTEX` in `.env.example`) |
| **Deepgram** | console.deepgram.com → API Keys | |
| **Hume** | platform.hume.ai → API Keys | Only if you keep the emotion feature — see Step 5 |
| **AWS** | IAM → the Rekognition user → Access keys | Rotate, and scope the policy to `rekognition:DetectFaces` only |
| **Daily** | dashboard.daily.co → Developers | |
| **Brevo** | Brevo → SMTP & API | Two separate credentials: SMTP key *and* REST API key |
| **Firebase Admin** | Console → Service accounts | Generate new private key, revoke old |

After rotating, have every user **clear their browser storage** (or bump the zustand store name) so stale Tavus keys don't linger in `localStorage`.

---

## Step 3 — Storage lifecycle rule (20 min)

Recordings in `interviews/**` currently live forever.

> ⚠️ **Do not apply a blanket rule to the whole bucket.** `invite_email_logos/` lives in the same bucket, and those images are loaded by **emails already sitting in candidates' inboxes**. Deleting them silently breaks every invite email you've ever sent. The prefix filter below is not optional.

Create `lifecycle.json`:

```json
{
  "rule": [
    {
      "action": { "type": "Delete" },
      "condition": { "age": 30, "matchesPrefix": ["interviews/"] }
    }
  ]
}
```

Apply it:

```bash
gcloud storage buckets update gs://talbotiq-9cc4e.firebasestorage.app \
  --lifecycle-file=lifecycle.json

# verify
gcloud storage buckets describe gs://talbotiq-9cc4e.firebasestorage.app \
  --format="default(lifecycle)"
```

`age: 30` is the placeholder from the decisions table — **replace it with whatever your candidate privacy notice actually promises.** If the notice says nothing, that's the real gap to fix first.

Also check your Firestore region while you're here (it's immutable, and everything else must match it):

```bash
gcloud firestore databases describe --database='(default)' \
  --format="value(locationId)"
```

---

## Step 4 — Alert on failing disk writes (20 min)

The code now reports this; nothing is listening.

`GET /api/health` returns:

```json
{ "ok": true, "persistence": { "ok": true, "consecutiveFailures": 0,
  "lastError": null, "lastSavedAt": "2026-08-12T..." } }
```

Set up **any** uptime monitor (Better Stack, Pingdom, UptimeRobot, GCP Monitoring) to poll `/api/health` and alert when `persistence.ok` is `false` or `consecutiveFailures > 0`.

Note the top-level `ok` stays `true` deliberately — it's Render's health check, and failing it would restart the service on a full disk, which fixes nothing and causes an outage. **Alert on the nested field, not the status code.**

---

## Step 5 — The legal gate (schedule this week, it blocks Phase 3/4)

Take [`EU_AI_ACT_COMPLIANCE.md`](./EU_AI_ACT_COMPLIANCE.md) to a privacy lawyer. The one question that decides engineering scope:

> Does AI Act Art 5(1)(f) prohibit our facial-expression and vocal-prosody emotion scoring of job candidates? If so, does that apply to UK-only deployments?

Three outcomes, three very different plans:

- **Prohibited & you serve EU/UK** → delete both features. Removes work from Phases 3 and 4.
- **Prohibited but you serve neither** → keep, behind a hard default-deny region gate.
- **Not prohibited** (contrary to the Commission's stated reading) → get that in writing, then proceed normally.

Until answered: the features stay, flag **OFF**, and Cursor does **not** build infrastructure for them.

---

## Step 6 — Decide the two open technical questions (30 min, with whoever owns architecture)

**6a. Firestore document layout.** Firestore caps documents at 1 MiB. A session holds up to 800 transcript turns + 20 k chars of résumé text + `facialSummary`. Recommended: `transcript` as a subcollection (`sessions/{id}/turns/{n}`), `resumeText` as its own document. **Decide before Cursor writes the repository interface** — changing it later means rewriting the interface.

**6b. Platform.** Render's disk pins you to one instance. Either migrate the API to Cloud Run (recommended, after Phase 3) or stay on Render and drop the disk once Firestore is the store. Phases 1–3 work either way, so you can defer this — but not past Phase 4.

---

## Step 7 — Set up GCP for the agent (1 hour)

```bash
# Install the SDK, then:
gcloud auth login
gcloud config set project talbotiq-9cc4e

# Enable what the phases need (skip Redis/BigQuery if deferring 4/5)
gcloud services enable secretmanager.googleapis.com firestore.googleapis.com \
  storage.googleapis.com run.googleapis.com cloudtasks.googleapis.com
```

> 🔐 **On giving an agent credentials.** Don't hand a coding agent broad project-owner access. Two safer options:
> - **Preferred:** the agent writes the `gcloud` commands and the code; **you run anything that provisions or spends.** Slower by minutes, and you keep the audit trail.
> - **If you want it automated:** create a dedicated service account with only the roles a phase needs (`roles/secretmanager.admin` for Phase 1, etc.), scoped to this project, and delete the key afterwards. Never reuse the Firebase Admin key for this.

---

## Step 8 — Run the phases with Cursor

Paste [`STORAGE_MIGRATION_PROMPT.md`](./STORAGE_MIGRATION_PROMPT.md) (below the horizontal rule). Two items are already marked ✅ done so it won't redo them.

After **every** phase, before approving the next:

```bash
cd talbotiq-platform
npm test          # must stay at 34+ passing
npm run build     # must typecheck clean
```

Then manually exercise the app: sign in as recruiter → create an invite → take the interview as a candidate → view the report. Automated tests don't cover the end-to-end flow.

**Phase-specific things to verify yourself:**

| Phase | Check this personally |
|---|---|
| 1 Secrets | Recruiter Setup/Replicas pages still work. Open devtools → Application → Local Storage → confirm no `tavusKey`. Confirm the **Flutter app still signs in** after the `recruiter_keys` rule change. |
| 2 Media | A two-way recording still plays on the report page. Old invite emails still show their logo. |
| 3 Firestore | 🔴 **A candidate can still start an avatar interview.** This is the predicted break — per-recruiter settings start empty and `avatarConfigured()` will 503. Verify before cutover, not after. |
| 4 Redis | Run 2 instances and check Gemini spend doesn't double. Take a long voice interview and confirm it survives. |
| 5 BigQuery | Analytics numbers match what the old endpoint returned. |

**Do not let Phase 3 cut over on a Friday.** Dual-write and shadow-read for at least a few days of real traffic first.

---

## Step 9 — After the migration

- Delete the Render disk (or the whole service, if you moved to Cloud Run).
- Remove the JSON-store implementation once Firestore has been authoritative for a couple of weeks — not immediately.
- Keep one final `db.json` backup in cold storage.
- Set Cloud Run min/max instances and load-test.
- Revisit the retention numbers once the privacy notice is written.

---

## Realistic timeline

| | Effort | Calendar |
|---|---|---|
| Steps 0–4 (urgent, console) | ~2 hours | **This week** |
| Step 5 (legal) | your lawyer's time | 1–2 weeks, start now |
| Steps 6–7 (decisions + setup) | ~2 hours | This week |
| Phase 1 (secrets) | 1–2 days dev | Week 2 |
| Phase 2 (media) | 1 day dev | Week 2 |
| Phase 3 (Firestore) | **1–2 weeks dev** + days of dual-write | Weeks 3–5 |
| Phase 4 (Redis) | 3–5 days dev | When you need N>1 |
| Phase 5 (BigQuery) | 2–3 days dev | When analytics hurts |

Phase 3 is the bulk of the work and the only one that's genuinely hard. Everything before it is hours, not weeks.

---

## One thing that is not on any list

Nothing in this runbook writes your **candidate privacy notice**. You process video, voice, facial analysis and résumés through six third-party processors, with no stated retention. Every retention number here is a placeholder precisely because there's no notice to align them to. That document is what makes the rest defensible — and it's cheaper to write now than to retrofit.
