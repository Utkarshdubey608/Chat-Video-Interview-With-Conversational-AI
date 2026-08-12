/**
 * The `two_way` track (live recruiter↔candidate interview) is conversation-style
 * and NON-timed — exempt from the fixed-slot timing engine exactly like
 * `chatbot`/`video_avatar`, and its transcript feeds the SAME speech-metrics
 * path as voice/avatar/video (spoken === true). Run with:
 *   npx tsx server/services/twoWayTrack.test.ts
 */
import { tick } from './timing'
import { computeSpeechMetrics } from './signals'
import { DEFAULT_TIMING, DEFAULT_INTEGRITY, DEFAULT_BRANDING, defaultRubric } from '../store/defaults'
import type { InterviewSession, InterviewTemplate } from '../../shared/types'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

function makeTemplate(): InterviewTemplate {
  return {
    id: 't1', name: 'Two-way', role: 'Engineer', track: 'two_way', questionSource: 'fixed',
    timing: { ...DEFAULT_TIMING }, rubric: defaultRubric(),
    integrity: { ...DEFAULT_INTEGRITY }, branding: { ...DEFAULT_BRANDING },
    createdAt: 'now', updatedAt: 'now',
  }
}
function makeSession(startMsAgo: number): InterviewSession {
  const started = new Date(Date.now() - startMsAgo).toISOString()
  return {
    id: 's1', templateId: 't1', track: 'two_way',
    candidate: { name: 'A', email: 'a@x.com' }, status: 'in_progress',
    questions: [{ id: 'q1', text: 'Q1', autoSubmitted: false, prepStartedAt: started }],
    currentIndex: 0, createdAt: started, startedAt: started, integrityEvents: [], tabSwitchCount: 0,
  }
}

console.log('\n=== two_way track: exempt from the timed engine (like chatbot/video_avatar) ===')
{
  // prep started long ago — if the timed engine applied, tick would open the
  // answer phase / mutate the question. two_way must be exempt, like video_avatar.
  const s = makeSession(31_000)
  const changed = tick(s, makeTemplate())
  assert('tick does NOT mutate an in-progress two_way session', changed === false)
  assert('answer phase NOT opened (no timed engine for two_way)', !s.questions[0].answerStartedAt)
}

console.log('\n=== two_way track: speech metrics computed like a spoken/conversation track ===')
{
  const s = makeSession(0)
  const now = new Date().toISOString()
  s.transcript = [
    { id: 't1', role: 'interviewer', content: 'Tell me about a challenging project.', turnType: 'question', questionIndex: 0, createdAt: now },
    { id: 't2', role: 'candidate', content: 'I led a migration of a legacy service to a new distributed architecture.', questionIndex: 0, createdAt: now },
  ]
  const m = computeSpeechMetrics(s)
  assert('speech metrics returned (not null) for two_way transcript', m !== null)
  assert('marked spoken (same as voice/avatar/video)', m?.spoken === true)
  assert('word count > 0 from the candidate turn', (m?.words ?? 0) > 0)
}

console.log(`\n${failures === 0 ? '✅ ALL TWO-WAY-TRACK TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
