# Configurable Brevo Invite Emails — Design Spec

**Date:** 2026-07-22
**Branch:** `feat/avatar-screening-migration`
**Status:** Approved to build (defaults locked; see Open-items)

## Problem

On the "Set up an interview & invite" flow (`/sessions/new`, `InviteWizard`), clicking
**Create invites** immediately creates the `interviews/{id}` docs *and* auto-sends a
hard-coded invite email (`server/routes/invites.ts` → `inviteEmail()` → SMTP via
`server/services/email.ts`). The recruiter cannot configure, preview, or test the email,
and cannot review the batch before it goes out.

This feature inserts a **configure → preview → test → review → send** step before the
actual send, and adds per-recruiter reusable email templates + delivery tracking — all
**additively**, without touching the frozen modules (sessions, templates, question sets)
or the invite-link / assigned-email auth logic.

## Verified context (facts this design relies on)

- **Invite flow:** `src/features/recruiter/InviteWizard.tsx` is a 3-step wizard
  (Mode & role → Tailor/reuse → Add candidates). `submit()` → `invitesApi.create` →
  `POST /api/invites` (`server/routes/invites.ts:65`).
- **Send today:** `nodemailer` → **Brevo SMTP relay** (`server/services/email.ts`);
  HTML built in `inviteEmail()` (`invites.ts:40`). **No Brevo REST API is used.**
  Dry-run when SMTP env vars are absent.
- **Per-candidate link:** `${origin}/take/<interviewId>` (`invites.ts:152`). The link
  and the *"this invitation is linked to <email> — use this exact email"* note are
  **functionally required**: enforced server-side by a 403 at claim time
  (`server/services/inviteBridge.ts` `materializeInviteSession`).
- **Isolation reality:** Question Sets & Templates are **not** in Firestore and have
  **no** per-recruiter isolation (in-memory Express store → `server/data/db.json`). The
  only genuine owned-per-recruiter pattern is **Sessions**: `recruiterId: auth.uid`
  stamped server-side (`server/routes/sessions.ts:163`), reads filtered by `ownsSession`
  (`server/middleware/auth.ts:91`). **We mirror Sessions, not question sets.**
- **Design system:** primitives in `src/components/ui/index.tsx` (Button, Card, Input,
  Textarea, Select, Toggle, Modal, Badge…); brand green `#0d5c3a`; wizard `Stepper` in
  `InviteWizard.tsx:61`. **No WYSIWYG editor installed.**
- **Branding type exists:** `BrandingConfig { companyName, logoUrl?, accentColor, welcomeMessage? }`
  (`shared/types.ts:80`).
- **`.env` is gitignored** (local-only; not in git history). `.env.example` does **not**
  document the SMTP vars — a gap this spec fixes.

## Resolved decisions

| Fork | Decision |
|---|---|
| Template storage & isolation | **Express/JSON store**, mirror Sessions (`recruiterId` server-stamped, `ownsSession`-style filter). No new Firestore surface. |
| Brevo send path | **Keep SMTP send**; add Brevo **REST** only for `GET /v3/senders` (verified senders). New server-only `BREVO_API_KEY`. |
| Body editor | **WYSIWYG (Tiptap)** for the body region; locked non-editable CTA/link + note blocks; server-side HTML sanitization. |
| Send status | **Full delivery tracking via Brevo webhooks** + send-time accepted/failed baseline + retry. |
| Editor library | **Tiptap** (StarterKit + Link), styled to tokens. |
| Scheduling | **Send-now only in v1**; scheduling deferred (SMTP has no native scheduled send). |
| Wizard layout | **5 steps** (add "Invite email" + "Review & send" before send). |

## Data model

### New: `InviteEmailTemplate` (owned per recruiter)

```ts
interface InviteEmailTemplate {
  id: string
  recruiterId: string            // OWNER — server-stamped from auth.uid, never client-supplied
  name: string
  isDefault: boolean             // one preloaded default per recruiter
  sender: {
    verifiedSenderEmail: string  // must match a Brevo-verified sender
    fromName: string
    replyTo?: string
  }
  subject: string                // supports {{vars}}
  bodyHtml: string               // sanitized WYSIWYG output (editable body region only)
  intro?: string                 // optional structured fallback / plain-text seed
  cta: { text: string; color: string }        // default "Start your interview" / #0d5c3a
  branding: BrandingConfig & { footer?: string }
  deadlineText?: string
  createdAt: string
  updatedAt: string
}
```

Storage: `db.inviteEmailTemplates = new Map<string, InviteEmailTemplate>()` in
`server/store/db.ts` (add to snapshot load/save like `sessions`). Router
`server/routes/inviteEmailTemplates.ts` (list/get/create/update/duplicate/delete),
mounted `authenticate, requireRecruiter`; **create stamps `recruiterId: auth.uid`**,
**list filters by owner**, get/update/delete `assertOwner`. Client `inviteEmailTemplatesApi`
in `src/lib/api.ts`; React Query hooks in the UI mirroring `QuestionSetsPage`.

### Additive fields on `interviews/{id}` (Flutter-safe, unknown keys ignored)

```ts
invite?: {
  messageId?: string
  status: 'accepted' | 'delivered' | 'bounced' | 'spam' | 'failed' | 'opened' | 'clicked'
  error?: string
  sentAt?: Timestamp
  attempts: number
  lastEventAt?: Timestamp
}
```

Frozen interop fields (`testId`, `candidateEmailLower`, `type`, `status`, …) untouched.

## Merge variables

Single source of truth: `renderTemplate(str, vars)` in `shared/` (used by client preview
**and** server send — identical output).

| Variable | Source at send |
|---|---|
| `{{interview_link}}` | **Locked.** `${origin}/take/<newId>` — backend, per candidate |
| `{{candidate_name}}` | `candidateName` → email local-part → `"there"` |
| `{{role}}` | per-candidate role |
| `{{recruiter_name}}` | existing recruiter-name lookup / `auth.email` |
| `{{company}}` | `branding.companyName` (prefilled from settings branding if present) |
| `{{deadline}}` | `deadlineText` |

## Locked-safety (with a freeform editor)

- WYSIWYG edits **only the body prose**. The **interview-link CTA** block and the
  **"exact email" note** block are injected by the backend into a table-based,
  inline-styled email shell — restyleable (color/label), **not removable**.
- Pre-send/pre-test **validation gate** blocks if `{{interview_link}}` or the note block
  is missing; warns on unknown/malformed tokens.
- WYSIWYG HTML is **sanitized server-side** (tag/attr allowlist) before entering any
  email or preview — prevents injection/XSS.

## Sending + webhooks

- Send stays SMTP (`sendMail`). Each message carries
  `X-Mailin-custom: {"interviewId":"<id>"}` so webhook events correlate back.
- `POST /api/invites/brevo-webhook` — **public** (excluded from `authenticate`),
  verified (Brevo token/IP check), updates `interviews/{id}.invite` via Admin SDK.
- `GET /api/invites/senders` — server calls Brevo `GET /v3/senders` with `BREVO_API_KEY`;
  returns verified senders for the sender dropdown.
- `POST /api/invites/test` — sends one email to `auth.email` with sample/real merge data.
- **Caveat (documented in-UI + README):** webhooks need a public URL. On
  `localhost:8787`, delivered/opened won't arrive without a tunnel; **send-time
  accepted/failed + retry still work**.
- New env: `BREVO_API_KEY` (server-only, never `VITE_`). Fix `.env.example` to document
  SMTP vars + the new key.

## UI / flow

`InviteWizard` Stepper 3 → 5 (reuse `Stepper`, `Button`, `Card`, `Modal`):

1. Mode & role *(unchanged)*
2. Tailor / reuse *(unchanged)*
3. Add candidates *(unchanged)*
4. **Invite email** — verified-sender dropdown + from-name + reply-to (+ branded-domain
   SPF/DKIM note); subject; Tiptap body + "Insert variable"; CTA (text/color); branding
   (logo/accent/footer); **live preview** (sample data + "preview as <real recipient>"
   switch); **"Send test to me"**; **Save as template** + load/duplicate/delete templates.
   A **default template preloads**.
5. **Review & send** — recipient list and configured email **side by side** → confirm →
   send (send-now v1). Then **status view**: per-recipient accepted/delivered/failed with
   **retry** on failures.

## Out of scope / deferred

- Scheduling (send-now vs schedule) — follow-on.
- Any change to frozen modules or invite-link/auth logic — untouched; invite create path
  is only *extended*.

## Testing

- Unit: `renderTemplate`; locked-token validator; HTML sanitizer.
- Server: create path injects locked link + note and stamps `invite`; `/test` endpoint;
  webhook handler correlates event → interview doc; `inviteEmailTemplates` owner isolation.
- Manual: walk the Brevo verified-sender + SPF/DKIM path; local dry-run vs configured send.

## Open items (defaults locked; flag to change)

- Tiptap vs lighter editor → **Tiptap**.
- Scheduling in v1 → **deferred**.
- 5-step vs single combined screen → **5-step**.
