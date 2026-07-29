import { renderTemplate, type InviteRenderVars } from '@shared/inviteEmail'
import type { InviteEmailTemplate } from '@shared/types'
import { useAuth } from '@/features/auth/AuthProvider'
import { EmailPreview } from './EmailPreview'
import { sampleName } from './InviteEmailStep'

/**
 * Step 5 — final review: the recipient list and the configured email side by side.
 * The actual send is triggered by the wizard footer's "Send invites" button.
 */
export function ReviewSend({
  candidates,
  draft,
  role,
  origin,
}: {
  candidates: { email: string; role: string }[]
  draft: InviteEmailTemplate
  role: string
  origin: string
}) {
  const { user, firebaseUser } = useAuth()
  const recruiterName = user?.displayName || firebaseUser?.displayName || firebaseUser?.email || 'A recruiter'
  const first = candidates[0]?.email || firebaseUser?.email || 'candidate@example.com'

  const vars: InviteRenderVars = {
    candidate_name: sampleName(first),
    role: candidates[0]?.role || role || 'the role',
    recruiter_name: recruiterName,
    company: draft.branding.companyName || 'TalbotIQ',
    deadline: draft.deadlineText || '—',
  }
  const fromLine = draft.sender.verifiedSenderEmail
    ? `${draft.sender.fromName} <${draft.sender.verifiedSenderEmail}>`
    : `${draft.sender.fromName} (server default sender)`

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
      {/* Recipients */}
      <div className="space-y-3">
        <div className="rounded-xl border border-border bg-white p-4">
          <p className="text-sm font-semibold text-neutral-800">
            {candidates.length} recipient{candidates.length === 1 ? '' : 's'}
          </p>
          <dl className="mt-2 space-y-1 text-xs text-neutral-500">
            <div className="flex justify-between gap-3"><dt>From</dt><dd className="truncate font-medium text-neutral-700">{fromLine}</dd></div>
            {draft.sender.replyTo && <div className="flex justify-between gap-3"><dt>Reply-to</dt><dd className="text-neutral-700">{draft.sender.replyTo}</dd></div>}
            <div className="flex justify-between gap-3"><dt>Subject</dt><dd className="truncate text-neutral-700">{renderTemplate(draft.subject, { ...vars })}</dd></div>
          </dl>
        </div>
        <div className="max-h-[420px] overflow-y-auto overflow-x-auto rounded-xl border border-border">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border bg-neutral-50 text-left text-[11px] font-semibold uppercase tracking-wide text-neutral-500">
                <th className="px-3 py-2">Email</th><th className="px-3 py-2">Role</th>
              </tr>
            </thead>
            <tbody>
              {candidates.map((c) => (
                <tr key={c.email} className="border-b border-border last:border-0">
                  <td className="px-3 py-1.5 font-mono text-xs text-neutral-700">{c.email}</td>
                  <td className="px-3 py-1.5 text-xs text-neutral-500">{c.role || role}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="px-1 text-xs text-neutral-400">
          Each recipient gets their own unique interview link tied to this exact email address.
        </p>
      </div>

      {/* Email preview (as the first recipient) */}
      <div className="lg:sticky lg:top-4 lg:self-start">
        <EmailPreview draft={draft} vars={vars} candidateEmail={first} origin={origin} />
      </div>
    </div>
  )
}
