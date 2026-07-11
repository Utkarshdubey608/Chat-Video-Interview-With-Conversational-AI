import { Router } from 'express'
import { randomUUID } from 'node:crypto'
import multer from 'multer'
import { db } from '../store/db'
import { ah, HttpError } from '../util/ah'
import { tick, computePublicState, answerTimeUsed } from '../services/timing'
import { scoreSession } from '../services/scoring'
import { extractResumeText } from '../services/resume'
import { generateQuestions, geminiEnabled } from '../services/gemini'
import {
  beginConversation, submitChatAnswer, computeChatbotState,
  advanceChatbotTiming, skipThinking, currentInterviewerTurn, isTimed,
  primaryQuestionGroups,
} from '../services/conversation'
import type {
  InterviewSession,
  InterviewTemplate,
  SessionQuestion,
  SessionListItem,
  SessionReportView,
} from '../../shared/types'

export const sessionsRouter = Router()

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 8 * 1024 * 1024 } })

/** Generic fallback questions when adaptive generation isn't available (no Gemini key). */
function fallbackQuestions(role: string, count: number): { text: string; category: string; idealAnswerNotes: string }[] {
  const pool = [
    { text: `Tell me about your background and what draws you to this ${role} role.`, category: 'Intro', idealAnswerNotes: 'Relevant narrative tying experience to the role.' },
    { text: 'Walk me through a project you’re most proud of and your specific contribution.', category: 'Experience', idealAnswerNotes: 'Ownership, impact, and concrete detail.' },
    { text: 'Describe a difficult technical or professional problem you solved recently.', category: 'Problem-Solving', idealAnswerNotes: 'STAR; clear approach and measurable result.' },
    { text: 'How do you handle feedback and disagreement with teammates?', category: 'Collaboration', idealAnswerNotes: 'Empathy, openness, constructive resolution.' },
    { text: 'How do you prioritise when everything feels urgent?', category: 'Behavioral', idealAnswerNotes: 'Frameworks, trade-offs, communication.' },
    { text: 'Where do you want to grow over the next couple of years?', category: 'Motivation', idealAnswerNotes: 'Self-awareness and alignment with the role.' },
  ]
  return Array.from({ length: count }, (_, i) => pool[i % pool.length])
}

/** Generate the fixed-slot question list from the résumé (chat track, adaptive source). */
async function generateAdaptiveChatQuestions(session: InterviewSession, template: InterviewTemplate) {
  const count = template.adaptive?.numberOfQuestions ?? template.timing.numberOfQuestions ?? 5
  let generated: { text: string; category?: string; idealAnswerNotes?: string }[]
  try {
    generated = geminiEnabled()
      ? await generateQuestions({ resumeText: session.resumeText ?? '', role: template.role, seniority: template.seniority, count })
      : fallbackQuestions(template.role, count)
  } catch (err) {
    console.error('[adaptive] generation failed, using fallback questions:', err)
    generated = fallbackQuestions(template.role, count)
  }
  session.questions = generated.map((g) => ({
    id: randomUUID(),
    text: g.text,
    category: g.category,
    idealAnswerNotes: g.idealAnswerNotes,
    autoSubmitted: false,
  }))
  session.currentIndex = 0
}

/* ─── helpers ───────────────────────────────────────────────────────────── */

function load(id: string): { session: InterviewSession; template: InterviewTemplate } {
  const session = db.sessions.get(id)
  if (!session) throw new HttpError(404, 'Session not found')
  const template = db.templates.get(session.templateId)
  if (!template) throw new HttpError(404, 'Template for session not found')
  return { session, template }
}

/** tick, persist if changed, and trigger scoring once the session completes. */
function settle(session: InterviewSession, template: InterviewTemplate) {
  const changed = tick(session, template)
  if (changed) db.scheduleSave()
  maybeScore(session, template)
}

const scoringInFlight = new Set<string>()
function maybeScore(session: InterviewSession, template: InterviewTemplate) {
  if (session.status !== 'completed') return
  if (db.reports.has(session.id) || scoringInFlight.has(session.id)) return
  scoringInFlight.add(session.id)
  // Fire-and-forget: the candidate's completion screen never waits on scoring.
  scoreSession(session, template)
    .then((report) => {
      db.reports.set(session.id, report)
      db.scheduleSave()
    })
    .catch((err) => console.error('[scoring] failed for', session.id, err))
    .finally(() => scoringInFlight.delete(session.id))
}

/* ─── candidate lifecycle ───────────────────────────────────────────────── */

// Create a session from a template (recruiter action — produces a /take link).
sessionsRouter.post('/', ah((req, res) => {
  const { templateId, candidate, track } = req.body ?? {}
  const template = db.templates.get(templateId)
  if (!template) throw new HttpError(400, 'Unknown templateId')

  let questions: SessionQuestion[] = []
  if (template.questionSource === 'fixed') {
    const set = template.fixedQuestionSetId
      ? db.questionSets.get(template.fixedQuestionSetId)
      : undefined
    if (!set || set.questions.length === 0)
      throw new HttpError(400, 'Template references an empty or missing question set')
    questions = set.questions.map((q) => ({
      id: randomUUID(),
      text: q.text,
      category: q.category,
      idealAnswerNotes: q.idealAnswerNotes,
      autoSubmitted: false,
    }))
  }

  const now = new Date().toISOString()
  const session: InterviewSession = {
    id: randomUUID(),
    templateId,
    track: track ?? template.track,
    candidate: {
      name: candidate?.name ?? 'Candidate',
      email: candidate?.email ?? '',
    },
    status: 'created',
    questions,
    currentIndex: 0,
    createdAt: now,
    integrityEvents: [],
    tabSwitchCount: 0,
  }
  db.sessions.set(session.id, session)
  db.scheduleSave()
  res.status(201).json({ id: session.id })
}))

// The ONLY view the candidate receives — current question + server time only.
sessionsRouter.get('/:id/state', ah((req, res) => {
  const { session, template } = load(req.params.id)
  settle(session, template)
  res.json(computePublicState(session, template))
}))

// Candidate picks a track on the entry screen.
sessionsRouter.post('/:id/track', ah((req, res) => {
  const { session, template } = load(req.params.id)
  if (session.status !== 'created' && session.status !== 'system_check')
    throw new HttpError(409, 'Track can only be chosen before the interview begins')
  const track = req.body?.track
  if (track !== 'chat' && track !== 'chatbot' && track !== 'video_avatar')
    throw new HttpError(400, 'Invalid track')
  session.track = track
  db.scheduleSave()
  res.json(computePublicState(session, template))
}))

// Candidate reaches the system-check screen.
sessionsRouter.post('/:id/system-check', ah((req, res) => {
  const { session, template } = load(req.params.id)
  if (session.status === 'created') session.status = 'system_check'
  db.scheduleSave()
  res.json(computePublicState(session, template))
}))

// Adaptive track: upload résumé → parse → generate tailored questions (server-side).
sessionsRouter.post('/:id/resume', upload.single('resume'), ah(async (req, res) => {
  const { session, template } = load(req.params.id)
  if (template.questionSource !== 'adaptive')
    throw new HttpError(400, 'This interview does not use résumé-based questions')
  if (session.status === 'in_progress' || session.status === 'completed')
    throw new HttpError(409, 'The interview has already started')
  const file = (req as typeof req & { file?: { buffer: Buffer; mimetype: string; originalname: string } }).file
  if (!file) throw new HttpError(400, 'No résumé file uploaded')

  const text = await extractResumeText(file.buffer, file.mimetype, file.originalname)
  if (text.length < 30) throw new HttpError(400, 'Could not read meaningful text from that file')
  session.resumeText = text.slice(0, 20000)

  // Conversational tracks (by the SESSION's track) generate questions live — just store the résumé.
  if (session.track === 'chatbot' || session.track === 'video_avatar') {
    session.currentIndex = 0
    db.scheduleSave()
    res.json(computePublicState(session, template))
    return
  }

  // Chat track: generate the fixed-slot question list from the résumé now.
  await generateAdaptiveChatQuestions(session, template)
  db.scheduleSave()
  res.json(computePublicState(session, template))
}))

// "I'm ready, begin" — starts question 0's preparation phase.
sessionsRouter.post('/:id/begin', ah(async (req, res) => {
  const { session, template } = load(req.params.id)
  if (session.status === 'in_progress')
    return res.json(computePublicState(session, template))
  if (session.status === 'completed' || session.status === 'expired')
    throw new HttpError(409, 'Interview already finished')

  // Adaptive chat sessions generate their question list from the résumé here if not already done.
  if (session.questions.length === 0 && template.questionSource === 'adaptive' && session.resumeText) {
    await generateAdaptiveChatQuestions(session, template)
  }
  if (session.questions.length === 0)
    throw new HttpError(400, session.resumeText ? 'No questions could be generated' : 'A résumé is required before starting')

  const now = new Date().toISOString()
  session.status = 'in_progress'
  session.startedAt = now
  session.currentIndex = 0
  session.questions[0].prepStartedAt = now
  db.scheduleSave()
  res.json(computePublicState(session, template))
}))

// Skip the preparation phase and start answering now (if allowed).
sessionsRouter.post('/:id/skip-prep', ah((req, res) => {
  const { session, template } = load(req.params.id)
  settle(session, template)
  if (!template.timing.allowSkipPrep) throw new HttpError(403, 'Skipping preparation is disabled')
  const q = session.questions[session.currentIndex]
  if (session.status !== 'in_progress' || !q || !q.prepStartedAt || q.answerStartedAt)
    throw new HttpError(409, 'Not in a preparation phase')
  q.answerStartedAt = new Date().toISOString()
  db.scheduleSave()
  res.json(computePublicState(session, template))
}))

// Auto-save in-progress answer text (resilience across refresh).
sessionsRouter.post('/:id/draft', ah((req, res) => {
  const { session, template } = load(req.params.id)
  settle(session, template)
  const q = session.questions[session.currentIndex]
  if (!q || q.id !== req.body?.questionId)
    return res.status(409).json({ error: 'Stale question — refresh state' })
  q.draft = String(req.body?.draft ?? '')
  db.scheduleSave()
  res.json({ ok: true })
}))

// Submit the current answer → lock → advance.
sessionsRouter.post('/:id/answers', ah((req, res) => {
  const { session, template } = load(req.params.id)
  settle(session, template) // may have already auto-advanced

  const q = session.questions[session.currentIndex]
  if (session.status !== 'in_progress' || !q)
    return res.status(409).json({ error: 'No active question', state: computePublicState(session, template) })
  if (q.id !== req.body?.questionId)
    return res.status(409).json({ error: 'Not the current question', state: computePublicState(session, template) })
  if (!q.answerStartedAt)
    throw new HttpError(400, 'Cannot submit during preparation')

  const elapsed = (Date.now() - Date.parse(q.answerStartedAt)) / 1000
  const beforeDeadline = elapsed < template.timing.answerSeconds
  if (beforeDeadline && !template.timing.allowEarlySubmit)
    throw new HttpError(403, 'Early submission is disabled')

  const now = new Date().toISOString()
  q.answerText =
    typeof req.body?.answerText === 'string' ? req.body.answerText : q.draft ?? ''
  if (req.body?.videoUrl) q.videoUrl = req.body.videoUrl
  q.submittedAt = now
  q.autoSubmitted = false

  // advance
  session.currentIndex += 1
  const next = session.questions[session.currentIndex]
  if (next) next.prepStartedAt = now
  else {
    session.status = 'completed'
    session.completedAt = now
  }
  db.scheduleSave()
  maybeScore(session, template)
  res.json(computePublicState(session, template))
}))

// Log an integrity event (tab switch, blur, blocked paste/copy, fullscreen exit).
sessionsRouter.post('/:id/integrity-event', ah((req, res) => {
  const { session, template } = load(req.params.id)
  if (!template.integrity.logEvents) return res.json({ ok: true, ignored: true })
  const type = String(req.body?.type ?? 'unknown')
  session.integrityEvents.push({ type, at: new Date().toISOString() })
  if (type === 'tab_switch' || type === 'window_blur') session.tabSwitchCount += 1
  db.scheduleSave()
  res.json({
    ok: true,
    tabSwitchWarnings: session.tabSwitchCount,
    maxTabSwitchWarnings: template.integrity.maxTabSwitchWarnings,
  })
}))

// Force-complete (e.g. candidate quits) → finalize + trigger scoring.
sessionsRouter.post('/:id/complete', ah((req, res) => {
  const { session, template } = load(req.params.id)

  if (session.track === 'chatbot' || session.track === 'video_avatar') {
    if (session.status === 'in_progress') {
      const turn = currentInterviewerTurn(session)
      const now = new Date().toISOString()
      if (turn) {
        turn.submittedAt = now
        turn.autoAdvanced = true
        ;(session.transcript ??= []).push({
          id: randomUUID(), role: 'candidate', content: turn.draft ?? '',
          questionIndex: turn.questionIndex, isFollowUp: turn.isFollowUp, createdAt: now,
        })
      }
      session.status = 'completed'
      session.completedAt = now
      db.scheduleSave()
    }
    maybeScore(session, template)
    return res.json(computeChatbotState(session, template))
  }

  settle(session, template)
  if (session.status === 'in_progress') {
    const q = session.questions[session.currentIndex]
    if (q && !q.submittedAt) {
      q.answerText = q.answerText ?? q.draft ?? ''
      q.submittedAt = new Date().toISOString()
      q.autoSubmitted = true
    }
    session.status = 'completed'
    session.completedAt = new Date().toISOString()
    db.scheduleSave()
  }
  maybeScore(session, template)
  res.json(computePublicState(session, template))
}))

/* ─── chatbot (conversational) track ────────────────────────────────────── */

// Start the conversation — generates the first interviewer turn.
sessionsRouter.post('/:id/chat/begin', ah(async (req, res) => {
  const { session, template } = load(req.params.id)
  if (session.track !== 'chatbot' && session.track !== 'video_avatar')
    throw new HttpError(400, 'Not a conversational session')
  if (session.status === 'completed' || session.status === 'expired')
    throw new HttpError(409, 'Interview already finished')
  if (template.questionSource === 'adaptive' && !session.resumeText)
    throw new HttpError(400, 'A résumé is required before starting')
  if (session.status !== 'in_progress') {
    await beginConversation(session, template)
    db.scheduleSave()
  }
  res.json(computeChatbotState(session, template))
}))

// The ONLY conversational view the candidate receives (revealed transcript + timers).
sessionsRouter.get('/:id/chat/state', ah(async (req, res) => {
  const { session, template } = load(req.params.id)
  // Timed backstop: if the answer window expired, auto-submit the saved draft.
  if (advanceChatbotTiming(session, template) === 'answer_expired') {
    const turn = currentInterviewerTurn(session)
    await submitChatAnswer(session, template, turn?.draft ?? '', true)
  }
  db.scheduleSave()
  maybeScore(session, template)
  res.json(computeChatbotState(session, template))
}))

// Submit the candidate's answer to the current turn → produce the next turn.
sessionsRouter.post('/:id/chat/answer', ah(async (req, res) => {
  const { session, template } = load(req.params.id)
  if (session.status !== 'in_progress')
    return res.status(409).json({ error: 'Interview is not in progress', state: computeChatbotState(session, template) })
  const turn = currentInterviewerTurn(session)
  if (!turn)
    return res.status(409).json({ error: 'No question is awaiting an answer', state: computeChatbotState(session, template) })
  if (req.body?.turnId && req.body.turnId !== turn.id)
    return res.status(409).json({ error: 'Stale turn — refresh', state: computeChatbotState(session, template) })

  if (isTimed(template)) {
    const ct = template.conversationTiming!
    if (!turn.answerStartedAt) throw new HttpError(400, 'Still in thinking time')
    const remaining = ct.perQuestionSeconds - (Date.now() - Date.parse(turn.answerStartedAt)) / 1000
    if (remaining > 0 && !ct.allowEarlySubmit) throw new HttpError(403, 'Early submission is disabled')
  }

  await submitChatAnswer(session, template, String(req.body?.answerText ?? turn.draft ?? ''))
  db.scheduleSave()
  maybeScore(session, template)
  res.json(computeChatbotState(session, template))
}))

// Auto-save the in-progress answer (resilience across refresh).
sessionsRouter.post('/:id/chat/draft', ah((req, res) => {
  const { session } = load(req.params.id)
  const turn = currentInterviewerTurn(session)
  if (!turn || (req.body?.turnId && req.body.turnId !== turn.id))
    return res.status(409).json({ error: 'Stale turn — refresh' })
  turn.draft = String(req.body?.draft ?? '')
  db.scheduleSave()
  res.json({ ok: true })
}))

// Timed mode: end thinking early and start answering now.
sessionsRouter.post('/:id/chat/skip-thinking', ah((req, res) => {
  const { session, template } = load(req.params.id)
  if (!skipThinking(session, template)) throw new HttpError(409, 'Cannot skip thinking right now')
  db.scheduleSave()
  res.json(computeChatbotState(session, template))
}))

/* ─── recruiter views ───────────────────────────────────────────────────── */

sessionsRouter.get('/', (_req, res) => {
  const items: SessionListItem[] = [...db.sessions.values()]
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .map((s) => ({
      id: s.id,
      candidate: s.candidate,
      templateId: s.templateId,
      templateName: db.templates.get(s.templateId)?.name ?? '(deleted template)',
      track: s.track,
      status: s.status,
      createdAt: s.createdAt,
      startedAt: s.startedAt,
      completedAt: s.completedAt,
      overallScore: db.reports.get(s.id)?.overallScore,
    }))
  res.json(items)
})

sessionsRouter.get('/:id/report', ah((req, res) => {
  const { session, template } = load(req.params.id)

  // Chatbot: synthesise the per-question view from the transcript (ids `q{index}`
  // matching the scored perQuestion), so the existing report UI renders it.
  const questions =
    session.track === 'chatbot' || session.track === 'video_avatar'
      ? primaryQuestionGroups(session).map((g) => ({
          id: `q${g.index}`,
          text: g.question,
          answerText: g.answer,
          autoSubmitted: g.autoAdvanced,
        }))
      : session.questions.map((q) => ({
          id: q.id,
          text: q.text,
          category: q.category,
          answerText: q.answerText,
          videoUrl: q.videoUrl,
          timeUsedSeconds: answerTimeUsed(q),
          autoSubmitted: q.autoSubmitted,
        }))

  const view: SessionReportView = {
    session: {
      id: session.id,
      candidate: session.candidate,
      templateName: template.name,
      track: session.track,
      status: session.status,
      createdAt: session.createdAt,
      startedAt: session.startedAt,
      completedAt: session.completedAt,
      questions,
      integrityEvents: session.integrityEvents,
      tabSwitchCount: session.tabSwitchCount,
    },
    rubric: template.rubric,
    report: db.reports.get(session.id) ?? null,
  }
  res.json(view)
}))
