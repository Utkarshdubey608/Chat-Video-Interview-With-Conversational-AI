# Multi-Round Pipeline — Plan 2: Setup Authoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a recruiter choose Single Interview (unchanged default) or Multiple Rounds at setup; for Multiple, build an ordered set of rounds and, on submit, create the pipeline + invite candidates into Round 1 — reusing the existing invite email, without touching the invite route.

**Architecture:** A new additive server service `interviewInvite.ts` builds one `interviews/{id}` doc (frozen fields + `mode`/`role`/`screening` + optional `pipeline` ref) and creates+sends it — the shared home both the pipeline Round-1 flow and (later) the invite route can use. A new `server/routes/pipelines.ts` provides owner-isolated CRUD (mirroring `inviteEmailTemplates.ts`) plus a Round-1 invite action that creates `PipelineCandidate` records. The client gains `pipelinesApi` and, in `InviteWizard`, a Single/Multiple segmented toggle (Step 1) and a round-builder (Step 2). `invites.ts` is NOT modified.

**Tech Stack:** TypeScript, Node/Express, React 18 + Vite, `@dnd-kit` (already used for single-list sorting), the repo's `tsx` unit-test convention.

## Global Constraints

- **ADDITIVE ONLY.** The single-interview path stays byte-for-byte unchanged. `server/routes/invites.ts` and the email module are NOT modified (per the reuse decision: new shared service). `mode`/`role`/`screening` doc fields and the `/take/:id` link shape are reused exactly.
- **Frozen modules untouched:** auth/role, the invite-link `/take/:id` + `materializeInviteSession` claim path, and the Firestore `interviews/{id}` interop field names. Each round doc is an ordinary single-attempt invite doc (`maxAttempts: 1`).
- **Ownership (mirror Sessions/inviteEmailTemplates):** `Pipeline.recruiterId` and `PipelineCandidate.recruiterId` are server-stamped from `auth.uid`, never client-supplied; list is owner-filtered; single-item reads 404 on cross-owner (no existence leak); admins (`auth.admin`) see all.
- **Round modes (v1):** allowed round modes are `chatbot`, `voice`, `video_avatar`, `chat`, `video`. `two_way` is REJECTED by the pipeline validator (deferred).
- **Gates:** `npx tsx <file>.test.ts` (per test), `npm run build` (src+shared), `npx tsc -p server/tsconfig.json --noEmit` (server). `npm run lint` is non-functional — do not rely on it.
- **Brand green** `#0d5c3a`; segmented toggles follow the codebase's hand-rolled `<button>`-grid idiom (no shared SegmentedControl exists).
- Interview link is always `${origin}/take/${docId}` (origin from `body.origin` = `window.location.origin`).

## File structure (this plan)

- `server/services/interviewInvite.ts` — CREATE: `buildInterviewDocFields(ctx, candidate)` (pure) + `createAndSendInterview(ctx, candidate, emailTpl, sendEmails)` (Firestore + email side effects). Replicates the 6-line `typeForMode`/`MODE_LABEL` maps (does not import the route).
- `server/services/interviewInvite.test.ts` — CREATE: unit tests for `buildInterviewDocFields` (pure).
- `shared/types.ts` — MODIFY: add `CreatePipelineRequest`, `PipelineInviteRequest`, `PipelineInviteResult` DTOs.
- `server/routes/pipelines.ts` — CREATE: owner-isolated CRUD + `POST /:id/invite` (Round-1).
- `server/routes/pipelines.test.ts` — CREATE: owner-isolation + rounds-validation unit tests.
- `server/index.ts` — MODIFY: mount `pipelinesRouter`.
- `src/lib/api.ts` — MODIFY: add `pipelinesApi`.
- `src/features/recruiter/InviteWizard.tsx` — MODIFY: Single/Multiple toggle (Step 1), round-builder branch (Step 2), multi-submit.
- `src/features/recruiter/RoundBuilder.tsx` — CREATE: the round-builder UI component.

---

## Task 1: Shared interview-invite service (`server/services/interviewInvite.ts`)

**Files:**
- Create: `server/services/interviewInvite.ts`
- Test: `server/services/interviewInvite.test.ts`

**Interfaces:**
- Consumes: `adminFirestore` from `server/services/firebaseAdmin.ts`; `buildInviteEmailHtml` from `server/services/inviteEmailRender.ts`; `sendMail` from `server/services/email.ts`; `renderTemplate`/`renderTransitionEmail` from `shared/inviteEmail.ts`; types from `shared/types.ts`.
- Produces (Tasks 3 relies on these):
  - `interface InterviewDocCtx { testId: string; recruiterId: string; recruiterEmail: string; recruiterName: string | null; nowIso: string; mode: TrackType; questions: string[]; source?: 'tailor'|'set'; config?: RoundDef['config']; questionSetId?: string; pipeline?: InterviewPipelineRef }`
  - `interface RoundCandidate { email: string; role: string }`
  - `function buildInterviewDocFields(ctx: InterviewDocCtx, c: RoundCandidate): Record<string, unknown>`
  - `interface SendCtx extends InterviewDocCtx { origin: string; fromName: string; company: string; deadline: string }`
  - `async function createAndSendInterview(ctx: SendCtx, c: RoundCandidate, emailTpl: InviteEmailTemplate | null, sendEmails: boolean): Promise<{ id: string; email: string; link: string; sent?: boolean; status?: InviteSendStatusValue; error?: string }>`

- [ ] **Step 1: Write the failing test `server/services/interviewInvite.test.ts`**

```ts
/**
 * Unit tests for the pure interview-doc builder. Run with:
 *   npx tsx server/services/interviewInvite.test.ts
 * Only buildInterviewDocFields is pure/tested here; the create+send path has
 * Firestore/email side effects and is covered by build/tsc + manual walkthrough.
 */
import { buildInterviewDocFields, type InterviewDocCtx } from './interviewInvite'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

const baseCtx: InterviewDocCtx = {
  testId: 'batch-1', recruiterId: 'rec-1', recruiterEmail: 'r@x.com', recruiterName: 'Rex',
  nowIso: '2026-07-22T00:00:00.000Z', mode: 'chatbot', questions: [],
  source: 'tailor',
  config: { style: 'mix', techCount: 3, nonTechCount: 2, difficulty: 'mixed', domains: ['api'], model: 'gemini-2.5-flash' },
}

const d = buildInterviewDocFields(baseCtx, { email: 'Ada@x.com', role: 'Backend Dev' })
assert('frozen recruiterId', d.recruiterId === 'rec-1')
assert('candidateEmail preserved case', d.candidateEmail === 'Ada@x.com')
assert('candidateEmailLower lowercased', d.candidateEmailLower === 'ada@x.com')
assert('type maps chatbot->chat', d.type === 'chat')
assert('title format', d.title === 'Backend Dev — Chatbot interview')
assert('status assigned', d.status === 'assigned')
assert('maxAttempts 1', d.maxAttempts === 1)
assert('resultPublished false', d.resultPublished === false)
assert('mode additive', d.mode === 'chatbot')
assert('role per-candidate', d.role === 'Backend Dev')
assert('screening tailor source', (d.screening as any).source === 'tailor')
assert('screening tailor techCount', (d.screening as any).techCount === 3)
assert('no pipeline ref when absent', d.pipeline === undefined)

// video mode maps to type 'video'
const dv = buildInterviewDocFields({ ...baseCtx, mode: 'video' }, { email: 'b@x.com', role: 'QA' })
assert('type maps video->video', dv.type === 'video')

// pipeline ref included when provided; set source
const dp = buildInterviewDocFields(
  { ...baseCtx, source: 'set', questionSetId: 'qs-9', config: undefined,
    pipeline: { pipelineId: 'pl-1', roundIndex: 2, pipelineCandidateId: 'pc-1' } },
  { email: 'c@x.com', role: 'Backend Dev' },
)
assert('screening set questionSetId', (dp.screening as any).questionSetId === 'qs-9')
assert('screening set has no tailor fields', (dp.screening as any).techCount === undefined)
assert('pipeline ref present', (dp.pipeline as any)?.pipelineId === 'pl-1' && (dp.pipeline as any)?.roundIndex === 2)

console.log(`\n${failures === 0 ? '✅ ALL INTERVIEW-INVITE TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx tsx server/services/interviewInvite.test.ts`
Expected: FAIL — module `./interviewInvite` does not exist / no export `buildInterviewDocFields`.

- [ ] **Step 3: Implement `server/services/interviewInvite.ts`**

```ts
/**
 * Shared interview-invite service — builds one interviews/{id} doc and (optionally)
 * sends its invite/advance email. Additive: this is the reusable home for the
 * per-candidate doc + email logic. server/routes/invites.ts is NOT modified and
 * continues to use its own inline copy; the pipeline Round-1 flow uses THIS.
 *
 * The interviews doc schema mirrors APPLICATION_FLOW.md (frozen Flutter fields) plus
 * the web-only additive fields (mode/role/screening) and, for pipelines, an additive
 * `pipeline` ref. `type` is Flutter's 'video'|'chat' bucket.
 */
import { adminFirestore } from './firebaseAdmin'
import { buildInviteEmailHtml } from './inviteEmailRender'
import { sendMail } from './email'
import { renderTemplate } from '../../shared/inviteEmail'
import type {
  TrackType, RoundDef, InterviewPipelineRef, InviteEmailTemplate,
  InviteSendStatus, InviteSendStatusValue,
} from '../../shared/types'

// Local copies (kept in sync with invites.ts by shape — both derive from TrackType).
// Duplicated intentionally so this service does not import the route module.
const typeForMode = (mode: TrackType): 'video' | 'chat' =>
  mode === 'video_avatar' || mode === 'video' || mode === 'two_way' ? 'video' : 'chat'
const MODE_LABEL: Record<string, string> = {
  chatbot: 'Chatbot', voice: 'Voice', video_avatar: 'Video Avatar',
  chat: 'Timed Q&A', video: 'Video Interview', two_way: 'Two-way Interview',
}

export interface InterviewDocCtx {
  testId: string
  recruiterId: string
  recruiterEmail: string
  recruiterName: string | null
  nowIso: string
  mode: TrackType
  questions: string[]
  source?: 'tailor' | 'set'
  config?: RoundDef['config']
  questionSetId?: string
  pipeline?: InterviewPipelineRef
}
export interface RoundCandidate { email: string; role: string }

/** Pure — the exact interviews/{id} doc object for one candidate (no side effects). */
export function buildInterviewDocFields(ctx: InterviewDocCtx, c: RoundCandidate): Record<string, unknown> {
  return {
    // ── frozen Flutter schema (exact field names) ──
    testId: ctx.testId,
    recruiterId: ctx.recruiterId,
    recruiterEmail: ctx.recruiterEmail,
    recruiterName: ctx.recruiterName ?? null,
    candidateEmail: c.email,
    candidateEmailLower: c.email.toLowerCase(),
    candidateName: null,
    type: typeForMode(ctx.mode),
    title: `${c.role} — ${MODE_LABEL[ctx.mode]} interview`,
    prompt: '',
    questions: ctx.questions,
    durationMinutes: 20,
    status: 'assigned',
    keyOverrides: {},
    maxAttempts: 1,
    attemptsUsed: 0,
    resultPublished: false,
    createdAt: ctx.nowIso,
    updatedAt: ctx.nowIso,
    // ── web-only additive (Flutter ignores unknown keys) ──
    mode: ctx.mode,
    role: c.role,
    screening: {
      ...(ctx.source ? { source: ctx.source } : {}),
      ...(ctx.source === 'tailor' && ctx.config ? {
        style: ctx.config.style,
        techCount: ctx.config.techCount,
        nonTechCount: ctx.config.nonTechCount,
        difficulty: ctx.config.difficulty,
        domains: Array.isArray(ctx.config.domains) ? ctx.config.domains : [],
        model: ctx.config.model,
      } : {}),
      ...(ctx.source === 'set' ? { questionSetId: ctx.questionSetId } : {}),
    },
    // ── pipeline ref (additive; only for multi-round rounds) ──
    ...(ctx.pipeline ? { pipeline: ctx.pipeline } : {}),
  }
}

export interface SendCtx extends InterviewDocCtx {
  origin: string
  fromName: string
  company: string
  deadline: string
}

/** Create the Firestore doc, build the link, render + send the email, stamp invite status. */
export async function createAndSendInterview(
  ctx: SendCtx,
  c: RoundCandidate,
  emailTpl: InviteEmailTemplate | null,
  sendEmails: boolean,
): Promise<{ id: string; email: string; link: string; sent?: boolean; status?: InviteSendStatusValue; error?: string }> {
  const col = adminFirestore().collection('interviews')
  const ref = await col.add(buildInterviewDocFields(ctx, c))
  const link = ctx.origin ? `${ctx.origin}/take/${ref.id}` : `/take/${ref.id}`
  const row: { id: string; email: string; link: string; sent?: boolean; status?: InviteSendStatusValue; error?: string } =
    { id: ref.id, email: c.email, link }

  if (!sendEmails) return row

  // Render: configured template merged per-candidate, else a minimal built-in.
  const vars = {
    candidate_name: c.email.split('@')[0] || 'there',
    role: c.role, recruiter_name: ctx.fromName, company: ctx.company, deadline: ctx.deadline,
  }
  let subject: string, html: string
  if (emailTpl) {
    const rendered = buildInviteEmailHtml(emailTpl, vars, { interviewLink: link, candidateEmail: c.email })
    subject = rendered.subject; html = rendered.html
  } else {
    subject = renderTemplate('Interview invitation — {{role}}', vars)
    html = `<p>Hi,</p><p>You've been invited to an interview for ${vars.role}. Open your interview: <a href="${link}">${link}</a></p><p>Sign in with ${c.email}.</p>`
  }

  const headers = emailTpl ? { 'X-Mailin-custom': JSON.stringify({ interviewId: ref.id }) } : undefined
  const from = emailTpl?.sender?.verifiedSenderEmail
    ? `${emailTpl.sender.fromName} <${emailTpl.sender.verifiedSenderEmail}>` : undefined
  const replyTo = emailTpl?.sender?.replyTo || undefined
  try {
    const r = await sendMail({ to: c.email, subject, html, from, replyTo, headers })
    row.sent = r.sent
    row.status = r.sent ? 'accepted' : 'failed'
    if (!r.sent) row.error = r.dryRun ? 'Mailer not configured (dry-run)' : 'Not sent'
    const invite: InviteSendStatus = {
      status: row.status, messageId: r.messageId, sentAt: new Date().toISOString(),
      attempts: 1, ...(row.error ? { error: row.error } : {}),
    }
    await ref.update({ invite }).catch(() => {})
  } catch (err) {
    row.sent = false; row.status = 'failed'
    row.error = err instanceof Error ? err.message : String(err)
    await ref.update({ invite: { status: 'failed', attempts: 1, sentAt: new Date().toISOString(), error: row.error } as InviteSendStatus }).catch(() => {})
  }
  return row
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx tsx server/services/interviewInvite.test.ts`
Expected: PASS — `✅ ALL INTERVIEW-INVITE TESTS PASSED`.

- [ ] **Step 5: Type-check**

Run: `npx tsc -p server/tsconfig.json --noEmit`
Expected: exit 0.

- [ ] **Step 6: Confirm invites.ts untouched, then commit**

Run: `git diff --name-only` — must NOT list `server/routes/invites.ts`.
```bash
git add server/services/interviewInvite.ts server/services/interviewInvite.test.ts
git commit -m "feat(pipeline): shared interview-invite service (doc builder + send)"
```

---

## Task 2: Pipelines CRUD route (`server/routes/pipelines.ts`)

**Files:**
- Modify: `shared/types.ts` (DTOs)
- Create: `server/routes/pipelines.ts`
- Modify: `server/index.ts` (mount)
- Test: `server/routes/pipelines.test.ts`

**Interfaces:**
- Consumes: `db.pipelines` (Task-1-plan store); `requireAuth`, `ah`, `HttpError`; `randomUUID`.
- Produces:
  - DTOs in `shared/types.ts`: `CreatePipelineRequest { role: string; name?: string; rounds: RoundDef[] }`
  - `pipelinesRouter` mounted at `/api/pipelines`; `__test = { owns, normalize, loadOwned, ALLOWED_ROUND_MODES }`
  - `normalize(body)` returns `Omit<Pipeline,'id'|'recruiterId'|'createdAt'|'updatedAt'>` with validated `rounds` (≥1, reindexed contiguously, disallowed modes rejected via `HttpError(400)`).

- [ ] **Step 1: Add DTOs to `shared/types.ts`**

Add near the pipeline block:

```ts
export interface CreatePipelineRequest {
  role: string
  name?: string
  rounds: RoundDef[]
}
```

- [ ] **Step 2: Write the failing test `server/routes/pipelines.test.ts`**

```ts
/**
 * Pipeline route ownership + rounds-validation. Run with:
 *   npx tsx server/routes/pipelines.test.ts
 * Exercises exported helpers directly (no HTTP harness / Firestore).
 */
import { db } from '../store/db'
import { __test } from './pipelines'
import type { AuthContext, RoundDef } from '../../shared/types'

const { owns, normalize, loadOwned } = __test
let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}
function throws(label: string, fn: () => void, statusWanted?: number) {
  try { fn(); assert(label, false, 'expected throw') }
  catch (e: any) { assert(label, statusWanted ? e?.status === statusWanted : true, `status=${e?.status}`) }
}
const alice: AuthContext = { uid: 'alice', email: 'a@x.com', emailVerified: true, role: 'recruiter', admin: false }
const bob: AuthContext = { uid: 'bob', email: 'b@x.com', emailVerified: true, role: 'recruiter', admin: false }

const goodRounds: RoundDef[] = [
  { index: 0, name: 'Screening', mode: 'chatbot', source: 'tailor',
    config: { style: 'mix', techCount: 3, nonTechCount: 2, difficulty: 'mixed', domains: [], model: 'gemini-2.5-flash' } },
  { index: 1, name: 'Technical', mode: 'video', advanceRule: { kind: 'threshold', value: 60 } },
]

// normalize: valid
const n = normalize({ role: 'Backend', rounds: goodRounds })
assert('type forced multi', n.type === 'multi')
assert('role kept', n.role === 'Backend')
assert('rounds count', n.rounds.length === 2)
assert('advanceRule kept', n.rounds[1].advanceRule?.value === 60)

// normalize: reindex non-contiguous
const nr = normalize({ role: 'R', rounds: [{ index: 5, name: 'A', mode: 'chat' }, { index: 9, name: 'B', mode: 'voice' }] })
assert('reindexed 0..n', nr.rounds[0].index === 0 && nr.rounds[1].index === 1)

// normalize: reject empty rounds
throws('empty rounds -> 400', () => normalize({ role: 'R', rounds: [] }), 400)
// normalize: reject disallowed mode (two_way)
throws('two_way mode -> 400', () => normalize({ role: 'R', rounds: [{ index: 0, name: 'X', mode: 'two_way' }] }), 400)
// normalize: reject round without name
throws('missing name -> 400', () => normalize({ role: 'R', rounds: [{ index: 0, name: '', mode: 'chat' }] }), 400)
// normalize: reject missing role
throws('missing role -> 400', () => normalize({ role: '', rounds: goodRounds }), 400)

// owns / loadOwned
const now = '2026-07-22T00:00:00.000Z'
db.pipelines.set('pl-a', { id: 'pl-a', recruiterId: 'alice', role: 'R', type: 'multi', rounds: goodRounds, createdAt: now, updatedAt: now })
assert('owner owns', owns(db.pipelines.get('pl-a')!, alice))
assert('non-owner does not', !owns(db.pipelines.get('pl-a')!, bob))
assert('loadOwned returns for owner', loadOwned('pl-a', alice).id === 'pl-a')
throws('loadOwned 404 cross-owner', () => loadOwned('pl-a', bob), 404)
throws('loadOwned 404 missing', () => loadOwned('nope', alice), 404)
db.pipelines.delete('pl-a')

console.log(`\n${failures === 0 ? '✅ ALL PIPELINE-ROUTE TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `npx tsx server/routes/pipelines.test.ts`
Expected: FAIL — module `./pipelines` / `__test` does not exist.

- [ ] **Step 4: Implement `server/routes/pipelines.ts`**

```ts
/**
 * Multi-round pipelines — owned per recruiter, mirroring the inviteEmailTemplates
 * isolation pattern (recruiterId server-stamped, owner-filtered list, 404-no-leak).
 * Storage is the in-memory Express/JSON store (server/store/db.ts). Additive: does
 * not touch sessions/invites/auth. Round-1 invites are created via the shared
 * interviewInvite service.
 */
import { Router } from 'express'
import { randomUUID } from 'node:crypto'
import { db } from '../store/db'
import { ah, HttpError } from '../util/ah'
import { requireAuth } from '../middleware/auth'
import type { AuthContext, Pipeline, RoundDef, TrackType } from '../../shared/types'

export const pipelinesRouter = Router()

const ALLOWED_ROUND_MODES: TrackType[] = ['chatbot', 'voice', 'video_avatar', 'chat', 'video']

const owns = (p: Pipeline, auth: AuthContext) => auth.admin || p.recruiterId === auth.uid

function loadOwned(id: string, auth: AuthContext): Pipeline {
  const p = db.pipelines.get(id)
  if (!p || !owns(p, auth)) throw new HttpError(404, 'Pipeline not found')
  return p
}

/** Validate + coerce one round. Throws HttpError(400) on invalid input. */
function normalizeRound(raw: unknown, index: number): RoundDef {
  const r = (raw ?? {}) as Record<string, any>
  const name = typeof r.name === 'string' ? r.name.trim() : ''
  if (!name) throw new HttpError(400, `Round ${index + 1}: name is required`)
  if (!ALLOWED_ROUND_MODES.includes(r.mode)) {
    throw new HttpError(400, `Round ${index + 1}: mode "${r.mode}" is not allowed (two_way deferred)`)
  }
  const round: RoundDef = { index, name, mode: r.mode }
  if (r.source === 'tailor' || r.source === 'set') round.source = r.source
  if (round.source === 'tailor' && r.config) {
    round.config = {
      style: r.config.style, techCount: Number(r.config.techCount) || 0,
      nonTechCount: Number(r.config.nonTechCount) || 0, difficulty: r.config.difficulty,
      domains: Array.isArray(r.config.domains) ? r.config.domains : [], model: r.config.model,
    }
  }
  if (round.source === 'set' && typeof r.questionSetId === 'string') round.questionSetId = r.questionSetId
  if (r.advanceRule && (r.advanceRule.kind === 'threshold' || r.advanceRule.kind === 'topN')) {
    round.advanceRule = { kind: r.advanceRule.kind, value: Number(r.advanceRule.value) || 0 }
  }
  return round
}

function normalize(body: unknown): Omit<Pipeline, 'id' | 'recruiterId' | 'createdAt' | 'updatedAt'> {
  const b = (body ?? {}) as Record<string, any>
  const role = typeof b.role === 'string' ? b.role.trim() : ''
  if (role.length < 2) throw new HttpError(400, 'role is required')
  if (!Array.isArray(b.rounds) || b.rounds.length < 1) throw new HttpError(400, 'at least one round is required')
  const rounds = b.rounds.map((r: unknown, i: number) => normalizeRound(r, i)) // reindexes 0..n
  return { role, type: 'multi', name: typeof b.name === 'string' ? b.name.trim() : undefined, rounds }
}

pipelinesRouter.get('/', ah((req, res) => {
  const auth = requireAuth(req)
  const role = typeof req.query.role === 'string' ? req.query.role : ''
  let mine = [...db.pipelines.values()].filter((p) => owns(p, auth))
  if (role) mine = mine.filter((p) => p.role === role)
  res.json(mine.sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || '')))
}))

pipelinesRouter.get('/:id', ah((req, res) => {
  res.json(loadOwned(req.params.id, requireAuth(req)))
}))

pipelinesRouter.post('/', ah((req, res) => {
  const auth = requireAuth(req)
  const now = new Date().toISOString()
  const p: Pipeline = { id: randomUUID(), recruiterId: auth.uid, createdAt: now, updatedAt: now, ...normalize(req.body) }
  db.pipelines.set(p.id, p)
  db.scheduleSave()
  res.status(201).json(p)
}))

pipelinesRouter.put('/:id', ah((req, res) => {
  const auth = requireAuth(req)
  const existing = loadOwned(req.params.id, auth)
  const updated: Pipeline = { ...existing, ...normalize(req.body), id: existing.id, recruiterId: existing.recruiterId, createdAt: existing.createdAt, updatedAt: new Date().toISOString() }
  db.pipelines.set(updated.id, updated)
  db.scheduleSave()
  res.json(updated)
}))

pipelinesRouter.delete('/:id', ah((req, res) => {
  const auth = requireAuth(req)
  loadOwned(req.params.id, auth)
  db.pipelines.delete(req.params.id)
  db.scheduleSave()
  res.status(204).end()
}))

export const __test = { owns, normalize, loadOwned, ALLOWED_ROUND_MODES }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `npx tsx server/routes/pipelines.test.ts`
Expected: PASS — `✅ ALL PIPELINE-ROUTE TESTS PASSED`.

- [ ] **Step 6: Mount the router in `server/index.ts`**

Add the import alongside the other route imports:
```ts
import { pipelinesRouter } from './routes/pipelines'
```
Add the mount alongside the other recruiter routers (e.g. right after the `inviteEmailTemplates` mount):
```ts
app.use('/api/pipelines', authenticate, requireRecruiter, pipelinesRouter)
```

- [ ] **Step 7: Type-check + build, then commit**

Run: `npx tsc -p server/tsconfig.json --noEmit` (exit 0), then `npm run build` (exit 0).
```bash
git add shared/types.ts server/routes/pipelines.ts server/routes/pipelines.test.ts server/index.ts
git commit -m "feat(pipeline): pipelines CRUD route with owner isolation + rounds validation"
```

---

## Task 3: Round-1 invite action (`POST /api/pipelines/:id/invite`) + PipelineCandidate creation

**Files:**
- Modify: `shared/types.ts` (invite DTOs)
- Modify: `server/routes/pipelines.ts` (add the invite route + a pure candidate-builder helper)
- Test: `server/routes/pipelines.test.ts` (extend)

**Interfaces:**
- Consumes: Task 1's `createAndSendInterview`/`SendCtx`; `db.pipelineCandidates`; `resolveEmailTemplate` (loads the recruiter's invite template or inline config).
- Produces:
  - DTOs: `PipelineInviteRequest { candidates: { email: string; role: string }[]; emailConfig?: Partial<InviteEmailTemplate>; emailTemplateId?: string; origin?: string; sendEmails?: boolean }`; `PipelineInviteResult { pipelineId: string; created: { id: string; email: string; link: string; sent?: boolean; status?: InviteSendStatusValue; error?: string }[]; emailed: number; dryRun: boolean }`
  - `buildPipelineCandidate(pipeline, recruiterId, candidate, interviewId, nowIso): PipelineCandidate` (pure, in `__test`)
  - `POST /api/pipelines/:id/invite`

- [ ] **Step 1: Add DTOs to `shared/types.ts`**

```ts
export interface PipelineInviteRequest {
  candidates: { email: string; role: string }[]
  emailConfig?: Partial<InviteEmailTemplate>
  emailTemplateId?: string
  origin?: string
  sendEmails?: boolean
}
export interface PipelineInviteResult {
  pipelineId: string
  created: { id: string; email: string; link: string; sent?: boolean; status?: InviteSendStatusValue; error?: string }[]
  emailed: number
  dryRun: boolean
}
```

- [ ] **Step 2: Add failing test assertions to `server/routes/pipelines.test.ts`**

Add `buildPipelineCandidate` to the `__test` destructure at the top, and add before the summary block:

```ts
{
  const { buildPipelineCandidate } = __test
  const now = '2026-07-22T00:00:00.000Z'
  const pipe = { id: 'pl-x', recruiterId: 'alice', role: 'Backend', type: 'multi' as const, rounds: goodRounds, createdAt: now, updatedAt: now }
  const pc = buildPipelineCandidate(pipe, 'alice', { email: 'Ada@x.com', role: 'Backend' }, 'iv-1', now)
  assert('pc pipelineId', pc.pipelineId === 'pl-x')
  assert('pc recruiterId owner', pc.recruiterId === 'alice')
  assert('pc emailLower', pc.candidateEmailLower === 'ada@x.com')
  assert('pc starts round 0', pc.currentRoundIndex === 0 && pc.status === 'in_round')
  assert('pc perRound[0] interviewId', pc.perRound[0].interviewId === 'iv-1' && pc.perRound[0].roundIndex === 0)
  assert('pc history invited', pc.history[0].action === 'invited' && pc.history[0].toRound === 0)
}
```

- [ ] **Step 3: Run the test to verify the new assertions fail**

Run: `npx tsx server/routes/pipelines.test.ts`
Expected: FAIL — `buildPipelineCandidate` is undefined.

- [ ] **Step 4: Implement in `server/routes/pipelines.ts`**

Add imports:
```ts
import { createAndSendInterview, type SendCtx } from '../services/interviewInvite'
import { defaultTemplateFor } from '../../shared/inviteEmail'
import type { PipelineCandidate, PipelineInviteResult, InviteEmailTemplate, RoundDef } from '../../shared/types'
```

Add the pure candidate-builder + a template resolver (place above the routes):
```ts
function buildPipelineCandidate(
  pipeline: Pipeline, recruiterId: string,
  c: { email: string; role: string }, interviewId: string, nowIso: string,
): PipelineCandidate {
  return {
    id: randomUUID(), pipelineId: pipeline.id, recruiterId,
    candidateEmail: c.email, candidateEmailLower: c.email.toLowerCase(),
    role: c.role, currentRoundIndex: 0, status: 'in_round',
    perRound: [{ roundIndex: 0, interviewId, invitedAt: nowIso }],
    history: [{ at: nowIso, byUid: recruiterId, action: 'invited', toRound: 0, basis: 'round-1 invite' }],
    createdAt: nowIso, updatedAt: nowIso,
  }
}

/** Resolve the invite-email template for Round 1: inline config wins, else owned id, else default. */
function resolveEmailTemplate(auth: AuthContext, body: Record<string, any>): InviteEmailTemplate | null {
  const now = new Date().toISOString()
  const stamp = (seed: Partial<InviteEmailTemplate>): InviteEmailTemplate => ({
    id: 'inline', recruiterId: auth.uid, createdAt: now, updatedAt: now,
    ...(defaultTemplateFor('invite') as any), ...seed,
  })
  if (body.emailConfig) return stamp(body.emailConfig)
  if (typeof body.emailTemplateId === 'string') {
    const t = db.inviteEmailTemplates.get(body.emailTemplateId)
    if (t && (auth.admin || t.recruiterId === auth.uid)) return t
    throw new HttpError(404, 'Email template not found')
  }
  return stamp({})
}
```

Add the invite route (round questions come from each round's own config; Round 1 = `rounds[0]`):
```ts
pipelinesRouter.post('/:id/invite', ah(async (req, res) => {
  const auth = requireAuth(req)
  const pipeline = loadOwned(req.params.id, auth)
  const body = (req.body ?? {}) as Record<string, any>
  const candidates: { email: string; role: string }[] = Array.isArray(body.candidates) ? body.candidates : []
  if (candidates.length === 0) throw new HttpError(400, 'no candidates')
  const round0: RoundDef = pipeline.rounds[0]
  const emailTpl = resolveEmailTemplate(auth, body)
  const sendEmails = body.sendEmails !== false
  const origin = typeof body.origin === 'string' ? body.origin : ''
  const nowIso = new Date().toISOString()
  const testId = randomUUID()

  // Resolve round-0 questions from a saved set (tailor generates later, per résumé).
  const questions: string[] =
    round0.source === 'set' && round0.questionSetId
      ? (db.questionSets.get(round0.questionSetId)?.questions.map((q) => q.text) ?? [])
      : []

  const created: PipelineInviteResult['created'] = []
  let emailed = 0, dryRun = false
  for (const c of candidates) {
    const pcId = randomUUID()
    const ctx: SendCtx = {
      testId, recruiterId: auth.uid, recruiterEmail: auth.email, recruiterName: null, nowIso,
      mode: round0.mode, questions, source: round0.source, config: round0.config, questionSetId: round0.questionSetId,
      pipeline: { pipelineId: pipeline.id, roundIndex: 0, pipelineCandidateId: pcId },
      origin, fromName: emailTpl?.sender?.fromName || 'TalbotIQ', company: emailTpl?.branding?.companyName || 'TalbotIQ', deadline: emailTpl?.deadlineText || '',
    }
    const row = await createAndSendInterview(ctx, c, emailTpl, sendEmails)
    const pc = { ...buildPipelineCandidate(pipeline, auth.uid, c, row.id, nowIso), id: pcId }
    db.pipelineCandidates.set(pc.id, pc)
    if (row.sent) emailed++
    if (row.status === 'failed' && row.error?.includes('dry-run')) dryRun = true
    created.push(row)
  }
  db.scheduleSave()
  const result: PipelineInviteResult = { pipelineId: pipeline.id, created, emailed, dryRun }
  res.status(201).json(result)
}))
```

Add `buildPipelineCandidate` to the `__test` export:
```ts
export const __test = { owns, normalize, loadOwned, ALLOWED_ROUND_MODES, buildPipelineCandidate }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `npx tsx server/routes/pipelines.test.ts`
Expected: PASS — all assertions incl. the new `buildPipelineCandidate` ones.

- [ ] **Step 6: Type-check + build, then commit**

Run: `npx tsc -p server/tsconfig.json --noEmit` (exit 0), `npm run build` (exit 0).
```bash
git add shared/types.ts server/routes/pipelines.ts server/routes/pipelines.test.ts
git commit -m "feat(pipeline): round-1 invite action creates round docs + pipeline candidates"
```

---

## Task 4: `pipelinesApi` client (`src/lib/api.ts`)

**Files:**
- Modify: `src/lib/api.ts`

**Interfaces:**
- Consumes: the `http<T>` helper; DTOs from `shared/types.ts`.
- Produces: `pipelinesApi` with `list/get/create/update/remove/inviteRound1`.

- [ ] **Step 1: Add `pipelinesApi` (after `inviteEmailTemplatesApi`)**

```ts
import type { Pipeline, CreatePipelineRequest, PipelineInviteRequest, PipelineInviteResult } from '../../shared/types'

export const pipelinesApi = {
  list: (role?: string) => http<Pipeline[]>(`/pipelines${role ? `?role=${encodeURIComponent(role)}` : ''}`),
  get: (id: string) => http<Pipeline>(`/pipelines/${id}`),
  create: (body: CreatePipelineRequest) => http<Pipeline>('/pipelines', { method: 'POST', body: JSON.stringify(body) }),
  update: (id: string, body: CreatePipelineRequest) => http<Pipeline>(`/pipelines/${id}`, { method: 'PUT', body: JSON.stringify(body) }),
  remove: (id: string) => http<void>(`/pipelines/${id}`, { method: 'DELETE' }),
  inviteRound1: (id: string, body: PipelineInviteRequest) =>
    http<PipelineInviteResult>(`/pipelines/${id}/invite`, { method: 'POST', body: JSON.stringify(body) }),
}
```
(Add the type imports to the existing `import type { … } from '../../shared/types'` line rather than duplicating it, if one exists.)

- [ ] **Step 2: Type-check + build, then commit**

Run: `npm run build` (exit 0).
```bash
git add src/lib/api.ts
git commit -m "feat(pipeline): pipelinesApi client"
```

---

## Task 5: Single/Multiple toggle in InviteWizard Step 1

**Files:**
- Modify: `src/features/recruiter/InviteWizard.tsx`

**Interfaces:**
- Consumes: existing wizard state.
- Produces: a `setupType: 'single' | 'multi'` state that Task 6/7 branch on; `step1Valid` updated.

- [ ] **Step 1: Add state (next to the other Step-1 state, ~line 201)**

```ts
const [setupType, setSetupType] = useState<'single' | 'multi'>('single')
```

- [ ] **Step 2: Render a segmented toggle at the top of Step 1's body (just inside the `{!result && step === 1 && (` block, before the mode grid at ~line 424)**

```tsx
<section className="mb-6">
  <SectionTitle title="Interview type" subtitle="One interview, or an ordered set of rounds." />
  <div className="grid grid-cols-2 gap-3 max-w-md">
    {(['single', 'multi'] as const).map((t) => (
      <button
        key={t}
        type="button"
        onClick={() => setSetupType(t)}
        className={cn(
          'rounded-2xl border px-4 py-3 text-left transition',
          setupType === t ? 'border-primary-700 bg-primary-700 text-white' : 'border-border bg-white hover:border-primary-300',
        )}
      >
        <div className="font-semibold">{t === 'single' ? 'Single Interview' : 'Multiple Rounds'}</div>
        <div className={cn('text-sm', setupType === t ? 'text-white/80' : 'text-neutral-500')}>
          {t === 'single' ? 'One interview per candidate (default).' : 'Screening → … → Final, with advancement.'}
        </div>
      </button>
    ))}
  </div>
</section>
```

- [ ] **Step 3: Hide the single-mode grid for multi, and update `step1Valid`**

Wrap the existing mode-card grid (lines ~424–468) so it only renders when `setupType === 'single'`:
```tsx
{setupType === 'single' && (
  /* …existing mode grid… */
)}
```
Change `step1Valid` (line ~334):
```ts
const step1Valid = setupType === 'single'
  ? !!mode && role.trim().length >= 2
  : role.trim().length >= 2 // multi: mode is per-round (chosen in Step 2)
```
Ensure `cn` and `SectionTitle` are imported from `@/components/ui` (add to the existing import if missing).

- [ ] **Step 4: Build + commit**

Run: `npm run build` (exit 0). Manually load `/sessions/new` and confirm the toggle switches, single still shows the mode grid, multi hides it, and Next is enabled for multi once a role is typed.
```bash
git add src/features/recruiter/InviteWizard.tsx
git commit -m "feat(pipeline): Single/Multiple interview-type toggle in setup Step 1"
```

---

## Task 6: Round-builder component (`src/features/recruiter/RoundBuilder.tsx`)

**Files:**
- Create: `src/features/recruiter/RoundBuilder.tsx`

**Interfaces:**
- Consumes: `RoundDef`, `TrackType` types; `@dnd-kit`; UI primitives.
- Produces: `RoundDraft` (a `RoundDef` + client `_id`), `<RoundBuilder rounds onChange />`, and a `toRoundDefs(drafts): RoundDef[]` helper (strips `_id`, reindexes).

- [ ] **Step 1: Implement `src/features/recruiter/RoundBuilder.tsx`**

```tsx
import { useState } from 'react'
import { DndContext, closestCenter, PointerSensor, KeyboardSensor, useSensor, useSensors, type DragEndEvent } from '@dnd-kit/core'
import { SortableContext, useSortable, verticalListSortingStrategy, arrayMove, sortableKeyboardCoordinates } from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { GripVertical, Plus, Trash2 } from 'lucide-react'
import { Button, Card, Input, Select, cn } from '@/components/ui'
import type { RoundDef, TrackType } from '../../../shared/types'

export interface RoundDraft extends Omit<RoundDef, 'index'> { _id: string }

const ROUND_MODES: { value: TrackType; label: string }[] = [
  { value: 'chatbot', label: 'Chatbot' },
  { value: 'voice', label: 'Voice' },
  { value: 'video_avatar', label: 'Video Avatar' },
  { value: 'chat', label: 'Timed Q&A' },
  { value: 'video', label: 'Video Interview' },
]

let seq = 0
const newDraft = (name: string): RoundDraft => ({ _id: `r${Date.now()}-${seq++}`, name, mode: 'chatbot', source: 'tailor' })

export function defaultRounds(): RoundDraft[] {
  return [newDraft('Screening'), newDraft('Technical'), newDraft('Final')]
}

/** Strip client ids, reindex 0..n. */
export function toRoundDefs(drafts: RoundDraft[]): RoundDef[] {
  return drafts.map((d, index) => {
    const { _id, ...rest } = d
    return { ...rest, index }
  })
}

function RoundCard({ d, n, onChange, onRemove, canRemove }: {
  d: RoundDraft; n: number; onChange: (p: Partial<RoundDraft>) => void; onRemove: () => void; canRemove: boolean
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: d._id })
  const style = { transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.6 : 1 }
  return (
    <Card ref={setNodeRef as any} style={style} className="p-4">
      <div className="flex items-start gap-2">
        <button {...attributes} {...listeners} className="mt-1 cursor-grab touch-none rounded p-1 text-neutral-300 hover:text-neutral-500" aria-label="Drag to reorder round">
          <GripVertical size={16} />
        </button>
        <div className="flex-1 space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-xs font-semibold uppercase tracking-wide text-neutral-400">Round {n}</span>
            {canRemove && (
              <button type="button" onClick={onRemove} className="text-neutral-400 hover:text-danger-600" aria-label="Remove round"><Trash2 size={15} /></button>
            )}
          </div>
          <Input label="Round name" value={d.name} onChange={(e) => onChange({ name: e.target.value })} placeholder="e.g. Technical" />
          <Select label="Mode" value={d.mode} options={ROUND_MODES} onChange={(e) => onChange({ mode: e.target.value as TrackType })} />
          <div className="grid grid-cols-2 gap-2">
            <Select label="Advance rule" value={d.advanceRule?.kind ?? ''} options={[{ value: '', label: 'None' }, { value: 'threshold', label: 'Score ≥' }, { value: 'topN', label: 'Top N' }]}
              onChange={(e) => onChange({ advanceRule: e.target.value ? { kind: e.target.value as 'threshold' | 'topN', value: d.advanceRule?.value ?? (e.target.value === 'threshold' ? 60 : 5) } : undefined })} />
            {d.advanceRule && (
              <Input label="Value" type="number" value={d.advanceRule.value}
                onChange={(e) => onChange({ advanceRule: { kind: d.advanceRule!.kind, value: Number(e.target.value) || 0 } })} />
            )}
          </div>
        </div>
      </div>
    </Card>
  )
}

export function RoundBuilder({ rounds, onChange }: { rounds: RoundDraft[]; onChange: (r: RoundDraft[]) => void }) {
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  )
  const onDragEnd = (e: DragEndEvent) => {
    if (!e.over || e.active.id === e.over.id) return
    const from = rounds.findIndex((r) => r._id === e.active.id)
    const to = rounds.findIndex((r) => r._id === e.over!.id)
    onChange(arrayMove(rounds, from, to))
  }
  const update = (id: string, p: Partial<RoundDraft>) => onChange(rounds.map((r) => (r._id === id ? { ...r, ...p } : r)))
  return (
    <div className="space-y-3">
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
        <SortableContext items={rounds.map((r) => r._id)} strategy={verticalListSortingStrategy}>
          <div className="space-y-3">
            {rounds.map((r, i) => (
              <RoundCard key={r._id} d={r} n={i + 1} canRemove={rounds.length > 1}
                onChange={(p) => update(r._id, p)} onRemove={() => onChange(rounds.filter((x) => x._id !== r._id))} />
            ))}
          </div>
        </SortableContext>
      </DndContext>
      <Button variant="outline" size="sm" icon={<Plus size={15} />} onClick={() => onChange([...rounds, newDraft(`Round ${rounds.length + 1}`)])}>
        Add round
      </Button>
    </div>
  )
}
```

Note: `Card` must accept a forwarded `ref` + `style`. If the current `Card` (`src/components/ui/index.tsx`) does not forward refs, use a plain `<div ref={setNodeRef} style={style} className="card p-4">` inside `RoundCard` instead of `<Card ref=…>` — check the `Card` signature first and pick the form that compiles.

- [ ] **Step 2: Build + commit**

Run: `npm run build` (exit 0).
```bash
git add src/features/recruiter/RoundBuilder.tsx
git commit -m "feat(pipeline): round-builder component (reorderable rounds + per-round mode/rule)"
```

---

## Task 7: Multi-round Step 2 + submit wiring

**Files:**
- Modify: `src/features/recruiter/InviteWizard.tsx`

**Interfaces:**
- Consumes: `pipelinesApi` (Task 4), `RoundBuilder`/`defaultRounds`/`toRoundDefs` (Task 6), `setupType` (Task 5).
- Produces: the multi-round authoring + submit path; single path unchanged.

- [ ] **Step 1: Add rounds state + imports**

```ts
import { RoundBuilder, defaultRounds, toRoundDefs, type RoundDraft } from './RoundBuilder'
import { pipelinesApi } from '@/lib/api'
```
```ts
const [rounds, setRounds] = useState<RoundDraft[]>(defaultRounds())
```

- [ ] **Step 2: Branch Step 2 body on `setupType`**

At the top of the `{!result && step === 2 && (` block, render the round-builder for multi and keep the existing single UI otherwise:
```tsx
{setupType === 'multi' ? (
  <section>
    <SectionTitle title="Rounds" subtitle="Order candidates advance through. Each round has its own mode." />
    <RoundBuilder rounds={rounds} onChange={setRounds} />
    <div className="mt-6 flex justify-between">
      <Button variant="ghost" onClick={() => setStep(1)}>Back</Button>
      <Button disabled={!step2ValidMulti} onClick={() => setStep(3)}>Next</Button>
    </div>
  </section>
) : (
  /* …existing single-mode Step 2 body (source picker + panels + its own footer)… */
)}
```

- [ ] **Step 3: Add the multi validation gate (next to `step2Valid`, ~line 340)**

```ts
const step2ValidMulti = rounds.length >= 1 && rounds.every((r) => r.name.trim().length >= 1 && !!r.mode)
```

- [ ] **Step 4: Branch `submit()` for multi**

Replace the single-path call in `submit()` with a branch (keep the single path exactly as-is):
```ts
if (setupType === 'multi') {
  const pipeline = await pipelinesApi.create({ role: role.trim(), rounds: toRoundDefs(rounds) })
  const res = await pipelinesApi.inviteRound1(pipeline.id, {
    candidates: validCandidates,
    origin: window.location.origin,
    emailConfig: emailConfigPayload(),
    sendEmails: true,
  })
  setResult({
    testId: pipeline.id,
    created: res.created,
    emailed: res.emailed,
    dryRun: res.dryRun,
  } as CreateInvitesResult)
  toast.success(`Pipeline created — invited ${res.created.length} to Round 1`)
  return
}
// …existing single-interview invitesApi.create(...) path unchanged below…
```
(The `PipelineInviteResult.created` rows share the `{ id, email, link, sent?, status?, error? }` shape the success view already renders, so the existing success table works unchanged.)

- [ ] **Step 5: Build + manual walkthrough**

Run: `npm run build` (exit 0). Then manually: `/sessions/new` → Multiple Rounds → type a role → Next → add/rename/reorder rounds → Next → add a candidate email → configure the invite email → Review → send. Confirm: a pipeline is created, a Round-1 `interviews/{id}` doc exists per candidate with `pipeline.roundIndex === 0`, the invite email path runs (dry-run if SMTP unconfigured), and the single-interview path still works end to end.

- [ ] **Step 6: Commit**

```bash
git add src/features/recruiter/InviteWizard.tsx
git commit -m "feat(pipeline): multi-round Step 2 round-builder + submit creates pipeline & invites round 1"
```

---

## Self-review notes (author)

- **Reuse decision honored:** `server/routes/invites.ts` and the email module are not modified. Round-1 uses the new `interviewInvite` service; the small merge-var/sender glue lives in that service (the canonical shared home), not duplicated from the route. A later cleanup can point `invites.ts` at the service.
- **Additive schema:** DTOs (`CreatePipelineRequest`, `PipelineInviteRequest/Result`) added to `shared/types.ts`; pipeline records use the Task-1 store maps; the round doc carries the additive `pipeline` ref.
- **Testability:** pure units (`buildInterviewDocFields`, `normalize`/rounds validation, `buildPipelineCandidate`) are unit-tested via the repo's `tsx` convention; the Firestore/email send loop and the UI are verified by `tsc`/`build` + the manual walkthrough (no HTTP/browser harness exists — consistent with prior features per the ledger).
- **Single path unchanged:** every single-interview branch (`step1Valid`, Step 2 source picker, `submit()` `invitesApi.create`) is preserved; multi is a parallel branch gated on `setupType`.
- **Placeholder scan:** no TBD/TODO; the two "…existing…" markers in Tasks 5 & 7 explicitly mean "leave the current code as-is" and name the exact lines from the code map.
- **Follow-ups (not this plan):** the results progression Kanban, advancement (drag/threshold), transition emails, Selected/CSV, and safeguards are Plan 3. `RoundDef.config` reuses the invite `TailorConfig` inline shape; a richer per-round question editor is out of scope for v1.
