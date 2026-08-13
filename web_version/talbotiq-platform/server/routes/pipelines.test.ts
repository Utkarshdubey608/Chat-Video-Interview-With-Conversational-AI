/**
 * Pipeline route ownership + rounds-validation. Run with:
 *   npx tsx server/routes/pipelines.test.ts
 * Exercises exported helpers directly (no HTTP harness / Firestore).
 */
import { db } from '../store/db'
import { __test } from './pipelines'
import type { AuthContext, RoundDef } from '../../shared/types'

const { owns, normalize, loadOwned, buildPipelineCandidate, buildBoard, selectByCriteria, assertAdvanceable, resolveEmailTemplate } = __test
let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}
function throws(label: string, fn: () => void, statusWanted?: number) {
  try { fn(); assert(label, false, 'expected throw') }
  catch (e: any) { assert(label, statusWanted ? e?.status === statusWanted : true, `status=${e?.status}`) }
}
const alice: AuthContext = { uid: 'alice', email: 'a@x.com', emailVerified: true, role: 'recruiter', admin: false }
const bob: AuthContext = { uid: 'bob', email: 'b@x.com', emailVerified: true, role: 'recruiter', admin: false }

const goodRounds: RoundDef[] = [
  { index: 0, name: 'Screening', mode: 'chatbot', source: 'tailor',
    config: { style: 'mix', techCount: 3, nonTechCount: 2, difficulty: 'mixed', domains: [], model: 'gemini-2.5-flash' } },
  { index: 1, name: 'Technical', mode: 'video', advanceRule: { kind: 'threshold', value: 60 } },
]

// normalize: valid
const n = normalize({ role: 'Backend', rounds: goodRounds })
assert('type forced multi', n.type === 'multi')
assert('role kept', n.role === 'Backend')
assert('rounds count', n.rounds.length === 2)
assert('advanceRule kept', n.rounds[1].advanceRule?.value === 60)

// normalize: reindex non-contiguous
const nr = normalize({ role: 'R', rounds: [{ index: 5, name: 'A', mode: 'chat' }, { index: 9, name: 'B', mode: 'voice' }] })
assert('reindexed 0..n', nr.rounds[0].index === 0 && nr.rounds[1].index === 1)

// normalize: reject empty rounds
throws('empty rounds -> 400', () => normalize({ role: 'R', rounds: [] }), 400)
// normalize: reject disallowed mode (two_way)
throws('two_way mode -> 400', () => normalize({ role: 'R', rounds: [{ index: 0, name: 'X', mode: 'two_way' }] }), 400)
// normalize: reject round without name
throws('missing name -> 400', () => normalize({ role: 'R', rounds: [{ index: 0, name: '', mode: 'chat' }] }), 400)
// normalize: reject missing role
throws('missing role -> 400', () => normalize({ role: '', rounds: goodRounds }), 400)

// owns / loadOwned
const now = '2026-07-22T00:00:00.000Z'
db.pipelines.set('pl-a', { id: 'pl-a', recruiterId: 'alice', role: 'R', type: 'multi', rounds: goodRounds, createdAt: now, updatedAt: now })
assert('owner owns', owns(db.pipelines.get('pl-a')!, alice))
assert('non-owner does not', !owns(db.pipelines.get('pl-a')!, bob))
assert('loadOwned returns for owner', loadOwned('pl-a', alice).id === 'pl-a')
throws('loadOwned 404 cross-owner', () => loadOwned('pl-a', bob), 404)
throws('loadOwned 404 missing', () => loadOwned('nope', alice), 404)
db.pipelines.delete('pl-a')

// buildPipelineCandidate: pure Round-1 candidate builder
{
  const { buildPipelineCandidate } = __test
  const now = '2026-07-22T00:00:00.000Z'
  const pipe = { id: 'pl-x', recruiterId: 'alice', role: 'Backend', type: 'multi' as const, rounds: goodRounds, createdAt: now, updatedAt: now }
  const pc = buildPipelineCandidate(pipe, 'alice', { email: 'Ada@x.com', role: 'Backend' }, 'iv-1', now)
  assert('pc pipelineId', pc.pipelineId === 'pl-x')
  assert('pc recruiterId owner', pc.recruiterId === 'alice')
  assert('pc emailLower', pc.candidateEmailLower === 'ada@x.com')
  assert('pc starts round 0', pc.currentRoundIndex === 0 && pc.status === 'in_round')
  assert('pc perRound[0] interviewId', pc.perRound[0].interviewId === 'iv-1' && pc.perRound[0].roundIndex === 0)
  assert('pc history invited', pc.history[0].action === 'invited' && pc.history[0].toRound === 0)
}

// buildBoard: pure candidate/round/report/session join for the results board
{
  const { buildBoard } = __test
  const now = '2026-07-22T00:00:00.000Z'
  const pipe = { id: 'pl-b', recruiterId: 'alice', role: 'Backend', type: 'multi' as const, rounds: goodRounds, createdAt: now, updatedAt: now }
  // c1: completed + scored in round 0 -> advanceable in round 0 column
  const c1 = { id: 'c1', pipelineId: 'pl-b', recruiterId: 'alice', candidateEmail: 'a@x.com', candidateEmailLower: 'a@x.com', role: 'Backend', currentRoundIndex: 0, status: 'in_round' as const, perRound: [{ roundIndex: 0, interviewId: 'iv-c1', invitedAt: now }], history: [{ at: now, byUid: 'alice', action: 'invited' as const, toRound: 0, basis: 'round-1 invite' }], createdAt: now, updatedAt: now }
  // c2: invited only (no session/report) -> not advanceable
  const c2 = { ...c1, id: 'c2', candidateEmail: 'b@x.com', candidateEmailLower: 'b@x.com', perRound: [{ roundIndex: 0, interviewId: 'iv-c2', invitedAt: now }] }
  // c3: selected (terminal)
  const c3 = { ...c1, id: 'c3', candidateEmail: 'c@x.com', candidateEmailLower: 'c@x.com', status: 'selected' as const, currentRoundIndex: 1, perRound: [{ roundIndex: 0, interviewId: 'iv-c3a', invitedAt: now }, { roundIndex: 1, interviewId: 'iv-c3b', invitedAt: now }] }
  const reports: Record<string, { overallScore?: number; notEvaluated?: boolean }> = { 'iv-c1': { overallScore: 72 } }
  const sessions: Record<string, string> = { 'iv-c1': 'completed', 'iv-c2': 'created' }
  const board = buildBoard(pipe, [c1, c2, c3], (id) => reports[id], (id) => sessions[id])

  assert('columns = rounds + selected + not_advancing', board.columns.length === goodRounds.length + 2)
  const round0 = board.columns.find((c) => c.kind === 'round' && c.roundIndex === 0)!
  const selectedCol = board.columns.find((c) => c.kind === 'selected')!
  assert('c1 in round0 column', round0.cards.some((k) => k.pipelineCandidateId === 'c1'))
  const c1card = round0.cards.find((k) => k.pipelineCandidateId === 'c1')!
  assert('c1 scored 72', c1card.score === 72 && c1card.roundStatus === 'completed')
  assert('c1 advanceable', c1card.advanceable === true)
  assert('c1 history carried onto card', c1card.history.length === 1 && c1card.history[0].action === 'invited')
  const c2card = round0.cards.find((k) => k.pipelineCandidateId === 'c2')!
  assert('c2 not scored -> null score, not advanceable', c2card.score === null && c2card.advanceable === false)
  assert('c3 in selected column, not advanceable', selectedCol.cards.some((k) => k.pipelineCandidateId === 'c3') && selectedCol.cards[0].advanceable === false)
}

// selectByCriteria / assertAdvanceable: pure eligibility + selection helpers
{
  const { selectByCriteria, assertAdvanceable } = __test
  const cards = [
    { pipelineCandidateId: 'a', score: 80 }, { pipelineCandidateId: 'b', score: 55 },
    { pipelineCandidateId: 'c', score: 65 }, { pipelineCandidateId: 'd', score: null },
  ]
  assert('threshold>=60 picks a,c', JSON.stringify(selectByCriteria(cards, { kind: 'threshold', value: 60 }).sort()) === JSON.stringify(['a', 'c']))
  assert('topN=2 picks a,c (highest)', JSON.stringify(selectByCriteria(cards, { kind: 'topN', value: 2 }).sort()) === JSON.stringify(['a', 'c']))
  assert('null score never selected', !selectByCriteria(cards, { kind: 'threshold', value: 0 }).includes('d'))

  const cand = { id: 'x', status: 'in_round', currentRoundIndex: 0 } as any
  assertAdvanceable(cand, 1, 3, true) // ok, no throw
  throws('advance not scored -> 400', () => assertAdvanceable(cand, 1, 3, false), 400)
  throws('advance skip round -> 400', () => assertAdvanceable(cand, 2, 3, true), 400)
  throws('advance when selected -> 400', () => assertAdvanceable({ ...cand, status: 'selected' }, 1, 3, true), 400)
  assertAdvanceable({ ...cand, currentRoundIndex: 2 }, 3, 3, true) // last round -> selected (target === roundCount)
}

// resolveEmailTemplate: kind-aware default (plan correction — must NOT always default to 'invite')
{
  const { resolveEmailTemplate } = __test
  const auth: AuthContext = { uid: 'alice', email: 'a@x.com', emailVerified: true, role: 'recruiter', admin: false }
  const inviteDefault = resolveEmailTemplate(auth, {}, 'invite')
  const advanceDefault = resolveEmailTemplate(auth, {}, 'advance')
  const selectedDefault = resolveEmailTemplate(auth, {}, 'selected')
  const rejectionDefault = resolveEmailTemplate(auth, {}, 'rejection')
  assert('invite default kind invite (backward-compat)', inviteDefault?.kind === undefined || inviteDefault?.kind === 'invite')
  assert('advance default kind advance', advanceDefault?.kind === 'advance')
  assert('selected default kind selected', selectedDefault?.kind === 'selected')
  assert('rejection default kind rejection', rejectionDefault?.kind === 'rejection')
  assert('advance default subject differs from invite default', advanceDefault?.subject !== inviteDefault?.subject)
}

console.log(`\n${failures === 0 ? '✅ ALL PIPELINE-ROUTE TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
