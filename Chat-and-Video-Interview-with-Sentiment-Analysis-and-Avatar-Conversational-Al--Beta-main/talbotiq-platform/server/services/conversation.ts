import { randomUUID } from 'node:crypto'
import { Type } from '@google/genai'
import type {
  InterviewSession,
  InterviewTemplate,
  Turn,
  TurnType,
  FixedQuestion,
  ChatbotSessionState,
  ChatbotTimerConfig,
  TimeOfDay,
} from '../../shared/types'
import { db } from '../store/db'
import { geminiClient, modelName, geminiEnabled } from './gemini'

const nowIso = () => new Date().toISOString()
const at = (iso: string) => Date.parse(iso)

/* ─── question brevity guard (§4) ───────────────────────────────────────── */

const QUESTION_WORD_CAP = 55 // whole message: a short acknowledgment + one ≤40-word question
const countWords = (s: string) => (s.trim().match(/\S+/g) ?? []).length
/** More than one question mark reads as a compound / multi-part question. */
const isMultiPart = (s: string) => (s.match(/\?/g) ?? []).length > 1
const tooLong = (s: string) => countWords(s) > QUESTION_WORD_CAP || isMultiPart(s)

/** Last-resort trim to a single clean question when regeneration still over-runs. */
function trimToSingleQuestion(msg: string): string {
  const clean = msg.trim()
  const q = clean.indexOf('?')
  if (q !== -1) return clean.slice(0, q + 1).trim()
  const words = clean.split(/\s+/)
  return words.length > 40 ? words.slice(0, 40).join(' ').replace(/[,;:]$/, '') + '…' : clean
}

/**
 * Replace em/en dashes (—, –) with commas — a heavy dash style reads as
 * AI-written. Regular hyphens in words (follow-up, real-time) are left alone.
 */
export function humanizePunctuation(s: string): string {
  return (s ?? '')
    .replace(/\s*[—–]\s*/g, ', ')
    .replace(/,\s*,/g, ',')
    .replace(/,\s*([.!?])/g, '$1')
    .replace(/\s{2,}/g, ' ')
    .trim()
}

async function withRetry<T>(fn: () => Promise<T>, tries = 2): Promise<T> {
  let last: unknown
  for (let i = 0; i < tries; i++) {
    try { return await fn() } catch (e) { last = e; await new Promise((r) => setTimeout(r, 400 * (i + 1))) }
  }
  throw last
}

/* ─── config helpers ────────────────────────────────────────────────────── */

export function isTimed(template: InterviewTemplate): boolean {
  return template.mode === 'timed' && !!template.conversationTiming
}

/**
 * Resolve the chatbot timer config for a template. Explicit config always wins;
 * a CHAT-track template taken as a chatbot session (the candidate can switch
 * tracks on the entry screen) has no chatbot timer of its own, so it inherits
 * the template's fixed-slot TimingConfig — the recruiter's per-question answer
 * limit stays enforced and the countdown stays visible on the chatbot track.
 */
export function effectiveChatbotTimer(template: InterviewTemplate): ChatbotTimerConfig | undefined {
  if (template.chatbotTimer) return template.chatbotTimer
  if (template.track !== 'chat') return undefined
  const t = template.timing
  return {
    enabled: true,
    perQuestionSeconds: t.answerSeconds,
    timeFollowUps: true,
    includeThinkingPhase: false,
    warningThresholdSeconds: t.warningThresholdSeconds,
    allowEarlySubmit: t.allowEarlySubmit,
    autoSubmitOnExpiry: true,
  }
}

/** Does this interview time any question turns at all (legacy timed mode OR the
 *  conversational per-question timer overlay)? Drives the client timer machinery. */
export function timerEnabled(template: InterviewTemplate): boolean {
  return !!effectiveChatbotTimer(template)?.enabled || isTimed(template)
}

/** Effective timing for the ANSWERING window of a specific interviewer turn, or
 *  null when the turn is untimed (greeting/readiness/wrap-up) or timing is off.
 *  The chatbotTimer overlay wins when present+enabled; else the legacy timed
 *  mode's conversationTiming is used. Only question / follow-up turns are timed. */
export interface EffectiveTurnTiming {
  thinkingSeconds: number
  answerSeconds: number
  warningThresholdSeconds: number
  allowSkipThinking: boolean
  allowEarlySubmit: boolean
  autoSubmitOnExpiry: boolean
}
function isQuestionTurn(turn: Turn): boolean {
  if (turn.turnType) return turn.turnType === 'question' || turn.turnType === 'follow_up'
  // Legacy turns (pre-turnType): any turn tied to a primary question is timed.
  return typeof turn.questionIndex === 'number'
}
export function turnTiming(template: InterviewTemplate, turn: Turn): EffectiveTurnTiming | null {
  if (!timerEnabled(template) || !isQuestionTurn(turn)) return null
  const isFollowUp = turn.turnType === 'follow_up' || (!turn.turnType && !!turn.isFollowUp)

  const c = effectiveChatbotTimer(template)
  if (c?.enabled) {
    if (isFollowUp && !c.timeFollowUps) return null
    const override =
      template.questionSource === 'fixed' && typeof turn.questionIndex === 'number'
        ? c.perQuestionOverrides?.[fixedQuestions(template)[turn.questionIndex]?.id ?? '']
        : undefined
    const answerSeconds = override ?? (isFollowUp ? c.followUpSeconds ?? c.perQuestionSeconds : c.perQuestionSeconds)
    return {
      thinkingSeconds: c.includeThinkingPhase ? c.thinkingSeconds ?? 0 : 0,
      answerSeconds,
      warningThresholdSeconds: c.warningThresholdSeconds,
      allowSkipThinking: c.includeThinkingPhase,
      allowEarlySubmit: c.allowEarlySubmit,
      autoSubmitOnExpiry: c.autoSubmitOnExpiry,
    }
  }

  // Legacy timed mode.
  const ct = template.conversationTiming!
  return {
    thinkingSeconds: ct.thinkingSeconds,
    answerSeconds: ct.perQuestionSeconds,
    warningThresholdSeconds: ct.warningThresholdSeconds,
    allowSkipThinking: ct.allowSkipThinking,
    allowEarlySubmit: ct.allowEarlySubmit,
    autoSubmitOnExpiry: true,
  }
}

function fixedQuestions(template: InterviewTemplate): FixedQuestion[] {
  const set = template.fixedQuestionSetId ? db.questionSets.get(template.fixedQuestionSetId) : undefined
  return set?.questions ?? []
}

export function plannedCountFor(template: InterviewTemplate): number {
  if (template.questionSource === 'fixed') return fixedQuestions(template).length
  return template.adaptive?.numberOfQuestions ?? template.timing.numberOfQuestions ?? 5
}

function appendInterviewer(
  session: InterviewSession,
  template: InterviewTemplate,
  content: string,
  turnType: TurnType,
  questionIndex: number | undefined,
  isFollowUp: boolean,
) {
  // Timed clocks are NOT armed here. They start only once the client has
  // finished the "Thinking…" indicator and presented the question (see
  // revealTimedTurn / the question_presented event), so the indicator and any
  // acknowledgment prefix never eat into a timer.
  const turn: Turn = { id: randomUUID(), role: 'interviewer', content, turnType, questionIndex, isFollowUp, createdAt: nowIso() }
  ;(session.transcript ??= []).push(turn)
}

/**
 * Arm the answer/thinking clock for the current (unanswered) interviewer turn —
 * called when the client presents the question (the `question_presented` event).
 * Idempotent; only the first call starts the clock; no-op for untimed turns.
 * Returns true if it armed something.
 */
export function revealTimedTurn(
  session: InterviewSession,
  template: InterviewTemplate,
  nowMs: number = Date.now(),
): boolean {
  if (session.status !== 'in_progress') return false
  const turn = currentInterviewerTurn(session)
  if (!turn) return false
  const t = turnTiming(template, turn)
  if (!t) return false // untimed turn or timing disabled
  if (turn.thinkingStartedAt || turn.answerStartedAt) return false // already presented
  const iso = new Date(nowMs).toISOString()
  if (t.thinkingSeconds > 0) turn.thinkingStartedAt = iso
  else turn.answerStartedAt = iso
  return true
}

function endConversation(session: InterviewSession, closing?: string) {
  if (closing?.trim()) {
    ;(session.transcript ??= []).push({ id: randomUUID(), role: 'interviewer', content: closing.trim(), turnType: 'wrap_up', createdAt: nowIso() })
  }
  session.status = 'completed'
  session.completedAt = nowIso()
}

/* ─── offline fallbacks (no Gemini key / error) ─────────────────────────── */

const GENERIC = [
  'Tell me about a project you’re especially proud of and your specific contribution.',
  'Describe a difficult technical problem you solved recently. How did you approach it?',
  'How do you handle disagreement with a teammate about a technical decision?',
  'What part of your experience is most relevant to this role, and why?',
  'Where do you want to grow over the next couple of years?',
  'Tell me about a time you had to learn something new quickly.',
]
const greetingWord = (tod?: TimeOfDay) =>
  tod === 'morning' ? 'Good morning' : tod === 'afternoon' ? 'Good afternoon' : tod === 'evening' ? 'Good evening' : 'Hello'
/** Opening greeting + welcome that ENDS by asking if the candidate is ready — the
 *  first real question is only asked after they respond (readiness gate). */
const readinessMessage = (_t: InterviewTemplate, tod?: TimeOfDay, name?: string) =>
  `${greetingWord(tod)}${name ? `, ${name}` : ''}! Thanks so much for joining. I'm really looking forward to our chat. ` +
  `We'll keep this relaxed. I'll ask a few questions, one at a time, so take your time with each one. ` +
  `Whenever you're set, just let me know. Are you ready to begin?`
const fallbackFirstQuestion = (t: InterviewTemplate) =>
  `Great, let's dive in. To start, tell me a bit about your background and what drew you to the ${t.role || 'this'} role.`
const genericPrimary = (idx: number) => GENERIC[idx % GENERIC.length]

/* ─── guaranteed per-answer positive acknowledgment ─────────────────────── */

/** Always-positive, motivating openers. Rotated by a seed so they don't repeat. */
const MOTIVATIONS = [
  'Excellent answer!',
  "Great, that's really well explained!",
  'Love that, thank you for sharing!',
  "Nice, that's a strong response!",
  'Awesome, I really appreciate the detail!',
  'Perfect, that paints a clear picture!',
  'Brilliant, thank you for that!',
  "Wonderful, that's really helpful!",
]
/** Gentle, still-positive transitions for when no answer text was captured. */
const SOFT_TRANSITIONS = [
  "No problem at all, let's keep going.",
  "That's alright, let's move on to the next one.",
  "No worries, here's the next question.",
]
/** Fallback positive acknowledgment (rotated by seed) when no answer-specific
 *  one is available — e.g. Gemini is off or returned an empty acknowledgment. */
function fallbackAck(seed: number): string {
  return MOTIVATIONS[Math.abs(seed) % MOTIVATIONS.length]
}

/**
 * Append a standalone acknowledgment bubble (when present) followed by the
 * question bubble, so the client reveals them as TWO separate turns, each behind
 * its own "Thinking…" beat. The acknowledgment carries no questionIndex, so it
 * is never scored and never arms a timer.
 */
function appendAckThenQuestion(
  session: InterviewSession,
  template: InterviewTemplate,
  ack: string,
  questionText: string,
  questionIndex: number,
  isFollowUp: boolean,
) {
  const a = (ack ?? '').trim()
  if (a) appendInterviewer(session, template, a, 'acknowledgment', undefined, false)
  appendInterviewer(session, template, questionText, isFollowUp ? 'follow_up' : 'question', questionIndex, isFollowUp)
}

/** Strip wrapping quotes / stray markdown, and guarantee terminal punctuation so
 *  the acknowledgment joins cleanly to the question that follows it. */
function cleanAck(s: string): string {
  const t = humanizePunctuation((s ?? '').replace(/[*`]/g, '').replace(/^["'\s]+|["'\s]+$/g, '').trim())
  if (!t) return ''
  return /[.!?]$/.test(t) ? t : `${t}.`
}

/**
 * Produce ONE short, warm, ALWAYS-POSITIVE sentence acknowledging the
 * candidate's latest answer — specific to what they said when Gemini is
 * available — used to prefix the next fixed question so every answer earns a
 * motivating beat. Falls back to a rotating motivating phrase when Gemini is
 * off or errors, and to a gentle transition when no answer text was captured.
 */
async function positiveAcknowledgment(question: string, answer: string, seed: number): Promise<string> {
  const ans = (answer ?? '').trim()
  if (!ans) return SOFT_TRANSITIONS[Math.abs(seed) % SOFT_TRANSITIONS.length]
  const fallback = MOTIVATIONS[Math.abs(seed) % MOTIVATIONS.length]
  if (!geminiEnabled()) return fallback
  try {
    const res = await withRetry(() =>
      geminiClient().models.generateContent({
        model: modelName(),
        contents:
          `The interviewer asked: "${question}"\n` +
          `The candidate answered: "${ans.slice(0, 2000)}"\n\n` +
          `Write ONE short sentence (max 16 words) that warmly and specifically acknowledges the candidate's answer and encourages them, e.g. "Excellent, that's a really thoughtful approach!". ` +
          `It will be shown immediately before the next question, so keep it upbeat and forward-moving. ` +
          `ALWAYS stay positive and motivating no matter the quality of the answer: never critical, never neutral, never lukewarm. ` +
          `Plain text only: no markdown, no surrounding quotes, and no em dashes or en dashes.`,
      }),
    )
    return cleanAck(res.text ?? '') || fallback
  } catch {
    return fallback
  }
}

/* ─── adaptive turn generation (Gemini) ─────────────────────────────────── */

interface TurnDecision { acknowledgment: string; message: string; action: 'next_question' | 'follow_up' | 'end_interview' }

async function generateAdaptiveTurn(session: InterviewSession, template: InterviewTemplate): Promise<TurnDecision> {
  const a = template.adaptive!
  const transcript = session.transcript ?? []
  // Three phases: the opening greeting/readiness prompt (empty transcript); the
  // FIRST real question (the candidate has just confirmed readiness, but no
  // question with a questionIndex has been asked yet); then the normal flow.
  const isGreeting = transcript.length === 0
  const askedAny = transcript.some((t) => t.role === 'interviewer' && typeof t.questionIndex === 'number')
  const isFirstQuestion = !isGreeting && !askedAny
  const followBudget = a.maxFollowUpsPerQuestion - (session.followUpsThisQuestion ?? 0)
  const primariesLeft = (session.plannedQuestionCount ?? a.numberOfQuestions) - ((session.currentIndex ?? 0) + 1)
  const resume = (session.resumeText ?? '').slice(0, 14000)
  const name = session.candidate?.name && session.candidate.name !== 'Candidate' ? session.candidate.name : ''

  const style = a.style ?? 'mix'
  const techN = a.technicalCount ?? Math.ceil(a.numberOfQuestions / 2)
  const nonTechN = a.nonTechnicalCount ?? Math.floor(a.numberOfQuestions / 2)
  const styleLine =
    style === 'technical'
      ? 'Ask ONLY technical questions, grounded in the specific technologies, tools, and projects in the résumé.'
      : style === 'non_technical'
        ? 'Ask ONLY non-technical questions (behavioral, situational, culture-fit), grounded in the candidate’s experience.'
        : `Ask a MIX of technical and non-technical questions (about ${techN} technical and ${nonTechN} non-technical across the whole interview).`

  // The acknowledgment and the next question are returned as SEPARATE fields so
  // the client can show them as two distinct bubbles (each behind its own
  // "Thinking…" beat). Keep them apart: the "message" field is the question ONLY.
  const ackLine =
    `After EVERY answer you MUST fill the "acknowledgment" field with ONE short, warm, GENUINE sentence that positively acknowledges and encourages the candidate about what they just said (make it specific to their answer when you can), and put ONLY the next question in the "message" field. ALWAYS keep the acknowledgment positive and motivating, never critical or lukewarm, even if the answer was weak. Vary it every single time and never reuse a phrase (e.g. "Excellent, that's a really thoughtful answer!", "Great, I love that example!", "Nice, that's a strong response!", "Perfect, that paints a clear picture!"). Never leave the acknowledgment empty on an answer, and never put the acknowledgment inside "message".`

  const system = [
    `You are ${a.interviewerTone ? a.interviewerTone : 'a warm, personable senior'} interviewer running a live ${a.difficulty} interview for a ${a.seniority ? a.seniority + ' ' : ''}${a.role} role${a.language ? `, conducted in ${a.language}` : ''}.`,
    `Speak naturally, the way a friendly human would: use contractions, vary your phrasing, and sound genuinely engaged and encouraging. Never sound robotic, templated, corporate, or repetitive. Keep a natural human rhythm; don't over-explain or lecture.`,
    `Write with plain punctuation only. Do NOT use em dashes or en dashes ("—" or "–") anywhere; use commas, periods, or the word "and" instead. Dash-heavy writing reads as AI-generated.`,
    `You have the candidate's résumé and the conversation so far.`,
    styleLine,
    a.focusTopics?.length ? `Emphasize these topics when relevant: ${a.focusTopics.join(', ')}.` : '',
    `Ask EXACTLY ONE question per message — never compound or multi-part. Keep each question SHORT: at most 3 lines (~40 words), conversational, and grounded in the résumé and role.`,
    `Never reveal upcoming questions, the plan, or how many remain.`,
    isGreeting
      ? `This is your OPENING message — do NOT ask any interview question yet. Give a short "${greetingWord(session.greetingTimeOfDay)}" greeting, warmly welcome the candidate${name ? ` by name (${name})` : ''}, add a one-line note to put them at ease about how this will go, and then ASK WHETHER THEY'RE READY TO BEGIN. Put all of that in "message" and leave "acknowledgment" empty. End with that readiness question. Use action "next_question".`
      : isFirstQuestion
        ? `The candidate has just confirmed they're ready. Do NOT treat their reply as an interview answer and do NOT acknowledge it like one, so leave "acknowledgment" empty. If they seemed hesitant, reassure them warmly in one short line. Then ask your FIRST interview question (in "message"), grounded in the résumé and role. Use action "next_question".`
        : ackLine,
    isGreeting || isFirstQuestion
      ? ''
      : `Then decide: ask a sharp FOLLOW-UP that drills into the previous answer, or move to the NEXT primary question.`,
    isGreeting || isFirstQuestion
      ? ''
      : `Budget — follow-ups left for the current question: ${Math.max(0, followBudget)}; primary questions left after this one: ${Math.max(0, primariesLeft)}. If follow-ups left is 0, do not follow up. You MUST NOT use "end_interview" while any primary questions remain — keep going until primary questions left reaches 0, then close warmly with "end_interview".`,
    !a.allowFollowUps ? 'Follow-ups are DISABLED — always use "next_question" or "end_interview".' : '',
  ].filter(Boolean).join('\n')

  const contents: { role: 'user' | 'model'; parts: { text: string }[] }[] = []
  if (isGreeting) {
    contents.push({ role: 'user', parts: [{ text: `CANDIDATE RÉSUMÉ:\n"""${resume}"""\n\nGreet the candidate and ask if they're ready to begin.` }] })
  } else {
    contents.push({ role: 'user', parts: [{ text: `CANDIDATE RÉSUMÉ (context):\n"""${resume}"""` }] })
    for (const t of transcript) {
      contents.push({ role: t.role === 'interviewer' ? 'model' : 'user', parts: [{ text: t.content }] })
    }
  }

  const callModel = async (extra?: string): Promise<TurnDecision> => {
    const res = await withRetry(() =>
      geminiClient().models.generateContent({
        model: modelName(),
        contents,
        config: {
          systemInstruction: extra ? `${system}\n${extra}` : system,
          responseMimeType: 'application/json',
          responseSchema: {
            type: Type.OBJECT,
            properties: {
              acknowledgment: { type: Type.STRING },
              message: { type: Type.STRING },
              action: { type: Type.STRING, enum: ['next_question', 'follow_up', 'end_interview'] },
            },
            required: ['message', 'action'],
          },
        },
      }),
    )
    const parsed = JSON.parse(res.text ?? '{}') as Partial<TurnDecision>
    return {
      acknowledgment: cleanAck(parsed.acknowledgment ?? ''),
      message: humanizePunctuation(parsed.message?.trim() || 'Thanks, could you tell me a little more about that?'),
      action: (parsed.action as TurnDecision['action']) || 'next_question',
    }
  }

  let decision = await callModel()

  // Brevity guard (§4): the greeting legitimately carries a welcome + readiness
  // prompt, and a closing needs no brevity — only police actual questions.
  // Regenerate once, then trim as a last resort.
  if (!isGreeting && decision.action !== 'end_interview' && tooLong(decision.message)) {
    try {
      decision = await callModel(
        'IMPORTANT: your previous "message" was too long or multi-part. Reply again with the acknowledgment in "acknowledgment" and EXACTLY ONE single-focus question of at most 40 words in "message". No compound questions.',
      )
    } catch { /* keep the first decision, trimmed below */ }
    if (tooLong(decision.message)) decision.message = trimToSingleQuestion(decision.message)
  }
  return decision
}

/* ─── public engine ─────────────────────────────────────────────────────── */

/** Initialise a chatbot session and produce the first interviewer turn. */
export async function beginConversation(
  session: InterviewSession,
  template: InterviewTemplate,
  opts?: { timeOfDay?: TimeOfDay },
): Promise<void> {
  session.transcript = []
  session.currentIndex = 0
  session.followUpsThisQuestion = 0
  session.mode = template.mode ?? 'conversational'
  session.plannedQuestionCount = plannedCountFor(template)
  if (opts?.timeOfDay) session.greetingTimeOfDay = opts.timeOfDay
  session.status = 'in_progress'
  session.startedAt = nowIso()

  const name = session.candidate?.name && session.candidate.name !== 'Candidate' ? session.candidate.name : undefined

  // The FIRST interviewer turn is a greeting + welcome that ends by asking if
  // the candidate is ready — NOT the first question. It has no questionIndex, so
  // it is never scored and (in timed mode) never arms a clock. The first real
  // question is produced once the candidate replies (see submitChatAnswer).
  let message: string
  if (template.questionSource === 'adaptive' && !session.resumeText) {
    throw new Error('A résumé is required before starting this interview')
  }
  if (template.questionSource === 'adaptive' && geminiEnabled()) {
    try {
      message = (await generateAdaptiveTurn(session, template)).message
    } catch {
      message = readinessMessage(template, session.greetingTimeOfDay, name)
    }
  } else {
    // Fixed source, or adaptive without Gemini: a static, time-aware greeting.
    message = readinessMessage(template, session.greetingTimeOfDay, name)
  }
  appendInterviewer(session, template, message, 'greeting', undefined, false)
}

/** Record the candidate's answer to the current turn and produce the next turn. */
export async function submitChatAnswer(
  session: InterviewSession,
  template: InterviewTemplate,
  answerText: string,
  autoAdvanced = false,
): Promise<void> {
  const transcript = (session.transcript ??= [])
  const lastInterviewer = [...transcript].reverse().find((t) => t.role === 'interviewer')

  // Readiness gate: the current interviewer turn is the opening greeting (no
  // questionIndex). The candidate's reply is a "yes, I'm ready" — not a scored
  // answer — so tag it with no questionIndex, then ask the FIRST real question.
  const isReadinessReply = !!lastInterviewer && typeof lastInterviewer.questionIndex !== 'number'

  transcript.push({
    id: randomUUID(),
    role: 'candidate',
    content: (answerText ?? '').trim(),
    questionIndex: isReadinessReply ? undefined : (lastInterviewer?.questionIndex ?? session.currentIndex),
    isFollowUp: isReadinessReply ? undefined : lastInterviewer?.isFollowUp,
    createdAt: nowIso(),
  })
  if (lastInterviewer) {
    lastInterviewer.submittedAt = nowIso()
    if (autoAdvanced) lastInterviewer.autoAdvanced = true
  }

  if (isReadinessReply) {
    // Start the interview: emit the first real question at index 0. No scoring,
    // no advance, no early end — this is the beginning of the actual Q&A.
    session.currentIndex = 0
    session.followUpsThisQuestion = 0
    let firstMsg: string
    if (template.questionSource === 'fixed') {
      const qs = fixedQuestions(template)
      if (qs.length === 0) return endConversation(session, 'Thanks for your time. We’ll be in touch!')
      firstMsg = qs[0].text
    } else {
      try {
        firstMsg = geminiEnabled()
          ? (await generateAdaptiveTurn(session, template)).message
          : fallbackFirstQuestion(template)
      } catch {
        firstMsg = fallbackFirstQuestion(template)
      }
    }
    appendInterviewer(session, template, firstMsg, 'question', 0, false)
    return
  }

  const plannedCount = session.plannedQuestionCount ?? plannedCountFor(template)
  const atLastPrimary = (session.currentIndex ?? 0) >= plannedCount - 1

  // Fixed source: deterministic walk, no follow-ups (v1). Every answer still
  // earns a positive, answer-aware acknowledgment before the next question.
  if (template.questionSource === 'fixed') {
    const qs = fixedQuestions(template)
    const nextIdx = (session.currentIndex ?? 0) + 1
    const ack = await positiveAcknowledgment(lastInterviewer?.content ?? '', answerText, transcript.length)
    if (nextIdx >= qs.length) {
      // Last answer: the "All done" screen replaces the transcript, so a separate
      // acknowledgment bubble wouldn't be seen — fold it into the closing line.
      return endConversation(session, `${ack} That’s all the questions I had. Thank you for your time!`)
    }
    session.currentIndex = nextIdx
    session.followUpsThisQuestion = 0
    appendAckThenQuestion(session, template, ack, qs[nextIdx].text, nextIdx, false)
    return
  }

  // Adaptive: let Gemini decide, then clamp to server-side limits.
  const a = template.adaptive!
  let decision: TurnDecision
  const fallbackDecision = (): TurnDecision => ({
    acknowledgment: atLastPrimary ? '' : fallbackAck((session.transcript?.length ?? 0)),
    message: atLastPrimary ? '' : genericPrimary((session.currentIndex ?? 0) + 1),
    action: atLastPrimary ? 'end_interview' : 'next_question',
  })
  try {
    decision = geminiEnabled() ? await generateAdaptiveTurn(session, template) : fallbackDecision()
  } catch {
    decision = fallbackDecision()
  }

  const followBudgetLeft = a.allowFollowUps && (session.followUpsThisQuestion ?? 0) < a.maxFollowUpsPerQuestion

  // Server-enforced clamps: never end before every primary question is asked,
  // and never exceed the follow-up budget.
  let action = decision.action
  if (action === 'end_interview' && !atLastPrimary) action = 'next_question'
  if (action === 'follow_up' && !followBudgetLeft) action = 'next_question'

  if (action === 'end_interview') {
    return endConversation(session, decision.message || 'Thank you, that concludes our interview.')
  }

  // Every post-answer turn earns a positive acknowledgment bubble of its own,
  // then the question bubble — revealed as two separate "Thinking…" beats.
  const ackText = (decision.acknowledgment || '').trim() || fallbackAck(transcript.length)

  if (action === 'follow_up') {
    session.followUpsThisQuestion = (session.followUpsThisQuestion ?? 0) + 1
    appendAckThenQuestion(session, template, ackText, decision.message || 'Could you go a little deeper on that?', session.currentIndex ?? 0, true)
    return
  }

  // next_question
  if (atLastPrimary) return endConversation(session, 'Thank you, that concludes our interview.')
  const nextIdx = (session.currentIndex ?? 0) + 1
  session.currentIndex = nextIdx
  session.followUpsThisQuestion = 0
  // If the model handed us a closing line while questions remain, use a real question.
  const looksClosing = /thank you|concludes|all the questions|that'?s all/i.test(decision.message || '')
  const msg = decision.message && !looksClosing ? decision.message : genericPrimary(nextIdx)
  appendAckThenQuestion(session, template, ackText, msg, nextIdx, false)
}

/* ─── timed-mode server-authoritative advancement ───────────────────────── */

/**
 * Progress timed phases that have elapsed. Returns 'answer_expired' when the
 * answer window is up and the caller must auto-submit the current draft.
 * Thinking→answer transitions are handled here (cheap, synchronous).
 */
export function advanceChatbotTiming(
  session: InterviewSession,
  template: InterviewTemplate,
  nowMs: number = Date.now(),
): 'none' | 'answer_expired' {
  if (session.status !== 'in_progress') return 'none'
  const turn = currentInterviewerTurn(session)
  if (!turn) return 'none'
  const t = turnTiming(template, turn)
  if (!t) return 'none' // untimed turn (greeting/readiness/wrap-up) or timing off

  if (turn.thinkingStartedAt && !turn.answerStartedAt) {
    const deadline = at(turn.thinkingStartedAt) + t.thinkingSeconds * 1000
    if (nowMs >= deadline) turn.answerStartedAt = new Date(deadline).toISOString()
    else return 'none'
  }
  if (turn.answerStartedAt) {
    const deadline = at(turn.answerStartedAt) + t.answerSeconds * 1000
    if (nowMs >= deadline) return t.autoSubmitOnExpiry ? 'answer_expired' : 'none'
  }
  return 'none'
}

/** Candidate can end the thinking sub-timer early and start answering now. */
export function skipThinking(session: InterviewSession, template: InterviewTemplate): boolean {
  const turn = currentInterviewerTurn(session)
  if (!turn) return false
  const t = turnTiming(template, turn)
  if (!t || !t.allowSkipThinking) return false
  if (turn.submittedAt || turn.answerStartedAt || !turn.thinkingStartedAt) return false
  turn.answerStartedAt = nowIso()
  return true
}

/* ─── client-safe state view ────────────────────────────────────────────── */

export function currentInterviewerTurn(session: InterviewSession): Turn | undefined {
  return [...(session.transcript ?? [])].reverse().find((t) => t.role === 'interviewer' && !t.submittedAt)
}

/** Group the transcript by primary question for scoring / the recruiter report. */
export function primaryQuestionGroups(
  session: InterviewSession,
): { index: number; question: string; answer: string; autoAdvanced: boolean }[] {
  const turns = session.transcript ?? []
  const map = new Map<number, { question: string; answers: string[]; autoAdvanced: boolean }>()
  let lastIndex: number | undefined
  for (const t of turns) {
    if (t.role === 'interviewer' && typeof t.questionIndex === 'number') {
      lastIndex = t.questionIndex
      if (!t.isFollowUp && !map.has(t.questionIndex)) map.set(t.questionIndex, { question: t.content, answers: [], autoAdvanced: false })
      else if (!map.has(t.questionIndex)) map.set(t.questionIndex, { question: t.content, answers: [], autoAdvanced: false })
    } else if (t.role === 'candidate') {
      const qi = typeof t.questionIndex === 'number' ? t.questionIndex : lastIndex
      if (typeof qi === 'number') {
        if (!map.has(qi)) map.set(qi, { question: '', answers: [], autoAdvanced: false })
        if (t.content.trim()) map.get(qi)!.answers.push(t.content.trim())
        if (t.autoAdvanced) map.get(qi)!.autoAdvanced = true
      }
    }
  }
  return [...map.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([index, v]) => ({ index, question: v.question, answer: v.answers.join('\n\n'), autoAdvanced: v.autoAdvanced }))
}

export function computeChatbotState(
  session: InterviewSession,
  template: InterviewTemplate,
  nowMs: number = Date.now(),
): ChatbotSessionState {
  const transcript = session.transcript ?? []
  const awaiting = session.status === 'in_progress' ? currentInterviewerTurn(session) : undefined
  // Effective timing for the CURRENT turn — null on untimed turns (greeting, etc.).
  const t = awaiting ? turnTiming(template, awaiting) : null

  let phase: 'thinking' | 'answer' | null = null
  let remaining = 0
  let total = 0
  if (t && awaiting) {
    if (awaiting.answerStartedAt) {
      phase = 'answer'; total = t.answerSeconds
      remaining = total - (nowMs - at(awaiting.answerStartedAt)) / 1000
    } else if (awaiting.thinkingStartedAt) {
      phase = 'thinking'; total = t.thinkingSeconds
      remaining = total - (nowMs - at(awaiting.thinkingStartedAt)) / 1000
    }
    // else: timed turn not yet presented → phase null, but currentTurnTimed true.
  }

  const totalQ = session.plannedQuestionCount ?? plannedCountFor(template)
  return {
    sessionId: session.id,
    status: session.status,
    track: session.track,
    transcript: transcript.map((tt) => ({
      id: tt.id, role: tt.role, content: tt.content, turnType: tt.turnType, questionIndex: tt.questionIndex, isFollowUp: tt.isFollowUp,
    })),
    awaitingInterviewer: false,
    finished: session.status === 'completed' || session.status === 'expired',
    phase,
    remainingSeconds: Math.max(0, Math.ceil(remaining)),
    totalPhaseSeconds: total,
    currentTurnTimed: !!t,
    currentTurnId: awaiting?.id ?? null,
    progress: { current: Math.min((session.currentIndex ?? 0) + 1, totalQ || 1), total: totalQ },
    draft: awaiting?.draft ?? '',
    timing: {
      mode: session.mode ?? template.mode ?? 'conversational',
      enabled: timerEnabled(template),
      thinkingSeconds: t?.thinkingSeconds ?? 0,
      perQuestionSeconds: t?.answerSeconds ?? 0,
      allowSkipThinking: t?.allowSkipThinking ?? false,
      allowEarlySubmit: t?.allowEarlySubmit ?? true,
      warningThresholdSeconds: t?.warningThresholdSeconds ?? 15,
    },
    branding: template.branding,
    integrity: template.integrity,
    tabSwitchWarnings: session.tabSwitchCount,
    awaitingResume: template.questionSource === 'adaptive' && !session.resumeText,
  }
}
