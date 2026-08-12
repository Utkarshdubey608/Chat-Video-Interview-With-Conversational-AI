/**
 * Deterministic test for the Deepgram pre-recorded response parser. Run with:
 *   npx tsx server/services/transcription.test.ts
 * No network — we feed a canned Deepgram JSON shape.
 */
import { parseDeepgramTranscript } from './transcription'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

console.log('\n=== deepgram transcript parsing ===')
const ok = {
  results: { channels: [{ alternatives: [{ transcript: 'I built distributed systems.' }] }] },
}
assert('extracts the first alternative transcript', parseDeepgramTranscript(ok) === 'I built distributed systems.')
assert('empty channels → empty string', parseDeepgramTranscript({ results: { channels: [] } }) === '')
assert('garbage → empty string', parseDeepgramTranscript(null) === '' && parseDeepgramTranscript({}) === '')

console.log(`\n${failures === 0 ? '✅ ALL TRANSCRIPTION TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
