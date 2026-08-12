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
import { createAndSendInterview, sendTerminalEmail, type SendCtx } from '../services/interviewInvite'
import { adminFirestore } from '../services/firebaseAdmin'
import { defaultTemplateFor } from '../../shared/inviteEmail'
import type {
  AuthContext, Pipeline, RoundDef, TrackType, EmailKind,
  PipelineCandidate, PipelineInviteResult, InviteEmailTemplate,
  PipelineBoard, BoardColumn, BoardCard, AdvanceRule, AdvanceResult,
} from '../../shared/types'

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
  if (!role) throw new HttpError(400, 'role is required')
  if (!Array.isArray(b.rounds) || b.rounds.length < 1) throw new HttpError(400, 'at least one round is required')
  const rounds = b.rounds.map((r: unknown, i: number) => normalizeRound(r, i)) // reindexes 0..n
  return { role, type: 'multi', name: typeof b.name === 'string' ? b.name.trim() : undefined, rounds }
}

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

/** Join candidates with their current round's report/session into a board (pure). */
export function buildBoard(
  pipeline: Pipeline,
  candidates: PipelineCandidate[],
  reportOf: (id: string) => { overallScore?: number; notEvaluated?: boolean } | undefined,
  sessionStatusOf: (id: string) => string | undefined,
): PipelineBoard {
  const roundCols: BoardColumn[] = pipeline.rounds.map((r) => ({
    key: `round-${r.index}`, title: r.name, roundIndex: r.index, kind: 'round' as const, cards: [],
  }))
  const selectedCol: BoardColumn = { key: 'selected', title: 'Selected', roundIndex: null, kind: 'selected', cards: [] }
  const notCol: BoardColumn = { key: 'not-advancing', title: 'Not advancing', roundIndex: null, kind: 'not_advancing', cards: [] }

  for (const c of candidates) {
    const prog = c.perRound.find((p) => p.roundIndex === c.currentRoundIndex)
    const interviewId = prog?.interviewId
    const report = interviewId ? reportOf(interviewId) : undefined
    const scored = !!report && typeof report.overallScore === 'number' && report.notEvaluated !== true
    const sessionStatus = interviewId ? sessionStatusOf(interviewId) : undefined
    const roundStatus: BoardCard['roundStatus'] = !interviewId ? 'none'
      : scored || sessionStatus === 'completed' ? 'completed'
      : sessionStatus === 'in_progress' || sessionStatus === 'system_check' ? 'in_progress'
      : sessionStatus === 'expired' ? 'expired'
      : 'invited'
    const card: BoardCard = {
      pipelineCandidateId: c.id, candidateEmail: c.candidateEmail, candidateName: c.candidateName,
      currentRoundIndex: c.currentRoundIndex, status: c.status, roundStatus,
      score: scored ? (report!.overallScore as number) : null,
      advanceable: c.status === 'in_round' && scored,
      history: c.history,
    }
    if (c.status === 'selected') selectedCol.cards.push(card)
    else if (c.status === 'not_advancing') notCol.cards.push(card)
    else {
      const col = roundCols.find((rc) => rc.roundIndex === c.currentRoundIndex) ?? roundCols[0]
      col.cards.push(card)
    }
  }
  return { pipeline, columns: [...roundCols, selectedCol, notCol] }
}

/**
 * Resolve the email template for a given transition kind: inline config wins, else
 * owned id, else a kind-appropriate default. `kind` defaults to 'invite' for
 * backward compatibility, but callers for advance/selected/rejection MUST pass
 * their own kind — defaulting to the invite copy for those sends would be wrong.
 */
function resolveEmailTemplate(auth: AuthContext, body: Record<string, any>, kind: EmailKind = 'invite'): InviteEmailTemplate | null {
  const now = new Date().toISOString()
  const stamp = (seed: Partial<InviteEmailTemplate>): InviteEmailTemplate => ({
    id: 'inline', recruiterId: auth.uid, createdAt: now, updatedAt: now,
    ...(defaultTemplateFor(kind) as any), ...seed,
  })
  if (body.emailConfig) return stamp(body.emailConfig)
  if (typeof body.emailTemplateId === 'string') {
    const t = db.inviteEmailTemplates.get(body.emailTemplateId)
    if (t && (auth.admin || t.recruiterId === auth.uid)) return t
    throw new HttpError(404, 'Email template not found')
  }
  return stamp({})
}

/** Pure: pick candidate ids meeting an AdvanceRule. Null scores are never selected. */
export function selectByCriteria(cards: { pipelineCandidateId: string; score: number | null }[], rule: AdvanceRule): string[] {
  const scored = cards.filter((c) => typeof c.score === 'number') as { pipelineCandidateId: string; score: number }[]
  if (rule.kind === 'threshold') return scored.filter((c) => c.score >= rule.value).map((c) => c.pipelineCandidateId)
  return [...scored].sort((a, b) => b.score - a.score).slice(0, Math.max(0, rule.value)).map((c) => c.pipelineCandidateId)
}

/** Pure: throws HttpError(400) unless the candidate may advance to targetRoundIndex right now. */
export function assertAdvanceable(candidate: { status: string; currentRoundIndex: number }, targetRoundIndex: number, roundCount: number, scored: boolean): void {
  if (candidate.status !== 'in_round') throw new HttpError(400, 'Candidate is not in an active round')
  if (!scored) throw new HttpError(400, 'Candidate has not completed and been scored in the current round')
  if (targetRoundIndex !== candidate.currentRoundIndex + 1) throw new HttpError(400, 'Can only advance to the next round')
  if (targetRoundIndex > roundCount) throw new HttpError(400, 'Target round out of range')
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

pipelinesRouter.get('/:id/board', ah((req, res) => {
  const auth = requireAuth(req)
  const pipeline = loadOwned(req.params.id, auth)
  const candidates = [...db.pipelineCandidates.values()].filter((c) => c.pipelineId === pipeline.id)
  const board = buildBoard(
    pipeline, candidates,
    (id) => db.reports.get(id),
    (id) => db.sessions.get(id)?.status,
  )
  res.json(board)
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

pipelinesRouter.post('/:id/invite', ah(async (req, res) => {
  const auth = requireAuth(req)
  const pipeline = loadOwned(req.params.id, auth)
  const body = (req.body ?? {}) as Record<string, any>
  const candidates: { email: string; role: string }[] = Array.isArray(body.candidates) ? body.candidates : []
  if (candidates.length === 0) throw new HttpError(400, 'no candidates')
  const round0: RoundDef = pipeline.rounds[0]
  const emailTpl = resolveEmailTemplate(auth, body, 'invite')
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

/**
 * Advance one or more candidates: to the next round (creates + sends that round's
 * interview invite), or — when targetRoundIndex is the last round index + 1 — to
 * the terminal 'selected' status (email only, no interviews doc). Each candidate is
 * independently checked for ownership + pipeline membership + eligibility.
 */
pipelinesRouter.post('/:id/advance', ah(async (req, res) => {
  const auth = requireAuth(req)
  const pipeline = loadOwned(req.params.id, auth)
  const body = (req.body ?? {}) as Record<string, any>
  const ids: string[] = Array.isArray(body.candidateIds) ? body.candidateIds : []
  const target = Number(body.targetRoundIndex)
  if (ids.length === 0 || !Number.isInteger(target)) throw new HttpError(400, 'candidateIds and targetRoundIndex required')
  const emailTpl = resolveEmailTemplate(auth, body, target >= pipeline.rounds.length ? 'selected' : 'advance')
  const sendEmails = body.sendEmails !== false
  const origin = typeof body.origin === 'string' ? body.origin : ''
  const basis = typeof body.basis === 'string' ? body.basis : 'manual'
  const nowIso = new Date().toISOString()
  const results: AdvanceResult['results'] = []

  // Each candidate is independent: a failure (ownership/eligibility/send) for one
  // must not discard the mutations + emails + docs already committed for earlier
  // candidates in this batch. So every candidate's work is isolated in its own
  // try/catch — errors become a per-candidate row in `results` instead of an
  // aborted request, and we always persist + respond 200 with whatever we have.
  for (const pcId of ids) {
    let email = ''
    try {
      const c = db.pipelineCandidates.get(pcId)
      if (!c || c.pipelineId !== pipeline.id || (c.recruiterId !== auth.uid && !auth.admin)) throw new HttpError(404, 'Candidate not found')
      email = c.candidateEmail
      const curInterviewId = c.perRound.find((p) => p.roundIndex === c.currentRoundIndex)?.interviewId
      const report = curInterviewId ? db.reports.get(curInterviewId) : undefined
      const scored = !!report && typeof report.overallScore === 'number' && report.notEvaluated !== true
      assertAdvanceable(c, target, pipeline.rounds.length, scored)

      if (target >= pipeline.rounds.length) {
        // Final selection — no new interviews doc, terminal email only.
        c.status = 'selected'; c.updatedAt = nowIso
        c.history.push({ at: nowIso, byUid: auth.uid, action: 'selected', fromRound: c.currentRoundIndex, basis })
        let sent = false, error: string | undefined
        if (sendEmails) {
          const r = await sendTerminalEmail(c.candidateEmail, emailTpl, 'selected', {
            candidate_name: c.candidateEmail.split('@')[0], role: c.role,
            recruiter_name: emailTpl?.sender?.fromName || 'TalbotIQ', company: emailTpl?.branding?.companyName || 'TalbotIQ',
            score: String(report?.overallScore ?? ''),
          })
          sent = r.sent; error = r.error
        }
        c.history[c.history.length - 1].emailResult = sent ? 'accepted' : sendEmails ? 'failed' : 'skipped'
        results.push({ pipelineCandidateId: pcId, email: c.candidateEmail, toRound: 'selected', sent, error })
      } else {
        const round = pipeline.rounds[target]
        const questions = round.source === 'set' && round.questionSetId
          ? (db.questionSets.get(round.questionSetId)?.questions.map((q) => q.text) ?? [])
          : []
        const ctx: SendCtx = {
          testId: randomUUID(), recruiterId: auth.uid, recruiterEmail: auth.email, recruiterName: null, nowIso,
          mode: round.mode, questions, source: round.source, config: round.config, questionSetId: round.questionSetId,
          pipeline: { pipelineId: pipeline.id, roundIndex: target, pipelineCandidateId: pcId },
          origin, fromName: emailTpl?.sender?.fromName || 'TalbotIQ', company: emailTpl?.branding?.companyName || 'TalbotIQ', deadline: emailTpl?.deadlineText || '',
        }
        const row = await createAndSendInterview(
          ctx, { email: c.candidateEmail, role: c.role }, emailTpl, sendEmails,
          { emailKind: 'advance', roundName: round.name, previousRoundName: pipeline.rounds[c.currentRoundIndex]?.name, score: String(report?.overallScore ?? '') },
        )
        c.perRound.push({ roundIndex: target, interviewId: row.id, invitedAt: nowIso })
        c.history.push({ at: nowIso, byUid: auth.uid, action: 'advanced', fromRound: c.currentRoundIndex, toRound: target, basis, emailResult: row.sent ? 'accepted' : sendEmails ? 'failed' : 'skipped' })
        c.currentRoundIndex = target; c.status = 'in_round'; c.updatedAt = nowIso
        results.push({ pipelineCandidateId: pcId, email: c.candidateEmail, toRound: target, sent: row.sent, error: row.error })
      }
      db.pipelineCandidates.set(c.id, c)
    } catch (e) {
      results.push({
        pipelineCandidateId: pcId, email,
        toRound: target >= pipeline.rounds.length ? 'selected' : target,
        error: e instanceof Error ? e.message : String(e),
      })
    }
  }
  db.scheduleSave()
  res.status(200).json({ pipelineId: pipeline.id, results } as AdvanceResult)
}))

/**
 * Mark candidates as not advancing (rejected out of the pipeline). Rejection email
 * is OFF by default — only sent when the caller explicitly opts in via sendRejection.
 */
pipelinesRouter.post('/:id/not-advancing', ah(async (req, res) => {
  const auth = requireAuth(req)
  const pipeline = loadOwned(req.params.id, auth)
  const body = (req.body ?? {}) as Record<string, any>
  const ids: string[] = Array.isArray(body.candidateIds) ? body.candidateIds : []
  if (ids.length === 0) throw new HttpError(400, 'candidateIds required')
  const sendRejection = body.sendRejection === true // OFF by default
  const emailTpl = sendRejection ? resolveEmailTemplate(auth, body, 'rejection') : null
  const nowIso = new Date().toISOString()
  const results: AdvanceResult['results'] = []
  // See /advance: each candidate's mutation + email is isolated in its own
  // try/catch so one candidate's failure can't discard already-committed work
  // (status changes, emails) for earlier candidates in the same batch.
  for (const pcId of ids) {
    let email = ''
    try {
      const c = db.pipelineCandidates.get(pcId)
      if (!c || c.pipelineId !== pipeline.id || (c.recruiterId !== auth.uid && !auth.admin)) throw new HttpError(404, 'Candidate not found')
      email = c.candidateEmail
      c.status = 'not_advancing'; c.updatedAt = nowIso
      let sent = false, error: string | undefined
      if (sendRejection) {
        const r = await sendTerminalEmail(c.candidateEmail, emailTpl, 'rejection', {
          candidate_name: c.candidateEmail.split('@')[0], role: c.role,
          recruiter_name: emailTpl?.sender?.fromName || 'TalbotIQ', company: emailTpl?.branding?.companyName || 'TalbotIQ',
        })
        sent = r.sent; error = r.error
      }
      c.history.push({
        at: nowIso, byUid: auth.uid, action: 'not_advancing', fromRound: c.currentRoundIndex,
        basis: sendRejection ? 'rejection email' : 'no email', emailResult: sendRejection ? (sent ? 'accepted' : 'failed') : 'skipped',
      })
      db.pipelineCandidates.set(c.id, c)
      results.push({ pipelineCandidateId: pcId, email: c.candidateEmail, toRound: 'not_advancing', sent, error })
    } catch (e) {
      results.push({
        pipelineCandidateId: pcId, email, toRound: 'not_advancing',
        error: e instanceof Error ? e.message : String(e),
      })
    }
  }
  db.scheduleSave()
  res.status(200).json({ pipelineId: pipeline.id, results } as AdvanceResult)
}))

/**
 * Undo the most recent advance for one candidate: only while the round they were
 * advanced INTO has not yet been completed (no report). Deletes that round's
 * interviews/{id} doc directly via the Admin SDK — it does NOT touch
 * materializeInviteSession or any session/claim state.
 */
pipelinesRouter.post('/:id/move-back', ah(async (req, res) => {
  const auth = requireAuth(req)
  const pipeline = loadOwned(req.params.id, auth)
  const pcId = (req.body ?? {}).candidateId
  const c = db.pipelineCandidates.get(pcId)
  if (!c || c.pipelineId !== pipeline.id || (c.recruiterId !== auth.uid && !auth.admin)) throw new HttpError(404, 'Candidate not found')
  if (c.currentRoundIndex === 0 || c.status === 'selected' || c.status === 'not_advancing') throw new HttpError(400, 'Nothing to move back')
  const cur = c.perRound.find((p) => p.roundIndex === c.currentRoundIndex)
  // Only allowed while the current (advanced-into) round is not yet completed.
  if (cur && db.reports.get(cur.interviewId)) throw new HttpError(400, 'Current round already completed; cannot move back')
  const nowIso = new Date().toISOString()
  if (cur) {
    await adminFirestore().collection('interviews').doc(cur.interviewId).delete().catch(() => {})
    // Also drop any local session/report the candidate may have materialized by
    // opening the (now-deleted) next-round link, so the dead link can't be resumed
    // and no orphan report lingers for the reverted round.
    db.sessions.delete(cur.interviewId)
    db.reports.delete(cur.interviewId)
  }
  c.perRound = c.perRound.filter((p) => p.roundIndex !== c.currentRoundIndex)
  const from = c.currentRoundIndex
  c.currentRoundIndex = from - 1; c.status = 'in_round'; c.updatedAt = nowIso
  c.history.push({ at: nowIso, byUid: auth.uid, action: 'moved_back', fromRound: from, toRound: from - 1, basis: 'correction' })
  db.pipelineCandidates.set(c.id, c)
  db.scheduleSave()
  res.status(200).json({ ok: true })
}))

export const __test = {
  owns, normalize, loadOwned, ALLOWED_ROUND_MODES, buildPipelineCandidate, buildBoard,
  resolveEmailTemplate, selectByCriteria, assertAdvanceable,
}
