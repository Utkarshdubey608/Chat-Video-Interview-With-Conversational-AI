import { Router, type Request } from 'express'
import { randomUUID } from 'node:crypto'
import multer from 'multer'
import { db } from '../store/db'
import { ah, HttpError } from '../util/ah'
import {
  requireRecruiter, requireAuth, ownsSession, assertOwner, assertSessionParticipant,
} from '../middleware/auth'
import { tick, computePublicState, answerTimeUsed } from '../services/timing'
import { scoreSession } from '../services/scoring'
import { computeSpeechMetrics, analyzeSentiment } from '../services/signals'
import { extractResumeText } from '../services/resume'
import { generateQuestions, geminiEnabled } from '../services/gemini'
import { detectFaces } from '../services/rekognition'
import { createCandidateConversation, endCandidateConversation, fetchConversationTranscript } from '../services/tavusServer'
import { materializeInviteSession, syncInviteResult } from '../services/inviteBridge'
import { buildVideoTranscript } from '../services/videoTranscript'
import { ensureRoom, mintToken, deleteRoom } from '../services/dailyServer'
import { transcribeVideoUrl } from '../services/transcription'
import {
  beginConversation, submitChatAnswer, computeChatbotState,
  advanceChatbotTiming, skipThinking, currentInterviewerTurn, turnTiming,
  primaryQuestionGroups, revealTimedTurn,
} from '../services/conversation'
import type { TimeOfDay } from '../../shared/types'
import type {
  InterviewSession,
  InterviewTemplate,
  SessionQuestion,
  SessionListItem,
  SessionReportView,
  CandidateAssignedSession,
  AvatarStartResponse,
  TwoWayJoinResponse,
  Turn,
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
      ? await generateQuestions({
          resumeText: session.resumeText ?? '', role: template.role, seniority: template.seniority, count,
          // Bulk-invite "tailor" parameters (style/counts/difficulty/domains) ride on
          // the template's adaptive config — honor them so the generated set matches
          // exactly what the recruiter configured in the invite wizard.
          style: template.adaptive?.style,
          technicalCount: template.adaptive?.technicalCount,
          nonTechnicalCount: template.adaptive?.nonTechnicalCount,
          difficulty: template.adaptive?.difficulty,
          focusTopics: template.adaptive?.focusTopics,
        })
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

/**
 * Load a session for the authenticated caller, enforcing access as it does so.
 * Access = the assigned candidate (matched on VERIFIED email) OR the owning
 * recruiter. Anyone else — including another recruiter — gets 404, so the
 * response never reveals that a session they can't see exists.
 */
function load(req: Request): { session: InterviewSession; template: InterviewTemplate } {
  const auth = requireAuth(req)
  const session = db.sessions.get(req.params.id)
  if (!session) throw new HttpError(404, 'Session not found')
  assertSessionParticipant(session, auth)
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
  scoreSession(session, template)
    .then((report) => {
      db.reports.set(session.id, report)
      db.scheduleSave()
      syncInviteResult(session, report) // bulk-invite: push score back to Firestore (no-op otherwise)
    })
    .catch((err) => console.error('[scoring] failed for', session.id, err))
    .finally(() => scoringInFlight.delete(session.id))
}

/* ─── candidate lifecycle ───────────────────────────────────────────────── */

// Create a session from a template (recruiter action — produces a /take link).
sessionsRouter.post('/', requireRecruiter, ah((req, res) => {
  const auth = requireAuth(req)
  const { templateId, candidate, track } = req.body ?? {}
  const template = db.templates.get(templateId)
  if (!template) throw new HttpError(400, 'Unknown templateId')

  // The candidate email is how a candidate is later granted access to this
  // session (they must sign in with a matching, verified email), so it's
  // required and stored normalized.
  const candidateEmail = String(candidate?.email ?? '').trim().toLowerCase()
  if (!candidateEmail) throw new HttpError(400, 'A candidate email is required to assign this interview')

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
    recruiterId: auth.uid,      // OWNER — scopes all recruiter reads to this session
    track: track ?? template.track,
    candidate: {
      name: candidate?.name ?? 'Candidate',
      email: candidateEmail,
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

// Bulk-invite bridge: an assigned candidate opening their invite link. Resolves
// the Firestore `interviews/{id}` doc into a local session (id === interview id)
// + a synthesised template, then hands off to the normal candidate flow below.
// Idempotent — re-claiming just returns the current state.
sessionsRouter.post('/:id/claim', ah(async (req, res) => {
  const auth = requireAuth(req)
  const { session, template } = await materializeInviteSession(req.params.id, auth)
  settle(session, template)
  res.json(computePublicState(session, template))
}))

// The ONLY view the candidate receives — current question + server time only.
sessionsRouter.get('/:id/state', ah((req, res) => {
  const { session, template } = load(req)
  settle(session, template)
  res.json(computePublicState(session, template))
}))

// Candidate picks a track on the entry screen.
sessionsRouter.post('/:id/track', ah((req, res) => {
  const { session, template } = load(req)
  if (session.status !== 'created' && session.status !== 'system_check')
    throw new HttpError(409, 'Track can only be chosen before the interview begins')
  const track = req.body?.track
  if (track !== 'chat' && track !== 'chatbot' && track !== 'video_avatar' && track !== 'voice' && track !== 'video' && track !== 'two_way')
    throw new HttpError(400, 'Invalid track')
  session.track = track
  db.scheduleSave()
  res.json(computePublicState(session, template))
}))

// Candidate reaches the system-check screen.
sessionsRouter.post('/:id/system-check', ah((req, res) => {
  const { session, template } = load(req)
  if (session.status === 'created') session.status = 'system_check'
  db.scheduleSave()
  res.json(computePublicState(session, template))
}))

// Adaptive track: upload résumé → parse → generate tailored questions (server-side).
// The candidate's FULL NAME is asked on the same step (before the upload) and rides
// along as a form field — it becomes session.candidate.name so the AI interviewer
// addresses them by name in greetings and questions (conversation + voice engines
// already read candidate.name and ignore the 'Candidate' placeholder).
sessionsRouter.post('/:id/resume', upload.single('resume'), ah(async (req, res) => {
  const { session, template } = load(req)
  // Adaptive interviews need the résumé to GENERATE questions. Video-avatar
  // interviews accept it regardless of question source — it's fed to the Tavus
  // avatar so it knows who it's talking to (fixed questions stay untouched).
  if (template.questionSource !== 'adaptive' && session.track !== 'video_avatar')
    throw new HttpError(400, 'This interview does not use résumé-based questions')
  if (session.status === 'in_progress' || session.status === 'completed')
    throw new HttpError(409, 'The interview has already started')
  const file = (req as typeof req & { file?: { buffer: Buffer; mimetype: string; originalname: string } }).file
  if (!file) throw new HttpError(400, 'No résumé file uploaded')

  const fullName = String((req.body as { fullName?: string } | undefined)?.fullName ?? '').trim()
  if (fullName) session.candidate.name = fullName.slice(0, 80)

  const text = await extractResumeText(file.buffer, file.mimetype, file.originalname)
  if (text.length < 30) throw new HttpError(400, 'Could not read meaningful text from that file')
  session.resumeText = text.slice(0, 20000)

  // Chatbot / video-avatar generate questions turn-by-turn, so just store the résumé.
  if (session.track === 'chatbot' || session.track === 'video_avatar') {
    session.currentIndex = 0
    // Video-avatar + adaptive: the avatar's strict script needs the FULL plan up
    // front, and generating it inside avatar/start makes the candidate pay the
    // whole Gemini round-trip as a cold start on question 1. Kick generation off
    // NOW, in the background, while the candidate walks through system-check /
    // face-framing — avatar/start then merely awaits an already-running promise.
    if (session.track === 'video_avatar' && template.questionSource === 'adaptive' && session.questions.length === 0) {
      const gen = generateAdaptiveChatQuestions(session, template)
        .then(() => db.scheduleSave())
        .catch(() => { /* avatar/start falls back to a synchronous retry */ })
      pendingQuestionGen.set(session.id, gen)
      void gen.finally(() => {
        if (pendingQuestionGen.get(session.id) === gen) pendingQuestionGen.delete(session.id)
      })
    }
    db.scheduleSave()
    res.json(computePublicState(session, template))
    return
  }

  // Chat + voice tracks use an up-front ordered plan — generate it now, while the
  // candidate is on the "processing résumé" step, so the interview starts instantly
  // (no dead air waiting for generation once the voice call connects).
  await generateAdaptiveChatQuestions(session, template)
  db.scheduleSave()
  res.json(computePublicState(session, template))
}))

/* ─── Video Avatar (Tavus) — live avatar conducts the scripted interview ────
 * The conversation is created SERVER-side from the recruiter's applied Setup
 * config (replica/persona/greeting/context) + this session's question plan +
 * the candidate's name. The candidate browser only receives the join URL —
 * never a Tavus key. Utterances stream back via /avatar/transcript and are
 * bucketed per question for the existing conversational scoring. */

/** In-flight adaptive question generation started at résumé upload, keyed by
 *  session id — avatar/start awaits this instead of paying the Gemini
 *  round-trip itself (the candidate's Q1 cold start). */
const pendingQuestionGen = new Map<string, Promise<void>>()

/** Normalize for fuzzy question matching (the avatar reads questions verbatim). */
function normText(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim()
}

/** Which scripted question does this interviewer utterance correspond to? */
function matchQuestionIndex(session: InterviewSession, text: string): number | null {
  const t = normText(text)
  if (t.length < 8) return null
  const tTokens = new Set(t.split(' '))
  const asked = new Set((session.transcript ?? []).filter((x) => x.turnType === 'question').map((x) => x.questionIndex))
  const score = (i: number): number => {
    const q = normText(session.questions[i]?.text ?? '')
    if (!q) return 0
    if (t.includes(q) || q.includes(t)) return 1
    const qTokens = q.split(' ')
    const hit = qTokens.filter((w) => tTokens.has(w)).length
    return qTokens.length ? hit / qTokens.length : 0
  }
  // Prefer the not-yet-asked question with the strongest overlap.
  let best = -1, bestScore = 0
  for (let i = 0; i < session.questions.length; i++) {
    const s = score(i)
    const bonus = asked.has(i) ? 0 : 0.1 // tie-break toward unasked questions
    if (s >= 0.75 && s + bonus > bestScore) { best = i; bestScore = s + bonus }
  }
  return best >= 0 ? best : null
}

// Start (or restart after a refresh) the candidate's live avatar conversation.
sessionsRouter.post('/:id/avatar/start', ah(async (req, res) => {
  const { session, template } = load(req)
  if (session.track !== 'video_avatar')
    throw new HttpError(400, 'This interview does not use the video avatar')
  if (session.status === 'completed' || session.status === 'expired')
    throw new HttpError(409, 'The interview has already finished')

  // Ensure the question plan exists (the avatar's strict script needs it up front).
  // If the résumé step already kicked generation off in the background, just
  // await it — usually already resolved by the time the candidate gets here.
  if (session.questions.length === 0) {
    const pending = pendingQuestionGen.get(session.id)
    if (pending) await pending
  }
  if (session.questions.length === 0) {
    if (template.questionSource === 'adaptive' && session.resumeText) {
      await generateAdaptiveChatQuestions(session, template)
    } else if (template.questionSource === 'adaptive') {
      throw new HttpError(400, 'A résumé is required before starting')
    } else if (db.settings.avatar?.fallbackQuestions?.length) {
      session.questions = db.settings.avatar.fallbackQuestions.map((text) => ({
        id: randomUUID(), text, autoSubmitted: false,
      }))
      session.currentIndex = 0
    } else {
      throw new HttpError(400, 'No questions are configured for this interview')
    }
  }

  // A page refresh mid-call leaves an orphaned conversation — end it BEFORE
  // creating the replacement (bounded wait): Tavus concurrency limits can
  // reject the new create while the old conversation is still counted live.
  if (session.tavusConversationId) {
    await Promise.race([
      endCandidateConversation(session.tavusConversationId).catch(() => { /* best-effort */ }),
      new Promise((r) => setTimeout(r, 2500)),
    ])
  }

  // Candidate's LOCAL part of day → time-appropriate greeting ("Good morning …"),
  // exactly like the Voice Interview.
  const todRaw = (req.body as { timeOfDay?: string } | undefined)?.timeOfDay
  const tod: TimeOfDay | undefined =
    todRaw === 'morning' || todRaw === 'afternoon' || todRaw === 'evening' ? todRaw : undefined
  const name = session.candidate.name && session.candidate.name !== 'Candidate' ? session.candidate.name : ''
  // The candidate's résumé (collected at intake) rides into the avatar's context
  // so it knows who it's interviewing — background only, never extra questions.
  const conv = await createCandidateConversation(name, session.questions.map((q) => q.text), tod, session.resumeText)

  session.tavusConversationId = conv.conversation_id
  session.status = 'in_progress'
  if (!session.startedAt) session.startedAt = new Date().toISOString()
  session.mode = session.mode ?? 'conversational'
  session.transcript = session.transcript ?? []
  db.scheduleSave()

  res.json({ conversationUrl: conv.conversation_url, totalQuestions: session.questions.length } satisfies AvatarStartResponse)
}))

/** Append one avatar utterance to the session transcript, bucketed per question
 *  so the existing conversational scoring works unchanged. Shared by the live
 *  client bridge AND the server-side Tavus transcript recovery. */
function appendAvatarUtterance(session: InterviewSession, role: 'interviewer' | 'candidate', text: string): boolean {
  session.transcript = session.transcript ?? []
  if (session.transcript.length >= 800) return false // runaway guard

  const now = new Date().toISOString()
  if (role === 'interviewer') {
    const qi = matchQuestionIndex(session, text)
    const alreadyAsked = qi !== null && session.transcript.some((t) => t.turnType === 'question' && t.questionIndex === qi)
    const turn: Turn = {
      id: randomUUID(),
      role: 'interviewer',
      content: text,
      turnType: qi !== null && !alreadyAsked ? 'question' : 'acknowledgment',
      ...(qi !== null ? { questionIndex: qi } : {}),
      createdAt: now,
    }
    session.transcript.push(turn)
    if (qi !== null) session.currentIndex = qi
  } else {
    // Candidate speech counts as an answer only once a question has been asked
    // (greeting chatter like "yes, I'm ready" is kept but not bucketed).
    const anyAsked = session.transcript.some((t) => t.turnType === 'question')
    session.transcript.push({
      id: randomUUID(),
      role: 'candidate',
      content: text,
      ...(anyAsked ? { questionIndex: session.currentIndex } : {}),
      createdAt: now,
    })
  }
  return true
}

/** A not-evaluated report is a placeholder, not a judgment — new transcript
 *  content invalidates it so the session gets scored for real. */
function rescoreIfNotEvaluated(session: InterviewSession, template: InterviewTemplate) {
  const existing = db.reports.get(session.id)
  if (existing?.notEvaluated && (session.transcript ?? []).some((t) => t.role === 'candidate' && t.content.trim())) {
    db.reports.delete(session.id)
    maybeScore(session, template)
  }
}

// Live utterances (both speakers) → session transcript. Late utterances that
// arrive just after completion are still accepted (they'd otherwise be lost to
// the completion race) and re-trigger scoring if a placeholder report exists.
sessionsRouter.post('/:id/avatar/transcript', ah((req, res) => {
  const { session, template } = load(req)
  if (session.track !== 'video_avatar') throw new HttpError(400, 'This interview does not use the video avatar')
  const role = req.body?.role === 'interviewer' ? 'interviewer' : req.body?.role === 'candidate' ? 'candidate' : null
  const text = typeof req.body?.text === 'string' ? req.body.text.trim().slice(0, 4000) : ''
  if (!role || !text || (session.status !== 'in_progress' && session.status !== 'completed'))
    return res.json({ ok: false })

  if (!appendAvatarUtterance(session, role, text)) return res.json({ ok: false })
  db.scheduleSave()
  if (session.status === 'completed') rescoreIfNotEvaluated(session, template)
  res.json({
    ok: true,
    asked: new Set(session.transcript!.filter((t) => t.turnType === 'question').map((t) => t.questionIndex)).size,
    total: session.questions.length,
  })
}))

/**
 * Server-side transcript recovery: when the client-side capture bridge produced
 * no candidate answers, pull the authoritative transcript straight from Tavus
 * (it finalizes shortly after the call ends), rebuild the bucketed session
 * transcript, and (re)score. Runs fire-and-forget after completion.
 */
async function recoverAvatarTranscript(sessionId: string, conversationId: string) {
  const ATTEMPTS = 5
  const WAIT_MS = 6000
  for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
    await new Promise((r) => setTimeout(r, WAIT_MS))
    const session = db.sessions.get(sessionId)
    const template = session ? db.templates.get(session.templateId) : undefined
    if (!session || !template) return
    // Live utterances may have landed in the meantime — nothing to recover.
    if ((session.transcript ?? []).some((t) => t.role === 'candidate' && t.content.trim())) {
      rescoreIfNotEvaluated(session, template)
      maybeScore(session, template)
      return
    }
    const turns = await fetchConversationTranscript(conversationId)
    if (turns) {
      session.transcript = []
      session.currentIndex = 0
      for (const t of turns) appendAvatarUtterance(session, t.role, t.text)
      db.scheduleSave()
      console.log(`[avatar] recovered ${turns.length} transcript turns from Tavus for session ${sessionId}`)
      const existing = db.reports.get(sessionId)
      if (existing?.notEvaluated) db.reports.delete(sessionId)
      maybeScore(session, template)
      return
    }
    console.warn(`[avatar] transcript not ready on Tavus for ${sessionId} (attempt ${attempt}/${ATTEMPTS})`)
  }
  // Recovery failed — score whatever we have so the report resolves honestly.
  const session = db.sessions.get(sessionId)
  const template = session ? db.templates.get(session.templateId) : undefined
  if (session && template) maybeScore(session, template)
}

// Candidate (or the avatar) finished → end the Tavus call, complete + score.
// If the live bridge captured no candidate answers, scoring is deferred to the
// Tavus transcript recovery above instead of instantly producing a 0 report.
sessionsRouter.post('/:id/avatar/complete', ah((req, res) => {
  const { session, template } = load(req)
  if (session.track !== 'video_avatar') throw new HttpError(400, 'This interview does not use the video avatar')

  const conversationId = session.tavusConversationId
  if (conversationId) {
    void endCandidateConversation(conversationId)
    session.tavusConversationId = undefined
  }
  if (session.status !== 'completed' && session.status !== 'expired') {
    session.status = 'completed'
    session.completedAt = new Date().toISOString()
  }
  db.scheduleSave()

  const hasAnswers = (session.transcript ?? []).some((t) => t.role === 'candidate' && t.content.trim())
  if (!hasAnswers && conversationId) {
    void recoverAvatarTranscript(session.id, conversationId)
  } else {
    maybeScore(session, template)
  }
  res.json({ ok: true })
}))

/* ─── Two-way Interview (Daily) — live recruiter↔candidate video call ──────
 * No avatar, no scripted transcript capture — the recruiter conducts the
 * interview live; a single (interviewer, candidate) transcript pair is
 * synthesised from the call recording on completion so it scores like any
 * other conversation track. */

// Recruiter starts (or resumes) the live call as the room owner. Creates the
// Daily room deterministically (`room-{sessionId}`) so both `join` calls
// converge on the same room, and mints an owner meeting token (cloud
// recording enabled) so the candidate's later knock can be admitted.
sessionsRouter.post('/:id/twoway/host', requireRecruiter, ah(async (req, res) => {
  const auth = requireAuth(req)
  // A bulk-invited two_way session doesn't exist in the LOCAL store until the
  // candidate opens their /take/:id link at least once (materializeInviteSession
  // creates it then — see docs/TWO_WAY_INTERVIEW.md) — until that happens there's
  // nothing here for the recruiter to host yet. Surface that plainly instead of
  // load()'s generic "Session not found", but only once we've confirmed THIS
  // recruiter actually owns the underlying Firestore invite (never leak that some
  // OTHER recruiter's invite exists at this id).
  if (!db.sessions.has(req.params.id)) {
    try {
      const { adminFirestore } = await import('../services/firebaseAdmin')
      const snap = await adminFirestore().collection('interviews').doc(req.params.id).get()
      if (snap.exists && snap.get('recruiterId') === auth.uid) {
        throw new HttpError(409, 'The candidate must open their interview link before you can join.')
      }
    } catch (err) {
      if (err instanceof HttpError) throw err
      // Firestore lookup is best-effort (outage / not configured) — fall through
      // to load()'s generic 404 below rather than blocking on it.
    }
  }
  const { session } = load(req)
  assertOwner(session, auth)
  if (session.track !== 'two_way') throw new HttpError(400, 'Not a two-way interview')
  if (session.status === 'completed' || session.status === 'expired')
    throw new HttpError(409, 'This interview has already ended')

  const roomName = session.liveRoomName ?? `room-${session.id}`
  const room = await ensureRoom(roomName)
  session.liveRoomName = roomName
  if (session.status === 'created' || session.status === 'system_check') {
    session.status = 'in_progress'
    session.startedAt ??= new Date().toISOString()
  }
  db.scheduleSave()

  const token = await mintToken({ roomName, isOwner: true, userName: 'Interviewer' })
  res.json({ roomUrl: room.url, token, isOwner: true } satisfies TwoWayJoinResponse)
}))

// Candidate joins the live call (non-owner — knocks, waits for the recruiter
// to admit). Fails with 409 until the recruiter has started the room.
sessionsRouter.post('/:id/twoway/join', ah(async (req, res) => {
  const { session } = load(req) // load() enforces participant access
  if (session.track !== 'two_way') throw new HttpError(400, 'Not a two-way interview')
  if (session.status === 'completed' || session.status === 'expired')
    throw new HttpError(409, 'This interview has already ended')
  if (!session.liveRoomName) throw new HttpError(409, 'The interviewer has not started this interview yet.')

  const room = await ensureRoom(session.liveRoomName)
  const token = await mintToken({
    roomName: session.liveRoomName,
    isOwner: false,
    userName: session.candidate.name || 'Candidate',
  })
  res.json({ roomUrl: room.url, token, isOwner: false } satisfies TwoWayJoinResponse)
}))

// A client-supplied recording URL is fetched server-side (transcribeVideoUrl
// does a raw `fetch(url)`) and persisted onto the session, so it must be
// validated before either happens: it MUST be a Firebase Storage download URL
// scoped to THIS session's own object path. This closes a blind SSRF (an
// arbitrary host, or an internal/metadata endpoint, fetched by the server on
// the caller's behalf) and stops a cross-session URL from being attached.
function isValidSessionRecordingUrl(url: string, sessionId: string): boolean {
  let u: URL
  try { u = new URL(url) } catch { return false }
  const allowedHosts = new Set(['firebasestorage.googleapis.com', 'storage.googleapis.com'])
  if (u.protocol !== 'https:' || !allowedHosts.has(u.hostname)) return false
  let decodedPath: string
  try { decodedPath = decodeURIComponent(u.pathname) } catch { return false }
  return decodedPath.includes(`interviews/${sessionId}/`)
}

// End the live call → complete the session → (owner-only, best-effort) tear
// down the Daily room → if a recording URL was uploaded, transcribe it into
// the conversational transcript and score. Transcription never blocks completion.
//
// Both parties hit this route independently: the candidate calls it with NO
// recordingUrl, the recruiter calls it once the recording has uploaded, WITH
// one. Whichever arrives first must not permanently win — the recording is
// processed exactly once (guarded by `!session.recordingUrl`), and if it lands
// AFTER a placeholder `notEvaluated` report was already cached (from the other
// party's earlier empty call), that placeholder is dropped so scoring re-runs
// on the real transcript.
//
// SECURITY: a `recordingUrl` is only ever honored from the OWNING recruiter's
// call — load() lets the candidate reach this route too (they must be able to
// complete their own side), but a candidate-supplied recordingUrl is a blind
// SSRF vector (see isValidSessionRecordingUrl above) AND, since recordingUrl is
// set-once, would let a candidate permanently preempt the recruiter's real
// recording just by completing first with a bogus URL. Candidate `complete`
// therefore carries no recording, by construction. Likewise `deleteRoom` only
// runs on the owner's complete — a candidate ending first must not tear the
// Daily room out from under a recruiter who may still be recording/uploading;
// the room self-expires (`exp`) regardless.
sessionsRouter.post('/:id/twoway/complete', ah(async (req, res) => {
  const { session, template } = load(req)
  if (session.track !== 'two_way') throw new HttpError(400, 'Not a two-way interview')

  const auth = requireAuth(req)
  const isOwner = ownsSession(session, auth)

  const rawRecordingUrl = typeof req.body?.recordingUrl === 'string' ? req.body.recordingUrl : ''
  const recordingUrl = isOwner && rawRecordingUrl && isValidSessionRecordingUrl(rawRecordingUrl, session.id)
    ? rawRecordingUrl
    : ''

  if (session.status !== 'completed') {
    session.status = 'completed'
    session.completedAt = new Date().toISOString()
  }
  if (isOwner && session.liveRoomName) void deleteRoom(session.liveRoomName)
  db.scheduleSave()

  if (recordingUrl && !session.recordingUrl) {
    // Set recordingUrl FIRST — this is the idempotency guard. If transcription
    // below throws, a retry with the same recordingUrl still won't reprocess
    // (no duplicate transcript turns), consistent with "process once, best-effort".
    session.recordingUrl = recordingUrl
    session.mode ??= 'conversational'
    session.transcript ??= []
    try {
      const text = await transcribeVideoUrl(recordingUrl)
      session.transcript.push(
        {
          id: randomUUID(), role: 'interviewer', turnType: 'question', questionIndex: 0,
          content: 'Live two-way interview', createdAt: new Date().toISOString(),
        },
        {
          id: randomUUID(), role: 'candidate', questionIndex: 0,
          content: text, createdAt: new Date().toISOString(),
        },
      )
    } catch (err) {
      console.error('[twoway] transcription failed for', session.id, err)
    }
    db.scheduleSave()

    // A placeholder report cached by the OTHER party's earlier (recording-less)
    // completion call is now stale — drop it so scoring re-runs on the real content.
    const existing = db.reports.get(session.id)
    if (session.recordingUrl && existing?.notEvaluated) db.reports.delete(session.id)
  }
  maybeScore(session, template)
  res.json({ ok: true })
}))

// Recruiter's manual rating/notes — a dual path alongside the AI scorecard,
// since a two-way interview is recruiter-scored more than model-scored. The
// SESSION is the source of truth (survives even if no report has landed yet —
// e.g. scoring is still pending, or the interview was never evaluated); the
// report copy is just an immediate-display convenience for the current view.
sessionsRouter.post('/:id/twoway/review', requireRecruiter, ah((req, res) => {
  const { session } = load(req)
  assertOwner(session, requireAuth(req))
  if (session.track !== 'two_way') throw new HttpError(400, 'Not a two-way interview')

  const rating = Math.max(0, Math.min(5, Number(req.body?.rating) || 0))
  const notes = String(req.body?.notes ?? '').slice(0, 4000)
  const manualReview = { rating, notes, by: requireAuth(req).email, at: new Date().toISOString() }

  session.manualReview = manualReview
  db.scheduleSave()

  const report = db.reports.get(session.id)
  if (report) {
    report.manualReview = manualReview
    db.reports.set(session.id, report)
    db.scheduleSave()
  }
  res.json({ ok: true })
}))

// "I'm ready, begin" — starts question 0's preparation phase.
sessionsRouter.post('/:id/begin', ah(async (req, res) => {
  const { session, template } = load(req)
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
  const { session, template } = load(req)
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
  const { session, template } = load(req)
  settle(session, template)
  const q = session.questions[session.currentIndex]
  if (!q || q.id !== req.body?.questionId)
    return res.status(409).json({ error: 'Stale question — refresh state' })
  q.draft = String(req.body?.draft ?? '')
  db.scheduleSave()
  res.json({ ok: true })
}))

// Submit the current answer → lock → advance.
sessionsRouter.post('/:id/answers', ah(async (req, res) => {
  const { session, template } = load(req)
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
  // Video track: the live transcript IS the answer (no video, no upload). Mirror it
  // into session.transcript as (question, answer) turns so scoring/results run the
  // same conversation path as Voice.
  if (session.track === 'video') {
    session.mode = session.mode ?? 'conversational'
    session.transcript = session.transcript ?? []
    session.transcript.push(...buildVideoTranscript(q, session.currentIndex, now))
  }
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

// Video Interview: per-frame Rekognition proxy the CANDIDATE can reach (the
// /api/avatar/analyze-face route is recruiter-only). Authorized as a session
// participant; same request/response shape the client RekognitionService uses.
sessionsRouter.post('/:id/facial-frame', ah(async (req, res) => {
  const { session } = load(req)               // asserts participant (candidate or owner)
  if (session.track !== 'video') throw new HttpError(400, 'This interview does not capture facial analysis')
  const { imageBase64, questionIdx, timestampMs } = req.body ?? {}
  if (!imageBase64 || typeof imageBase64 !== 'string') return res.status(400).json({ success: false, error: 'imageBase64 required' })
  if ((imageBase64.length * 3) / 4 < 5000) return res.json({ success: false, reason: 'frame_too_small', questionIdx, timestampMs })
  try {
    const r = await detectFaces(imageBase64)
    if (!r.success) return res.status(400).json({ success: false, error: r.error })
    res.json({ success: true, faceDetails: r.faceDetails, questionIdx, timestampMs })
  } catch (err) {
    const e = err as { message?: string }
    console.error('[facial-frame] Rekognition error for', session.id, e?.message)
    res.status(500).json({ success: false, error: e?.message ?? String(err) })
  }
}))

// Video Interview: candidate uploads the aggregated AWS Rekognition facial
// summary (computed client-side) on completion. Additive; stored opaquely.
sessionsRouter.post('/:id/facial', ah((req, res) => {
  const { session } = load(req)
  if (session.track !== 'video') throw new HttpError(400, 'This interview does not capture facial analysis')
  const summary = req.body?.summary
  if (summary && typeof summary === 'object' && !Array.isArray(summary) && Array.isArray((summary as { perQuestion?: unknown }).perQuestion)) {
    session.facialSummary = summary as Record<string, unknown>
    db.scheduleSave()
    return res.json({ ok: true })
  }
  res.json({ ok: false })
}))

// Log an integrity event (tab switch, blur, blocked paste/copy, fullscreen exit).
sessionsRouter.post('/:id/integrity-event', ah((req, res) => {
  const { session, template } = load(req)
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
  const { session, template } = load(req)

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
  const { session, template } = load(req)
  if (session.track !== 'chatbot' && session.track !== 'video_avatar')
    throw new HttpError(400, 'Not a conversational session')
  if (session.status === 'completed' || session.status === 'expired')
    throw new HttpError(409, 'Interview already finished')
  if (template.questionSource === 'adaptive' && !session.resumeText)
    throw new HttpError(400, 'A résumé is required before starting')
  if (session.status !== 'in_progress') {
    const tod = req.body?.timeOfDay
    const timeOfDay = (tod === 'morning' || tod === 'afternoon' || tod === 'evening' ? tod : undefined) as TimeOfDay | undefined
    await beginConversation(session, template, { timeOfDay })
    db.scheduleSave()
  }
  res.json(computeChatbotState(session, template))
}))

// The ONLY conversational view the candidate receives (revealed transcript + timers).
sessionsRouter.get('/:id/chat/state', ah(async (req, res) => {
  const { session, template } = load(req)
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
  const { session, template } = load(req)
  if (session.status !== 'in_progress')
    return res.status(409).json({ error: 'Interview is not in progress', state: computeChatbotState(session, template) })
  const turn = currentInterviewerTurn(session)
  if (!turn)
    return res.status(409).json({ error: 'No question is awaiting an answer', state: computeChatbotState(session, template) })
  if (req.body?.turnId && req.body.turnId !== turn.id)
    return res.status(409).json({ error: 'Stale turn — refresh', state: computeChatbotState(session, template) })

  // Only timed question turns are clock-gated. Untimed turns (the opening
  // greeting/readiness turn, or any turn when the timer is off) pass through.
  const tt = turnTiming(template, turn)
  if (tt) {
    if (!turn.answerStartedAt) throw new HttpError(400, 'Still in thinking time')
    const remaining = tt.answerSeconds - (Date.now() - Date.parse(turn.answerStartedAt)) / 1000
    if (remaining > 0 && !tt.allowEarlySubmit) throw new HttpError(403, 'Early submission is disabled')
  }

  await submitChatAnswer(session, template, String(req.body?.answerText ?? turn.draft ?? ''))
  db.scheduleSave()
  maybeScore(session, template)
  res.json(computeChatbotState(session, template))
}))

// Auto-save the in-progress answer (resilience across refresh).
sessionsRouter.post('/:id/chat/draft', ah((req, res) => {
  const { session } = load(req)
  const turn = currentInterviewerTurn(session)
  if (!turn || (req.body?.turnId && req.body.turnId !== turn.id))
    return res.status(409).json({ error: 'Stale turn — refresh' })
  turn.draft = String(req.body?.draft ?? '')
  db.scheduleSave()
  res.json({ ok: true })
}))

// The client finished the "Thinking…" indicator and presented the question —
// start its thinking/answer clock now (idempotent). No-op for untimed turns
// (greeting, readiness, wrap-up). Keeps the indicator + acknowledgment prefix
// off the timer. This is the `question_presented` event.
sessionsRouter.post('/:id/chat/question-presented', ah((req, res) => {
  const { session, template } = load(req)
  if (revealTimedTurn(session, template)) db.scheduleSave()
  res.json(computeChatbotState(session, template))
}))

// Timed mode: end thinking early and start answering now.
sessionsRouter.post('/:id/chat/skip-thinking', ah((req, res) => {
  const { session, template } = load(req)
  if (!skipThinking(session, template)) throw new HttpError(409, 'Cannot skip thinking right now')
  db.scheduleSave()
  res.json(computeChatbotState(session, template))
}))

/* ─── recruiter views ───────────────────────────────────────────────────── */

// Recruiter dashboard list — ONLY sessions this recruiter owns. Admins see all,
// including legacy sessions with no owner ("admin-only until claimed").
sessionsRouter.get('/', requireRecruiter, (req, res) => {
  const auth = requireAuth(req)
  const items: SessionListItem[] = [...db.sessions.values()]
    .filter((s) => ownsSession(s, auth))
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

// Candidate's own assigned interviews — scoped strictly to the caller's VERIFIED
// email. Never includes scores/reports or any other candidate's sessions. An
// empty array (rendered as "Access Denied — no interviews") reveals nothing
// about sessions assigned to anyone else. Merges LOCAL sessions with Firestore
// bulk-invites assigned to this email that haven't been claimed yet (a claimed
// invite has a local session with the same id, which takes precedence).
sessionsRouter.get('/mine', ah(async (req, res) => {
  const auth = requireAuth(req)
  const email = auth.email
  if (!email) return res.json([])

  const items: CandidateAssignedSession[] = [...db.sessions.values()]
    .filter((s) => (s.candidate?.email ?? '').trim().toLowerCase() === email)
    .map((s) => ({
      id: s.id,
      templateName: db.templates.get(s.templateId)?.name ?? '(deleted template)',
      role: db.templates.get(s.templateId)?.role,
      track: s.track,
      status: s.status,
      createdAt: s.createdAt,
      completedAt: s.completedAt,
    }))

  // Firestore invites (best-effort — a Firestore outage never hides local sessions).
  try {
    const { adminFirestore } = await import('../services/firebaseAdmin')
    const snap = await adminFirestore().collection('interviews')
      .where('candidateEmailLower', '==', email).get()
    const seen = new Set(items.map((i) => i.id))
    for (const doc of snap.docs) {
      if (seen.has(doc.id)) continue
      const d = doc.data() as Record<string, unknown>
      const mode = d.mode as string | undefined
      const track = (mode === 'chatbot' || mode === 'voice' || mode === 'video_avatar' || mode === 'chat' || mode === 'video' || mode === 'two_way')
        ? mode
        : d.type === 'video' ? 'video_avatar' as const : 'chat' as const
      const created = (d.createdAt as { toDate?: () => Date } | undefined)?.toDate?.()?.toISOString() ?? new Date().toISOString()
      const completed = (d.completedAt as { toDate?: () => Date } | undefined)?.toDate?.()?.toISOString()
      items.push({
        id: doc.id,
        templateName: (d.title as string) || 'Interview',
        role: (d.role as string) || undefined,
        track,
        status: d.status === 'completed' ? 'completed' : d.status === 'in_progress' ? 'in_progress' : 'created',
        createdAt: created,
        completedAt: completed,
      })
    }
  } catch (err) {
    console.error('[sessions/mine] Firestore invite lookup failed:', err)
  }

  items.sort((a, b) => b.createdAt.localeCompare(a.createdAt))
  res.json(items)
}))

sessionsRouter.get('/:id/report', requireRecruiter, ah(async (req, res) => {
  const { session, template } = load(req)
  assertOwner(session, requireAuth(req))   // owner-only; candidates never see reports/scores

  // Conversation tracks: synthesise the per-question view from the transcript
  // (ids `q{index}` matching the scored perQuestion). When the transcript is
  // empty, fall back to the PLANNED question script so the report still shows
  // what the interview asked instead of an empty accordion.
  const isConversation =
    session.track === 'chatbot' || session.track === 'video_avatar' || session.track === 'voice' || session.track === 'video' || session.track === 'two_way'
  const groups = isConversation ? primaryQuestionGroups(session) : []
  const questions = isConversation
    ? groups.length > 0
      ? groups.map((g) => ({
          id: `q${g.index}`,
          text: g.question,
          answerText: g.answer,
          autoSubmitted: g.autoAdvanced,
        }))
      : session.questions.map((q, i) => ({
          id: `q${i}`,
          text: q.text,
          category: q.category,
          answerText: '',
          autoSubmitted: false,
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
      // Full conversation transcript for the report's transcript panel.
      ...(isConversation
        ? {
            transcript: (session.transcript ?? []).map((t) => ({
              role: t.role,
              content: t.content,
              questionIndex: t.questionIndex,
              createdAt: t.createdAt,
            })),
          }
        : {}),
      // Two-way Interview: call recording URL, for report playback.
      ...(session.recordingUrl ? { recordingUrl: session.recordingUrl } : {}),
      // Two-way Interview: the recruiter's manual rating/notes. Surfaced from the
      // SESSION (the source of truth — see /twoway/review) rather than only via
      // `report.manualReview`, so the recruiter can rate before AI scoring lands
      // (report is still null while scoring is in flight).
      ...(session.manualReview ? { manualReview: session.manualReview } : {}),
    },
    rubric: template.rubric,
    report: db.reports.get(session.id) ?? null,
    // Transcript-derived delivery metrics (voice / chatbot / avatar).
    ...(isConversation ? { speech: computeSpeechMetrics(session) ?? undefined } : {}),
    // AWS Rekognition facial summary (video track).
    ...(session.facialSummary ? { facial: session.facialSummary } : {}),
  }

  // The session is the source of truth for the recruiter's manual review (it's
  // never lost, even if written before scoring produced a report — see
  // /twoway/review). Surface it onto the report once one exists, so it
  // displays even when the review predates the report landing.
  const report = view.report
  if (report && session.manualReview) {
    report.manualReview = session.manualReview
    db.reports.set(session.id, report)
    db.scheduleSave()
  }

  // Backfill the text sentiment read for conversation reports scored before this
  // feature existed, so older sessions show it too (computed once, then cached).
  if (isConversation && report && !report.sentiment && !report.notEvaluated && geminiEnabled()) {
    const sentiment = await analyzeSentiment(session).catch(() => null)
    if (sentiment) {
      report.sentiment = sentiment
      db.reports.set(session.id, report)
      db.scheduleSave()
    }
  }

  res.json(view)
}))
