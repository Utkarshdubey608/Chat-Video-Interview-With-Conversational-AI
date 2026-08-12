/**
 * Deterministic unit tests for the shared invite-email helpers. Run with:
 *   npx tsx shared/inviteEmail.test.ts
 * Pure functions — no network/Firestore.
 */
import {
  renderTemplate,
  validateLockedTokens,
  unknownTokens,
  defaultInviteEmailTemplate,
} from './inviteEmail'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

console.log('\n=== renderTemplate ===')
assert(
  'substitutes known tokens',
  renderTemplate('Hi {{candidate_name}} — {{role}}', { candidate_name: 'Sam', role: 'SWE' }) ===
    'Hi Sam — SWE',
)
assert('leaves unknown tokens untouched', renderTemplate('x {{nope}}', {}) === 'x {{nope}}')
assert('tolerates inner whitespace', renderTemplate('{{ role }}', { role: 'SWE' }) === 'SWE')
assert('empty input → empty string', renderTemplate('', { role: 'SWE' }) === '')
assert(
  'missing value renders empty, not undefined',
  renderTemplate('a{{deadline}}b', { deadline: '' }) === 'ab',
)

console.log('\n=== validateLockedTokens ===')
{
  const r = validateLockedTokens('Subject', '<p>no link here</p>')
  assert('fails when interview_link missing', r.ok === false)
  assert('reports the missing token', r.missing.includes('{{interview_link}}'))
}
assert(
  'passes when interview_link present in body',
  validateLockedTokens('S', '<a>{{interview_link}}</a>').ok === true,
)
assert(
  'passes when interview_link present in subject',
  validateLockedTokens('open {{interview_link}}', '<p>hi</p>').ok === true,
)

console.log('\n=== unknownTokens ===')
assert('flags unrecognised tokens', unknownTokens('{{role}} {{bogus}}').join(',') === '{{bogus}}')
assert('empty when all known', unknownTokens('{{role}} {{company}}').length === 0)

console.log('\n=== defaultInviteEmailTemplate ===')
{
  const t = defaultInviteEmailTemplate()
  assert('CTA defaults to "Start your interview"', t.cta.text === 'Start your interview')
  assert('CTA colour is brand green', t.cta.color === '#0d5c3a')
  assert('is marked isDefault', t.isDefault === true)
  assert(
    'default passes locked-token validation',
    validateLockedTokens(t.subject, t.bodyHtml).ok === true,
  )
  assert('default uses only known tokens', unknownTokens(t.subject + t.bodyHtml).length === 0)
}

console.log(
  `\n${failures === 0 ? '✅ ALL INVITE-EMAIL HELPER TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`,
)
process.exit(failures === 0 ? 0 : 1)
