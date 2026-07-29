# Configurable Brevo Invite Emails — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a recruiter configure, preview, test, and review the Brevo invite email before it is sent — with reusable per-recruiter templates and delivery tracking — additively, without touching frozen modules or the invite-link/auth logic.

**Architecture:** Extend the existing `InviteWizard` (3→5 steps). Store invite-email templates in the existing Express/JSON store, owned per recruiter (mirror Sessions). Keep SMTP sending; render each email from the template config with per-candidate merge values and a locked interview-link + "exact email" block injected server-side. Add Brevo REST for verified-sender listing and a public webhook for delivery status.

**Tech Stack:** React 18 + Vite + TypeScript, Tailwind (design system in `src/components/ui/index.tsx`), Express 4 (`tsx`), Firebase Admin (`interviews` docs), nodemailer→Brevo SMTP, Brevo REST v3, Tiptap (WYSIWYG), sanitize-html.

## Global Constraints

- **Additive only.** Do not modify frozen modules: sessions, templates, question sets. Only *extend* `server/routes/invites.ts` and `src/features/recruiter/InviteWizard.tsx`.
- **Never remove the locked bits.** Per-candidate link `${origin}/take/<interviewId>` and the "this invitation is linked to <email> — use this exact email" note MUST always be present in every email; recruiter can restyle, not delete. Block send/test if missing.
- **Preserve Firebase interop field names** on `interviews/{id}` exactly. New fields are additive only (`invite`).
- **Server-side secrets only.** `BREVO_API_KEY` and SMTP creds are server-only; never `VITE_`-prefixed, never in the client bundle.
- **Owner isolation.** Invite-email templates are owned per recruiter: `recruiterId` stamped server-side from `auth.uid`; list filtered by owner; get/update/delete `assertOwner`.
- **Merge var syntax:** `{{candidate_name}}`, `{{role}}`, `{{recruiter_name}}`, `{{company}}`, `{{interview_link}}`, `{{deadline}}`.
- **Brand green** `#0d5c3a`; reuse `src/components/ui/index.tsx` primitives and the `Stepper` in `InviteWizard.tsx`.
- **If a task forces a change to frozen modules or invite-link/auth logic → STOP and ask.**

---

### Task 1: Shared template renderer + types + locked-token validator

**Files:**
- Modify: `shared/types.ts` (add `InviteEmailTemplate`, `InviteSendStatus`, `MERGE_VARS`)
- Create: `shared/inviteEmail.ts` (`renderTemplate`, `REQUIRED_TOKENS`, `validateLockedTokens`, `defaultInviteEmailTemplate`)
- Test: `shared/inviteEmail.test.ts`

**Interfaces:**
- Produces: `renderTemplate(str: string, vars: Record<string,string>): string`; `validateLockedTokens(subject: string, bodyHtml: string): { ok: boolean; missing: string[] }`; `defaultInviteEmailTemplate(): Omit<InviteEmailTemplate,'id'|'recruiterId'|'createdAt'|'updatedAt'>`; `MERGE_VARS: {token,label}[]`.
- `InviteEmailTemplate` shape per spec §Data model.

- [ ] **Step 1: Write failing tests** (`shared/inviteEmail.test.ts`)

```ts
import { describe, it, expect } from 'vitest'
import { renderTemplate, validateLockedTokens, defaultInviteEmailTemplate } from './inviteEmail'

describe('renderTemplate', () => {
  it('substitutes known tokens', () => {
    expect(renderTemplate('Hi {{candidate_name}} — {{role}}', { candidate_name: 'Sam', role: 'SWE' }))
      .toBe('Hi Sam — SWE')
  })
  it('leaves unknown tokens untouched', () => {
    expect(renderTemplate('x {{nope}}', {})).toBe('x {{nope}}')
  })
  it('is case-sensitive and trims token whitespace', () => {
    expect(renderTemplate('{{ role }}', { role: 'SWE' })).toBe('SWE')
  })
})

describe('validateLockedTokens', () => {
  it('fails when interview_link missing from body', () => {
    const r = validateLockedTokens('Subject', '<p>no link here</p>')
    expect(r.ok).toBe(false)
    expect(r.missing).toContain('{{interview_link}}')
  })
  it('passes when interview_link present', () => {
    expect(validateLockedTokens('S', '<a>{{interview_link}}</a>').ok).toBe(true)
  })
})

describe('defaultInviteEmailTemplate', () => {
  it('preloads a valid default that passes locked-token validation', () => {
    const t = defaultInviteEmailTemplate()
    expect(t.cta.text).toBe('Start your interview')
    expect(validateLockedTokens(t.subject, t.bodyHtml).ok).toBe(true)
  })
})
```

- [ ] **Step 2: Run to verify fail** — `npx vitest run shared/inviteEmail.test.ts` → FAIL (module not found).

- [ ] **Step 3: Add types to `shared/types.ts`**

```ts
export interface InviteEmailSender { verifiedSenderEmail: string; fromName: string; replyTo?: string }
export interface InviteEmailTemplate {
  id: string
  recruiterId: string
  name: string
  isDefault: boolean
  sender: InviteEmailSender
  subject: string
  bodyHtml: string
  cta: { text: string; color: string }
  branding: BrandingConfig & { footer?: string }
  deadlineText?: string
  createdAt: string
  updatedAt: string
}
export type InviteSendStatusValue =
  | 'accepted' | 'delivered' | 'bounced' | 'spam' | 'failed' | 'opened' | 'clicked'
```

- [ ] **Step 4: Implement `shared/inviteEmail.ts`**

```ts
export const MERGE_VARS = [
  { token: '{{candidate_name}}', label: 'Candidate name' },
  { token: '{{role}}', label: 'Role' },
  { token: '{{recruiter_name}}', label: 'Recruiter name' },
  { token: '{{company}}', label: 'Company' },
  { token: '{{interview_link}}', label: 'Interview link (locked)' },
  { token: '{{deadline}}', label: 'Deadline' },
] as const

export const REQUIRED_TOKENS = ['{{interview_link}}'] as const

export function renderTemplate(str: string, vars: Record<string, string>): string {
  return str.replace(/\{\{\s*([a-z_]+)\s*\}\}/g, (m, key) =>
    Object.prototype.hasOwnProperty.call(vars, key) ? vars[key] : m)
}

export function validateLockedTokens(subject: string, bodyHtml: string): { ok: boolean; missing: string[] } {
  const hay = `${subject}\n${bodyHtml}`
  const missing = REQUIRED_TOKENS.filter((t) => !hay.includes(t))
  return { ok: missing.length === 0, missing }
}

export function defaultInviteEmailTemplate() {
  return {
    name: 'Default invite',
    isDefault: true,
    sender: { verifiedSenderEmail: '', fromName: 'TalbotIQ', replyTo: '' },
    subject: 'Interview invitation — {{role}}',
    bodyHtml:
      '<p>Hi {{candidate_name}},</p>' +
      '<p><strong>{{recruiter_name}}</strong> has invited you to a screening interview for the <strong>{{role}}</strong> role at {{company}}.</p>' +
      '<p>When you\'re ready, open your interview, upload your résumé, and begin — it takes just a few minutes:</p>' +
      '<p>{{interview_link}}</p>',
    cta: { text: 'Start your interview', color: '#0d5c3a' },
    branding: { companyName: 'TalbotIQ', accentColor: '#0d5c3a', footer: 'Sent via TalbotIQ.' },
    deadlineText: '',
  }
}
```

- [ ] **Step 5: Run tests → PASS.** `npx vitest run shared/inviteEmail.test.ts`
- [ ] **Step 6: Commit** — `git add shared/inviteEmail.ts shared/inviteEmail.test.ts shared/types.ts && git commit -m "feat(invite-email): shared renderer, types, locked-token validator + default template"`

> **Note on vitest:** if the repo has no test runner configured, add `vitest` as a devDependency and a `"test": "vitest run"` script in this task's Step 3, and a minimal `vitest.config.ts` with the `@shared` alias. Verify with `npx vitest --version` first.

---

### Task 2: Server-side email HTML shell + sanitizer (locked block injection)

**Files:**
- Create: `server/services/inviteEmailRender.ts` (`buildInviteEmailHtml`, `sanitizeBodyHtml`)
- Modify: `package.json` (add `sanitize-html`, `@types/sanitize-html`)
- Test: `server/services/inviteEmailRender.test.ts`

**Interfaces:**
- Consumes: `renderTemplate` from `shared/inviteEmail`.
- Produces: `buildInviteEmailHtml(tpl: InviteEmailTemplate, vars: Record<string,string>, opts:{interviewLink:string; candidateEmail:string}): { subject:string; html:string }`; `sanitizeBodyHtml(html:string):string`.

- [ ] **Step 1: Write failing test**

```ts
import { describe, it, expect } from 'vitest'
import { buildInviteEmailHtml, sanitizeBodyHtml } from './inviteEmailRender'
import { defaultInviteEmailTemplate } from '../../shared/inviteEmail'

const tpl = { id:'t', recruiterId:'r', createdAt:'', updatedAt:'', ...defaultInviteEmailTemplate() } as any

describe('sanitizeBodyHtml', () => {
  it('strips script tags and on* handlers', () => {
    const out = sanitizeBodyHtml('<p onclick="x()">hi</p><script>evil()</script>')
    expect(out).not.toContain('script'); expect(out).not.toContain('onclick')
  })
})

describe('buildInviteEmailHtml', () => {
  const built = buildInviteEmailHtml(tpl, { candidate_name:'Sam', role:'SWE', recruiter_name:'Dana', company:'Acme', deadline:'' },
    { interviewLink: 'https://x/take/abc', candidateEmail: 'sam@x.com' })
  it('injects the per-candidate link', () => expect(built.html).toContain('https://x/take/abc'))
  it('injects the locked "exact email" note with the candidate email', () =>
    expect(built.html).toContain('sam@x.com') && expect(built.html.toLowerCase()).toContain('exact email'))
  it('renders the CTA label', () => expect(built.html).toContain('Start your interview'))
  it('renders the subject with merged role', () => expect(built.subject).toBe('Interview invitation — SWE'))
})
```

- [ ] **Step 2: Run → FAIL.** `npx vitest run server/services/inviteEmailRender.test.ts`
- [ ] **Step 3: Install dep** — `npm i sanitize-html && npm i -D @types/sanitize-html`
- [ ] **Step 4: Implement `server/services/inviteEmailRender.ts`**

Key requirements in the implementation:
- `sanitizeBodyHtml`: allowlist `p,strong,em,u,a,ul,ol,li,br,h1..h3,span,div,blockquote`; allow `a[href]`, `span[style]` limited to color; strip all `on*`, `script`, `style` tags.
- `buildInviteEmailHtml`: `renderTemplate` on subject + sanitized body; the `{{interview_link}}` token in the body is replaced by an anchor styled as the CTA button (`tpl.cta.color`, `tpl.cta.text`) pointing at `opts.interviewLink`; then always append the **locked note block**:
  `<p style="background:#f0faf5;border:1px solid #dcf5e8;border-radius:8px;padding:10px 14px;color:#0a4a2e;font-size:13px"><strong>Important:</strong> this invitation is linked to <strong>${candidateEmail}</strong>. Sign in — or create your candidate account — using this exact email address to open it.</p>`
  plus a plain-link fallback and the footer; wrap everything in a table-based, inline-styled shell with optional logo (`tpl.branding.logoUrl`) and `tpl.branding.accentColor`.

- [ ] **Step 5: Run → PASS.**
- [ ] **Step 6: Commit** — `git commit -am "feat(invite-email): server email shell + sanitizer with locked link/note injection"`

---

### Task 3: Owned template store + CRUD router + client API

**Files:**
- Modify: `server/store/db.ts` (add `inviteEmailTemplates` map + snapshot load/save)
- Create: `server/routes/inviteEmailTemplates.ts`
- Modify: `server/index.ts` (mount `authenticate, requireRecruiter`)
- Modify: `src/lib/api.ts` (add `inviteEmailTemplatesApi`)
- Test: `server/routes/inviteEmailTemplates.test.ts` (supertest) or a store unit test if no HTTP harness exists.

**Interfaces:**
- Produces routes under `/api/invite-email-templates`: `GET /` (owner-filtered list), `POST /` (create, stamps `recruiterId`), `GET /:id`, `PUT /:id`, `POST /:id/duplicate`, `DELETE /:id`. All `assertOwner` except list/create.
- Client `inviteEmailTemplatesApi = { list, get, create, update, duplicate, remove }`.
- On first list for a recruiter with zero templates, seed a `defaultInviteEmailTemplate()` owned by them.

- [ ] **Step 1: Write failing test** — creating a template stamps `recruiterId` from auth; another recruiter's list does not see it; `assertOwner` blocks cross-owner get (expect 404).
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: `db.ts`** — `inviteEmailTemplates = new Map<string, InviteEmailTemplate>()`; include in `init()` load and `saveNow()` snapshot exactly like `sessions`.
- [ ] **Step 4: `inviteEmailTemplates.ts`** — mirror `server/routes/questionSets.ts` structure but: `create` sets `recruiterId: auth.uid`; `list` returns `[...db.inviteEmailTemplates.values()].filter(t => t.recruiterId === auth.uid)` and seeds a default if empty; `get/update/delete` load then `if (t.recruiterId !== auth.uid) throw new HttpError(404,'Not found')`.
- [ ] **Step 5: Mount in `server/index.ts`** — `app.use('/api/invite-email-templates', authenticate, requireRecruiter, inviteEmailTemplatesRouter)`.
- [ ] **Step 6: `src/lib/api.ts`** — add `inviteEmailTemplatesApi` using the `http<T>()` helper.
- [ ] **Step 7: Run → PASS.**
- [ ] **Step 8: Commit** — `git commit -am "feat(invite-email): owned per-recruiter template store + CRUD + client api"`

---

### Task 4: Brevo verified-senders endpoint + BREVO_API_KEY + env docs

**Files:**
- Create: `server/services/brevo.ts` (`listVerifiedSenders`, `brevoReady`)
- Modify: `server/routes/invites.ts` (add `GET /senders`)
- Modify: `src/lib/api.ts` (`invitesApi.senders`)
- Modify: `.env.example` (document SMTP vars + `BREVO_API_KEY`)
- Test: `server/services/brevo.test.ts` (mock fetch)

**Interfaces:**
- Produces: `listVerifiedSenders(): Promise<{email:string;name:string;active:boolean}[]>` (GET `https://api.brevo.com/v3/senders` with `api-key` header); `GET /api/invites/senders` returns `{ senders, brevoReady }`. If `!brevoReady()` return `{ senders: [], brevoReady: false }` (UI shows manual-entry fallback + guidance).

- [ ] **Step 1..6:** TDD as above; mock global fetch; assert the `api-key` header is set from `process.env.BREVO_API_KEY` and never leaked to client. Commit `feat(invite-email): Brevo verified-senders lookup + env docs`.

---

### Task 5: Extend the send path — per-candidate render + status stamp + test-send

**Files:**
- Modify: `server/routes/invites.ts` — `POST /` accepts optional `emailTemplateId` / inline `emailConfig`; when present, render via `buildInviteEmailHtml` per candidate; stamp `invite:{status:'accepted'|'failed', messageId, sentAt, attempts:1, error?}` on the doc; set `X-Mailin-custom` header `{interviewId}`. Add `POST /test` (send one to `auth.email`). Add `POST /:interviewId/retry`.
- Modify: `server/services/email.ts` — allow passing `headers` + `from`/`replyTo`/`sender name` through to nodemailer; return messageId.
- Modify: `src/lib/api.ts` — `invitesApi.test`, `invitesApi.retry`; extend `create` payload.
- Test: `server/routes/invites.sendrender.test.ts` — the rendered email for a candidate contains that candidate's link + email note; `invite` status stamped.

**Interfaces:**
- Consumes: `buildInviteEmailHtml` (Task 2), template store (Task 3).
- Produces: `sendMail(input:{to,subject,html,headers?,fromName?,replyTo?,from?}): Promise<{sent:boolean;dryRun?:boolean;messageId?:string}>`.
- **Backwards-compatible:** when no `emailTemplateId`/`emailConfig` is provided, fall back to the current `inviteEmail()` (do not break existing behavior).

- [ ] TDD steps; **do not alter** frozen interop fields. Commit `feat(invite-email): configurable per-candidate send + status stamp + test-send + retry`.

---

### Task 6: Brevo delivery webhook

**Files:**
- Create: `server/routes/brevoWebhook.ts` (`POST /api/invites/brevo-webhook`)
- Modify: `server/index.ts` — mount BEFORE `authenticate` on the invites router (public), with a shared-secret/token check (`?token=` or header compared to `BREVO_WEBHOOK_SECRET`).
- Test: `server/routes/brevoWebhook.test.ts` — a `delivered` event with `X-Mailin-custom` interviewId updates `interviews/{id}.invite.status`.

**Interfaces:**
- Consumes: Admin SDK (`adminFirestore`).
- Maps Brevo event → status: `delivered→delivered`, `hard_bounce/soft_bounce→bounced`, `spam→spam`, `opened→opened`, `click→clicked`, `error/blocked→failed`.
- Correlate via the `interviewId` carried in `X-Mailin-custom`; update `invite.status`, `invite.lastEventAt`.

- [ ] TDD; document the public-URL/local-tunnel caveat in README. Commit `feat(invite-email): Brevo delivery webhook + status correlation`.

---

### Task 7: Wizard UI — Invite email step + Review & send + status view + Tiptap

**Files:**
- Modify: `package.json` — add `@tiptap/react`, `@tiptap/starter-kit`, `@tiptap/extension-link`.
- Create: `src/features/recruiter/invite-email/InviteEmailStep.tsx` (sender/subject/body/CTA/branding + preview + test + save-as-template)
- Create: `src/features/recruiter/invite-email/RichTextEditor.tsx` (Tiptap wrapper w/ toolbar + Insert-variable)
- Create: `src/features/recruiter/invite-email/EmailPreview.tsx` (client render via `renderTemplate`; sample + "preview as recipient" switch)
- Create: `src/features/recruiter/invite-email/TemplatePicker.tsx` (load/duplicate/delete via `inviteEmailTemplatesApi`)
- Create: `src/features/recruiter/invite-email/ReviewSend.tsx` (recipients + email side by side; confirm; send)
- Modify: `src/features/recruiter/InviteWizard.tsx` — `STEPS` 3→5; hold `emailConfig` state; step 4 renders `InviteEmailStep`, step 5 renders `ReviewSend`; `submit()` sends the chosen `emailTemplateId`/`emailConfig`; success view adds per-recipient status + retry buttons.

**Interfaces:**
- Consumes: `inviteEmailTemplatesApi`, `invitesApi.senders/test/create/retry`, `renderTemplate`, `validateLockedTokens`, design-system primitives.
- Locked-safety: the `{{interview_link}}` CTA and the "exact email" note render as **locked preview blocks**; "Send test"/"Send" call `validateLockedTokens` first and block with a toast if missing.

- [ ] **Steps:** add deps; build `RichTextEditor` (toolbar: bold/italic/lists/link/H2 + an "Insert variable" dropdown from `MERGE_VARS`); build `EmailPreview`; build `InviteEmailStep` (verified-sender `Select` from `invitesApi.senders`, with a note about SPF/DKIM + branded-domain when senders empty, plus reply-to/from-name Inputs); wire `TemplatePicker` save/load/duplicate/delete; build `ReviewSend`; splice steps into `InviteWizard` reusing `Stepper`; extend success view with status + retry. Manual-verify the flow end to end (`npm run dev`, `/sessions/new`). Commit per sub-part.

---

## Self-Review

- **Spec coverage:** sender/subject/body/branding/CTA/vars → Task 1,2,7. Locked link+note un-removable → Task 2 (inject) + Task 1 (validate) + Task 7 (block). Preview sample+real → Task 7. Test-send → Task 5. Review + send + per-recipient status + retry → Task 5,7. Templates save/load/duplicate/delete owned+isolated → Task 3. Verified senders + SPF/DKIM guidance → Task 4,7. Server-side Brevo key → Task 4. Webhooks delivery status → Task 6. Additive/frozen preserved → Global Constraints + Task 5 back-compat. All covered.
- **Placeholders:** none — logic tasks (1,2) carry full code; 3–7 carry exact files, interfaces, and the non-obvious code inline. UI task lists concrete components/props.
- **Type consistency:** `InviteEmailTemplate`, `renderTemplate`, `validateLockedTokens`, `buildInviteEmailHtml`, `sendMail` signatures are consistent across tasks.
- **Deferred:** scheduling (send-now only v1) — explicitly out of scope per spec.
