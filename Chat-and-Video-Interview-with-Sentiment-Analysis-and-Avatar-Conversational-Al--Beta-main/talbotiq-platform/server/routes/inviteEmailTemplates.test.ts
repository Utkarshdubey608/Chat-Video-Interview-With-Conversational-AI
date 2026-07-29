/**
 * Deterministic unit tests for invite-email-template ownership isolation. Run with:
 *   npx tsx server/routes/inviteEmailTemplates.test.ts
 * Exercises the exported helpers directly (no HTTP harness / Firestore / network).
 */
import { db } from '../store/db'
import { __test } from './inviteEmailTemplates'
import { kindOf } from '../../shared/inviteEmail'
import type { AuthContext, InviteEmailTemplate, EmailKind } from '../../shared/types'

const { owns, normalize, loadOwned, seedDefault } = __test

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}
function throws(label: string, fn: () => void, statusWanted?: number) {
  try {
    fn()
    assert(label, false, 'expected throw')
  } catch (e: any) {
    assert(label, statusWanted ? e?.status === statusWanted : true, statusWanted ? `status=${e?.status}` : '')
  }
}

const alice: AuthContext = { uid: 'alice', email: 'a@x.com', emailVerified: true, role: 'recruiter', admin: false }
const bob: AuthContext = { uid: 'bob', email: 'b@x.com', emailVerified: true, role: 'recruiter', admin: false }
const admin: AuthContext = { uid: 'root', email: 'r@x.com', emailVerified: true, role: 'recruiter', admin: true }

let idSeq = 0
const mk = (recruiterId: string): InviteEmailTemplate => ({
  id: `tpl-${recruiterId}-${++idSeq}`,
  recruiterId,
  createdAt: '', updatedAt: '',
  name: 'x', isDefault: false,
  sender: { verifiedSenderEmail: '', fromName: 'x' },
  subject: 's', bodyHtml: '<p>{{interview_link}}</p>',
  cta: { text: 'go', color: '#0d5c3a' },
  branding: { companyName: 'c', accentColor: '#0d5c3a' },
})

console.log('\n=== owns ===')
{
  const t = mk('alice')
  assert('owner sees own', owns(t, alice) === true)
  assert('non-owner does NOT see', owns(t, bob) === false)
  assert('admin sees others', owns(mk('someoneelse'), admin) === true)
}

console.log('\n=== normalize server-owns id/owner/timestamps ===')
{
  const n = normalize({ name: 'My tpl', recruiterId: 'HACK', id: 'HACK', createdAt: 'HACK', subject: 'Hi {{role}}' }) as any
  assert('name kept', n.name === 'My tpl')
  assert('subject kept', n.subject === 'Hi {{role}}')
  assert('client cannot inject recruiterId', !('recruiterId' in n))
  assert('client cannot inject id', !('id' in n))
  assert('client cannot inject createdAt', !('createdAt' in n))
  assert('defaults fill missing cta', n.cta.text === 'Start your interview')
}

console.log('\n=== loadOwned isolation (cross-owner → 404) ===')
{
  const t = mk('alice')
  db.inviteEmailTemplates.set(t.id, t)
  assert('owner loads own', loadOwned(t.id, alice).id === t.id)
  throws('cross-owner load throws 404', () => loadOwned(t.id, bob), 404)
  throws('missing id throws 404', () => loadOwned('does-not-exist', alice), 404)
  assert('admin loads any', loadOwned(t.id, admin).id === t.id)
  db.inviteEmailTemplates.delete(t.id)
}

console.log('\n=== seedDefault ===')
{
  const before = db.inviteEmailTemplates.size
  const seeded = seedDefault(bob)
  assert('seed is owned by caller', seeded.recruiterId === 'bob')
  assert('seed marked default', seeded.isDefault === true)
  assert('seed passes into store', db.inviteEmailTemplates.size === before + 1)
  db.inviteEmailTemplates.delete(seeded.id)
}

{
  const { normalize, seedDefault } = __test
  // normalize defaults kind to 'invite' and preserves a valid kind
  assert('normalize defaults kind invite', (normalize({}) as any).kind === 'invite')
  assert('normalize keeps advance kind', (normalize({ kind: 'advance' }) as any).kind === 'advance')
  assert('normalize rejects bogus kind', (normalize({ kind: 'bogus' }) as any).kind === 'invite')

  // seedDefault(kind) creates a template of that kind
  const adv = seedDefault(alice, 'advance' as EmailKind)
  assert('seed advance owned by caller', adv.recruiterId === alice.uid)
  assert('seed advance kind', kindOf(adv) === 'advance')
  assert('seed advance requires link token', adv.bodyHtml.includes('{{interview_link}}'))
  db.inviteEmailTemplates.delete(adv.id)

  const sel = seedDefault(alice, 'selected' as EmailKind)
  assert('seed selected kind', kindOf(sel) === 'selected')
  assert('seed selected has no link token', !sel.bodyHtml.includes('{{interview_link}}'))
  db.inviteEmailTemplates.delete(sel.id)

  // PUT-preserving-kind regression: normalize's fallbackKind must not let an absent
  // body.kind silently downgrade a non-invite template to 'invite' on update.
  assert('normalize fallbackKind used when body omits kind', (normalize({}, 'advance' as EmailKind) as any).kind === 'advance')
  assert('normalize body kind wins over fallback', (normalize({ kind: 'selected' }, 'advance' as EmailKind) as any).kind === 'selected')
  assert('normalize default fallback still invite', (normalize({}) as any).kind === 'invite')
}

console.log(
  `\n${failures === 0 ? '✅ ALL INVITE-EMAIL-TEMPLATE TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`,
)
process.exit(failures === 0 ? 0 : 1)
