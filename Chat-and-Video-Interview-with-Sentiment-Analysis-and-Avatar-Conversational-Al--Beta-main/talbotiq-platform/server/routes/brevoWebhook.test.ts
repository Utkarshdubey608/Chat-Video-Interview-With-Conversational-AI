/**
 * Deterministic unit tests for the Brevo webhook event mapping + correlation. Run:
 *   npx tsx server/routes/brevoWebhook.test.ts
 * Pure functions — no Firestore/network (the DB update path is exercised in dev).
 */
import { mapBrevoEvent, interviewIdFromPayload } from './brevoWebhook'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

console.log('\n=== mapBrevoEvent ===')
assert("delivered → 'delivered'", mapBrevoEvent('delivered') === 'delivered')
assert("hardBounce → 'bounced'", mapBrevoEvent('hardBounce') === 'bounced')
assert("soft_bounce → 'bounced'", mapBrevoEvent('soft_bounce') === 'bounced')
assert("spam → 'spam'", mapBrevoEvent('spam') === 'spam')
assert("blocked → 'failed'", mapBrevoEvent('blocked') === 'failed')
assert("opened → 'opened'", mapBrevoEvent('opened') === 'opened')
assert("uniqueOpened → 'opened'", mapBrevoEvent('uniqueOpened') === 'opened')
assert("click → 'clicked'", mapBrevoEvent('click') === 'clicked')
assert('request → null (ignored)', mapBrevoEvent('request') === null)
assert('unknown → null', mapBrevoEvent('whatever') === null)

console.log('\n=== interviewIdFromPayload ===')
assert(
  'parses interviewId from X-Mailin-custom string',
  interviewIdFromPayload({ 'X-Mailin-custom': '{"interviewId":"abc123"}' }) === 'abc123',
)
assert(
  'parses interviewId from already-parsed object',
  interviewIdFromPayload({ 'X-Mailin-custom': { interviewId: 'zzz' } }) === 'zzz',
)
assert('null when no custom header', interviewIdFromPayload({ email: 'a@b.com' }) === null)
assert('null on malformed JSON', interviewIdFromPayload({ 'X-Mailin-custom': '{bad' }) === null)

console.log(
  `\n${failures === 0 ? '✅ ALL BREVO-WEBHOOK TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`,
)
process.exit(failures === 0 ? 0 : 1)
