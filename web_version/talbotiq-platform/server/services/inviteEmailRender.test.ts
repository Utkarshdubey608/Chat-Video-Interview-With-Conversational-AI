/**
 * Deterministic unit tests for invite-email rendering + sanitisation. Run with:
 *   npx tsx server/services/inviteEmailRender.test.ts
 * No network/Firestore.
 */
import { buildInviteEmailHtml, sanitizeBodyHtml } from './inviteEmailRender'
import { defaultInviteEmailTemplate } from '../../shared/inviteEmail'
import type { InviteEmailTemplate } from '../../shared/types'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

const tpl: InviteEmailTemplate = {
  id: 't1',
  recruiterId: 'r1',
  createdAt: '',
  updatedAt: '',
  ...defaultInviteEmailTemplate(),
}

console.log('\n=== sanitizeBodyHtml ===')
{
  const out = sanitizeBodyHtml('<p onclick="steal()">hi</p><script>evil()</script>')
  assert('strips <script>', !/script/i.test(out))
  assert('strips on* handlers', !/onclick/i.test(out))
  assert('keeps allowed text', /hi/.test(out))
}
assert('drops disallowed tags (iframe)', !/iframe/i.test(sanitizeBodyHtml('<iframe src=x></iframe><p>ok</p>')))
assert('keeps safe links', /href="https:\/\/x"/.test(sanitizeBodyHtml('<a href="https://x">l</a>')))
assert('strips javascript: scheme', !/javascript:/i.test(sanitizeBodyHtml('<a href="javascript:alert(1)">x</a>')))

console.log('\n=== buildInviteEmailHtml ===')
{
  const built = buildInviteEmailHtml(
    tpl,
    { candidate_name: 'Sam', role: 'SWE', recruiter_name: 'Dana', company: 'Acme', deadline: '' },
    { interviewLink: 'https://x/take/abc', candidateEmail: 'sam@x.com' },
  )
  assert('subject merges role', built.subject === 'Interview invitation — SWE')
  assert('injects the per-candidate link', built.html.includes('https://x/take/abc'))
  assert('renders CTA label', built.html.includes('Start your interview'))
  assert('injects locked "exact email" note w/ candidate email', built.html.includes('sam@x.com') && /exact email/i.test(built.html))
  assert('renders merged body values', built.html.includes('Sam') && built.html.includes('Acme') && built.html.includes('SWE'))
  // Exactly ONE CTA button (default body has {{interview_link}}, no duplicate append).
  const buttonCount = (built.html.match(/take\/abc/g) || []).length
  assert('link appears twice (button + plain fallback), not 3x', buttonCount === 2, `count=${buttonCount}`)
}

// HTML-escaping of a hostile merge value (defence in depth).
{
  const built = buildInviteEmailHtml(
    tpl,
    { candidate_name: '<img src=x onerror=alert(1)>', role: 'R', recruiter_name: 'D', company: 'C', deadline: '' },
    { interviewLink: 'https://x/take/z', candidateEmail: 'a@b.com' },
  )
  assert('escapes hostile merge value', !/<img/i.test(built.html) && built.html.includes('&lt;img'))
}

// Fallback: body without the link token still gets a CTA + the note.
{
  const noLink: InviteEmailTemplate = { ...tpl, bodyHtml: '<p>Hello {{candidate_name}}</p>' }
  const built = buildInviteEmailHtml(
    noLink,
    { candidate_name: 'Sam', role: 'SWE', recruiter_name: 'Dana', company: 'Acme', deadline: '' },
    { interviewLink: 'https://x/take/def', candidateEmail: 'sam@x.com' },
  )
  assert('fallback CTA present when body lacks the token', built.html.includes('https://x/take/def'))
  assert('note still present in fallback case', /exact email/i.test(built.html))
}

console.log(
  `\n${failures === 0 ? '✅ ALL INVITE-EMAIL RENDER TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`,
)
process.exit(failures === 0 ? 0 : 1)
