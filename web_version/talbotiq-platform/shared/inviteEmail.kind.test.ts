/**
 * Unit tests for the kind-aware email engine. Run with:
 *   npx tsx shared/inviteEmail.kind.test.ts
 * Pure — no store/network. Asserts invite output is unchanged and transition
 * kinds render with the correct locked blocks.
 */
import {
  kindOf, mergeVarsFor, requiredTokensFor, validateLockedTokens,
  renderInviteEmail, renderTransitionEmail, defaultTemplateFor, MERGE_VARS,
} from './inviteEmail'
import type { InviteEmailTemplate } from './types'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

const base: InviteEmailTemplate = {
  id: 't1', recruiterId: 'r1', name: 'x', isDefault: false,
  sender: { verifiedSenderEmail: '', fromName: 'TalbotIQ', replyTo: '' },
  subject: 'Interview invitation — {{role}}',
  bodyHtml: '<p>Hi {{candidate_name}},</p><p>{{interview_link}}</p>',
  cta: { text: 'Start your interview', color: '#6B2BE0' },
  branding: { companyName: 'TalbotIQ', accentColor: '#6B2BE0', footer: 'Sent via TalbotIQ.' },
  deadlineText: '', createdAt: 'n', updatedAt: 'n',
}

// kindOf
assert('kindOf absent -> invite', kindOf({}) === 'invite')
assert('kindOf explicit', kindOf({ kind: 'advance' }) === 'advance')

// mergeVarsFor
assert('invite vars === MERGE_VARS', mergeVarsFor('invite') === MERGE_VARS)
assert('advance vars include round_name',
  mergeVarsFor('advance').some((v) => v.token === '{{round_name}}'))
assert('selected vars exclude interview_link',
  !mergeVarsFor('selected').some((v) => v.token === '{{interview_link}}'))

// requiredTokensFor
assert('invite requires link', requiredTokensFor('invite').includes('{{interview_link}}'))
assert('advance requires link', requiredTokensFor('advance').includes('{{interview_link}}'))
assert('selected requires none', requiredTokensFor('selected').length === 0)
assert('rejection requires none', requiredTokensFor('rejection').length === 0)

// validateLockedTokens kind-aware
assert('validate default(invite) fails w/o link',
  validateLockedTokens('hi', '<p>no link</p>').ok === false)
assert('validate selected ok w/o link',
  validateLockedTokens('hi', '<p>no link</p>', 'selected').ok === true)

// invite render (characterization: same structural invariants as before)
const inv = renderInviteEmail(base,
  { candidate_name: 'Ada', role: 'Senior Dev', recruiter_name: 'Rex', company: 'Acme', deadline: '' },
  { interviewLink: 'https://x/take/abc', candidateEmail: 'ada@x.com' })
assert('invite subject substitutes role', inv.subject === 'Interview invitation — Senior Dev')
assert('invite html has CTA anchor', inv.html.includes('background:#6B2BE0') && inv.html.includes('href="https://x/take/abc"'))
assert('invite html has exact-email note', inv.html.includes('linked to <strong>ada@x.com</strong>'))
assert('invite html has paste-link line', inv.html.includes('Or paste this link'))

// advance render (link + note present)
const advTpl = { ...base, kind: 'advance' as const, subject: 'Next round — {{role}}',
  bodyHtml: '<p>Hi {{candidate_name}}, advance to {{round_name}}.</p><p>{{interview_link}}</p>' }
const adv = renderTransitionEmail(advTpl, 'advance',
  { candidate_name: 'Ada', role: 'Senior Dev', recruiter_name: 'Rex', company: 'Acme', round_name: 'Technical' },
  { interviewLink: 'https://x/take/r2', candidateEmail: 'ada@x.com' })
assert('advance substitutes round_name', adv.html.includes('advance to Technical'))
assert('advance has CTA link', adv.html.includes('href="https://x/take/r2"'))
assert('advance has exact-email note', adv.html.includes('linked to <strong>ada@x.com</strong>'))

// selected render (no link, no note)
const selTpl = { ...base, kind: 'selected' as const, subject: 'Selected — {{role}}',
  bodyHtml: '<p>Congrats {{candidate_name}} for {{role}}.</p>' }
const sel = renderTransitionEmail(selTpl, 'selected',
  { candidate_name: 'Ada', role: 'Senior Dev', recruiter_name: 'Rex', company: 'Acme' })
assert('selected has body text', sel.html.includes('Congrats Ada for Senior Dev'))
assert('selected has NO exact-email note', !sel.html.includes('linked to'))
assert('selected has NO paste-link line', !sel.html.includes('Or paste this link'))

// escaping
const xssTpl = { ...base, kind: 'selected' as const, bodyHtml: '<p>{{candidate_name}}</p>' }
const xss = renderTransitionEmail(xssTpl, 'selected',
  { candidate_name: '<script>x</script>', role: 'R', recruiter_name: 'Rex', company: 'Acme' })
assert('candidate name is escaped', xss.html.includes('&lt;script&gt;') && !xss.html.includes('<script>x'))

// defaultTemplateFor
assert('default advance has link token', defaultTemplateFor('advance').bodyHtml.includes('{{interview_link}}'))
assert('default advance kind', defaultTemplateFor('advance').kind === 'advance')
assert('default selected has no link token', !defaultTemplateFor('selected').bodyHtml.includes('{{interview_link}}'))
assert('default rejection kind', defaultTemplateFor('rejection').kind === 'rejection')

console.log(`\n${failures === 0 ? '✅ ALL EMAIL-KIND TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
