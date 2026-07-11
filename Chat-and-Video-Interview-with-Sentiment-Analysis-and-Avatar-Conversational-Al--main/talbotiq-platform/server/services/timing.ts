import type {
  InterviewSession,
  InterviewTemplate,
  SessionQuestion,
  CandidateSessionState,
} from '../../shared/types'

const at = (iso: string) => Date.parse(iso)
const iso = (ms: number) => new Date(ms).toISOString()

/** Total question count for progress display. */
function totalQuestions(session: InterviewSession, template: InterviewTemplate): number {
  if (session.questions.length > 0) return session.questions.length
  return template.timing.numberOfQuestions ?? 0
}

function autoSubmit(q: SessionQuestion, whenMs: number) {
  q.answerText = q.answerText ?? q.draft ?? ''
  q.submittedAt = iso(whenMs)
  q.autoSubmitted = true
}

function startNext(session: InterviewSession, whenMs: number) {
  session.currentIndex += 1
  const next = session.questions[session.currentIndex]
  if (next) {
    next.prepStartedAt = iso(whenMs)
  } else {
    session.status = 'completed'
    session.completedAt = session.completedAt ?? iso(whenMs)
  }
}

/**
 * Advance the session through every phase boundary that has already elapsed in
 * real (server) time. Mutates the session and is idempotent — safe to call on
 * every read or write. This is what makes timing tamper-proof: the client's
 * clock is irrelevant; only server timestamps drive transitions.
 *
 * Returns true if anything changed (so callers can persist).
 */
export function tick(
  session: InterviewSession,
  template: InterviewTemplate,
  nowMs: number = Date.now(),
): boolean {
  // The conversational tracks (chatbot + video_avatar) have their own engine —
  // never apply the fixed-slot question timing to them (no questions[] array).
  if (session.track === 'chatbot' || session.track === 'video_avatar') return false
  if (session.status !== 'in_progress') return false
  let mutated = false

  // Overall interview cap (optional).
  const cap = template.timing.totalTimeCapSeconds
  if (cap && session.startedAt && nowMs >= at(session.startedAt) + cap * 1000) {
    const current = session.questions[session.currentIndex]
    if (current && !current.submittedAt) autoSubmit(current, nowMs)
    session.status = 'completed'
    session.completedAt = iso(nowMs)
    return true
  }

  let guard = 0
  while (guard++ < 10_000) {
    const q = session.questions[session.currentIndex]
    if (!q) {
      session.status = 'completed'
      session.completedAt = session.completedAt ?? iso(nowMs)
      mutated = true
      break
    }
    if (q.submittedAt) {
      // Defensive: a submitted question should never be current.
      startNext(session, at(q.submittedAt))
      mutated = true
      continue
    }
    if (!q.prepStartedAt) break // not begun yet (awaiting /begin)

    if (!q.answerStartedAt) {
      const prepDeadline = at(q.prepStartedAt) + template.timing.prepSeconds * 1000
      if (nowMs >= prepDeadline) {
        q.answerStartedAt = iso(prepDeadline)
        mutated = true
        continue
      }
      break
    }

    const answerDeadline = at(q.answerStartedAt) + template.timing.answerSeconds * 1000
    if (nowMs >= answerDeadline) {
      autoSubmit(q, answerDeadline)
      startNext(session, answerDeadline)
      mutated = true
      continue
    }
    break
  }

  return mutated
}

/** Compute the candidate-safe view AFTER a tick. Never leaks future questions. */
export function computePublicState(
  session: InterviewSession,
  template: InterviewTemplate,
  nowMs: number = Date.now(),
): CandidateSessionState {
  const total = totalQuestions(session, template)
  const q = session.questions[session.currentIndex]

  let phase: CandidateSessionState['phase'] = null
  let remaining = 0
  let totalPhase = 0

  if (session.status === 'in_progress' && q) {
    if (q.answerStartedAt) {
      phase = 'answer'
      totalPhase = template.timing.answerSeconds
      remaining = totalPhase - (nowMs - at(q.answerStartedAt)) / 1000
    } else if (q.prepStartedAt) {
      phase = 'prep'
      totalPhase = template.timing.prepSeconds
      remaining = totalPhase - (nowMs - at(q.prepStartedAt)) / 1000
    } else {
      phase = 'prep'
      totalPhase = template.timing.prepSeconds
      remaining = totalPhase
    }
  }

  const awaitingResume =
    template.questionSource === 'adaptive' && !session.resumeText

  return {
    sessionId: session.id,
    status: session.status,
    track: session.track,
    phase,
    remainingSeconds: Math.max(0, Math.ceil(remaining)),
    totalPhaseSeconds: totalPhase,
    question:
      session.status === 'in_progress' && q ? { id: q.id, text: q.text } : null,
    progress: { current: Math.min(session.currentIndex + 1, total || 1), total },
    draft: q?.draft ?? q?.answerText ?? '',
    timing: {
      prepSeconds: template.timing.prepSeconds,
      answerSeconds: template.timing.answerSeconds,
      allowSkipPrep: template.timing.allowSkipPrep,
      allowEarlySubmit: template.timing.allowEarlySubmit,
      warningThresholdSeconds: template.timing.warningThresholdSeconds,
    },
    branding: template.branding,
    integrity: template.integrity,
    tabSwitchWarnings: session.tabSwitchCount,
    awaitingResume,
  }
}

/** Seconds the candidate actually spent answering (for the recruiter view). */
export function answerTimeUsed(q: SessionQuestion): number | undefined {
  if (!q.answerStartedAt || !q.submittedAt) return undefined
  return Math.max(0, Math.round((at(q.submittedAt) - at(q.answerStartedAt)) / 1000))
}
