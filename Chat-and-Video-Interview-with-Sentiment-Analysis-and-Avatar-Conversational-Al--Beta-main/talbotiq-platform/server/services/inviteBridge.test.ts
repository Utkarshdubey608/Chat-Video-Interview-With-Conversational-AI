/**
 * Deterministic unit tests for the invite → track mapping. Run with:
 *   npx tsx server/services/inviteBridge.test.ts
 * No Firestore / network needed — trackForInvite/typeForMode are pure.
 */
import { __test } from './inviteBridge'
import { typeForMode } from '../routes/invites'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

console.log('\n=== invite → track mapping ===')
assert("mode 'video' → track 'video'", __test.trackForInvite({ mode: 'video' }) === 'video')
assert("mode 'chat' → track 'chat'", __test.trackForInvite({ mode: 'chat' }) === 'chat')
assert("no mode, type 'video' → 'video_avatar' (legacy fallback)", __test.trackForInvite({ type: 'video' }) === 'video_avatar')
assert("typeForMode('video') === 'video'", typeForMode('video') === 'video')
assert("typeForMode('chat') === 'chat'", typeForMode('chat') === 'chat')

console.log(`\n${failures === 0 ? '✅ ALL INVITE-BRIDGE TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
