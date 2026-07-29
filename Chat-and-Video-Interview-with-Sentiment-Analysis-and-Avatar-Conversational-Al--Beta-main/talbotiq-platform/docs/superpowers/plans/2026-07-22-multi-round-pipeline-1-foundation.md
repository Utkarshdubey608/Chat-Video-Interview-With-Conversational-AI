# Multi-Round Pipeline — Plan 1: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the additive data-model foundation for multi-round interview pipelines — the shared pipeline types, the local-store maps, and a kind-aware extension of the existing configurable-email module — with the invite path unchanged.

**Architecture:** Pipelines and per-candidate progression live in the existing in-memory Express/JSON store (`server/store/db.ts`), mirroring the Sessions ownership model. The just-built invite-email module (`shared/inviteEmail.ts`, `server/routes/inviteEmailTemplates.ts`) gains an optional `kind` discriminator (`invite | advance | selected | rejection`, default `invite`) so the same render/validate/CRUD machinery serves the pipeline's transition emails. No UI, no new HTTP surface for pipelines yet — that is Plan 2. This plan produces tested primitives only.

**Tech Stack:** TypeScript, Node/Express, the repo's hand-rolled `tsx` unit-test convention (a `.test.ts` file that imports exported helpers directly, asserts with a local `assert()` counter, and `process.exit(failures === 0 ? 0 : 1)`). No test framework is installed — do NOT add one.

## Global Constraints

- **Additive only.** The single-interview path and the invite-email flow stay byte-for-byte unchanged. `kind` is OPTIONAL and resolves to `'invite'` when absent, so existing persisted templates and all existing call sites behave exactly as before.
- **Frozen modules untouched:** sessions/templates/question-sets internals, auth/role model, the invite-link `/take/:id` + `materializeInviteSession` claim logic, and the Firestore `interviews/{id}` interop field names. This plan touches none of them.
- **`shared/types.ts` is the single source of truth** for cross-boundary shapes (imported by both the Vite client and the Express server). New shapes go there.
- **Ownership pattern (mirror Sessions):** `recruiterId` is server-stamped from `auth.uid`, never client-supplied; list endpoints filter by owner; single-item reads 404 on cross-owner access (no existence leak). Admins (`auth.admin`) may see all.
- **Test command form:** `npx tsx <path>.test.ts`; expected output ends with `✅ ALL … PASSED` and exit code 0.
- **Brand green** is `#0d5c3a`; default sender name `TalbotIQ`; default footer `Sent via TalbotIQ.`
- **Merge-token syntax** is `{{lower_snake}}`; `renderTemplate` leaves unknown tokens untouched.

## File structure (this plan)

- `shared/types.ts` — MODIFY: add `EmailKind`; add optional `kind` to `InviteEmailTemplate`; add pipeline record types (`AdvanceRule`, `RoundDef`, `Pipeline`, `RoundProgress`, `AuditEntry`, `PipelineCandidate`, `InterviewPipelineRef`).
- `shared/inviteEmail.ts` — MODIFY: add `kindOf`, `mergeVarsFor`, `requiredTokensFor`, `renderEmailShell`, `renderTransitionEmail`, `defaultTemplateFor`; make `renderInviteEmail` a thin wrapper over `renderEmailShell`; give `validateLockedTokens` an optional `kind` param. Existing exports keep their behavior.
- `shared/inviteEmail.kind.test.ts` — CREATE: unit tests for the kind-aware engine + a characterization test that invite output is unchanged.
- `server/store/db.ts` — MODIFY: add `pipelines` + `pipelineCandidates` maps and their snapshot load/save wiring.
- `server/store/db.pipelines.test.ts` — CREATE: unit test that pipelines/candidates persist across `saveNow()`/reload.
- `server/routes/inviteEmailTemplates.ts` — MODIFY: kind-aware `normalize`, `seedDefault(auth, kind)`, and `GET /?kind=` filter; extend `__test`.
- `server/routes/inviteEmailTemplates.test.ts` — MODIFY: add kind assertions.

---

## Task 1: Kind-aware email engine (`shared/inviteEmail.ts` + types)

**Files:**
- Modify: `shared/types.ts` (add `EmailKind`; add `kind?` to `InviteEmailTemplate`)
- Modify: `shared/inviteEmail.ts`
- Test: `shared/inviteEmail.kind.test.ts` (create)

**Interfaces:**
- Consumes: existing `InviteEmailTemplate`, `renderTemplate`, `escapeHtml`, `MERGE_VARS`, `ctaButton` (private), `exactEmailNote`, `defaultInviteEmailTemplate` from `shared/inviteEmail.ts`.
- Produces (later tasks/plans rely on these exact signatures):
  - `type EmailKind = 'invite' | 'advance' | 'selected' | 'rejection'` (in `shared/types.ts`)
  - `kindOf(tpl: { kind?: EmailKind }): EmailKind`
  - `mergeVarsFor(kind: EmailKind): readonly { token: string; label: string }[]`
  - `requiredTokensFor(kind: EmailKind): string[]`
  - `validateLockedTokens(subject: string, bodyHtml: string, kind?: EmailKind): { ok: boolean; missing: string[] }`
  - `renderEmailShell(tpl: InviteEmailTemplate, textVars: Record<string,string>, opts: { interviewLink?: string; candidateEmail?: string }, flags: { includeLink: boolean; includeNote: boolean }): { subject: string; html: string }`
  - `renderTransitionEmail(tpl: InviteEmailTemplate, kind: 'advance'|'selected'|'rejection', vars: TransitionRenderVars, opts?: { interviewLink?: string; candidateEmail?: string }): { subject: string; html: string }`
  - `interface TransitionRenderVars { candidate_name: string; role: string; recruiter_name: string; company: string; round_name?: string; previous_round_name?: string; score?: string }`
  - `defaultTemplateFor(kind: EmailKind): Omit<InviteEmailTemplate,'id'|'recruiterId'|'createdAt'|'updatedAt'>`
  - `renderInviteEmail` — unchanged signature/output (now internally delegates to `renderEmailShell`).

- [ ] **Step 1: Add `EmailKind` and optional `kind` to `shared/types.ts`**

Add near the invite-email block (just above `export interface InviteEmailSender`):

```ts
/** Discriminates configurable emails by transition purpose. Absent === 'invite'. */
export type EmailKind = 'invite' | 'advance' | 'selected' | 'rejection'
```

Then add the `kind` field to `InviteEmailTemplate` (after `isDefault: boolean`):

```ts
  isDefault: boolean
  kind?: EmailKind // absent === 'invite' (backward-compatible; see kindOf())
```

- [ ] **Step 2: Write the failing test `shared/inviteEmail.kind.test.ts`**

```ts
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
  cta: { text: 'Start your interview', color: '#0d5c3a' },
  branding: { companyName: 'TalbotIQ', accentColor: '#0d5c3a', footer: 'Sent via TalbotIQ.' },
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
assert('invite html has CTA anchor', inv.html.includes('background:#0d5c3a') && inv.html.includes('href="https://x/take/abc"'))
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
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `npx tsx shared/inviteEmail.kind.test.ts`
Expected: FAIL — module has no export `kindOf` / `mergeVarsFor` / etc. (import error or assertion failures).

- [ ] **Step 4: Implement the engine in `shared/inviteEmail.ts`**

First, change the import at the top so `EmailKind` comes from types:

```ts
import type { EmailKind, InviteEmailTemplate } from './types'
```

Add these exports (place after `escapeHtml`, before `const HEX`):

```ts
/** Resolve a template's kind (absent === 'invite'). */
export function kindOf(tpl: { kind?: EmailKind }): EmailKind {
  return tpl?.kind ?? 'invite'
}

const ADVANCE_VARS = [
  { token: '{{candidate_name}}', label: 'Candidate name' },
  { token: '{{role}}', label: 'Role' },
  { token: '{{round_name}}', label: 'Next round name' },
  { token: '{{interview_link}}', label: 'Interview link (locked)' },
  { token: '{{recruiter_name}}', label: 'Recruiter name' },
  { token: '{{company}}', label: 'Company' },
  { token: '{{previous_round_name}}', label: 'Previous round name' },
  { token: '{{score}}', label: 'Score' },
] as const
const SELECTED_VARS = [
  { token: '{{candidate_name}}', label: 'Candidate name' },
  { token: '{{role}}', label: 'Role' },
  { token: '{{recruiter_name}}', label: 'Recruiter name' },
  { token: '{{company}}', label: 'Company' },
  { token: '{{score}}', label: 'Score' },
] as const
const REJECTION_VARS = [
  { token: '{{candidate_name}}', label: 'Candidate name' },
  { token: '{{role}}', label: 'Role' },
  { token: '{{recruiter_name}}', label: 'Recruiter name' },
  { token: '{{company}}', label: 'Company' },
] as const

/** Merge variables offered for a given email kind. */
export function mergeVarsFor(kind: EmailKind): readonly { token: string; label: string }[] {
  switch (kind) {
    case 'advance': return ADVANCE_VARS
    case 'selected': return SELECTED_VARS
    case 'rejection': return REJECTION_VARS
    default: return MERGE_VARS
  }
}

/** Tokens that MUST survive to send time, by kind. Link is required only where one is sent. */
export function requiredTokensFor(kind: EmailKind): string[] {
  return kind === 'invite' || kind === 'advance' ? ['{{interview_link}}'] : []
}
```

Replace the existing `validateLockedTokens` with a kind-aware version (default `'invite'` keeps every existing 2-arg call identical):

```ts
export function validateLockedTokens(
  subject: string,
  bodyHtml: string,
  kind: EmailKind = 'invite',
): { ok: boolean; missing: string[] } {
  const hay = `${subject ?? ''}\n${bodyHtml ?? ''}`
  const missing = requiredTokensFor(kind).filter((t) => !hay.includes(t))
  return { ok: missing.length === 0, missing }
}
```

Add the generalized shell (place just before `renderInviteEmail`):

```ts
export interface EmailShellFlags {
  includeLink: boolean
  includeNote: boolean
}

/**
 * Generalized email shell. `textVars` are ALREADY-ESCAPED values (excluding
 * interview_link, handled here). `flags` toggle the locked link CTA and the
 * "exact email" note so the same shell serves invite/advance (link+note) and
 * selected/rejection (neither). `bodyHtml` on `tpl` is assumed SAFE.
 */
export function renderEmailShell(
  tpl: InviteEmailTemplate,
  textVars: Record<string, string>,
  opts: { interviewLink?: string; candidateEmail?: string },
  flags: EmailShellFlags,
): { subject: string; html: string } {
  const link = opts.interviewLink ?? ''
  const subject = renderTemplate(tpl.subject, { ...textVars, interview_link: link })

  const bodyHasLink = (tpl.bodyHtml || '').includes('{{interview_link}}')
  const bodyRendered = renderTemplate(tpl.bodyHtml || '', {
    ...textVars,
    interview_link: flags.includeLink ? ctaButton(tpl, link) : '',
  })
  const fallbackCta = flags.includeLink && !bodyHasLink
    ? `<p style="margin:16px 0">${ctaButton(tpl, link)}</p>` : ''
  const note = flags.includeNote && opts.candidateEmail ? exactEmailNote(opts.candidateEmail) : ''
  const pasteLink = flags.includeLink
    ? `<p style="color:#64748b;font-size:13px">Or paste this link into your browser:<br>${escapeHtml(link)}</p>` : ''

  const accent = HEX.test(tpl.branding?.accentColor || '') ? tpl.branding.accentColor : '#0d5c3a'
  const logo = tpl.branding?.logoUrl
    ? `<img src="${escapeHtml(tpl.branding.logoUrl)}" alt="${escapeHtml(tpl.branding.companyName || '')}" style="max-height:40px;margin-bottom:8px" />`
    : `<div style="font-weight:700;color:${accent};font-size:18px">${escapeHtml(tpl.branding?.companyName || 'TalbotIQ')}</div>`
  const footer = escapeHtml(tpl.branding?.footer || 'Sent via TalbotIQ.')

  const html = `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#eff5f0;padding:24px 0;font-family:Inter,Arial,sans-serif">
  <tr><td align="center">
    <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;background:#ffffff;border:1px solid #dde8e0;border-radius:16px;overflow:hidden">
      <tr><td style="border-top:4px solid ${accent};padding:20px 28px 8px">${logo}</td></tr>
      <tr><td style="padding:8px 28px;color:#0f172a;font-size:15px;line-height:1.6">
        ${bodyRendered}
        ${fallbackCta}
        ${note}
        ${pasteLink}
      </td></tr>
      <tr><td style="padding:14px 28px 22px;color:#94a3b8;font-size:12px;border-top:1px solid #dde8e0">${footer}</td></tr>
    </table>
  </td></tr>
</table>`

  return { subject, html }
}
```

Replace the body of `renderInviteEmail` so it delegates (signature unchanged):

```ts
export function renderInviteEmail(
  tpl: InviteEmailTemplate,
  vars: InviteRenderVars,
  opts: InviteRenderOpts,
): { subject: string; html: string } {
  const textVars: Record<string, string> = {
    candidate_name: escapeHtml(vars.candidate_name),
    role: escapeHtml(vars.role),
    recruiter_name: escapeHtml(vars.recruiter_name),
    company: escapeHtml(vars.company),
    deadline: escapeHtml(vars.deadline),
  }
  return renderEmailShell(
    tpl, textVars,
    { interviewLink: opts.interviewLink, candidateEmail: opts.candidateEmail },
    { includeLink: true, includeNote: true },
  )
}
```

Add the transition renderer + vars type (after `renderInviteEmail`):

```ts
export interface TransitionRenderVars {
  candidate_name: string
  role: string
  recruiter_name: string
  company: string
  round_name?: string
  previous_round_name?: string
  score?: string
}

/** Render a transition email (advance/selected/rejection). advance carries the link+note. */
export function renderTransitionEmail(
  tpl: InviteEmailTemplate,
  kind: 'advance' | 'selected' | 'rejection',
  vars: TransitionRenderVars,
  opts: { interviewLink?: string; candidateEmail?: string } = {},
): { subject: string; html: string } {
  const textVars: Record<string, string> = {
    candidate_name: escapeHtml(vars.candidate_name),
    role: escapeHtml(vars.role),
    recruiter_name: escapeHtml(vars.recruiter_name),
    company: escapeHtml(vars.company),
    round_name: escapeHtml(vars.round_name ?? ''),
    previous_round_name: escapeHtml(vars.previous_round_name ?? ''),
    score: escapeHtml(vars.score ?? ''),
  }
  const includeLink = kind === 'advance'
  return renderEmailShell(tpl, textVars, opts, { includeLink, includeNote: includeLink })
}
```

Finally, add `defaultTemplateFor` (after `defaultInviteEmailTemplate`):

```ts
type EmailTemplateSeed = Omit<InviteEmailTemplate, 'id' | 'recruiterId' | 'createdAt' | 'updatedAt'>

/** Kind-appropriate default template. `defaultTemplateFor('invite')` === the invite default + kind. */
export function defaultTemplateFor(kind: EmailKind): EmailTemplateSeed {
  const sender = { verifiedSenderEmail: '', fromName: 'TalbotIQ', replyTo: '' }
  const branding = { companyName: 'TalbotIQ', accentColor: '#0d5c3a', footer: 'Sent via TalbotIQ.' } as {
    companyName: string; accentColor: string; footer?: string; logoUrl?: string
  }
  if (kind === 'advance') {
    return {
      name: 'Default advance', isDefault: true, kind: 'advance', sender,
      subject: "You've advanced — {{role}} ({{round_name}})",
      bodyHtml:
        '<p>Hi {{candidate_name}},</p>' +
        '<p>Congratulations — you\'ve advanced to the <strong>{{round_name}}</strong> round for the <strong>{{role}}</strong> role at {{company}}.</p>' +
        '<p>Open your next interview to continue:</p>' +
        '<p>{{interview_link}}</p>',
      cta: { text: 'Start next round', color: '#0d5c3a' }, branding, deadlineText: '',
    }
  }
  if (kind === 'selected') {
    return {
      name: 'Default selection', isDefault: true, kind: 'selected', sender,
      subject: "You've been selected — {{role}}",
      bodyHtml:
        '<p>Hi {{candidate_name}},</p>' +
        '<p>Congratulations — following your interviews for the <strong>{{role}}</strong> role at {{company}}, we\'re delighted to move you forward as a selected candidate. Our team will be in touch with next steps.</p>',
      cta: { text: 'View details', color: '#0d5c3a' }, branding, deadlineText: '',
    }
  }
  if (kind === 'rejection') {
    return {
      name: 'Default rejection', isDefault: true, kind: 'rejection', sender,
      subject: 'Update on your {{role}} application',
      bodyHtml:
        '<p>Hi {{candidate_name}},</p>' +
        '<p>Thank you for taking the time to interview for the <strong>{{role}}</strong> role at {{company}}. After careful consideration we won\'t be moving forward at this time. We genuinely appreciate the effort you put in and wish you every success.</p>',
      cta: { text: '', color: '#0d5c3a' }, branding, deadlineText: '',
    }
  }
  return { ...defaultInviteEmailTemplate(), kind: 'invite' }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `npx tsx shared/inviteEmail.kind.test.ts`
Expected: PASS — ends with `✅ ALL EMAIL-KIND TESTS PASSED`, exit code 0.

- [ ] **Step 6: Verify the invite flow's existing tests still pass**

Run: `npx tsx shared/inviteEmail.test.ts`
Expected: PASS (the pre-existing invite-email tests are unaffected — `renderInviteEmail` output is structurally unchanged).

- [ ] **Step 7: Commit**

```bash
git add shared/types.ts shared/inviteEmail.ts shared/inviteEmail.kind.test.ts
git commit -m "feat(pipeline): kind-aware email engine (invite/advance/selected/rejection)"
```

---

## Task 2: Pipeline data model + local-store maps (`shared/types.ts` + `server/store/db.ts`)

**Files:**
- Modify: `shared/types.ts` (pipeline record types)
- Modify: `server/store/db.ts` (maps + snapshot wiring)
- Test: `server/store/db.pipelines.test.ts` (create)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces (Plan 2/3 rely on these):
  - `type AdvanceRule = { kind: 'threshold'; value: number } | { kind: 'topN'; value: number }`
  - `interface RoundDef { index: number; name: string; mode: TrackType; source?: 'tailor'|'set'; config?: TailorConfig; questionSetId?: string; advanceRule?: AdvanceRule }`
  - `interface Pipeline { id: string; recruiterId: string; role: string; type: 'multi'; name?: string; rounds: RoundDef[]; createdAt: string; updatedAt: string }`
  - `type PipelineCandidateStatus = 'in_round'|'advanced'|'selected'|'not_advancing'`
  - `interface RoundProgress { roundIndex: number; interviewId: string; invitedAt: string }`
  - `interface AuditEntry { at: string; byUid: string; action: 'invited'|'advanced'|'selected'|'not_advancing'|'moved_back'; fromRound?: number; toRound?: number; basis?: string; emailResult?: 'accepted'|'failed'|'skipped' }`
  - `interface PipelineCandidate { id: string; pipelineId: string; recruiterId: string; candidateEmail: string; candidateEmailLower: string; candidateName?: string; role: string; currentRoundIndex: number; status: PipelineCandidateStatus; perRound: RoundProgress[]; history: AuditEntry[]; createdAt: string; updatedAt: string }`
  - `interface InterviewPipelineRef { pipelineId: string; roundIndex: number; pipelineCandidateId: string }`
  - `db.pipelines: Map<string, Pipeline>` and `db.pipelineCandidates: Map<string, PipelineCandidate>` (keyed by `id`), persisted in the snapshot.

- [ ] **Step 1: Add pipeline types to `shared/types.ts`**

`TrackType` and `TailorConfig` already exist in `shared/types.ts` (`TrackType` near the top; the tailor config fields are used by `CreateInvitesRequest.config`). Add this block near the invite-email block. If a `TailorConfig` interface is not already exported, add the `RoundDef.config` field as the inline object shown here (matching `CreateInvitesRequest.config`).

```ts
/* ── Multi-round interview pipelines (additive; local Express/JSON store) ──────
 * A Pipeline groups ordered rounds for a role. Each round a candidate enters is a
 * real interviews/{id} invite doc (reuses the /take/:id + claim + scoring path).
 * Per-candidate progression is tracked in PipelineCandidate. Owned per recruiter
 * (recruiterId server-stamped), mirroring Sessions. */
export type AdvanceRule =
  | { kind: 'threshold'; value: number }  // overall score >= value
  | { kind: 'topN'; value: number }       // top N by score

export interface RoundDef {
  index: number                 // 0-based, contiguous
  name: string
  mode: TrackType               // async auto-scored subset in v1
  source?: 'tailor' | 'set'
  config?: {
    style: QuestionStyle
    techCount: number
    nonTechCount: number
    difficulty: DifficultyChoice
    domains: string[]
    model: GeminiModel
  }
  questionSetId?: string
  advanceRule?: AdvanceRule
}

export interface Pipeline {
  id: string
  recruiterId: string           // OWNER — server-stamped
  role: string
  type: 'multi'                 // single-interview setups create no pipeline
  name?: string
  rounds: RoundDef[]            // ordered; length >= 1
  createdAt: string
  updatedAt: string
}

export type PipelineCandidateStatus = 'in_round' | 'advanced' | 'selected' | 'not_advancing'

export interface RoundProgress {
  roundIndex: number
  interviewId: string           // interviews/{id} doc + local session id for this round
  invitedAt: string
}

export interface AuditEntry {
  at: string
  byUid: string
  action: 'invited' | 'advanced' | 'selected' | 'not_advancing' | 'moved_back'
  fromRound?: number
  toRound?: number
  basis?: string                // "drag" | "threshold>=60" | "topN=5"
  emailResult?: 'accepted' | 'failed' | 'skipped'
}

export interface PipelineCandidate {
  id: string
  pipelineId: string
  recruiterId: string           // OWNER — server-stamped
  candidateEmail: string
  candidateEmailLower: string
  candidateName?: string
  role: string
  currentRoundIndex: number
  status: PipelineCandidateStatus
  perRound: RoundProgress[]
  history: AuditEntry[]
  createdAt: string
  updatedAt: string
}

/** Additive, Flutter-ignored ref written onto a round's interviews/{id} doc. */
export interface InterviewPipelineRef {
  pipelineId: string
  roundIndex: number
  pipelineCandidateId: string
}
```

Note: `QuestionStyle`, `DifficultyChoice`, `GeminiModel` are already exported in `shared/types.ts`; if any is missing, use the inline union from `CreateInvitesRequest.config` instead. Do NOT redefine them.

- [ ] **Step 2: Write the failing test `server/store/db.pipelines.test.ts`**

```ts
/**
 * Pipelines persist across save/reload in the Express/JSON store. Run with:
 *   npx tsx server/store/db.pipelines.test.ts
 * Uses the real db singleton + saveNow(); asserts the snapshot round-trips.
 */
import { db } from './db'
import type { Pipeline, PipelineCandidate } from '../../shared/types'

let failures = 0
function assert(label: string, cond: boolean) {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}`)
  if (!cond) failures++
}

db.init()

const now = '2026-07-22T00:00:00.000Z'
const p: Pipeline = {
  id: 'pl-test-1', recruiterId: 'rec-1', role: 'Backend Dev', type: 'multi',
  rounds: [
    { index: 0, name: 'Screening', mode: 'chatbot' },
    { index: 1, name: 'Technical', mode: 'video', advanceRule: { kind: 'threshold', value: 60 } },
  ],
  createdAt: now, updatedAt: now,
}
const c: PipelineCandidate = {
  id: 'pc-test-1', pipelineId: 'pl-test-1', recruiterId: 'rec-1',
  candidateEmail: 'A@x.com', candidateEmailLower: 'a@x.com', role: 'Backend Dev',
  currentRoundIndex: 0, status: 'in_round',
  perRound: [{ roundIndex: 0, interviewId: 'iv-1', invitedAt: now }],
  history: [{ at: now, byUid: 'rec-1', action: 'invited', toRound: 0 }],
  createdAt: now, updatedAt: now,
}

db.pipelines.set(p.id, p)
db.pipelineCandidates.set(c.id, c)
db.saveNow()

// Simulate reload: clear the maps, re-init from the file just written.
db.pipelines.clear()
db.pipelineCandidates.clear()
db.init()

const rp = db.pipelines.get('pl-test-1')
const rc = db.pipelineCandidates.get('pc-test-1')
assert('pipeline reloaded', !!rp && rp.rounds.length === 2)
assert('round advanceRule survives', rp?.rounds[1].advanceRule?.value === 60)
assert('candidate reloaded', !!rc && rc.perRound[0].interviewId === 'iv-1')
assert('candidate history survives', rc?.history[0].action === 'invited')

// cleanup so we don't leave test rows in db.json
db.pipelines.delete('pl-test-1')
db.pipelineCandidates.delete('pc-test-1')
db.saveNow()

console.log(`\n${failures === 0 ? '✅ ALL PIPELINE-STORE TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `npx tsx server/store/db.pipelines.test.ts`
Expected: FAIL — `db.pipelines`/`db.pipelineCandidates` are undefined (`Cannot read properties of undefined (reading 'set')`).

- [ ] **Step 4: Add the maps + snapshot wiring in `server/store/db.ts`**

Extend the type import (add the two new types):

```ts
import type {
  InterviewTemplate,
  QuestionSet,
  InterviewSession,
  ResultReport,
  AppUser,
  AvatarInterviewSettings,
  InviteEmailTemplate,
  Pipeline,
  PipelineCandidate,
} from '../../shared/types'
```

Add to the `Snapshot` interface (after `inviteEmailTemplates?`):

```ts
  pipelines?: Pipeline[]
  pipelineCandidates?: PipelineCandidate[]
```

Add the maps to the `Database` class (after `inviteEmailTemplates`):

```ts
  pipelines = new Map<string, Pipeline>()                     // owned per recruiter
  pipelineCandidates = new Map<string, PipelineCandidate>()   // owned per recruiter
```

Add to `init()` load loop (after the `inviteEmailTemplates` line):

```ts
        snap.pipelines?.forEach((p) => this.pipelines.set(p.id, p))
        snap.pipelineCandidates?.forEach((c) => this.pipelineCandidates.set(c.id, c))
```

Add to `saveNow()` snapshot object (after `inviteEmailTemplates`):

```ts
        pipelines: [...this.pipelines.values()],
        pipelineCandidates: [...this.pipelineCandidates.values()],
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `npx tsx server/store/db.pipelines.test.ts`
Expected: PASS — ends with `✅ ALL PIPELINE-STORE TESTS PASSED`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add shared/types.ts server/store/db.ts server/store/db.pipelines.test.ts
git commit -m "feat(pipeline): pipeline + candidate types and store persistence"
```

---

## Task 3: Kind support in the email-templates router (`server/routes/inviteEmailTemplates.ts`)

**Files:**
- Modify: `server/routes/inviteEmailTemplates.ts`
- Test: `server/routes/inviteEmailTemplates.test.ts` (extend)

**Interfaces:**
- Consumes: `defaultTemplateFor`, `kindOf` from Task 1; `db.inviteEmailTemplates`.
- Produces: `GET /api/invite-email-templates?kind=<kind>` returns owner-scoped templates of that kind, seeding a kind-appropriate default when none exist; `normalize` preserves/validates `kind`; `seedDefault(auth, kind)`; `__test` also exports `defaultTemplateFor` usage indirectly. `GET /` with no `kind` behaves exactly as today (kind `invite`).

- [ ] **Step 1: Add kind assertions to `server/routes/inviteEmailTemplates.test.ts`**

Open the existing test file. Add these imports at the top (extend the existing import lines; do not duplicate):

```ts
import { kindOf } from '../../shared/inviteEmail'
import type { EmailKind } from '../../shared/types'
```

Then, immediately BEFORE the final `console.log(...)` summary block, insert:

```ts
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
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx tsx server/routes/inviteEmailTemplates.test.ts`
Expected: FAIL — `normalize({}).kind` is `undefined` (no `kind` in output) and `seedDefault` does not accept a `kind` argument.

- [ ] **Step 3: Implement kind support in `server/routes/inviteEmailTemplates.ts`**

Update the imports:

```ts
import { defaultTemplateFor, kindOf } from '../../shared/inviteEmail'
import type { AuthContext, EmailKind, InviteEmailTemplate } from '../../shared/types'
```

Add a kind allowlist + parser near the top (after `const owns = ...`):

```ts
const EMAIL_KINDS: EmailKind[] = ['invite', 'advance', 'selected', 'rejection']
const parseKind = (v: unknown): EmailKind =>
  (EMAIL_KINDS as string[]).includes(String(v)) ? (v as EmailKind) : 'invite'
```

Replace `normalize` so it carries `kind` and defaults from the kind-appropriate template:

```ts
function normalize(body: unknown): Omit<InviteEmailTemplate, 'id' | 'recruiterId' | 'createdAt' | 'updatedAt'> {
  const b = (body ?? {}) as Record<string, any>
  const kind = parseKind(b.kind)
  const d = defaultTemplateFor(kind)
  return {
    kind,
    name: (typeof b.name === 'string' && b.name.trim()) || d.name,
    isDefault: Boolean(b.isDefault),
    sender: {
      verifiedSenderEmail: String(b.sender?.verifiedSenderEmail ?? d.sender.verifiedSenderEmail),
      fromName: String(b.sender?.fromName ?? d.sender.fromName),
      replyTo: b.sender?.replyTo ? String(b.sender.replyTo) : '',
    },
    subject: typeof b.subject === 'string' ? b.subject : d.subject,
    bodyHtml: typeof b.bodyHtml === 'string' ? b.bodyHtml : d.bodyHtml,
    cta: {
      text: typeof b.cta?.text === 'string' ? b.cta.text : d.cta.text,
      color: (typeof b.cta?.color === 'string' && b.cta.color.trim()) || d.cta.color,
    },
    branding: {
      companyName: String(b.branding?.companyName ?? d.branding.companyName),
      logoUrl: b.branding?.logoUrl ? String(b.branding.logoUrl) : undefined,
      accentColor: (typeof b.branding?.accentColor === 'string' && b.branding.accentColor.trim()) || d.branding.accentColor,
      footer: b.branding?.footer != null ? String(b.branding.footer) : d.branding.footer,
    },
    deadlineText: b.deadlineText != null ? String(b.deadlineText) : d.deadlineText,
  }
}
```

Note: `cta.text` no longer coerces empty-to-default (selected/rejection defaults use an empty CTA text meaningfully). This keeps invite behavior intact because the invite default `cta.text` is non-empty and normalize only falls back when the field is absent.

Replace `seedDefault` to accept a kind:

```ts
function seedDefault(auth: AuthContext, kind: EmailKind = 'invite'): InviteEmailTemplate {
  const now = new Date().toISOString()
  const tpl: InviteEmailTemplate = {
    id: randomUUID(),
    recruiterId: auth.uid,
    createdAt: now,
    updatedAt: now,
    ...defaultTemplateFor(kind),
  }
  db.inviteEmailTemplates.set(tpl.id, tpl)
  db.scheduleSave()
  return tpl
}
```

Replace the `GET /` handler to filter by kind (defaults to invite → unchanged for existing callers):

```ts
inviteEmailTemplatesRouter.get('/', ah((req, res) => {
  const auth = requireAuth(req)
  const kind = parseKind(req.query.kind)
  let mine = [...db.inviteEmailTemplates.values()].filter((t) => owns(t, auth) && kindOf(t) === kind)
  if (mine.length === 0) mine = [seedDefault(auth, kind)]
  res.json(mine.sort((a, b) => Number(b.isDefault) - Number(a.isDefault) || a.name.localeCompare(b.name)))
}))
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx tsx server/routes/inviteEmailTemplates.test.ts`
Expected: PASS — ends with `✅ ALL INVITE-EMAIL-TEMPLATE TESTS PASSED`, exit code 0.

- [ ] **Step 5: Re-run the full foundation test set**

Run each; all must end in `✅` / exit 0:
```bash
npx tsx shared/inviteEmail.test.ts
npx tsx shared/inviteEmail.kind.test.ts
npx tsx server/store/db.pipelines.test.ts
npx tsx server/routes/inviteEmailTemplates.test.ts
```
Expected: all PASS (invite flow unaffected; new kind + store behavior verified).

- [ ] **Step 6: Commit**

```bash
git add server/routes/inviteEmailTemplates.ts server/routes/inviteEmailTemplates.test.ts
git commit -m "feat(pipeline): kind-aware email-template CRUD (?kind= filter, per-kind default seed)"
```

---

## Self-review notes (author)

- **Spec coverage (Plan 1 slice):** pipeline data model → Task 2; `EmailKind` extension + kind-aware render/validate/defaults → Task 1; kind-aware template storage/CRUD → Task 3. The additive `interviews/{id}.pipeline` ref is defined (`InterviewPipelineRef`, Task 2) and consumed in Plan 2. Setup UI, results Kanban, advancement, transition send/preview, Selected/CSV, safeguards are **out of scope for Plan 1** (Plans 2–3).
- **Backward compatibility:** `kind` optional + `kindOf` default; `validateLockedTokens` kind defaults to `'invite'`; `GET /` with no `kind` → invite. `renderInviteEmail` output structurally unchanged (Task 1 characterization asserts CTA, exact-email note, and paste-link line all still present, and the pre-existing `shared/inviteEmail.test.ts` still passes).
- **Type consistency:** `EmailKind` defined once in `shared/types.ts`, imported by `shared/inviteEmail.ts` and the router. `defaultTemplateFor` returns `Omit<InviteEmailTemplate,'id'|'recruiterId'|'createdAt'|'updatedAt'>`, matching `normalize`'s return type and `seedDefault`'s spread.
- **No placeholders.** Every step has runnable code/commands and expected output.
