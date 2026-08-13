/**
 * Deterministic unit tests for the Voice end-flow controller. Run with:
 *   npx tsx server/services/voiceFlow.test.ts
 * No Gemini / network needed — we feed simulated Live message sequences and
 * assert the returned actions + final state.
 */
import { createVoiceFlow, type FlowAction } from './voiceFlow'

const QS = [
  'Tell me about your experience with distributed systems.',
  'How did you optimize the SQL queries in the registration system?',
  'Describe a time you handled a difficult production incident.',
]

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}
const has = (acts: FlowAction[], kind: FlowAction['kind']) => acts.some((a) => a.kind === kind)
const finalizeOf = (acts: FlowAction[]) => acts.find((a) => a.kind === 'finalize') as Extract<FlowAction, { kind: 'finalize' }> | undefined

/* ── 1. Happy path: no early end, correct alignment, graceful finish ────── */
{
  console.log('\n=== 1. Happy path ===')
  const f = createVoiceFlow(QS)
  f.start()
  f.onInterviewerTurn('Good afternoon! Ready to begin?')            // greeting (no match)
  f.onCandidateTurn('Yes, ready.')                                  // readiness (discarded)
  let a = f.onInterviewerTurn('Great! Tell me about your experience with distributed systems?')
  assert('Q1 asked, no finalize', f.askedIndex === 1 && !finalizeOf(a))
  f.onCandidateTurn('I built sharded services on AWS handling 12k rps.')
  f.onInterviewerTurn('Nice! How did you optimize the SQL queries in the registration system?')
  assert('Q2 asked', f.askedIndex === 2)
  f.onCandidateTurn('I added composite indexes and rewrote N+1 queries.')
  a = f.onInterviewerTurn('Love that! Describe a time you handled a difficult production incident?')
  assert('Q3 asked (last), still interviewing, NOT finalized', f.askedIndex === 3 && f.phase === 'interviewing' && !finalizeOf(a))
  f.onCandidateTurn('A cache stampede at 2am; I added jittered backoff and paged the team.')
  a = f.onInterviewerTurn("That's everything, thank you so much. You're all done and free to leave; our HR team will be in touch about next steps, and feel free to reach out anytime.")
  assert('entered closing after last answer + closing turn (NOT finalized yet)', f.phase === 'closing' && !finalizeOf(a))
  a = f.onCandidateTurn('Thank you, goodbye!')
  const fin = finalizeOf(a)
  assert('finalizes only after candidate farewell', !!fin && fin.graceful === true)
  assert('all 3 answers aligned + captured', f.answers.every((x) => x.length > 0), JSON.stringify(f.answers.map((x) => x.slice(0, 20))))
}

/* ── 2. VAD-split answer: two candidate turns for one question ───────────── */
{
  console.log('\n=== 2. VAD-split answer concatenates, no early end ===')
  const f = createVoiceFlow(QS)
  f.start()
  f.onInterviewerTurn('Hi! Ready?'); f.onCandidateTurn('yes')
  f.onInterviewerTurn('Tell me about your experience with distributed systems?')
  f.onCandidateTurn('I worked on distributed systems')             // split part 1
  const a = f.onCandidateTurn('for about six years, mostly on Kafka.') // split part 2, no question between
  assert('askedIndex stays 1', f.askedIndex === 1)
  assert('no premature finalize', !finalizeOf(a))
  assert('both fragments merged into answers[0]', f.answers[0].includes('six years') && f.answers[0].includes('distributed'))
}

/* ── 3. Multi-turn readiness discarded, no off-by-one ───────────────────── */
{
  console.log('\n=== 3. Multi-turn readiness ===')
  const f = createVoiceFlow(QS)
  f.start()
  f.onInterviewerTurn('Hello! Are you ready?')
  f.onCandidateTurn("I'm not sure yet")                            // readiness
  f.onInterviewerTurn("No rush at all, take your time. Are you ready now?") // non-question-ish reassurance
  f.onCandidateTurn('ok yes now')                                  // readiness
  f.onInterviewerTurn('Tell me about your experience with distributed systems?')
  f.onCandidateTurn('My real answer about distributed systems.')
  assert('askedIndex === 1 (only the real Q matched)', f.askedIndex === 1, `askedIndex=${f.askedIndex}`)
  assert('answers[0] contains only the post-Q answer', f.answers[0] === 'My real answer about distributed systems.')
}

/* ── 4. Silent question: no left-shift ──────────────────────────────────── */
{
  console.log('\n=== 4. Silent (unanswered) question ===')
  const f = createVoiceFlow(QS)
  f.start()
  f.onInterviewerTurn('Hi! Ready?'); f.onCandidateTurn('yes')
  f.onInterviewerTurn('Tell me about your experience with distributed systems?')
  f.onCandidateTurn('Answer one.')
  f.onInterviewerTurn('How did you optimize the SQL queries in the registration system?') // Q2, no answer
  f.onInterviewerTurn('Describe a time you handled a difficult production incident?')      // Q3
  f.onCandidateTurn('Answer three.')
  assert('askedIndex advanced to 3 despite a silent Q2', f.askedIndex === 3, `askedIndex=${f.askedIndex}`)
  assert('answers[0] filled, answers[1] empty, answers[2] filled (no shift)',
    f.answers[0] === 'Answer one.' && f.answers[1] === '' && f.answers[2] === 'Answer three.', JSON.stringify(f.answers))
}

/* ── 5. Hard closing MID-interview → nudge, never finalize ──────────────── */
{
  console.log('\n=== 5. Early closing attempt is nudged, not ended ===')
  const f = createVoiceFlow(QS)
  f.start()
  f.onInterviewerTurn('Hi! Ready?'); f.onCandidateTurn('yes')
  f.onInterviewerTurn('Tell me about your experience with distributed systems?')
  f.onCandidateTurn('answer 1')
  const a = f.onInterviewerTurn('Thank you for your time, this concludes the interview. Goodbye!') // early close, only 1/3 asked
  assert('emits a nudge', has(a, 'nudge'))
  assert('does NOT finalize', !finalizeOf(a))
  assert('phase still interviewing', f.phase === 'interviewing')
}

/* ── 6. Missing farewell in closing → candidate-silence timer finalizes ──── */
{
  console.log('\n=== 6. Silent candidate during closing → graceful timeout finish ===')
  const f = createVoiceFlow(QS)
  f.start()
  f.onInterviewerTurn('Hi! Ready?'); f.onCandidateTurn('yes')
  f.onInterviewerTurn('Tell me about your experience with distributed systems?'); f.onCandidateTurn('a1')
  f.onInterviewerTurn('How did you optimize the SQL queries in the registration system?'); f.onCandidateTurn('a2')
  f.onInterviewerTurn('Describe a time you handled a difficult production incident?'); f.onCandidateTurn('a3')
  f.onInterviewerTurn("That's everything, thank you. You can leave now; HR will be in touch.")
  assert('in closing', f.phase === 'closing')
  const a = f.onTimer('candidateSilence')
  const fin = finalizeOf(a)
  assert('candidate-silence timer finalizes gracefully', !!fin && fin.graceful === true)
}

/* ── 7. Total stall → idle nudges once then finalizes non-graceful ──────── */
{
  console.log('\n=== 7. Idle watchdog: nudge then non-graceful finalize ===')
  const f = createVoiceFlow(QS)
  f.start()
  f.onInterviewerTurn('Hi! Ready?'); f.onCandidateTurn('yes')
  f.onInterviewerTurn('Tell me about your experience with distributed systems?'); f.onCandidateTurn('a1')
  const first = f.onTimer('idle')
  assert('first idle → nudge, no finalize', has(first, 'nudge') && !finalizeOf(first))
  const second = f.onTimer('idle')
  const fin = finalizeOf(second)
  assert('second idle → non-graceful finalize', !!fin && fin.graceful === false, `graceful=${fin?.graceful}`)
}

/* ── 8. Extra backchannel turns never advance coverage / end early ──────── */
{
  console.log('\n=== 8. Backchannels do not inflate coverage ===')
  const f = createVoiceFlow(QS)
  f.start()
  f.onInterviewerTurn('Hi! Ready?'); f.onCandidateTurn('yes')
  f.onInterviewerTurn('Tell me about your experience with distributed systems?')
  f.onCandidateTurn('um'); f.onCandidateTurn('let me think'); f.onCandidateTurn('okay here it is')
  assert('askedIndex still 1 after 3 candidate turns', f.askedIndex === 1)
  assert('not finalized, not coverage-complete', !f.finalized && !f.coverageComplete)
}

/* ── 9. Partial answer bucketed before End is preserved (driver flush path) ── */
{
  console.log('\n=== 9. Flush-before-end preserves the last partial answer ===')
  const f = createVoiceFlow(QS)
  f.start()
  f.onInterviewerTurn('Hi! Ready?'); f.onCandidateTurn('yes')
  f.onInterviewerTurn('Tell me about your experience with distributed systems?')
  // Driver flushes the in-progress answer into the flow, THEN calls onEnd.
  f.onCandidateTurn('I was mid-sentence describing my Kafka work')
  const a = f.onEnd('ended')
  const fin = finalizeOf(a)
  assert('partial answer preserved in bucket', f.answers[0] === 'I was mid-sentence describing my Kafka work')
  assert('early End finalizes as NOT graceful (coverage incomplete)', !!fin && fin.graceful === false)
}

/* ── 10. Candidate activity resets the idle watchdog (no mid-answer end) ──── */
{
  console.log('\n=== 10. Candidate speech re-arms idle; long answer is not cut off ===')
  const f = createVoiceFlow(QS)
  f.start()
  f.onInterviewerTurn('Hi! Ready?'); f.onCandidateTurn('yes')
  f.onInterviewerTurn('Tell me about your experience with distributed systems?')
  // Candidate is still speaking (streaming partials) — this must re-arm 'idle'.
  const act = f.onCandidateActivity()
  assert('activity re-arms the idle timer', has(act, 'armTimer') && act.some((a) => a.kind === 'armTimer' && a.tag === 'idle'))
  assert('activity does NOT finalize and does NOT advance coverage', !finalizeOf(act) && f.askedIndex === 1)
}

/* ── 11. Activity in closing does NOT re-arm idle (candidateSilence governs) ── */
{
  console.log('\n=== 11. Closing-phase activity leaves the wrap-up timers alone ===')
  const f = createVoiceFlow(QS)
  f.start()
  f.onInterviewerTurn('Hi! Ready?'); f.onCandidateTurn('yes')
  f.onInterviewerTurn('Tell me about your experience with distributed systems?'); f.onCandidateTurn('a1')
  f.onInterviewerTurn('How did you optimize the SQL queries in the registration system?'); f.onCandidateTurn('a2')
  f.onInterviewerTurn('Describe a time you handled a difficult production incident?'); f.onCandidateTurn('a3')
  f.onInterviewerTurn("That's everything, thank you. You can leave now; HR will be in touch.")
  assert('in closing', f.phase === 'closing')
  const act = f.onCandidateActivity()
  assert('no idle re-arm during closing', !has(act, 'armTimer'))
}

console.log(`\n${failures === 0 ? '✅ ALL VOICE-FLOW TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
