# Storage Migration — Execution Prompt (ready to paste)

Paste everything below the horizontal rule into Cursor. Decisions are filled in; no blanks remain.

**Provenance:** this is your prompt, structure and wording preserved. Three corrections are folded in, each marked `[CORRECTED]` or `[ADDED]` inline, all verified against the code:

| Change | Why |
|---|---|
| `[CORRECTED]` Phase 0 data-loss warning | [`render.yaml`](../../render.yaml) already sets `DATA_DIR=/var/data` with a mounted 1 GB disk. The original wording opens on a false emergency. |
| `[ADDED]` Phase 0.5 — platform | Target is Cloud Run; the app runs on Render, whose disk *pins it to a single instance* by design. Phase 4's scaling work has nowhere to land otherwise. |
| `[ADDED]` Firestore 1 MiB limit in Phase 3 | Sessions carry ≤800 transcript turns + 20 k chars of résumé text + `facialSummary`. Long interviews will not fit one document. |

Baseline: all 33 test files pass as of 12 Aug 2026 (`npm test`).

---

# Cursor Prompt — Migrate TalbotIQ/MIMIC off db.json to a Scalable GCP Architecture

Execute the migration plan in our Data Storage Audit (`docs/DATA_STORAGE_AUDIT.md`, Part 2) — move all state off the single local `db.json` and in-process memory onto managed GCP services, so the API can run as N stateless Cloud Run instances and scale horizontally. Follow the audit's phased order EXACTLY. Do the work in small, reviewable, independently-shippable phases; keep the app running at every step; preserve Firebase field names for Flutter interop (`candidateEmailLower`, `recruiterId`, `resultPublished`, `invite`, `result.detail`). PAUSE for my approval between phases.

Target (from audit §2.1): SPA → Cloud Run (N stateless instances) → Firestore (structured, tenant-keyed) + Cloud Storage (media, lifecycle + signed URLs) + Memorystore/Redis (cache, locks, live state) + Pub/Sub + Cloud Tasks (async jobs) + BigQuery (analytics, cost) + Secret Manager (all keys). Invariant: no critical state on local disk or in one instance's memory.

## My decisions (from audit §2.5) — apply these

1. **Templates/Question Sets backfill owner: (c) seed shared + created owned.**
   ⚠️ There is **no `createdBy` field** on either model, so "created owned" cannot be derived for existing rows. Implement as: rows matching `seedData()` → shared read-only library (`shared: true`); **all other existing rows → the `ADMIN_EMAILS` uid**; recruiters clone what they need. "Created owned" applies only to rows created after the migration.
2. **`db.settings` per-recruiter split: yes, per-recruiter.**
   🔴 **Breakage warning:** `avatarConfigured()` ([`server/services/tavusServer.ts:42-44`](../server/services/tavusServer.ts#L42-L44)) gates candidate avatar interviews on a replica ID **and** a key. Per-recruiter settings start **empty**, so `createCandidateConversation` will 503 for every candidate the moment reads cut over. The migration **must** copy the existing global Tavus key + avatar config onto the recruiter(s) currently relying on it, verified before cutover.
3. **Retention** — recordings: **30 d** · transcripts: **12 mo** · résumé text: **6 mo** · leads: **24 mo** · integrity events: **90 d**.
   🔴 **These are placeholders, not findings.** No regulator-endorsed basis (the GDPR/UK research did not complete). They must also match whatever the existing candidate notice promises. Implement them as **configuration**, not hardcoded constants, so they can change without a code change.
4. **Raw résumé files: keep discarding.** Never persist the PDF/DOCX. Already the behaviour.
5. **Firestore vs Cloud SQL for pipelines: Firestore.** Interop with the existing `interviews` collection outweighs the relational fit.
6. **Emotion features: migrate-behind-flag pending legal.**
   Two mechanics are required: the region gate must be **default-deny, enforced at session creation** (not at render time), and the flag must default **OFF**. A flag does not cure processing already performed — the Art 5(1)(f) prohibition has applied since 2 Feb 2025, so treat the legal answer as time-sensitive, not backlog. See `docs/EU_AI_ACT_COMPLIANCE.md`.

## Ground rules

- Work behind interfaces so call sites and field shapes don't churn: introduce a **repository layer** for every `db.*` access and a **secrets resolver** for keys, then swap implementations underneath.
- Migrate live data safely: **dual-write → shadow-read verify → cut over → decommission**. Never a big-bang switch.
- Frozen modules (sessions / templates / question sets), migrated interview internals, and auth/invite-link logic keep their external shape. Storage underneath changes; behavior does not — unless a decision above says otherwise (then confirm first).
- Everything tenant-keyed by `recruiterId`; fix the tenancy leaks (§1.6) in the same pass as the Firestore move.
- ⚠️ **Emotion features (facialSummary / Hume prosody):** migrate behind the **feature flag + region gate** per decision 6, but do NOT deep-invest. Flag anything that would be wasted work if they're removed.
- `npm test` (33 files) passes today. Keep it passing after every phase.

## PHASE 0 — Stop the bleeding (no app-code changes; do first, report before proceeding)

- `[CORRECTED]` **`DATA_DIR` is already correct — do not raise this as an emergency.** [`render.yaml`](../../render.yaml) sets `DATA_DIR=/var/data` with a 1 GB disk mounted there, and `server/store/db.datadir.test.ts` covers the resolution logic. The only residual check: confirm the live `talbotiq-api` service was created **from the blueprint** rather than hand-provisioned in the dashboard (a hand-made service may lack both).
- Back up `db.json` off-box. **Still required** — a persistent disk is not a backup.
- ✅ **DONE — do not redo.** Save failures are already atomic + observable: [`server/store/db.ts`](../server/store/db.ts) now writes to a temp file and `renameSync`s over the target (so a crash or full disk cannot truncate the snapshot), tracks consecutive failures, and exposes `db.saveHealth()`, which `/api/health` returns as `persistence`. Covered by [`server/store/db.atomicsave.test.ts`](../server/store/db.atomicsave.test.ts). **Remaining work: point an alert at `persistence.ok === false`** (or the `[db] save failed` log line). `/api/health` intentionally still returns 200 — do not change that; it is `render.yaml`'s `healthCheckPath`, and a 503 would make Render restart on a full disk, converting degraded-but-serving into an outage.
- `[ADDED]` Note that [`server/routes/faceCache.ts:26`](../server/routes/faceCache.ts#L26) **ignores `DATA_DIR`** — it writes to the container's ephemeral layer, so the preview cache is wiped every deploy. Retired in Phase 2.
- Add a Firebase **Storage lifecycle rule** on `interviews/**` (30 d per decision 3).
- Confirm Firestore/Storage **region** matches intended data residency. Firestore's location is **immutable** — read the existing one and match it. Note Render runs `oregon` and `AWS_REGION` defaults to `us-east-2`, so facial frames land in Ohio.
- List every provider key to rotate (Tavus, Gemini, Deepgram, Hume, AWS, Daily, SMTP/Brevo) — I'll rotate; assume all current keys compromised.

Report Phase-0 status, then continue.

## `[ADDED]` PHASE 0.5 — Platform decision (blocks Phase 4; plan now, execute after Phase 3)

Render's persistent disk **pins the API to a single instance** — `render.yaml` states this in its own comment (*"a disk pins this service to a single instance — do not scale it out"*). **N>1 is unreachable on the current platform no matter what Phase 4 does.** Phases 1–3 are platform-neutral and ship on Render as-is.

Produce a written **Render → Cloud Run** cutover plan (do not execute): service config, Workload Identity bindings, env→Secret Manager mapping, DNS/CORS, WebSocket support for the voice + Deepgram relays, rollback. Sequence it *after* Phase 3 removes the disk dependency.

## PHASE 1 — Secrets → Secret Manager (audit items 1, 2, 22)

- Add a **secrets resolver** (Secret Manager + Cloud Run workload identity). Route all provider keys through it server-side.
- **Remove the browser-held keys.** ✅ `awsKey` and `anthropicKey` are **already deleted** (fields, setters, and `partialize`) — they had no consumer; confirmed absent from `dist/`. **Do not redo.**
  ⬜ **Remaining:** `tavusKey` is still persisted, because [`src/services/tavus.ts:19`](../src/services/tavus.ts#L19) calls `tavusapi.com` directly from the browser for the recruiter Setup/Replicas pages. Route those through a server proxy **first** (the candidate path already is — see `server/routes/avatar.ts`), then drop it from `partialize` ([`src/store/useAppStore.ts`](../src/store/useAppStore.ts), marked `TODO(phase-1)` in place).
- Move `db.settings.*` keys into Secret Manager. **Per-recruiter keys need one secret per tenant** (`tenant-{uid}-tavus`) — *not* versions of a shared secret; versions are one secret's history, not a keyspace. If tenant count will grow large, prefer **KMS envelope encryption** with ciphertext in Firestore (Secret Manager bills per secret and adds access latency). Pick one, document why.
- **`FIREBASE_PRIVATE_KEY`: delete rather than migrate.** [`server/services/firebaseAdmin.ts:43-45`](../server/services/firebaseAdmin.ts#L43-L45) already falls back to Application Default Credentials, so on Cloud Run with Workload Identity the key is unnecessary. Keep the env path working until Phase 0.5 lands.
- **Tighten `firestore.rules`** so `recruiter_keys` is owner-only. ⚠️ The current rule (`allow read: if isSignedIn()`) is what the **Flutter app** depends on — coordinate before deploying, and never deploy a deny-all ruleset to `talbotiq-9cc4e` (it would break both clients' role reads).
- No data migration here — ship independently.

## PHASE 2 — Media hardening (items 11, 14)

- Add the Storage lifecycle rule (if not done in P0) + **CMEK**. ⚠️ **CMEK is not retroactive** — it applies to new writes only; existing recordings stay under Google-managed keys unless rewritten. Either accept that or plan an explicit rewrite pass, but do not claim retroactive encryption.
- Replace `getDownloadURL()` tokenised links with **server-minted, short-TTL signed URLs** gated by RBAC (so link ≠ access). ⚠️ This changes what `session.recordingUrl` holds — it becomes an **object path**, not a playable URL, and the report page must mint on demand. That is a schema change: **coordinate it with Phase 3** rather than doing it twice.
- Retire the local `face-cache/*.mp4`: serve the Tavus CDN through **Cloud CDN** and delete the local cache path.

## PHASE 3 — Structured data → Firestore (items 3–10, 13) — the scaling unlock

- Introduce a **repository interface** behind every `db.sessions / db.reports / db.templates / db.questionSets / db.pipelines / db.pipelineCandidates / db.inviteEmailTemplates / db.leads / db.settings` call site (same method signatures + field names). Note `db.users` is **read-only and vestigial** ([`server/services/users.ts:41`](../server/services/users.ts#L41)) — drop it rather than migrate.
- `[ADDED]` 🔴 **Firestore's 1 MiB document limit is a hard constraint here.** A session carries up to **800 transcript turns** ([`server/routes/sessions.ts:380`](../server/routes/sessions.ts#L380)), **20 000 chars of `resumeText`** ([`sessions.ts:242`](../server/routes/sessions.ts#L242)), and an opaque `facialSummary`. Long interviews will exceed it. **Decide the document layout before writing the interface** — recommended: `transcript` as a subcollection (`sessions/{id}/turns/{n}`), `resumeText` as its own document. Do not discover this at cutover.
- Target layout: `tenants/{recruiterId}/{sessions|reports|templates|questionSets|pipelines|...}/{id}`; leads → `leads/{id}` (server-only writes + Cloud Armor/rate-limit on the public endpoint at [`server/index.ts:57`](../server/index.ts#L57)).
- **Fix tenancy in the same move:** templates & question sets get owner scoping per decision 1; `db.settings` splits per decision 2 (heed the breakage warning).
- Migrate: dual-write to Firestore + `db.json`, shadow-read and diff to verify parity, then cut reads over, then stop writing `db.json` and decommission it. Reports also **stream to BigQuery** on write (feeds Phase 5).
- ⚠️ **`db.settings` cannot be parity-checked by dual-write** — global→per-recruiter is a *shape* change, not a copy. Use migrate-then-verify for that one model.
- Résumé parsed text moves with sessions (consider field-level encryption for this PII field).

## PHASE 4 — Ephemeral state → Redis + Cloud Tasks (items 15–18) — the gate for N>1

Requires Phase 0.5 executed — the Render disk must be gone or the platform moved, or none of this yields scale.

- **`scoringInFlight` / `pendingQuestionGen` → Redis distributed locks** FIRST ([`server/routes/sessions.ts:112,284`](../server/routes/sessions.ts#L112)). These silently fail across instances → duplicate Gemini spend = real money. Nothing scales safely until this is done.
- Live voice `runtimes` → **Memorystore (Redis)** for turn/session state ([`server/services/voice.ts:202`](../server/services/voice.ts#L202)); keep the WebSocket pinned with session affinity + graceful drain for in-flight calls. ⚠️ Cloud Run session affinity is **best-effort, not guaranteed**, and Cloud Run caps request duration — verify long voice interviews survive both before relying on affinity.
- Prosody `voiceJobs` → **Cloud Tasks/Pub/Sub** + a Firestore job doc (client already polls, so the contract is unchanged; raw audio stays transient — do NOT persist it). *Gated by decision 6 — behind the flag, not deep-invested.*
- Guide TTS cache → Redis (or CDN).
- After this phase, set Cloud Run min/max instances and load-test N>1.

## PHASE 5 — Analytics → BigQuery (items 19–21)

- Replace the per-request full scan of `db.reports` with **BigQuery** + scheduled rollups; repoint `/api/analytics` at rollup tables ([`server/services/analytics.ts:89-174`](../server/services/analytics.ts#L89-L174)).
- Dual-write integrity events to a BigQuery events table, then trim from the session doc.
- ⚠️ **Transcripts/PII in BigQuery duplicate personal data into a second store** with its own retention and access model. Apply the transcript retention decision to the BigQuery copy too, or ship only derived metrics rather than raw text. State which you chose.
- Add **per-tenant, per-modality cost/spend logging** to BigQuery (new capability — critical for profitability at scale).

## Cross-cutting (apply throughout)

- Pin Firestore/Storage/Memorystore to the same region; document each sub-processor + data-residency implication.
- Add cost controls at the server boundary as you centralize AI calls: model tiering (flash for turns, pro for scoring), caching of reusable question-gen, and per-tenant rate-limit/spend caps in Redis.
- Observability: Cloud Logging/Monitoring/Trace + a cost-per-interview dashboard.

## Acceptance criteria

- [ ] Phase 0 verified (`DATA_DIR` confirmed blueprint-provisioned, backups, lifecycle rule, region, save-failure alert); keys listed for rotation.
- [ ] Phase 0.5 Cloud Run cutover plan written and reviewed.
- [ ] All provider keys in Secret Manager, server-only; browser-held Tavus key removed; `awsKey`/`anthropicKey` deleted; `recruiter_keys` rule owner-only **without breaking the Flutter client**.
- [ ] Media: lifecycle + CMEK + short-TTL signed URLs (link ≠ access); local face-cache retired via CDN; report page still plays two-way recordings.
- [ ] All `db.json` data on Firestore, tenant-keyed; document layout respects the 1 MiB limit; tenancy leaks fixed; `db.json` decommissioned; Flutter field names preserved; parity verified; **candidate avatar interviews still start successfully**.
- [ ] Redis locks eliminate duplicate scoring/question-gen; voice state + prosody jobs survive restarts; **app runs correctly on N>1 Cloud Run instances** (load-tested).
- [ ] Analytics on BigQuery rollups (no live-DB scans); per-tenant cost logging live; BigQuery retention configured.
- [ ] Emotion features behind a default-OFF flag + default-deny region gate, not deep-invested, pending legal.
- [ ] `npm test` (33 files) passes after every phase.
- [ ] App runs throughout; each phase shipped independently; no unreviewed big-bang cutover.

Follow the audit's phase order, ship phase by phase, and PAUSE for my review after each. If any step forces a change to frozen-module behavior, auth/invite-link logic, or shared Firestore field names beyond the approved decisions, STOP and ASK.
