/**
 * Pure, dependency-free state machine for the Voice Interview end-flow.
 *
 * It decides — from the KNOWN backend question plan, not from raw audio-turn
 * counts — when the interview is genuinely covered, when to nudge a model that
 * tries to wrap up early, and when the wrap-up handshake is complete. All timing
 * and I/O live in the driver (voice.ts); this module only returns Actions, so it
 * is fully unit-testable with simulated Live message sequences.
 *
 * Phases: readiness → interviewing → closing → done.
 */

export type VoiceFlowPhase = 'readiness' | 'interviewing' | 'closing' | 'done'
export type TimerTag = 'idle' | 'candidateSilence' | 'maxDuration'

export type FlowAction =
  | { kind: 'nudge'; text: string }                         // inject a director note to the model
  | { kind: 'armTimer'; tag: TimerTag; ms: number }         // (re)start a timer
  | { kind: 'clearTimer'; tag: TimerTag }
  | { kind: 'finalize'; reason: string; graceful: boolean } // end + score

export interface VoiceFlowOptions {
  idleMs?: number            // no interviewer turn for this long → nudge, then end
  candidateSilenceMs?: number // in closing, no candidate ack for this long → end gracefully
  maxDurationMs?: number     // hard cap
  matchThreshold?: number    // token-overlap ratio to count a planned question as asked
}

/* ─── text helpers (pure) ───────────────────────────────────────────────── */

const STOP = new Set([
  'the', 'a', 'an', 'to', 'of', 'and', 'or', 'in', 'on', 'for', 'with', 'your', 'you', 'i', 'we',
  'me', 'my', 'is', 'are', 'was', 'were', 'how', 'what', 'why', 'did', 'do', 'does', 'it', 'that',
  'this', 'about', 'can', 'could', 'would', 'tell', 'so', 'well', 'okay', 'ok', 'just', 'like',
])
const norm = (s: string) => (s ?? '').toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim()
const contentTokens = (s: string) => new Set(norm(s).split(' ').filter((w) => w.length > 2 && !STOP.has(w)))

/** Overlap of shared content words relative to the smaller token set (0..1). */
function tokenSetRatio(a: string, b: string): number {
  const A = contentTokens(a), B = contentTokens(b)
  if (A.size === 0 || B.size === 0) return 0
  let inter = 0
  for (const t of A) if (B.has(t)) inter++
  return inter / Math.min(A.size, B.size)
}

const QUESTION_LEAD = /^(tell me|walk me|describe|explain|how |what |why |where |when |which |who |can you|could you|would you|do you|did you|have you|are you|were you|give me|share|let'?s (talk|dive|start)|talk to me)/i
export function isQuestionShaped(text: string): boolean {
  const t = (text ?? '').trim()
  return t.includes('?') || QUESTION_LEAD.test(t)
}

const ACK_RE = /\b(thank|appreciat|great|nice|helpful|good|love|interesting|makes sense|gives me|glad|wonderful|awesome|perfect|excellent|brilliant|impressive|fantastic|lovely)\b/i
/** Drop a leading short acknowledgment sentence so it doesn't dilute the match. */
function questionClause(text: string): string {
  const parts = (text ?? '').split(/(?<=[.!?])\s+/)
  if (parts.length > 1 && ACK_RE.test(parts[0]) && contentTokens(parts[0]).size <= 6) {
    return parts.slice(1).join(' ')
  }
  return text ?? ''
}

/** Unambiguous, end-anchored closing phrases (used only to nudge early wrap-ups). */
const HARD_CLOSING_RE = /\b(this concludes|the interview is (now )?(over|complete|done)|thank you (so much )?for your time|that concludes (the|our) interview|we'?ve reached the end|wrap(ping)? (this )?up|goodbye|take care)\b/i

/* ─── controller ────────────────────────────────────────────────────────── */

export function createVoiceFlow(questions: string[], opts: VoiceFlowOptions = {}) {
  const idleMs = opts.idleMs ?? 180_000
  const candidateSilenceMs = opts.candidateSilenceMs ?? 15_000
  const maxDurationMs = opts.maxDurationMs ?? 18 * 60_000
  const threshold = opts.matchThreshold ?? 0.5
  const N = questions.length

  let phase: VoiceFlowPhase = N === 0 ? 'done' : 'readiness'
  let askedIndex = 0            // number of planned questions asked (0..N)
  let lastAnsweredIndex = -1
  const answers: string[] = questions.map(() => '')
  let candidateTurns = 0        // total candidate turns seen (guards the greeting match)
  let closingExchanges = 0
  let earlyNudges = 0
  let idleNudged = false
  let finalized = false

  const coverageComplete = () => askedIndex >= N && lastAnsweredIndex >= N - 1

  function onInterviewerTurn(text: string): FlowAction[] {
    if (finalized || phase === 'done') return []
    const actions: FlowAction[] = [{ kind: 'armTimer', tag: 'idle', ms: idleMs }]
    idleNudged = false

    // In closing, further interviewer turns just continue the wrap-up; keep waiting.
    if (phase === 'closing') {
      actions.push({ kind: 'armTimer', tag: 'candidateSilence', ms: candidateSilenceMs })
      return actions
    }

    // Coverage matching — never match the greeting (no candidate turn yet), and only
    // count a question-shaped turn. Forward window absorbs paraphrase/reorder/skips.
    if (candidateTurns > 0 && askedIndex < N && isQuestionShaped(text)) {
      const clause = questionClause(text)
      let bestJ = -1, best = threshold
      for (let j = askedIndex; j <= Math.min(askedIndex + 2, N - 1); j++) {
        const sc = tokenSetRatio(clause, questions[j])
        if (sc >= best) { best = sc; bestJ = j }
      }
      if (bestJ >= askedIndex) { askedIndex = bestJ + 1; phase = 'interviewing' }
    }

    // Enter the wrap-up: all questions asked AND the last one answered, and this is a
    // non-question turn (the closing). Never on the same turn that reaches full coverage.
    if (phase === 'interviewing' && coverageComplete() && !isQuestionShaped(text)) {
      phase = 'closing'
      actions.push({ kind: 'clearTimer', tag: 'idle' })
      actions.push({ kind: 'armTimer', tag: 'candidateSilence', ms: candidateSilenceMs })
      return actions
    }

    // Early wrap-up before covering the plan → nudge to continue (bounded).
    if (askedIndex < N && HARD_CLOSING_RE.test(text) && earlyNudges < 2) {
      earlyNudges++
      actions.push({ kind: 'nudge', text: 'You still have more questions to cover. Do not wrap up yet — continue and ask the next planned question now.' })
    }
    return actions
  }

  function onCandidateTurn(text: string): FlowAction[] {
    if (finalized || phase === 'done') return []
    candidateTurns++

    if (phase === 'closing') {
      // A closing-phase question earns one answer from the model; otherwise it's the
      // farewell → end gracefully.
      if (text.includes('?') && closingExchanges < 2) {
        closingExchanges++
        return [{ kind: 'armTimer', tag: 'candidateSilence', ms: candidateSilenceMs }]
      }
      finalized = true; phase = 'done'
      return [{ kind: 'clearTimer', tag: 'candidateSilence' }, { kind: 'finalize', reason: 'completed', graceful: true }]
    }

    // Readiness reply, or chatter after the plan is done → not a scored answer.
    if (askedIndex === 0 || coverageComplete()) return []

    // Bucket into the current question; consecutive splits concatenate.
    const idx = askedIndex - 1
    answers[idx] = answers[idx] ? `${answers[idx]} ${text}`.trim() : (text ?? '').trim()
    if (idx > lastAnsweredIndex) lastAnsweredIndex = idx
    return []
  }

  /** Barge-in: no state change, just informational. */
  function onInterrupted(): FlowAction[] { return [] }

  /**
   * The candidate is actively speaking (streaming ASR). The call is NOT idle, so
   * reset the idle watchdog — otherwise a long or thoughtful answer, during which
   * the interviewer takes no turn, would trip the idle timeout and end the
   * interview mid-answer. No coverage/answer state changes here; that happens on
   * the turn boundary (onCandidateTurn). In closing, the candidateSilence timer
   * governs instead, so leave it alone.
   */
  function onCandidateActivity(): FlowAction[] {
    if (finalized || phase === 'done' || phase === 'closing') return []
    return [{ kind: 'armTimer', tag: 'idle', ms: idleMs }]
  }

  function onTimer(tag: TimerTag): FlowAction[] {
    if (finalized || phase === 'done') return []
    if (tag === 'maxDuration') { finalized = true; phase = 'done'; return [{ kind: 'finalize', reason: 'timeout', graceful: coverageComplete() }] }
    if (tag === 'candidateSilence') {
      if (phase === 'closing') { finalized = true; phase = 'done'; return [{ kind: 'finalize', reason: 'completed', graceful: true }] }
      return []
    }
    // idle
    if (coverageComplete()) { finalized = true; phase = 'done'; return [{ kind: 'finalize', reason: 'completed', graceful: true }] }
    if (!idleNudged) {
      idleNudged = true
      return [{ kind: 'nudge', text: 'If you are ready, please continue with the next question.' }, { kind: 'armTimer', tag: 'idle', ms: idleMs }]
    }
    finalized = true; phase = 'done'
    return [{ kind: 'finalize', reason: 'timeout', graceful: false }]
  }

  /** Client 'end' button or transport close. */
  function onEnd(reason: string): FlowAction[] {
    if (finalized) return []
    finalized = true; phase = 'done'
    return [{ kind: 'clearTimer', tag: 'idle' }, { kind: 'clearTimer', tag: 'candidateSilence' }, { kind: 'clearTimer', tag: 'maxDuration' }, { kind: 'finalize', reason, graceful: coverageComplete() }]
  }

  function start(): FlowAction[] {
    return [{ kind: 'armTimer', tag: 'idle', ms: idleMs }, { kind: 'armTimer', tag: 'maxDuration', ms: maxDurationMs }]
  }

  return {
    onInterviewerTurn, onCandidateTurn, onInterrupted, onCandidateActivity, onTimer, onEnd, start,
    get phase() { return phase },
    get askedIndex() { return askedIndex },
    get answers() { return answers.slice() },
    get coverageComplete() { return coverageComplete() },
    get finalized() { return finalized },
  }
}

export type VoiceFlow = ReturnType<typeof createVoiceFlow>
