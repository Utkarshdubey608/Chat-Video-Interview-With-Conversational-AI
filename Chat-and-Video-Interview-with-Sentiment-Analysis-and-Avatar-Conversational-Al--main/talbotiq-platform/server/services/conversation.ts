import { randomUUID } from 'node:crypto'
import { Type } from '@google/genai'
import type {
  InterviewSession,
  InterviewTemplate,
  Turn,
  FixedQuestion,
  ChatbotSessionState,
} from '../../shared/types'
import { db } from '../store/db'
import { geminiClient, modelName, geminiEnabled } from './gemini'

const nowIso = () => new Date().toISOString()
const at = (iso: string) => Date.parse(iso)

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

function fixedQuestions(template: InterviewTemplate): FixedQuestion[] {
  const set = template.fixedQuestionSetId ? db.questionSets.get(template.fixedQuestionSetId) : undefined
  return set?.questions ?? []
}

export function plannedCountFor(template: InterviewTemplate): number {
  if (template.questionSource === 'fixed') return fixedQuestions(template).length
  return template.adaptive?.numberOfQuestions ?? template.timing.numberOfQuestions ?? 5
}

/** Attach timed-mode start timestamps to a freshly-appended interviewer turn. */
function armTimed(turn: Turn, template: InterviewTemplate) {
  if (!isTimed(template)) return
  const t = template.conversationTiming!
  if (t.thinkingSeconds > 0) turn.thinkingStartedAt = nowIso()
  else turn.answerStartedAt = nowIso()
}

function appendInterviewer(
  session: InterviewSession,
  template: InterviewTemplate,
  content: string,
  questionIndex: number | undefined,
  isFollowUp: boolean,
) {
  const turn: Turn = { id: randomUUID(), role: 'interviewer', content, questionIndex, isFollowUp, createdAt: nowIso() }
  if (typeof questionIndex === 'number') armTimed(turn, template)
  ;(session.transcript ??= []).push(turn)
}

function endConversation(session: InterviewSession, closing?: string) {
  if (closing?.trim()) {
    ;(session.transcript ??= []).push({ id: randomUUID(), role: 'interviewer', content: closing.trim(), createdAt: nowIso() })
  }
  session.status = 'completed'
  session.completedAt = nowIso()
}

/* ─── offline fallbacks (no Gemini key / error) ─────────────────────────── */

const GENERIC = [
  'Tell me about a project you’re especially proud of and your specific contribution.',
  'Describe a difficult technical problem you solved recently — how did you approach it?',
  'How do you handle disagreement with a teammate about a technical decision?',
  'What part of your experience is most relevant to this role, and why?',
  'Where do you want to grow over the next couple of years?',
  'Tell me about a time you had to learn something new quickly.',
]
const fallbackFirst = (t: InterviewTemplate) =>
  `Hi, thanks for joining! To start, tell me about your background and what drew you to the ${t.role || 'this'} role.`
const genericPrimary = (idx: number) => GENERIC[idx % GENERIC.length]

/* ─── adaptive turn generation (Gemini) ─────────────────────────────────── */

interface TurnDecision { message: string; action: 'next_question' | 'follow_up' | 'end_interview' }

async function generateAdaptiveTurn(session: InterviewSession, template: InterviewTemplate): Promise<TurnDecision> {
  const a = template.adaptive!
  const transcript = session.transcript ?? []
  const isFirst = transcript.length === 0
  const followBudget = a.maxFollowUpsPerQuestion - (session.followUpsThisQuestion ?? 0)
  const primariesLeft = (session.plannedQuestionCount ?? a.numberOfQuestions) - ((session.currentIndex ?? 0) + 1)
  const resume = (session.resumeText ?? '').slice(0, 14000)

  const style = a.style ?? 'mix'
  const techN = a.technicalCount ?? Math.ceil(a.numberOfQuestions / 2)
  const nonTechN = a.nonTechnicalCount ?? Math.floor(a.numberOfQuestions / 2)
  const styleLine =
    style === 'technical'
      ? 'Ask ONLY technical questions, grounded in the specific technologies, tools, and projects in the résumé.'
      : style === 'non_technical'
        ? 'Ask ONLY non-technical questions (behavioral, situational, culture-fit), grounded in the candidate’s experience.'
        : `Ask a MIX of technical and non-technical questions (about ${techN} technical and ${nonTechN} non-technical across the whole interview).`

  const system = [
    `You are ${a.interviewerTone ? a.interviewerTone : 'a warm, professional'} interviewer running a ${a.difficulty} interview for a ${a.seniority ? a.seniority + ' ' : ''}${a.role} role${a.language ? `, conducted in ${a.language}` : ''}.`,
    `You have the candidate's résumé and the conversation so far. Ask ONE question per message, grounded in the résumé and role.`,
    styleLine,
    a.focusTopics?.length ? `Emphasize these topics when relevant: ${a.focusTopics.join(', ')}.` : '',
    `Briefly acknowledge the candidate's previous answer, then either ask a sharp FOLLOW-UP that drills into it or move to the NEXT primary question. 1–3 sentences per message. Natural and conversational, but professional.`,
    `Never reveal upcoming questions, the plan, or how many remain. Never ask more than one question at a time.`,
    isFirst
      ? `This is the FIRST message: greet the candidate briefly and ask the first primary question. Use action "next_question".`
      : `Budget — follow-ups left for the current question: ${Math.max(0, followBudget)}; primary questions left after this one: ${Math.max(0, primariesLeft)}. If follow-ups left is 0, do not follow up. You MUST NOT use "end_interview" while any primary questions remain — keep going until primary questions left reaches 0, then close warmly with "end_interview".`,
    !a.allowFollowUps ? 'Follow-ups are DISABLED — always use "next_question" or "end_interview".' : '',
  ].filter(Boolean).join('\n')

  const contents: { role: 'user' | 'model'; parts: { text: string }[] }[] = []
  if (isFirst) {
    contents.push({ role: 'user', parts: [{ text: `CANDIDATE RÉSUMÉ:\n"""${resume}"""\n\nBegin the interview now.` }] })
  } else {
    contents.push({ role: 'user', parts: [{ text: `CANDIDATE RÉSUMÉ (context):\n"""${resume}"""` }] })
    for (const t of transcript) {
      contents.push({ role: t.role === 'interviewer' ? 'model' : 'user', parts: [{ text: t.content }] })
    }
  }

  const res = await withRetry(() =>
    geminiClient().models.generateContent({
      model: modelName(),
      contents,
      config: {
        systemInstruction: system,
        responseMimeType: 'application/json',
        responseSchema: {
          type: Type.OBJECT,
          properties: {
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
    message: parsed.message?.trim() || 'Thanks — could you tell me more about that?',
    action: (parsed.action as TurnDecision['action']) || 'next_question',
  }
}

/* ─── public engine ─────────────────────────────────────────────────────── */

/** Initialise a chatbot session and produce the first interviewer turn. */
export async function beginConversation(session: InterviewSession, template: InterviewTemplate): Promise<void> {
  session.transcript = []
  session.currentIndex = 0
  session.followUpsThisQuestion = 0
  session.mode = template.mode ?? 'conversational'
  session.plannedQuestionCount = plannedCountFor(template)
  session.status = 'in_progress'
  session.startedAt = nowIso()

  let message: string
  if (template.questionSource === 'fixed') {
    const qs = fixedQuestions(template)
    if (qs.length === 0) throw new Error('The template references an empty question set')
    message = qs[0].text
  } else {
    if (!session.resumeText) throw new Error('A résumé is required before starting this interview')
    try {
      message = geminiEnabled() ? (await generateAdaptiveTurn(session, template)).message : fallbackFirst(template)
    } catch {
      message = fallbackFirst(template)
    }
  }
  appendInterviewer(session, template, message, 0, false)
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

  transcript.push({
    id: randomUUID(),
    role: 'candidate',
    content: (answerText ?? '').trim(),
    questionIndex: lastInterviewer?.questionIndex ?? session.currentIndex,
    isFollowUp: lastInterviewer?.isFollowUp,
    createdAt: nowIso(),
  })
  if (lastInterviewer) {
    lastInterviewer.submittedAt = nowIso()
    if (autoAdvanced) lastInterviewer.autoAdvanced = true
  }

  const plannedCount = session.plannedQuestionCount ?? plannedCountFor(template)
  const atLastPrimary = (session.currentIndex ?? 0) >= plannedCount - 1

  // Fixed source: deterministic walk, no follow-ups (v1).
  if (template.questionSource === 'fixed') {
    const qs = fixedQuestions(template)
    const nextIdx = (session.currentIndex ?? 0) + 1
    if (nextIdx >= qs.length) return endConversation(session, 'That’s all the questions I had — thank you for your time!')
    session.currentIndex = nextIdx
    session.followUpsThisQuestion = 0
    appendInterviewer(session, template, qs[nextIdx].text, nextIdx, false)
    return
  }

  // Adaptive: let Gemini decide, then clamp to server-side limits.
  const a = template.adaptive!
  let decision: TurnDecision
  try {
    decision = geminiEnabled()
      ? await generateAdaptiveTurn(session, template)
      : { message: atLastPrimary ? '' : genericPrimary((session.currentIndex ?? 0) + 1), action: atLastPrimary ? 'end_interview' : 'next_question' }
  } catch {
    decision = { message: atLastPrimary ? '' : genericPrimary((session.currentIndex ?? 0) + 1), action: atLastPrimary ? 'end_interview' : 'next_question' }
  }

  const followBudgetLeft = a.allowFollowUps && (session.followUpsThisQuestion ?? 0) < a.maxFollowUpsPerQuestion

  // Server-enforced clamps: never end before every primary question is asked,
  // and never exceed the follow-up budget.
  let action = decision.action
  if (action === 'end_interview' && !atLastPrimary) action = 'next_question'
  if (action === 'follow_up' && !followBudgetLeft) action = 'next_question'

  if (action === 'end_interview') {
    return endConversation(session, decision.message || 'Thank you — that concludes our interview.')
  }
  if (action === 'follow_up') {
    session.followUpsThisQuestion = (session.followUpsThisQuestion ?? 0) + 1
    appendInterviewer(session, template, decision.message || 'Could you go a little deeper on that?', session.currentIndex ?? 0, true)
    return
  }

  // next_question
  if (atLastPrimary) return endConversation(session, 'Thank you — that concludes our interview.')
  const nextIdx = (session.currentIndex ?? 0) + 1
  session.currentIndex = nextIdx
  session.followUpsThisQuestion = 0
  // If the model handed us a closing line while questions remain, use a real question.
  const looksClosing = /thank you|concludes|all the questions|that'?s all/i.test(decision.message || '')
  const msg = decision.message && !looksClosing ? decision.message : genericPrimary(nextIdx)
  appendInterviewer(session, template, msg, nextIdx, false)
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
  if (session.status !== 'in_progress' || !isTimed(template)) return 'none'
  const ct = template.conversationTiming!
  const turn = [...(session.transcript ?? [])].reverse().find((t) => t.role === 'interviewer')
  if (!turn || turn.submittedAt || typeof turn.questionIndex !== 'number') return 'none'

  if (turn.thinkingStartedAt && !turn.answerStartedAt) {
    const deadline = at(turn.thinkingStartedAt) + ct.thinkingSeconds * 1000
    if (nowMs >= deadline) turn.answerStartedAt = new Date(deadline).toISOString()
    else return 'none'
  }
  if (turn.answerStartedAt) {
    const deadline = at(turn.answerStartedAt) + ct.perQuestionSeconds * 1000
    if (nowMs >= deadline) return 'answer_expired'
  }
  return 'none'
}

/** Candidate can end thinking early and start answering now. */
export function skipThinking(session: InterviewSession, template: InterviewTemplate): boolean {
  if (!isTimed(template) || !template.conversationTiming?.allowSkipThinking) return false
  const turn = [...(session.transcript ?? [])].reverse().find((t) => t.role === 'interviewer')
  if (!turn || turn.submittedAt || turn.answerStartedAt || !turn.thinkingStartedAt) return false
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
  const ct = template.conversationTiming
  const timed = isTimed(template)

  let phase: 'thinking' | 'answer' | null = null
  let remaining = 0
  let total = 0
  if (timed && ct && awaiting && typeof awaiting.questionIndex === 'number') {
    if (awaiting.answerStartedAt) {
      phase = 'answer'; total = ct.perQuestionSeconds
      remaining = total - (nowMs - at(awaiting.answerStartedAt)) / 1000
    } else if (awaiting.thinkingStartedAt) {
      phase = 'thinking'; total = ct.thinkingSeconds
      remaining = total - (nowMs - at(awaiting.thinkingStartedAt)) / 1000
    }
  }

  const totalQ = session.plannedQuestionCount ?? plannedCountFor(template)
  return {
    sessionId: session.id,
    status: session.status,
    track: session.track,
    transcript: transcript.map((t) => ({
      id: t.id, role: t.role, content: t.content, questionIndex: t.questionIndex, isFollowUp: t.isFollowUp,
    })),
    awaitingInterviewer: false,
    finished: session.status === 'completed' || session.status === 'expired',
    phase,
    remainingSeconds: Math.max(0, Math.ceil(remaining)),
    totalPhaseSeconds: total,
    currentTurnId: awaiting?.id ?? null,
    progress: { current: Math.min((session.currentIndex ?? 0) + 1, totalQ || 1), total: totalQ },
    draft: awaiting?.draft ?? '',
    timing: {
      mode: session.mode ?? template.mode ?? 'conversational',
      thinkingSeconds: ct?.thinkingSeconds ?? 0,
      perQuestionSeconds: ct?.perQuestionSeconds ?? 0,
      allowSkipThinking: ct?.allowSkipThinking ?? false,
      allowEarlySubmit: ct?.allowEarlySubmit ?? true,
      warningThresholdSeconds: ct?.warningThresholdSeconds ?? 15,
    },
    branding: template.branding,
    integrity: template.integrity,
    tabSwitchWarnings: session.tabSwitchCount,
    awaitingResume: template.questionSource === 'adaptive' && !session.resumeText,
  }
}
