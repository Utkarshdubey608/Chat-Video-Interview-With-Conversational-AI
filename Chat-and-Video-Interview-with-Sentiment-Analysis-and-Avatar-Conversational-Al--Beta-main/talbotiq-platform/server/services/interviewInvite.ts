/**
 * Shared interview-invite service — builds one interviews/{id} doc and (optionally)
 * sends its invite/advance email. Additive: this is the reusable home for the
 * per-candidate doc + email logic. server/routes/invites.ts is NOT modified and
 * continues to use its own inline copy; the pipeline Round-1 flow uses THIS.
 *
 * The interviews doc schema mirrors APPLICATION_FLOW.md (frozen Flutter fields) plus
 * the web-only additive fields (mode/role/screening) and, for pipelines, an additive
 * `pipeline` ref. `type` is Flutter's 'video'|'chat' bucket.
 */
import { FieldValue } from 'firebase-admin/firestore'
import { adminFirestore } from './firebaseAdmin'
import { buildInviteEmailHtml, sanitizeBodyHtml } from './inviteEmailRender'
import { sendMail } from './email'
import { renderTemplate, renderTransitionEmail } from '../../shared/inviteEmail'
import type {
  TrackType, RoundDef, InterviewPipelineRef, InviteEmailTemplate,
  InviteSendStatus, InviteSendStatusValue,
} from '../../shared/types'

// Local copies (kept in sync with invites.ts by shape — both derive from TrackType).
// Duplicated intentionally so this service does not import the route module.
const typeForMode = (mode: TrackType): 'video' | 'chat' =>
  mode === 'video_avatar' || mode === 'video' || mode === 'two_way' ? 'video' : 'chat'
const MODE_LABEL: Record<string, string> = {
  chatbot: 'Chatbot', voice: 'Voice', video_avatar: 'Video Avatar',
  chat: 'Timed Q&A', video: 'Video Interview', two_way: 'Two-way Interview',
}

export interface InterviewDocCtx {
  testId: string
  recruiterId: string
  recruiterEmail: string
  recruiterName: string | null
  nowIso: string
  mode: TrackType
  questions: string[]
  source?: 'tailor' | 'set'
  config?: RoundDef['config']
  questionSetId?: string
  pipeline?: InterviewPipelineRef
}
export interface RoundCandidate { email: string; role: string }

/** Pure — the exact interviews/{id} doc object for one candidate (no side effects). */
export function buildInterviewDocFields(ctx: InterviewDocCtx, c: RoundCandidate): Record<string, unknown> {
  return {
    // ── frozen Flutter schema (exact field names) ──
    testId: ctx.testId,
    recruiterId: ctx.recruiterId,
    recruiterEmail: ctx.recruiterEmail,
    recruiterName: ctx.recruiterName ?? null,
    candidateEmail: c.email,
    candidateEmailLower: c.email.toLowerCase(),
    candidateName: null,
    type: typeForMode(ctx.mode),
    title: `${c.role} — ${MODE_LABEL[ctx.mode]} interview`,
    prompt: '',
    questions: ctx.questions,
    durationMinutes: 20,
    status: 'assigned',
    keyOverrides: {},
    maxAttempts: 1,
    attemptsUsed: 0,
    resultPublished: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    // ── web-only additive (Flutter ignores unknown keys) ──
    mode: ctx.mode,
    role: c.role,
    screening: {
      ...(ctx.source ? { source: ctx.source } : {}),
      ...(ctx.source === 'tailor' && ctx.config ? {
        style: ctx.config.style,
        techCount: ctx.config.techCount,
        nonTechCount: ctx.config.nonTechCount,
        difficulty: ctx.config.difficulty,
        domains: Array.isArray(ctx.config.domains) ? ctx.config.domains : [],
        model: ctx.config.model,
      } : {}),
      ...(ctx.source === 'set' ? { questionSetId: ctx.questionSetId } : {}),
    },
    // ── pipeline ref (additive; only for multi-round rounds) ──
    ...(ctx.pipeline ? { pipeline: ctx.pipeline } : {}),
  }
}

export interface SendCtx extends InterviewDocCtx {
  origin: string
  fromName: string
  company: string
  deadline: string
}

export interface TransitionOpts {
  emailKind?: 'invite' | 'advance'
  roundName?: string
  previousRoundName?: string
  score?: string
}

/** Pure: build transition-email merge vars for a candidate (advance/selected/rejection). */
export function transitionVars(
  c: { email: string; role: string },
  ctx: { fromName: string; company: string },
  opts: { roundName?: string; previousRoundName?: string; score?: string },
) {
  return {
    candidate_name: c.email.split('@')[0] || 'there',
    role: c.role,
    recruiter_name: ctx.fromName,
    company: ctx.company,
    round_name: opts.roundName ?? '',
    previous_round_name: opts.previousRoundName ?? '',
    score: opts.score ?? '',
  }
}

/** Create the Firestore doc, build the link, render + send the email, stamp invite status. */
export async function createAndSendInterview(
  ctx: SendCtx,
  c: RoundCandidate,
  emailTpl: InviteEmailTemplate | null,
  sendEmails: boolean,
  opts: TransitionOpts = {},
): Promise<{ id: string; email: string; link: string; sent?: boolean; status?: InviteSendStatusValue; error?: string }> {
  const col = adminFirestore().collection('interviews')
  const ref = await col.add(buildInterviewDocFields(ctx, c))
  const link = ctx.origin ? `${ctx.origin}/take/${ref.id}` : `/take/${ref.id}`
  const row: { id: string; email: string; link: string; sent?: boolean; status?: InviteSendStatusValue; error?: string } =
    { id: ref.id, email: c.email, link }

  if (!sendEmails) return row

  const emailKind = opts.emailKind ?? 'invite'
  let subject: string, html: string
  if (emailKind === 'advance' && emailTpl) {
    // Transition (advance) email — rendered via the shared transition renderer.
    const vars = transitionVars(c, { fromName: ctx.fromName, company: ctx.company }, opts)
    const safeTpl = { ...emailTpl, bodyHtml: sanitizeBodyHtml(emailTpl.bodyHtml) }
    const rendered = renderTransitionEmail(safeTpl, 'advance', vars, { interviewLink: link, candidateEmail: c.email })
    subject = rendered.subject; html = rendered.html
  } else {
    // Render: configured template merged per-candidate, else a minimal built-in.
    const vars = {
      candidate_name: c.email.split('@')[0] || 'there',
      role: c.role, recruiter_name: ctx.fromName, company: ctx.company, deadline: ctx.deadline,
    }
    if (emailTpl) {
      const rendered = buildInviteEmailHtml(emailTpl, vars, { interviewLink: link, candidateEmail: c.email })
      subject = rendered.subject; html = rendered.html
    } else {
      subject = renderTemplate('Interview invitation — {{role}}', vars)
      html = `<p>Hi,</p><p>You've been invited to an interview for ${vars.role}. Open your interview: <a href="${link}">${link}</a></p><p>Sign in with ${c.email}.</p>`
    }
  }

  const headers = { 'X-Mailin-custom': JSON.stringify({ interviewId: ref.id }) }
  const from = emailTpl?.sender?.verifiedSenderEmail
    ? ((emailTpl.sender.fromName || '').trim()
        ? `${(emailTpl.sender.fromName || '').trim()} <${emailTpl.sender.verifiedSenderEmail}>`
        : emailTpl.sender.verifiedSenderEmail)
    : undefined
  const replyTo = emailTpl?.sender?.replyTo || undefined
  try {
    const r = await sendMail({ to: c.email, subject, html, from, replyTo, headers })
    row.sent = r.sent
    row.status = r.sent ? 'accepted' : 'failed'
    if (!r.sent) row.error = r.dryRun ? 'Mailer not configured (dry-run)' : 'Not sent'
    const invite: InviteSendStatus = {
      status: row.status, messageId: r.messageId, sentAt: new Date().toISOString(),
      attempts: 1, ...(row.error ? { error: row.error } : {}),
    }
    await ref.update({ invite }).catch(() => {})
  } catch (err) {
    row.sent = false; row.status = 'failed'
    row.error = err instanceof Error ? err.message : String(err)
    await ref.update({ invite: { status: 'failed', attempts: 1, sentAt: new Date().toISOString(), error: row.error } as InviteSendStatus }).catch(() => {})
  }
  return row
}

/**
 * Send a terminal (pipeline-ending) email — 'selected' or 'rejection'. Email only;
 * no interviews/{id} doc is created or touched (there's no next round to link to).
 */
export async function sendTerminalEmail(
  to: string,
  emailTpl: InviteEmailTemplate | null,
  kind: 'selected' | 'rejection',
  vars: { candidate_name: string; role: string; recruiter_name: string; company: string; score?: string },
): Promise<{ sent: boolean; error?: string }> {
  if (!emailTpl) return { sent: false, error: 'No email template' }
  const safeTpl = { ...emailTpl, bodyHtml: sanitizeBodyHtml(emailTpl.bodyHtml) }
  const { subject, html } = renderTransitionEmail(safeTpl, kind, { ...vars, round_name: '', previous_round_name: '' })
  const from = emailTpl.sender?.verifiedSenderEmail
    ? ((emailTpl.sender.fromName || '').trim() ? `${(emailTpl.sender.fromName || '').trim()} <${emailTpl.sender.verifiedSenderEmail}>` : emailTpl.sender.verifiedSenderEmail)
    : undefined
  try {
    const r = await sendMail({ to, subject, html, from, replyTo: emailTpl.sender?.replyTo || undefined })
    return { sent: r.sent, error: r.sent ? undefined : (r.dryRun ? 'Mailer not configured (dry-run)' : 'Not sent') }
  } catch (err) {
    return { sent: false, error: err instanceof Error ? err.message : String(err) }
  }
}
