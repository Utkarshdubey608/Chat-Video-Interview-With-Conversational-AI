# Multi-Round Pipeline — Plan 4: Advancement + Transition Emails + Safeguards

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let recruiters advance candidates round→round (by drag OR score-threshold/top-N), each advance previewed + confirmed, creating the next round's interview + sending a configurable "advance" email; continue to a Selected list (with CSV export) and an opt-in Not-advancing lane; with undo-before-send, move-back, and an audit log.

**Architecture:** The advancement engine is server-side. The `interviewInvite` service (ours) gains transition-email capability — an `advance` send creates the next round's `interviews/{id}` doc (reusing `buildInterviewDocFields`) and emails via `renderTransitionEmail` + `sanitizeBodyHtml`; `selected`/`rejection` are email-only (no doc). New owner-scoped endpoints (`/advance`, `/not-advancing`, `/move-back`) mutate `PipelineCandidate` state + append `AuditEntry`s. Pure helpers (`selectByCriteria`, `assertAdvanceable`, state transitions) are unit-tested. The board page gains cross-column drag, a per-round quick-advance criteria bar, and a confirm+preview modal (recipients + editable transition-email preview) — nothing sends until the recruiter confirms.

**Tech Stack:** TypeScript, Node/Express, React 18 + Vite, `@dnd-kit`, `@tanstack/react-query`, the repo's `tsx` unit-test convention.

## Global Constraints

- **ADDITIVE ONLY.** No changes to `invites.ts`, sessions, auth, or the email-module files. The `interviewInvite` service and `pipelines.ts` route are OURS and may be extended. Transition emails reuse the `kind` engine (`renderTransitionEmail`, `defaultTemplateFor`, kind-aware templates) built in Plan 1 and `sanitizeBodyHtml` from `inviteEmailRender.ts` (imported, not modified).
- **Frozen modules untouched:** auth/role, the `/take/:id` claim path, Firestore interop field names. A new round doc is an ordinary invite doc (frozen fields) + the additive `pipeline` ref. Move-back **deletes** the created next-round doc via Admin SDK (recruiter owns delete) so its `/take` link 404s — it never modifies `materializeInviteSession`.
- **Ownership:** every endpoint is owner-scoped via `loadOwned` (404 cross-owner). Candidate state changes verify the candidate belongs to the pipeline and is owned.
- **No silent auto-advance:** the server never advances on its own. Per-round `advanceRule` only pre-fills the quick-advance bar; a human clicks Apply → previews → confirms → sends. Every batch send requires an explicit confirm.
- **Advance eligibility:** a candidate is advanceable only if `status === 'in_round'` AND their current round is completed+scored (`db.reports` has numeric `overallScore`, `notEvaluated !== true`). Target round must be exactly `currentRoundIndex + 1`. Advancing from the last round → Selected.
- **Rejection email OFF by default:** the Not-advancing action sends a rejection email only when the recruiter explicitly opts in (`sendRejection === true`).
- **Server-side keys:** all sends go through `sendMail` (Brevo SMTP) server-side.
- **Gates:** `npx tsx <file>.test.ts`; `npm run build`; `npx tsc -p server/tsconfig.json --noEmit`. No browser harness — UI gates on build + diff review + documented manual walkthrough.

## File structure (this plan)

- `server/services/interviewInvite.ts` — MODIFY (ours): add transition-email support to `createAndSendInterview` (optional `emailKind` + transition vars) and a `sendTerminalEmail(...)` for selected/rejection. Add a unit test for the pure vars/kind selection.
- `server/services/interviewInvite.test.ts` — MODIFY: assert transition rendering path selection (pure parts).
- `shared/types.ts` — MODIFY: add `AdvanceRequest`, `NotAdvancingRequest`, `MoveBackRequest`, `AdvanceResult` DTOs.
- `server/routes/pipelines.ts` — MODIFY (ours): add `selectByCriteria`/`assertAdvanceable` pure helpers + `POST /:id/advance`, `POST /:id/not-advancing`, `POST /:id/move-back`. Extend `__test`.
- `server/routes/pipelines.test.ts` — MODIFY: unit-test `selectByCriteria` + `assertAdvanceable` + the state-transition helpers.
- `src/lib/api.ts` — MODIFY: add `pipelinesApi.advance/notAdvancing/moveBack`.
- `src/features/recruiter/TransitionEmailPreview.tsx` — CREATE: kind-aware preview (uses `renderTransitionEmail`).
- `src/features/recruiter/AdvanceModal.tsx` — CREATE: confirm+preview modal (recipients + editable transition-email + send).
- `src/features/recruiter/PipelineBoardPage.tsx` — MODIFY: cross-column drag, per-round quick-advance bar, wire the modal, Selected CSV export, Not-advancing action, audit view.

---

## Task 1: Transition-email capability in the interview-invite service

**Files:**
- Modify: `server/services/interviewInvite.ts`
- Test: `server/services/interviewInvite.test.ts`

**Interfaces:**
- Consumes: `sanitizeBodyHtml` (`inviteEmailRender.ts`), `renderTransitionEmail` (`shared/inviteEmail.ts`).
- Produces:
  - `createAndSendInterview(ctx, c, emailTpl, sendEmails, opts?)` where `opts?: { emailKind?: 'invite' | 'advance'; roundName?: string; previousRoundName?: string; score?: string }` (default `emailKind: 'invite'` → current behavior). For `emailKind: 'advance'`, the email is rendered via `renderTransitionEmail(tpl, 'advance', vars, {interviewLink, candidateEmail})` with `tpl.bodyHtml` sanitized first.
  - `async function sendTerminalEmail(to: string, emailTpl: InviteEmailTemplate | null, kind: 'selected' | 'rejection', vars: { candidate_name: string; role: string; recruiter_name: string; company: string; score?: string }): Promise<{ sent: boolean; error?: string }>` — email only, no Firestore doc.

- [ ] **Step 1: Write failing test assertions in `server/services/interviewInvite.test.ts`**

Since the send path has side effects, test the PURE rendering-selection by extracting a small helper. Add to `interviewInvite.ts` (and import in the test) a pure function:
`export function transitionVars(c, ctx, opts): { candidate_name; role; recruiter_name; company; round_name; previous_round_name; score }`.
Add assertions:
```ts
import { transitionVars } from './interviewInvite'
{
  const v = transitionVars({ email: 'Ada@x.com', role: 'Backend' },
    { fromName: 'Rex', company: 'Acme' } as any,
    { roundName: 'Technical', previousRoundName: 'Screening', score: '72' })
  assert('transition candidate_name from email', v.candidate_name === 'Ada')
  assert('transition round_name', v.round_name === 'Technical')
  assert('transition previous_round_name', v.previous_round_name === 'Screening')
  assert('transition score', v.score === '72')
  assert('transition recruiter/company', v.recruiter_name === 'Rex' && v.company === 'Acme')
}
```

- [ ] **Step 2: Run to verify fail**

Run: `npx tsx server/services/interviewInvite.test.ts`
Expected: FAIL — `transitionVars` not exported.

- [ ] **Step 3: Implement in `server/services/interviewInvite.ts`**

Add imports:
```ts
import { sanitizeBodyHtml } from './inviteEmailRender'
import { renderTransitionEmail } from '../../shared/inviteEmail'
```

Add the pure helper:
```ts
/** Pure: build transition-email merge vars for a candidate. */
export function transitionVars(
  c: { email: string; role: string },
  ctx: { fromName: string; company: string },
  opts: { roundName?: string; previousRoundName?: string; score?: string },
) {
  return {
    candidate_name: c.email.split('@')[0] || 'there',
    role: c.role,
    recruiter_name: ctx.fromName,
    company: ctx.company,
    round_name: opts.roundName ?? '',
    previous_round_name: opts.previousRoundName ?? '',
    score: opts.score ?? '',
  }
}
```

Change `createAndSendInterview` to accept `opts` and branch the render (keep the invite path identical when `emailKind` is absent/'invite'):
```ts
export async function createAndSendInterview(
  ctx: SendCtx,
  c: RoundCandidate,
  emailTpl: InviteEmailTemplate | null,
  sendEmails: boolean,
  opts: { emailKind?: 'invite' | 'advance'; roundName?: string; previousRoundName?: string; score?: string } = {},
): Promise<{ id: string; email: string; link: string; sent?: boolean; status?: InviteSendStatusValue; error?: string }> {
  const col = adminFirestore().collection('interviews')
  const ref = await col.add(buildInterviewDocFields(ctx, c))
  const link = ctx.origin ? `${ctx.origin}/take/${ref.id}` : `/take/${ref.id}`
  const row = { id: ref.id, email: c.email, link } as { id: string; email: string; link: string; sent?: boolean; status?: InviteSendStatusValue; error?: string }
  if (!sendEmails) return row

  const emailKind = opts.emailKind ?? 'invite'
  let subject: string, html: string
  if (emailKind === 'advance' && emailTpl) {
    const vars = transitionVars(c, { fromName: ctx.fromName, company: ctx.company }, opts)
    const safeTpl = { ...emailTpl, bodyHtml: sanitizeBodyHtml(emailTpl.bodyHtml) }
    const rendered = renderTransitionEmail(safeTpl, 'advance', vars, { interviewLink: link, candidateEmail: c.email })
    subject = rendered.subject; html = rendered.html
  } else {
    const vars = { candidate_name: c.email.split('@')[0] || 'there', role: c.role, recruiter_name: ctx.fromName, company: ctx.company, deadline: ctx.deadline }
    if (emailTpl) {
      const rendered = buildInviteEmailHtml(emailTpl, vars, { interviewLink: link, candidateEmail: c.email })
      subject = rendered.subject; html = rendered.html
    } else {
      subject = renderTemplate('Interview invitation — {{role}}', vars)
      html = `<p>Hi,</p><p>You've been invited to an interview for ${vars.role}. Open your interview: <a href="${link}">${link}</a></p><p>Sign in with ${c.email}.</p>`
    }
  }
  // (send + invite-status stamping unchanged from the current implementation)
  const headers = { 'X-Mailin-custom': JSON.stringify({ interviewId: ref.id }) }
  const from = emailTpl?.sender?.verifiedSenderEmail
    ? ((emailTpl.sender.fromName || '').trim() ? `${(emailTpl.sender.fromName || '').trim()} <${emailTpl.sender.verifiedSenderEmail}>` : emailTpl.sender.verifiedSenderEmail)
    : undefined
  const replyTo = emailTpl?.sender?.replyTo || undefined
  try {
    const r = await sendMail({ to: c.email, subject, html, from, replyTo, headers })
    row.sent = r.sent; row.status = r.sent ? 'accepted' : 'failed'
    if (!r.sent) row.error = r.dryRun ? 'Mailer not configured (dry-run)' : 'Not sent'
    await ref.update({ invite: { status: row.status, messageId: r.messageId, sentAt: new Date().toISOString(), attempts: 1, ...(row.error ? { error: row.error } : {}) } as InviteSendStatus }).catch(() => {})
  } catch (err) {
    row.sent = false; row.status = 'failed'; row.error = err instanceof Error ? err.message : String(err)
    await ref.update({ invite: { status: 'failed', attempts: 1, sentAt: new Date().toISOString(), error: row.error } as InviteSendStatus }).catch(() => {})
  }
  return row
}
```
Note: when adapting, DIFF against the current `createAndSendInterview` and keep the invite branch byte-identical to today's behavior — only add the `emailKind === 'advance'` branch and the `opts` param.

Add the terminal-email sender:
```ts
export async function sendTerminalEmail(
  to: string,
  emailTpl: InviteEmailTemplate | null,
  kind: 'selected' | 'rejection',
  vars: { candidate_name: string; role: string; recruiter_name: string; company: string; score?: string },
): Promise<{ sent: boolean; error?: string }> {
  if (!emailTpl) return { sent: false, error: 'No email template' }
  const safeTpl = { ...emailTpl, bodyHtml: sanitizeBodyHtml(emailTpl.bodyHtml) }
  const { subject, html } = renderTransitionEmail(safeTpl, kind, { ...vars, round_name: '', previous_round_name: '' })
  const from = emailTpl.sender?.verifiedSenderEmail
    ? ((emailTpl.sender.fromName || '').trim() ? `${(emailTpl.sender.fromName || '').trim()} <${emailTpl.sender.verifiedSenderEmail}>` : emailTpl.sender.verifiedSenderEmail)
    : undefined
  try {
    const r = await sendMail({ to, subject, html, from, replyTo: emailTpl.sender?.replyTo || undefined })
    return { sent: r.sent, error: r.sent ? undefined : (r.dryRun ? 'Mailer not configured (dry-run)' : 'Not sent') }
  } catch (err) {
    return { sent: false, error: err instanceof Error ? err.message : String(err) }
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `npx tsx server/services/interviewInvite.test.ts` (existing + new transition assertions).
Expected: PASS.

- [ ] **Step 5: Type-check, then commit**

Run: `npx tsc -p server/tsconfig.json --noEmit` (exit 0).
```bash
git add server/services/interviewInvite.ts server/services/interviewInvite.test.ts
git commit -m "feat(pipeline): transition-email (advance/selected/rejection) send in interviewInvite service"
```

---

## Task 2: Advancement endpoints + pure selection/eligibility helpers (`server/routes/pipelines.ts`)

**Files:**
- Modify: `shared/types.ts` (DTOs)
- Modify: `server/routes/pipelines.ts`
- Test: `server/routes/pipelines.test.ts` (extend)

**Interfaces:**
- Produces:
  - DTOs: `AdvanceRequest { candidateIds: string[]; targetRoundIndex: number; emailTemplateId?: string; emailConfig?: Partial<InviteEmailTemplate>; origin?: string; basis?: string; sendEmails?: boolean }`; `NotAdvancingRequest { candidateIds: string[]; sendRejection?: boolean; emailTemplateId?: string; emailConfig?: Partial<InviteEmailTemplate> }`; `MoveBackRequest { candidateId: string }`; `AdvanceResult { pipelineId: string; results: { pipelineCandidateId: string; email: string; toRound: number | 'selected'; sent?: boolean; error?: string }[] }`
  - Pure helpers (in `__test`): `selectByCriteria(cards: { pipelineCandidateId: string; score: number | null }[], rule: AdvanceRule): string[]`; `assertAdvanceable(candidate: PipelineCandidate, targetRoundIndex: number, roundCount: number, scored: boolean): void` (throws `HttpError(400)` when invalid).
  - `POST /:id/advance`, `POST /:id/not-advancing`, `POST /:id/move-back`.

- [ ] **Step 1: Add DTOs to `shared/types.ts`** (per Interfaces above — add the four interfaces near the pipeline block).

- [ ] **Step 2: Add failing test assertions to `server/routes/pipelines.test.ts`**

Add `selectByCriteria, assertAdvanceable` to the `__test` destructure. Add:
```ts
{
  const { selectByCriteria, assertAdvanceable } = __test
  const cards = [
    { pipelineCandidateId: 'a', score: 80 }, { pipelineCandidateId: 'b', score: 55 },
    { pipelineCandidateId: 'c', score: 65 }, { pipelineCandidateId: 'd', score: null },
  ]
  assert('threshold>=60 picks a,c', JSON.stringify(selectByCriteria(cards, { kind: 'threshold', value: 60 }).sort()) === JSON.stringify(['a', 'c']))
  assert('topN=2 picks a,c (highest)', JSON.stringify(selectByCriteria(cards, { kind: 'topN', value: 2 }).sort()) === JSON.stringify(['a', 'c']))
  assert('null score never selected', !selectByCriteria(cards, { kind: 'threshold', value: 0 }).includes('d'))

  const cand = { id: 'x', status: 'in_round', currentRoundIndex: 0 } as any
  assertAdvanceable(cand, 1, 3, true) // ok, no throw
  throws('advance not scored -> 400', () => assertAdvanceable(cand, 1, 3, false), 400)
  throws('advance skip round -> 400', () => assertAdvanceable(cand, 2, 3, true), 400)
  throws('advance when selected -> 400', () => assertAdvanceable({ ...cand, status: 'selected' }, 1, 3, true), 400)
  assertAdvanceable({ ...cand, currentRoundIndex: 2 }, 3, 3, true) // last round -> selected (target === roundCount)
}
```

- [ ] **Step 3: Run to verify fail** → `npx tsx server/routes/pipelines.test.ts` FAILS (`selectByCriteria` undefined).

- [ ] **Step 4: Implement helpers + endpoints in `server/routes/pipelines.ts`**

Add imports:
```ts
import { createAndSendInterview, sendTerminalEmail, transitionVars, type SendCtx } from '../services/interviewInvite'
import type { AdvanceRule, AdvanceResult, InviteEmailTemplate } from '../../shared/types'
```

Pure helpers:
```ts
export function selectByCriteria(cards: { pipelineCandidateId: string; score: number | null }[], rule: AdvanceRule): string[] {
  const scored = cards.filter((c) => typeof c.score === 'number') as { pipelineCandidateId: string; score: number }[]
  if (rule.kind === 'threshold') return scored.filter((c) => c.score >= rule.value).map((c) => c.pipelineCandidateId)
  return [...scored].sort((a, b) => b.score - a.score).slice(0, Math.max(0, rule.value)).map((c) => c.pipelineCandidateId)
}

export function assertAdvanceable(candidate: { status: string; currentRoundIndex: number }, targetRoundIndex: number, roundCount: number, scored: boolean): void {
  if (candidate.status !== 'in_round') throw new HttpError(400, 'Candidate is not in an active round')
  if (!scored) throw new HttpError(400, 'Candidate has not completed and been scored in the current round')
  if (targetRoundIndex !== candidate.currentRoundIndex + 1) throw new HttpError(400, 'Can only advance to the next round')
  if (targetRoundIndex > roundCount) throw new HttpError(400, 'Target round out of range')
}
```

`POST /:id/advance` (handles both "advance to next round" and "advance from last round → Selected"):
```ts
pipelinesRouter.post('/:id/advance', ah(async (req, res) => {
  const auth = requireAuth(req)
  const pipeline = loadOwned(req.params.id, auth)
  const body = (req.body ?? {}) as Record<string, any>
  const ids: string[] = Array.isArray(body.candidateIds) ? body.candidateIds : []
  const target = Number(body.targetRoundIndex)
  if (ids.length === 0 || !Number.isInteger(target)) throw new HttpError(400, 'candidateIds and targetRoundIndex required')
  const emailTpl = resolveEmailTemplate(auth, body) // reused from Plan 2; for advance/selected the caller passes the right kind template via emailConfig
  const sendEmails = body.sendEmails !== false
  const origin = typeof body.origin === 'string' ? body.origin : ''
  const basis = typeof body.basis === 'string' ? body.basis : 'manual'
  const nowIso = new Date().toISOString()
  const results: AdvanceResult['results'] = []

  for (const pcId of ids) {
    const c = db.pipelineCandidates.get(pcId)
    if (!c || c.pipelineId !== pipeline.id || (c.recruiterId !== auth.uid && !auth.admin)) throw new HttpError(404, 'Candidate not found')
    const curInterviewId = c.perRound.find((p) => p.roundIndex === c.currentRoundIndex)?.interviewId
    const report = curInterviewId ? db.reports.get(curInterviewId) : undefined
    const scored = !!report && typeof report.overallScore === 'number' && report.notEvaluated !== true
    assertAdvanceable(c, target, pipeline.rounds.length, scored)

    if (target >= pipeline.rounds.length) {
      // final selection — no new doc
      c.status = 'selected'; c.updatedAt = nowIso
      c.history.push({ at: nowIso, byUid: auth.uid, action: 'selected', fromRound: c.currentRoundIndex, basis })
      let sent = false, error: string | undefined
      if (sendEmails) {
        const r = await sendTerminalEmail(c.candidateEmail, emailTpl, 'selected',
          { candidate_name: c.candidateEmail.split('@')[0], role: c.role, recruiter_name: emailTpl?.sender?.fromName || 'TalbotIQ', company: emailTpl?.branding?.companyName || 'TalbotIQ', score: String(report?.overallScore ?? '') })
        sent = r.sent; error = r.error
      }
      c.history[c.history.length - 1].emailResult = sent ? 'accepted' : sendEmails ? 'failed' : 'skipped'
      results.push({ pipelineCandidateId: pcId, email: c.candidateEmail, toRound: 'selected', sent, error })
    } else {
      const round = pipeline.rounds[target]
      const questions = round.source === 'set' && round.questionSetId ? (db.questionSets.get(round.questionSetId)?.questions.map((q) => q.text) ?? []) : []
      const ctx: SendCtx = {
        testId: randomUUID(), recruiterId: auth.uid, recruiterEmail: auth.email, recruiterName: null, nowIso,
        mode: round.mode, questions, source: round.source, config: round.config, questionSetId: round.questionSetId,
        pipeline: { pipelineId: pipeline.id, roundIndex: target, pipelineCandidateId: pcId },
        origin, fromName: emailTpl?.sender?.fromName || 'TalbotIQ', company: emailTpl?.branding?.companyName || 'TalbotIQ', deadline: emailTpl?.deadlineText || '',
      }
      const row = await createAndSendInterview(ctx, { email: c.candidateEmail, role: c.role }, emailTpl, sendEmails,
        { emailKind: 'advance', roundName: round.name, previousRoundName: pipeline.rounds[c.currentRoundIndex]?.name, score: String(report?.overallScore ?? '') })
      c.perRound.push({ roundIndex: target, interviewId: row.id, invitedAt: nowIso })
      c.history.push({ at: nowIso, byUid: auth.uid, action: 'advanced', fromRound: c.currentRoundIndex, toRound: target, basis, emailResult: row.sent ? 'accepted' : sendEmails ? 'failed' : 'skipped' })
      c.currentRoundIndex = target; c.status = 'in_round'; c.updatedAt = nowIso
      results.push({ pipelineCandidateId: pcId, email: c.candidateEmail, toRound: target, sent: row.sent, error: row.error })
    }
    db.pipelineCandidates.set(c.id, c)
  }
  db.scheduleSave()
  res.status(200).json({ pipelineId: pipeline.id, results } as AdvanceResult)
}))
```

`POST /:id/not-advancing`:
```ts
pipelinesRouter.post('/:id/not-advancing', ah(async (req, res) => {
  const auth = requireAuth(req)
  const pipeline = loadOwned(req.params.id, auth)
  const body = (req.body ?? {}) as Record<string, any>
  const ids: string[] = Array.isArray(body.candidateIds) ? body.candidateIds : []
  if (ids.length === 0) throw new HttpError(400, 'candidateIds required')
  const sendRejection = body.sendRejection === true // OFF by default
  const emailTpl = sendRejection ? resolveEmailTemplate(auth, body) : null
  const nowIso = new Date().toISOString()
  const results: AdvanceResult['results'] = []
  for (const pcId of ids) {
    const c = db.pipelineCandidates.get(pcId)
    if (!c || c.pipelineId !== pipeline.id || (c.recruiterId !== auth.uid && !auth.admin)) throw new HttpError(404, 'Candidate not found')
    c.status = 'not_advancing'; c.updatedAt = nowIso
    let sent = false, error: string | undefined
    if (sendRejection) {
      const r = await sendTerminalEmail(c.candidateEmail, emailTpl, 'rejection',
        { candidate_name: c.candidateEmail.split('@')[0], role: c.role, recruiter_name: emailTpl?.sender?.fromName || 'TalbotIQ', company: emailTpl?.branding?.companyName || 'TalbotIQ' })
      sent = r.sent; error = r.error
    }
    c.history.push({ at: nowIso, byUid: auth.uid, action: 'not_advancing', fromRound: c.currentRoundIndex, basis: sendRejection ? 'rejection email' : 'no email', emailResult: sendRejection ? (sent ? 'accepted' : 'failed') : 'skipped' })
    db.pipelineCandidates.set(c.id, c)
    results.push({ pipelineCandidateId: pcId, email: c.candidateEmail, toRound: 'selected', sent, error }) // toRound unused for rejection
  }
  db.scheduleSave()
  res.status(200).json({ pipelineId: pipeline.id, results } as AdvanceResult)
}))
```

`POST /:id/move-back` (delete the created next-round doc, revert):
```ts
pipelinesRouter.post('/:id/move-back', ah(async (req, res) => {
  const auth = requireAuth(req)
  const pipeline = loadOwned(req.params.id, auth)
  const pcId = (req.body ?? {}).candidateId
  const c = db.pipelineCandidates.get(pcId)
  if (!c || c.pipelineId !== pipeline.id || (c.recruiterId !== auth.uid && !auth.admin)) throw new HttpError(404, 'Candidate not found')
  if (c.currentRoundIndex === 0 || c.status === 'selected' || c.status === 'not_advancing') throw new HttpError(400, 'Nothing to move back')
  const cur = c.perRound.find((p) => p.roundIndex === c.currentRoundIndex)
  // only allowed while the current (advanced-into) round is not completed
  if (cur && db.reports.get(cur.interviewId)) throw new HttpError(400, 'Current round already completed; cannot move back')
  const nowIso = new Date().toISOString()
  if (cur) { await adminFirestore().collection('interviews').doc(cur.interviewId).delete().catch(() => {}) }
  c.perRound = c.perRound.filter((p) => p.roundIndex !== c.currentRoundIndex)
  const from = c.currentRoundIndex
  c.currentRoundIndex = from - 1; c.status = 'in_round'; c.updatedAt = nowIso
  c.history.push({ at: nowIso, byUid: auth.uid, action: 'moved_back', fromRound: from, toRound: from - 1, basis: 'correction' })
  db.pipelineCandidates.set(c.id, c)
  db.scheduleSave()
  res.status(200).json({ ok: true })
}))
```
Add `adminFirestore` import (`import { adminFirestore } from '../services/firebaseAdmin'`). Add `selectByCriteria, assertAdvanceable` to `__test`.

- [ ] **Step 5: Run to verify pass** → `npx tsx server/routes/pipelines.test.ts` PASS (existing + new).

- [ ] **Step 6: Type-check + build, then commit**

Run: `npx tsc -p server/tsconfig.json --noEmit` (exit 0), `npm run build` (exit 0).
```bash
git add shared/types.ts server/routes/pipelines.ts server/routes/pipelines.test.ts
git commit -m "feat(pipeline): advance/not-advancing/move-back endpoints + criteria/eligibility helpers"
```

---

## Task 3: Client advancement API (`src/lib/api.ts`)

**Files:** Modify `src/lib/api.ts`.

**Interfaces:** `pipelinesApi.advance(id, body: AdvanceRequest)`, `notAdvancing(id, body: NotAdvancingRequest)`, `moveBack(id, body: MoveBackRequest)`.

- [ ] **Step 1: Add to `pipelinesApi`** (import the DTOs into the existing `@shared/types` import):
```ts
  advance: (id: string, body: AdvanceRequest) => http<AdvanceResult>(`/pipelines/${id}/advance`, { method: 'POST', body: JSON.stringify(body) }),
  notAdvancing: (id: string, body: NotAdvancingRequest) => http<AdvanceResult>(`/pipelines/${id}/not-advancing`, { method: 'POST', body: JSON.stringify(body) }),
  moveBack: (id: string, body: MoveBackRequest) => http<{ ok: boolean }>(`/pipelines/${id}/move-back`, { method: 'POST', body: JSON.stringify(body) }),
```

- [ ] **Step 2: Build + commit**

Run: `npm run build` (exit 0).
```bash
git add src/lib/api.ts
git commit -m "feat(pipeline): client advance/not-advancing/move-back api"
```

---

## Task 4: Confirm+preview modal + transition-email preview

**Files:**
- Create: `src/features/recruiter/TransitionEmailPreview.tsx`
- Create: `src/features/recruiter/AdvanceModal.tsx`

**Interfaces:**
- `TransitionEmailPreview({ draft, kind, vars, candidateEmail?, origin })` — renders via `renderTransitionEmail` (advance shows a sample link; selected/rejection none). Mirrors `EmailPreview`'s scaled layout.
- `AdvanceModal({ open, onClose, pipelineId, kind, targetRoundIndex, targetRoundName, candidates, onDone })` — loads the recruiter's default template for `kind` (`inviteEmailTemplatesApi.list(kind)`), lets the recruiter edit subject/body (RichTextEditor) + preview, lists recipients, and on confirm calls `pipelinesApi.advance`/`notAdvancing`, showing per-recipient send status.

- [ ] **Step 1: Implement `TransitionEmailPreview.tsx`**

```tsx
import { useMemo } from 'react'
import { renderTransitionEmail } from '@shared/inviteEmail'
import type { InviteEmailTemplate, EmailKind } from '@shared/types'

export function TransitionEmailPreview({ draft, kind, vars, origin }: {
  draft: InviteEmailTemplate
  kind: Exclude<EmailKind, 'invite'>
  vars: { candidate_name: string; role: string; recruiter_name: string; company: string; round_name?: string; score?: string }
  origin?: string
}) {
  const { html } = useMemo(() => renderTransitionEmail(
    draft, kind, vars,
    kind === 'advance' ? { interviewLink: `${origin || 'https://app.talbotiq.com'}/take/sample-next-round`, candidateEmail: `${vars.candidate_name}@example.com` } : {},
  ), [draft, kind, vars, origin])
  return (
    <div className="overflow-hidden rounded-xl border border-border bg-white">
      <div className="max-h-[420px] overflow-auto" dangerouslySetInnerHTML={{ __html: html }} />
    </div>
  )
}
```

- [ ] **Step 2: Implement `AdvanceModal.tsx`**

```tsx
import { useEffect, useMemo, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { Modal, Button, Input, Badge } from '@/components/ui'
import { RichTextEditor } from './invite-email/RichTextEditor'
import { TransitionEmailPreview } from './TransitionEmailPreview'
import { inviteEmailTemplatesApi, pipelinesApi } from '@/lib/api'
import { validateLockedTokens, defaultTemplateFor } from '@shared/inviteEmail'
import type { InviteEmailTemplate, BoardCard } from '@shared/types'

type Kind = 'advance' | 'selected' | 'rejection'

export function AdvanceModal({ open, onClose, pipelineId, kind, targetRoundIndex, targetRoundName, candidates, onDone }: {
  open: boolean; onClose: () => void; pipelineId: string; kind: Kind
  targetRoundIndex: number | null; targetRoundName: string; candidates: BoardCard[]; onDone: () => void
}) {
  const qc = useQueryClient()
  const [draft, setDraft] = useState<InviteEmailTemplate | null>(null)
  const [sending, setSending] = useState(false)
  const [rejectOptIn, setRejectOptIn] = useState(false)

  useEffect(() => {
    if (!open) return
    setDraft(null); setRejectOptIn(false)
    inviteEmailTemplatesApi.list(kind).then((list) => setDraft(list.find((t) => t.isDefault) ?? list[0] ?? ({ ...defaultTemplateFor(kind), id: 'draft', recruiterId: '', createdAt: '', updatedAt: '' } as InviteEmailTemplate)))
  }, [open, kind])

  const locked = useMemo(() => draft ? validateLockedTokens(draft.subject, draft.bodyHtml, kind) : { ok: true, missing: [] }, [draft, kind])
  const sampleVars = { candidate_name: candidates[0]?.candidateEmail.split('@')[0] || 'there', role: '', recruiter_name: draft?.sender.fromName || 'TalbotIQ', company: draft?.branding.companyName || 'TalbotIQ', round_name: targetRoundName, score: candidates[0]?.score != null ? String(candidates[0]?.score) : '' }

  const confirm = async () => {
    if (!draft) return
    if (!locked.ok) { toast.error(`Email missing required link: ${locked.missing.join(', ')}`); return }
    if (kind === 'rejection' && !rejectOptIn) { toast.error('Opt in to send the rejection email, or move without emailing.'); return }
    setSending(true)
    try {
      const emailConfig = { name: draft.name, kind, sender: draft.sender, subject: draft.subject, bodyHtml: draft.bodyHtml, cta: draft.cta, branding: draft.branding }
      const ids = candidates.map((c) => c.pipelineCandidateId)
      if (kind === 'rejection') {
        await pipelinesApi.notAdvancing(pipelineId, { candidateIds: ids, sendRejection: rejectOptIn, emailConfig })
      } else {
        await pipelinesApi.advance(pipelineId, { candidateIds: ids, targetRoundIndex: targetRoundIndex ?? 0, emailConfig, origin: window.location.origin, basis: 'confirm-modal' })
      }
      toast.success(kind === 'selected' ? 'Selected' : kind === 'rejection' ? 'Moved to Not advancing' : `Advanced to ${targetRoundName}`)
      qc.invalidateQueries({ queryKey: ['pipeline-board', pipelineId] })
      onDone(); onClose()
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Failed') }
    finally { setSending(false) }
  }

  const title = kind === 'advance' ? `Advance ${candidates.length} to ${targetRoundName}` : kind === 'selected' ? `Select ${candidates.length}` : `Move ${candidates.length} to Not advancing`
  return (
    <Modal open={open} onClose={onClose} title={title} width="lg">
      {!draft ? <p className="text-sm text-neutral-400">Loading email…</p> : (
        <div className="space-y-4">
          <div>
            <div className="mb-1 text-sm font-semibold">Recipients ({candidates.length})</div>
            <div className="max-h-24 overflow-auto rounded-lg border border-border p-2 text-sm">
              {candidates.map((c) => <div key={c.pipelineCandidateId}>{c.candidateEmail}{c.score != null ? ` · ${c.score}` : ''}</div>)}
            </div>
          </div>
          {kind === 'rejection' && (
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={rejectOptIn} onChange={(e) => setRejectOptIn(e.target.checked)} /> Send a polite rejection email (off by default)</label>
          )}
          {(kind !== 'rejection' || rejectOptIn) && (
            <>
              <Input label="Subject" value={draft.subject} onChange={(e) => setDraft({ ...draft, subject: e.target.value })} />
              <div><div className="mb-1 text-sm font-semibold">Body</div><RichTextEditor value={draft.bodyHtml} onChange={(html) => setDraft({ ...draft, bodyHtml: html })} /></div>
              {!locked.ok && <Badge variant="warning">Missing required link — insert {'{{interview_link}}'}</Badge>}
              <div><div className="mb-1 text-sm font-semibold">Preview</div><TransitionEmailPreview draft={draft} kind={kind} vars={sampleVars} origin={window.location.origin} /></div>
            </>
          )}
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={onClose}>Cancel</Button>
            <Button loading={sending} onClick={confirm}>{kind === 'rejection' && !rejectOptIn ? 'Move without email' : 'Confirm & send'}</Button>
          </div>
        </div>
      )}
    </Modal>
  )
}
```
Note: confirm `Modal` accepts `width="lg"` (or the real width prop values) and `RichTextEditor`'s `{value,onChange}` signature — adapt to the real props. `defaultTemplateFor`/`validateLockedTokens` are from `@shared/inviteEmail`.

- [ ] **Step 3: Build + commit**

Run: `npm run build` (exit 0).
```bash
git add src/features/recruiter/TransitionEmailPreview.tsx src/features/recruiter/AdvanceModal.tsx
git commit -m "feat(pipeline): confirm+preview advance modal + transition-email preview"
```

---

## Task 5: Wire board interactions — drag, quick-advance, modal, CSV, not-advancing, audit

**Files:** Modify `src/features/recruiter/PipelineBoardPage.tsx`.

**Interfaces:** Consumes `AdvanceModal`, `pipelinesApi`, `downloadCsv`, `@dnd-kit`.

- [ ] **Step 1: Add cross-column drag + quick-advance bar + modal wiring**

Extend `PipelineBoardPage` with:
- `@dnd-kit` `DndContext` wrapping the columns; each card `useDraggable({ id: pipelineCandidateId })` (drag only enabled when `card.advanceable`); each column `useDroppable({ id: column.key })`; a `DragOverlay` for the dragged card.
- `onDragEnd(e)`: resolve source card + target column. Valid targets: the next round column (`round-${currentRoundIndex+1}`) → open `AdvanceModal` kind `advance` with that one candidate; the Selected column when the card is in the LAST round → kind `selected`; the Not-advancing column → kind `rejection`. Any other target → ignore (toast "Can only advance to the next round"). Dragging opens the modal — it does NOT mutate directly.
- A **quick-advance bar** on each round column header: a small control (`score ≥ [input]` or `Top [N]`) + Apply. On Apply, compute eligible cards in that column (`advanceable`), run the same selection the server uses (import `selectByCriteria`? it's server-only — replicate the tiny logic client-side, or just filter by threshold/topN inline), and open `AdvanceModal` kind `advance` (target = round+1) with the selected candidates. Pre-fill the input from the round's `advanceRule` if present.
- Modal state: `const [modal, setModal] = useState<{ kind: 'advance'|'selected'|'rejection'; target: number | null; targetName: string; cards: BoardCard[] } | null>(null)`. Render `<AdvanceModal open={!!modal} ... onDone={() => refetch()} />`.

```tsx
// selection helper (client mirror of the server rule)
function pickByCriteria(cards: BoardCard[], mode: 'threshold' | 'topN', value: number): BoardCard[] {
  const scored = cards.filter((c) => c.advanceable && c.score !== null)
  if (mode === 'threshold') return scored.filter((c) => (c.score as number) >= value)
  return [...scored].sort((a, b) => (b.score as number) - (a.score as number)).slice(0, Math.max(0, value))
}
```

- [ ] **Step 2: Add Selected CSV export + Not-advancing + audit view**

- On the **Selected** column header, an "Export CSV" button → `downloadCsv(\`${board.pipeline.role}-selected.csv\`, ['Name','Email','Final score','Rounds'], selectedCards.map(...))`.
- Dragging to **Not-advancing** (or a per-card "Not advancing" action) opens `AdvanceModal` kind `rejection` (rejection email opt-in inside the modal, OFF by default).
- A per-card **move-back** affordance (only shown for cards where `currentRoundIndex > 0` and not completed): calls `pipelinesApi.moveBack(id, { candidateId })` → toast + refetch; a small confirm ("This deletes their next-round link; the email can't be unsent").
- An **audit** disclosure per card (or a pipeline-level "History" panel): render the candidate's `history` entries (`GET` a candidate detail or include history in the board — if the board doesn't include history, add a lightweight `GET /:id/candidate/:pcId` or include `history` on `BoardCard`; simplest: add `history` to `BoardCard` in a tiny board-helper tweak). Keep it read-only.

Note: if surfacing audit history requires more than the current `BoardCard`, add `history: AuditEntry[]` to `BoardCard` and populate it in `buildBoard` (a small additive change to Plan 3's helper + its test) — do that as the first step of this task and note it.

- [ ] **Step 3: Build + manual walkthrough + commit**

Run: `npm run build` (exit 0). Manual (no browser harness — do it in-app): with a candidate completed+scored in Round 1, (a) drag their card to Round 2 → modal previews the advance email → confirm → Round-2 doc + email (dry-run if SMTP off) + card moves; (b) quick-advance by `score ≥ X` selects the right candidates; (c) advancing from the last round moves to Selected + Export CSV downloads; (d) Not-advancing with rejection opt-in OFF just moves the card; (e) move-back on a not-yet-completed advanced card deletes the created doc + reverts; (f) audit shows the entries. Confirm single-interview + Plan 3 read-only paths still work.
```bash
git add src/features/recruiter/PipelineBoardPage.tsx server/routes/pipelines.ts server/routes/pipelines.test.ts shared/types.ts
git commit -m "feat(pipeline): board advancement — drag, quick-advance, confirm modal, CSV, not-advancing, move-back, audit"
```

---

## Self-review notes (author)

- **Spec coverage:** advance by drag AND threshold/top-N (Task 5) with confirm+preview before any send (Task 4); advancing creates the next round's interview + link + `advance` email (Tasks 1-2); final round → Selected + `selected` email + CSV (Tasks 2, 5); opt-in Not-advancing + `rejection` email OFF by default (Tasks 2, 4-5); transition emails configurable/previewable via the `kind` engine (Tasks 1, 4); undo-before-send (modal commits nothing until confirm) + move-back (Task 2, 5) + audit log (`AuditEntry` appended on every transition; surfaced in Task 5); no silent auto-advance (server never advances without an explicit request; `advanceRule` only pre-fills the bar).
- **Additive / guardrails:** `invites.ts`, sessions, auth, and the email-module files are not modified; the `interviewInvite` service + `pipelines.ts` (ours) are extended. Move-back deletes the created doc via Admin SDK — no change to the frozen claim path. Round docs keep frozen fields + the additive `pipeline` ref.
- **Testability:** the pure engine (`selectByCriteria`, `assertAdvanceable`, `transitionVars`, and the buildBoard tweak) is unit-tested; endpoints + UI gate on `tsc`/`build` + the documented manual walkthrough (no HTTP/browser harness, per prior features).
- **Reused server email path:** `resolveEmailTemplate` (Plan 2) is reused; for advance/selected/rejection the client passes an `emailConfig` carrying the right `kind`, and rendering routes through `renderTransitionEmail` + `sanitizeBodyHtml`.
- **Open items / follow-ups:** per-recipient retry on transition-email failure (advance/select return per-recipient status but retry UI is minimal — a fast-follow); the `roundStatus` `none` vs `invited` label refinement carried over from Plan 3; audit surfacing may add `history` to `BoardCard` (noted in Task 5).
