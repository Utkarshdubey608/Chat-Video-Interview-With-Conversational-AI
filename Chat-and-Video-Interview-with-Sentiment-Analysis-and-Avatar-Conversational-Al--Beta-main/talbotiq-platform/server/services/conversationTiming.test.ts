/**
 * Deterministic unit tests for the conversational per-question timer gating.
 * Run with:  npx tsx server/services/conversationTiming.test.ts
 * No Gemini / network / db needed — we build templates + turns in-memory and
 * assert the pure timing functions. This is the machine-checkable version of
 * the spec's critical rule: only 'question' / 'follow_up' turns are ever timed,
 * the clock arms on presentation, and it expires server-authoritatively.
 */
import type { InterviewSession, InterviewTemplate, Turn, TurnType } from '../../shared/types'
import { turnTiming, revealTimedTurn, advanceChatbotTiming, timerEnabled } from './conversation'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

const T0 = Date.parse('2020-01-01T00:00:00.000Z')
const iso = (ms: number) => new Date(ms).toISOString()

function makeTemplate(overrides: Partial<InterviewTemplate> = {}): InterviewTemplate {
  return {
    id: 't1', name: 'T', role: 'Engineer', track: 'chatbot', questionSource: 'adaptive',
    timing: { prepSeconds: 30, answerSeconds: 120, allowSkipPrep: true, allowEarlySubmit: true, warningThresholdSeconds: 15 },
    rubric: { kpis: [], scoreScale: 100 },
    integrity: { enforceFullscreen: false, detectTabSwitch: false, disablePasteInAnswers: false, disableCopy: false, maxTabSwitchWarnings: 3, logEvents: false },
    branding: { companyName: 'X', accentColor: '#000' },
    mode: 'conversational',
    adaptive: { role: 'Engineer', difficulty: 'mixed', numberOfQuestions: 3, allowFollowUps: true, maxFollowUpsPerQuestion: 1 },
    chatbotTimer: {
      enabled: true, perQuestionSeconds: 120, timeFollowUps: true, followUpSeconds: 90,
      includeThinkingPhase: false, thinkingSeconds: 20, warningThresholdSeconds: 15,
      allowEarlySubmit: true, autoSubmitOnExpiry: true,
    },
    createdAt: '', updatedAt: '',
    ...overrides,
  }
}

let seq = 0
function turn(turnType: TurnType | undefined, extra: Partial<Turn> = {}): Turn {
  return { id: `turn-${seq++}`, role: 'interviewer', content: 'x', turnType, createdAt: iso(T0), ...extra }
}
function makeSession(transcript: Turn[], overrides: Partial<InterviewSession> = {}): InterviewSession {
  return {
    id: 's1', templateId: 't1', track: 'chatbot', candidate: { name: 'A', email: '' },
    status: 'in_progress', questions: [], currentIndex: 0, createdAt: '',
    integrityEvents: [], tabSwitchCount: 0, transcript, ...overrides,
  }
}

/* ── 1. Only question / follow_up turns are timed ───────────────────────── */
{
  console.log('\n=== 1. Turn-type gating (the critical rule) ===')
  const tpl = makeTemplate()
  assert('greeting is NOT timed', turnTiming(tpl, turn('greeting')) === null)
  assert('readiness is NOT timed', turnTiming(tpl, turn('readiness')) === null)
  assert('acknowledgment is NOT timed', turnTiming(tpl, turn('acknowledgment')) === null)
  assert('wrap_up is NOT timed', turnTiming(tpl, turn('wrap_up')) === null)
  const q = turnTiming(tpl, turn('question', { questionIndex: 0 }))
  assert('question IS timed at perQuestionSeconds', q?.answerSeconds === 120)
  const fu = turnTiming(tpl, turn('follow_up', { questionIndex: 0 }))
  assert('follow_up IS timed at followUpSeconds', fu?.answerSeconds === 90)
}

/* ── 2. followUpSeconds falls back to perQuestionSeconds when unset ──────── */
{
  console.log('\n=== 2. Follow-up timing fallbacks ===')
  const noFuSecs = makeTemplate({ chatbotTimer: { ...makeTemplate().chatbotTimer!, followUpSeconds: undefined } })
  assert('follow_up uses perQuestionSeconds when followUpSeconds unset',
    turnTiming(noFuSecs, turn('follow_up', { questionIndex: 0 }))?.answerSeconds === 120)
  const noTimeFu = makeTemplate({ chatbotTimer: { ...makeTemplate().chatbotTimer!, timeFollowUps: false } })
  assert('follow_up is NOT timed when timeFollowUps is off', turnTiming(noTimeFu, turn('follow_up', { questionIndex: 0 })) === null)
  assert('primary question still timed when timeFollowUps is off',
    turnTiming(noTimeFu, turn('question', { questionIndex: 0 }))?.answerSeconds === 120)
}

/* ── 3. Disabled timer = pure conversational flow ───────────────────────── */
{
  console.log('\n=== 3. Disabled timer ===')
  const off = makeTemplate({ chatbotTimer: { ...makeTemplate().chatbotTimer!, enabled: false } })
  assert('timerEnabled is false', timerEnabled(off) === false)
  assert('question is NOT timed when disabled', turnTiming(off, turn('question', { questionIndex: 0 })) === null)
  const sess = makeSession([turn('question', { questionIndex: 0 })])
  assert('revealTimedTurn is a no-op when disabled', revealTimedTurn(sess, off, T0) === false)
  assert('advanceChatbotTiming is a no-op when disabled', advanceChatbotTiming(sess, off, T0 + 10_000_000) === 'none')
}

/* ── 4. Clock arms only on presentation, and is idempotent ──────────────── */
{
  console.log('\n=== 4. revealTimedTurn arms the answer clock once ===')
  const tpl = makeTemplate()
  const q = turn('question', { questionIndex: 0 })
  const sess = makeSession([q])
  assert('not armed before presentation', !q.answerStartedAt && !q.thinkingStartedAt)
  assert('first reveal arms', revealTimedTurn(sess, tpl, T0) === true)
  assert('answer clock started (no thinking phase configured)', q.answerStartedAt === iso(T0) && !q.thinkingStartedAt)
  assert('second reveal is a no-op (idempotent)', revealTimedTurn(sess, tpl, T0 + 5000) === false)
  assert('answerStartedAt unchanged by the second reveal', q.answerStartedAt === iso(T0))
}

/* ── 5. Greeting never arms a clock even after presentation ─────────────── */
{
  console.log('\n=== 5. Greeting never arms ===')
  const tpl = makeTemplate()
  const g = turn('greeting')
  const sess = makeSession([g])
  assert('revealTimedTurn returns false for greeting', revealTimedTurn(sess, tpl, T0) === false)
  assert('greeting has no clock', !g.answerStartedAt && !g.thinkingStartedAt)
  assert('advanceChatbotTiming ignores greeting', advanceChatbotTiming(sess, tpl, T0 + 999_999) === 'none')
}

/* ── 6. Thinking sub-timer → answer transition ──────────────────────────── */
{
  console.log('\n=== 6. Optional thinking sub-timer ===')
  const tpl = makeTemplate({ chatbotTimer: { ...makeTemplate().chatbotTimer!, includeThinkingPhase: true, thinkingSeconds: 20 } })
  const q = turn('question', { questionIndex: 0 })
  const sess = makeSession([q])
  revealTimedTurn(sess, tpl, T0)
  assert('reveal starts thinking, not answering', q.thinkingStartedAt === iso(T0) && !q.answerStartedAt)
  assert('mid-thinking: no expiry', advanceChatbotTiming(sess, tpl, T0 + 10_000) === 'none')
  assert('still thinking at 10s', !q.answerStartedAt)
  advanceChatbotTiming(sess, tpl, T0 + 20_000)
  assert('answer clock starts exactly at the thinking deadline', q.answerStartedAt === iso(T0 + 20_000))
}

/* ── 7. Answer expiry is server-authoritative + honors autoSubmitOnExpiry ─ */
{
  console.log('\n=== 7. Answer expiry ===')
  const tpl = makeTemplate() // perQuestionSeconds 120, autoSubmitOnExpiry true
  const q = turn('question', { questionIndex: 0, answerStartedAt: iso(T0) })
  const sess = makeSession([q])
  assert('before deadline → none', advanceChatbotTiming(sess, tpl, T0 + 119_000) === 'none')
  assert('after deadline → answer_expired', advanceChatbotTiming(sess, tpl, T0 + 121_000) === 'answer_expired')

  const noAuto = makeTemplate({ chatbotTimer: { ...makeTemplate().chatbotTimer!, autoSubmitOnExpiry: false } })
  const q2 = turn('question', { questionIndex: 0, answerStartedAt: iso(T0) })
  const sess2 = makeSession([q2])
  assert('after deadline with autoSubmit off → none (candidate must submit)',
    advanceChatbotTiming(sess2, noAuto, T0 + 121_000) === 'none')
}

/* ── 8. Cross-track fallback: a chat template taken as a chatbot session ── */
{
  console.log('\n=== 8. Cross-track fallback (chat template → chatbot session) ===')
  // A chat-track template has no chatbotTimer/conversationTiming of its own —
  // the chatbot engine must inherit its fixed-slot TimingConfig.
  const chatTpl = makeTemplate({ track: 'chat', chatbotTimer: undefined, mode: undefined, conversationTiming: undefined })
  assert('timer enabled via inherited chat timing', timerEnabled(chatTpl) === true)
  const q = turnTiming(chatTpl, turn('question', { questionIndex: 0 }))
  assert('question timed with timing.answerSeconds', q?.answerSeconds === 120, `got=${q?.answerSeconds}`)
  assert('no thinking phase in the fallback', q?.thinkingSeconds === 0)
  assert('auto-submit on expiry (matches the chat track)', q?.autoSubmitOnExpiry === true)
  assert('greeting still untimed', turnTiming(chatTpl, turn('greeting')) === null)
  assert('wrap_up still untimed', turnTiming(chatTpl, turn('wrap_up')) === null)

  // Arm + expiry work end-to-end through the fallback config.
  const qt = turn('question', { questionIndex: 0 })
  const sess = makeSession([qt])
  assert('revealTimedTurn arms via fallback', revealTimedTurn(sess, chatTpl, T0) === true)
  assert('answer clock started immediately', qt.answerStartedAt === iso(T0))
  assert('expires at timing.answerSeconds', advanceChatbotTiming(sess, chatTpl, T0 + 121_000) === 'answer_expired')

  // Explicit config always wins over the fallback.
  const off = makeTemplate({ chatbotTimer: { ...makeTemplate().chatbotTimer!, enabled: false } })
  assert('explicitly disabled chatbotTimer wins (no fallback)', timerEnabled(off) === false)
  const bare = makeTemplate({ track: 'chatbot', chatbotTimer: undefined })
  assert('chatbot-track template without config stays untimed', timerEnabled(bare) === false)
}

console.log(`\n${failures === 0 ? '✅ ALL CONVERSATION-TIMING TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
