/**
 * Unit tests for the pure interview-doc builder. Run with:
 *   npx tsx server/services/interviewInvite.test.ts
 * Only buildInterviewDocFields is pure/tested here; the create+send path has
 * Firestore/email side effects and is covered by build/tsc + manual walkthrough.
 */
import { buildInterviewDocFields, transitionVars, type InterviewDocCtx } from './interviewInvite'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

const baseCtx: InterviewDocCtx = {
  testId: 'batch-1', recruiterId: 'rec-1', recruiterEmail: 'r@x.com', recruiterName: 'Rex',
  nowIso: '2026-07-22T00:00:00.000Z', mode: 'chatbot', questions: [],
  source: 'tailor',
  config: { style: 'mix', techCount: 3, nonTechCount: 2, difficulty: 'mixed', domains: ['api'], model: 'gemini-2.5-flash' },
}

const d = buildInterviewDocFields(baseCtx, { email: 'Ada@x.com', role: 'Backend Dev' })
assert('frozen recruiterId', d.recruiterId === 'rec-1')
assert('candidateEmail preserved case', d.candidateEmail === 'Ada@x.com')
assert('candidateEmailLower lowercased', d.candidateEmailLower === 'ada@x.com')
assert('type maps chatbot->chat', d.type === 'chat')
assert('title format', d.title === 'Backend Dev — Chatbot interview')
assert('status assigned', d.status === 'assigned')
assert('maxAttempts 1', d.maxAttempts === 1)
assert('resultPublished false', d.resultPublished === false)
assert('mode additive', d.mode === 'chatbot')
assert('role per-candidate', d.role === 'Backend Dev')
assert('screening tailor source', (d.screening as any).source === 'tailor')
assert('screening tailor techCount', (d.screening as any).techCount === 3)
assert('no pipeline ref when absent', d.pipeline === undefined)

// video mode maps to type 'video'
const dv = buildInterviewDocFields({ ...baseCtx, mode: 'video' }, { email: 'b@x.com', role: 'QA' })
assert('type maps video->video', dv.type === 'video')

// pipeline ref included when provided; set source
const dp = buildInterviewDocFields(
  { ...baseCtx, source: 'set', questionSetId: 'qs-9', config: undefined,
    pipeline: { pipelineId: 'pl-1', roundIndex: 2, pipelineCandidateId: 'pc-1' } },
  { email: 'c@x.com', role: 'Backend Dev' },
)
assert('screening set questionSetId', (dp.screening as any).questionSetId === 'qs-9')
assert('screening set has no tailor fields', (dp.screening as any).techCount === undefined)
assert('pipeline ref present', (dp.pipeline as any)?.pipelineId === 'pl-1' && (dp.pipeline as any)?.roundIndex === 2)

assert('createdAt is a server-timestamp sentinel not the ISO string', typeof (d as any).createdAt === 'object' && (d as any).createdAt !== null && (d as any).createdAt !== baseCtx.nowIso)
assert('updatedAt is a server-timestamp sentinel not the ISO string', typeof (d as any).updatedAt === 'object' && (d as any).updatedAt !== null && (d as any).updatedAt !== baseCtx.nowIso)

// transitionVars — pure merge-vars builder for advance/selected/rejection emails
{
  const v = transitionVars({ email: 'Ada@x.com', role: 'Backend' },
    { fromName: 'Rex', company: 'Acme' } as any,
    { roundName: 'Technical', previousRoundName: 'Screening', score: '72' })
  assert('transition candidate_name from email', v.candidate_name === 'Ada')
  assert('transition role', v.role === 'Backend')
  assert('transition round_name', v.round_name === 'Technical')
  assert('transition previous_round_name', v.previous_round_name === 'Screening')
  assert('transition score', v.score === '72')
  assert('transition recruiter/company', v.recruiter_name === 'Rex' && v.company === 'Acme')
}
{
  // opts fields optional -> default to empty string, not undefined
  const v = transitionVars({ email: '', role: 'QA' }, { fromName: 'Rex', company: 'Acme' } as any, {})
  assert('transition candidate_name falls back to "there" when email local-part empty', v.candidate_name === 'there')
  assert('transition round_name defaults to empty string', v.round_name === '')
  assert('transition previous_round_name defaults to empty string', v.previous_round_name === '')
  assert('transition score defaults to empty string', v.score === '')
}

console.log(`\n${failures === 0 ? '✅ ALL INTERVIEW-INVITE TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
