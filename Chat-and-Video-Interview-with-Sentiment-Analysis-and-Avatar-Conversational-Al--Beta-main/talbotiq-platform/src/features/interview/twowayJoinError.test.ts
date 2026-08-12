/**
 * Deterministic unit tests for the two-way JOIN failure classifier. Run:
 *   npx tsx src/features/interview/twowayJoinError.test.ts
 * Pure function — no React/network/DOM.
 */
import { classifyJoinFailure } from './twowayJoinError'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

console.log('\n=== classifyJoinFailure: waiting-for-host (recruiter has not opened the room) ===')
assert(
  "409 'has not started' → 'waiting-host'",
  classifyJoinFailure(409, 'The interviewer has not started this interview yet.') === 'waiting-host',
)
assert(
  'match is case-insensitive',
  classifyJoinFailure(409, 'HAS NOT STARTED') === 'waiting-host',
)

console.log('\n=== classifyJoinFailure: transient (backend briefly unavailable — self-heals) ===')
assert(
  'body-less 500 (Vite proxy during a `tsx watch` restart) → transient',
  classifyJoinFailure(500, 'Request failed (500)') === 'transient',
)
assert("502 (reverse proxy during a prod deploy) → transient", classifyJoinFailure(502, 'Bad Gateway') === 'transient')
assert("503 → transient", classifyJoinFailure(503, 'Service Unavailable') === 'transient')
assert("504 → transient", classifyJoinFailure(504, 'Gateway Timeout') === 'transient')
assert(
  'null status (fetch rejected — no response reached the browser) → transient',
  classifyJoinFailure(null, 'Failed to fetch') === 'transient',
)

console.log('\n=== classifyJoinFailure: fatal (a definite client error — do not loop forever) ===')
assert("400 (not a two-way interview) → fatal", classifyJoinFailure(400, 'Not a two-way interview') === 'fatal')
assert("401 → fatal", classifyJoinFailure(401, 'Authentication required') === 'fatal')
assert("403 → fatal", classifyJoinFailure(403, 'Forbidden') === 'fatal')
assert("404 (session not found) → fatal", classifyJoinFailure(404, 'Session not found') === 'fatal')
assert(
  "409 'already ended' is NOT waiting-for-host → fatal",
  classifyJoinFailure(409, 'This interview has already ended') === 'fatal',
)

console.log(
  `\n${failures === 0 ? '✅ ALL TWOWAY-JOIN-ERROR TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`,
)
process.exit(failures === 0 ? 0 : 1)
