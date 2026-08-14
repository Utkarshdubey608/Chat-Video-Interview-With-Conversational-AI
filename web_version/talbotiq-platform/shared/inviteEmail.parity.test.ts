/**
 * Cross-language parity for invite-email rendering.
 *
 * `shared/inviteEmail.ts` is imported by both the recruiter's PREVIEW (this repo's
 * client) and, historically, the Express send path — which is what made the preview
 * byte-identical to the delivered mail. The sender is moving to Python
 * (`backend/app/web/shared/invite_email.py`), and nothing in either language notices
 * if the two drift. A recruiter would approve one email and the candidate would
 * receive another.
 *
 * So both implementations assert against ONE golden file, inputs and outputs
 * together: `contracts/invite_email.fixtures.json`. This test proves the TypeScript
 * still produces those outputs.
 *
 * To change rendering deliberately, in a single commit:
 *   1. change both implementations
 *   2. cd backend && REGENERATE_INVITE_FIXTURES=1 .venv/bin/python -m pytest \
 *        tests/web/test_web_invite_email.py
 *   3. re-run this test
 */
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

import { renderInviteEmail, renderTransitionEmail } from './inviteEmail'
import type { InviteEmailTemplate } from './types'

const here = path.dirname(fileURLToPath(import.meta.url))
// contracts/ sits beside backend/ and web_version/ — it belongs to neither.
const FIXTURES = path.resolve(here, '..', '..', '..', 'contracts', 'invite_email.fixtures.json')

interface FixtureInput {
  name: string
  why: string
  call: 'invite' | 'transition'
  kind?: 'advance' | 'selected' | 'rejection' | null
  template: Record<string, unknown>
  vars: Record<string, string>
  link: string | null
  email: string | null
}

interface Fixtures {
  inputs: FixtureInput[]
  cases: Record<string, { subject: string; html: string }>
}

function load(): Fixtures | null {
  if (!fs.existsSync(FIXTURES)) return null
  return JSON.parse(fs.readFileSync(FIXTURES, 'utf8')) as Fixtures
}

function render(input: FixtureInput): { subject: string; html: string } {
  const tpl = input.template as unknown as InviteEmailTemplate
  if (input.call === 'invite') {
    return renderInviteEmail(
      tpl,
      input.vars as never,
      { interviewLink: input.link ?? '', candidateEmail: input.email ?? '' },
    )
  }
  return renderTransitionEmail(
    tpl,
    input.kind as 'advance' | 'selected' | 'rejection',
    input.vars as never,
    { interviewLink: input.link ?? undefined, candidateEmail: input.email ?? undefined },
  )
}

const fixtures = load()

test('the invite-email golden contract exists', () => {
  assert.ok(
    fixtures,
    `${FIXTURES} is missing. Generate it from the backend:\n` +
      '  cd backend && REGENERATE_INVITE_FIXTURES=1 .venv/bin/python -m pytest ' +
      'tests/web/test_web_invite_email.py',
  )
})

if (fixtures) {
  for (const input of fixtures.inputs) {
    test(`renders ${input.name} identically to the Python sender`, () => {
      const expected = fixtures.cases[input.name]
      assert.ok(expected, `${input.name} has no expected output in the golden file`)

      const actual = render(input)
      assert.equal(actual.subject, expected.subject, `subject drifted — ${input.why}`)
      assert.equal(actual.html, expected.html, `html drifted — ${input.why}`)
    })
  }

  test('every golden case has an input', () => {
    assert.deepEqual(
      Object.keys(fixtures.cases).sort(),
      fixtures.inputs.map((i) => i.name).sort(),
    )
  })
}
