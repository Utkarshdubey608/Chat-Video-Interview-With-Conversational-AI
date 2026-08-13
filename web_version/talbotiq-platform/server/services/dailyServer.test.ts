/**
 * Pure-builder tests for the server-side Daily client (rooms + short-lived
 * tokens for the Two-way Interview). No network calls — only the pure
 * `buildRoomProperties`/`buildTokenProperties` helpers are exercised. Run with:
 *   npx tsx server/services/dailyServer.test.ts
 */
import { buildRoomProperties, buildTokenProperties } from './dailyServer'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

console.log('\n=== buildRoomProperties(nowSec) ===')
{
  const now = 1000
  const props = buildRoomProperties(now)
  assert('enable_knocking === true', props.enable_knocking === true)
  assert('eject_at_room_exp === true', props.eject_at_room_exp === true)
  assert('exp > nowSec', typeof props.exp === 'number' && (props.exp as number) > now)
}

console.log('\n=== buildTokenProperties(opts, nowSec) — owner (recruiter) ===')
{
  const now = 2000
  const props = buildTokenProperties({ roomName: 'room-1', isOwner: true, userName: 'Recruiter A' }, now)
  assert('room_name set', props.room_name === 'room-1')
  assert('is_owner === true', props.is_owner === true)
  assert('user_name set', props.user_name === 'Recruiter A')
  assert('exp > nowSec', typeof props.exp === 'number' && (props.exp as number) > now)
  assert('owner gets enable_recording: cloud', props.enable_recording === 'cloud')
}

console.log('\n=== buildTokenProperties(opts, nowSec) — non-owner (candidate) ===')
{
  const now = 3000
  const props = buildTokenProperties({ roomName: 'room-2', isOwner: false, userName: 'Candidate B' }, now)
  assert('is_owner === false', props.is_owner === false)
  assert('non-owner has no enable_recording', !('enable_recording' in props))
}

console.log(`\n${failures === 0 ? '✅ ALL DAILY-SERVER TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
