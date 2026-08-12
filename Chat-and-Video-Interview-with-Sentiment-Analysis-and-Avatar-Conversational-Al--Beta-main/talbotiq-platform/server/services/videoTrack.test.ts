/**
 * The `video` track keeps the timed per-question engine (like `chat`) for FLOW,
 * but each submitted answer's live transcript is mirrored into session.transcript
 * as (question, answer) turns so scoring/results run the SAME conversation path as
 * Voice (transcript + speech metrics + sentiment). Run with:
 *   npx tsx server/services/videoTrack.test.ts
 */
import { tick } from './timing'
import { computeSpeechMetrics } from './signals'
import { buildVideoTranscript } from './videoTranscript'
import { DEFAULT_TIMING, DEFAULT_INTEGRITY, DEFAULT_BRANDING, defaultRubric } from '../store/defaults'
import type { InterviewSession, InterviewTemplate, SessionQuestion } from '../../shared/types'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

function makeTemplate(): InterviewTemplate {
  return {
    id: 't1', name: 'Video', role: 'Engineer', track: 'video', questionSource: 'fixed',
    timing: { ...DEFAULT_TIMING }, rubric: defaultRubric(),
    integrity: { ...DEFAULT_INTEGRITY }, branding: { ...DEFAULT_BRANDING },
    createdAt: 'now', updatedAt: 'now',
  }
}
function makeSession(startMsAgo: number): InterviewSession {
  const started = new Date(Date.now() - startMsAgo).toISOString()
  return {
    id: 's1', templateId: 't1', track: 'video',
    candidate: { name: 'A', email: 'a@x.com' }, status: 'in_progress',
    questions: [{ id: 'q1', text: 'Q1', autoSubmitted: false, prepStartedAt: started }],
    currentIndex: 0, createdAt: started, startedAt: started, integrityEvents: [], tabSwitchCount: 0,
  }
}

console.log('\n=== video track: timed engine still applies (NOT exempt like chatbot/avatar) ===')
{
  // prep started 31s ago (> 30s prep) → tick should open the answer phase.
  const s = makeSession(31_000)
  const changed = tick(s, makeTemplate())
  assert('tick mutates a video session', changed === true)
  assert('answer phase opened after prep elapsed', Boolean(s.questions[0].answerStartedAt))
}

console.log('\n=== buildVideoTranscript: (question, answer) turns ===')
{
  const q: SessionQuestion = { id: 'q1', text: 'Describe an API request flow.', autoSubmitted: false,
    answerText: 'The client hits Express, which queries MySQL and returns JSON.' }
  const turns = buildVideoTranscript(q, 0, new Date().toISOString())
  assert('two turns produced', turns.length === 2)
  assert('turn 0 = interviewer question turn', turns[0].role === 'interviewer' && turns[0].turnType === 'question' && turns[0].questionIndex === 0 && turns[0].content === q.text)
  assert('turn 1 = candidate answer turn', turns[1].role === 'candidate' && turns[1].questionIndex === 0 && turns[1].content === q.answerText)
}

console.log('\n=== video track: speech metrics computed like a spoken/conversation track ===')
{
  const s = makeSession(0)
  const now = new Date().toISOString()
  s.transcript = buildVideoTranscript(
    { id: 'q1', text: 'Q1', autoSubmitted: false, answerText: 'I built distributed systems for six years handling high load.' },
    0, now,
  )
  const m = computeSpeechMetrics(s)
  assert('speech metrics returned (not null) for video transcript', m !== null)
  assert('marked spoken (same as voice/avatar)', m?.spoken === true)
  assert('word count > 0 from the candidate turn', (m?.words ?? 0) > 0)
}

console.log(`\n${failures === 0 ? '✅ ALL VIDEO-TRACK TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
