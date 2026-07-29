/**
 * Pipelines persist across save/reload in the Express/JSON store. Run with:
 *   npx tsx server/store/db.pipelines.test.ts
 * Uses the real db singleton + saveNow(); asserts the snapshot round-trips.
 */
import { db } from './db'
import type { Pipeline, PipelineCandidate } from '../../shared/types'

let failures = 0
function assert(label: string, cond: boolean) {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}`)
  if (!cond) failures++
}

db.init()

const now = '2026-07-22T00:00:00.000Z'
const p: Pipeline = {
  id: 'pl-test-1', recruiterId: 'rec-1', role: 'Backend Dev', type: 'multi',
  rounds: [
    { index: 0, name: 'Screening', mode: 'chatbot' },
    { index: 1, name: 'Technical', mode: 'video', advanceRule: { kind: 'threshold', value: 60 } },
  ],
  createdAt: now, updatedAt: now,
}
const c: PipelineCandidate = {
  id: 'pc-test-1', pipelineId: 'pl-test-1', recruiterId: 'rec-1',
  candidateEmail: 'A@x.com', candidateEmailLower: 'a@x.com', role: 'Backend Dev',
  currentRoundIndex: 0, status: 'in_round',
  perRound: [{ roundIndex: 0, interviewId: 'iv-1', invitedAt: now }],
  history: [{ at: now, byUid: 'rec-1', action: 'invited', toRound: 0 }],
  createdAt: now, updatedAt: now,
}

db.pipelines.set(p.id, p)
db.pipelineCandidates.set(c.id, c)
db.saveNow()

// Simulate reload: clear the maps, re-init from the file just written.
db.pipelines.clear()
db.pipelineCandidates.clear()
db.init()

const rp = db.pipelines.get('pl-test-1')
const rc = db.pipelineCandidates.get('pc-test-1')
assert('pipeline reloaded', !!rp && rp.rounds.length === 2)
assert('round advanceRule survives', rp?.rounds[1].advanceRule?.value === 60)
assert('candidate reloaded', !!rc && rc.perRound[0].interviewId === 'iv-1')
assert('candidate history survives', rc?.history[0].action === 'invited')

// cleanup so we don't leave test rows in db.json
db.pipelines.delete('pl-test-1')
db.pipelineCandidates.delete('pc-test-1')
db.saveNow()

console.log(`\n${failures === 0 ? '✅ ALL PIPELINE-STORE TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
