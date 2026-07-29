import { Router } from 'express'
import { randomUUID } from 'node:crypto'
import multer from 'multer'
import { FieldValue } from 'firebase-admin/firestore'
import { ah, HttpError } from '../util/ah'
import { requireAuth } from '../middleware/auth'
import { adminFirestore, adminBucket } from '../services/firebaseAdmin'
import { extractCandidates } from '../services/inviteExtract'
import { sendMail, mailerReady } from '../services/email'
import { db } from '../store/db'
import { isValidEmail } from '../services/inviteExtract'
import { buildInviteEmailHtml, type InviteRenderVars } from '../services/inviteEmailRender'
import { defaultInviteEmailTemplate, validateLockedTokens } from '../../shared/inviteEmail'
import { listVerifiedSenders, brevoReady } from '../services/brevo'
import type { AuthContext } from '../../shared/types'
import type {
  CreateInvitesRequest,
  CreateInvitesResult,
  TrackType,
  InviteEmailTemplate,
  InviteSendStatus,
  TestInviteEmailRequest,
  TestInviteEmailResult,
  InviteSendersResult,
} from '../../shared/types'

export const invitesRouter = Router()

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } })

/**
 * Parse candidate emails + roles out of an uploaded file (CSV / Excel / PDF /
 * DOCX / TXT) for the bulk-invite review step. Returns rows for the recruiter to
 * confirm — it does NOT create invites or send anything. Recruiter-only.
 */
invitesRouter.post('/extract', upload.single('file'), ah(async (req, res) => {
  const file = (req as typeof req & { file?: { buffer: Buffer; mimetype: string; originalname: string } }).file
  if (!file) throw new HttpError(400, 'No file uploaded')
  const fallbackRole = typeof req.body?.role === 'string' ? req.body.role.trim() : ''
  const result = await extractCandidates(file.buffer, file.mimetype, file.originalname, fallbackRole)
  res.json(result)
}))

/* ── Flutter `interviews.type` supports only video|chat. Map the web's richer
 *    modes onto it (so the Flutter app never chokes) and keep the precise track
 *    in an additive `mode` field the web candidate flow reads. ────────────── */
export const typeForMode = (mode: TrackType): 'video' | 'chat' =>
  (mode === 'video_avatar' || mode === 'video' || mode === 'two_way' ? 'video' : 'chat')
export const MODE_LABEL: Record<string, string> = {
  chatbot: 'Chatbot', voice: 'Voice', video_avatar: 'Video Avatar', chat: 'Timed Q&A', video: 'Video Interview', two_way: 'Two-way Interview',
}

function inviteEmail(role: string, fromName: string, link: string, candidateEmail: string) {
  const subject = `Interview invitation — ${role}`
  const html =
    `<div style="font-family:Inter,Arial,sans-serif;font-size:15px;color:#0f172a;line-height:1.6">
      <p>Hi,</p>
      <p><strong>${fromName}</strong> has invited you to a screening interview for the <strong>${role}</strong> role.</p>
      <p>When you're ready, open your interview, upload your résumé, and begin — it takes just a few minutes:</p>
      <p><a href="${link}" style="display:inline-block;background:#0d5c3a;color:#fff;text-decoration:none;padding:10px 18px;border-radius:8px;font-weight:600">Start your interview</a></p>
      <p style="background:#f0faf5;border:1px solid #dcf5e8;border-radius:8px;padding:10px 14px;color:#0a4a2e;font-size:13px">
        <strong>Important:</strong> this invitation is linked to <strong>${candidateEmail}</strong>.
        Sign in — or create your candidate account — using this exact email address to open it.
      </p>
      <p style="color:#64748b;font-size:13px">Or paste this link into your browser:<br>${link}</p>
      <p style="color:#94a3b8;font-size:12px">Sent via TalbotIQ.</p>
    </div>`
  return { subject, html }
}

/**
 * Resolve the invite-email config for a send: an inline `emailConfig` (wins),
 * a saved owned `emailTemplateId`, or `null` (use the legacy built-in email).
 * Inline config is merged onto sensible defaults so partial configs are safe.
 */
function resolveInviteEmail(
  opts: { emailTemplateId?: string; emailConfig?: Partial<InviteEmailTemplate> },
  auth: AuthContext,
): InviteEmailTemplate | null {
  const d = defaultInviteEmailTemplate()
  if (opts.emailConfig) {
    const c = opts.emailConfig
    return {
      id: 'inline',
      recruiterId: auth.uid,
      createdAt: '',
      updatedAt: '',
      name: c.name ?? d.name,
      isDefault: false,
      sender: { ...d.sender, ...(c.sender ?? {}) },
      subject: c.subject ?? d.subject,
      bodyHtml: c.bodyHtml ?? d.bodyHtml,
      cta: { ...d.cta, ...(c.cta ?? {}) },
      branding: { ...d.branding, ...(c.branding ?? {}) },
      deadlineText: c.deadlineText ?? d.deadlineText,
    }
  }
  if (opts.emailTemplateId) {
    const t = db.inviteEmailTemplates.get(opts.emailTemplateId)
    if (!t || !(auth.admin || t.recruiterId === auth.uid))
      throw new HttpError(404, 'Invite email template not found')
    return t
  }
  return null
}

/** Best-effort candidate display name from an email local-part (fallback "there"). */
function nameFromEmail(email: string): string {
  const local = (email.split('@')[0] || '').replace(/[._-]+/g, ' ').trim()
  if (!local) return 'there'
  return local.replace(/\b\w/g, (ch) => ch.toUpperCase())
}

function renderVarsFor(
  candidate: { email: string; role: string },
  ctx: { recruiterName: string; company: string; deadline: string },
): InviteRenderVars {
  return {
    candidate_name: nameFromEmail(candidate.email),
    role: candidate.role,
    recruiter_name: ctx.recruiterName,
    company: ctx.company,
    deadline: ctx.deadline,
  }
}

/** Build the SMTP From + reply-to + tracking header for a configured send. */
function senderFields(tpl: InviteEmailTemplate | null, interviewId: string) {
  const headers = { 'X-Mailin-custom': JSON.stringify({ interviewId }) }
  if (!tpl?.sender?.verifiedSenderEmail) return { headers } as { from?: string; replyTo?: string; headers: Record<string, string> }
  const name = (tpl.sender.fromName || '').trim()
  const from = name ? `${name} <${tpl.sender.verifiedSenderEmail}>` : tpl.sender.verifiedSenderEmail
  return { from, replyTo: tpl.sender.replyTo || undefined, headers }
}

/**
 * Create one `interviews/{id}` document per candidate (shared `testId`) in the
 * SAME Firestore collection the Flutter app uses, then email each candidate their
 * per-candidate link. Field names mirror APPLICATION_FLOW.md exactly; web-only
 * extras (`mode`, `role`, `screening`, `invite`) are additive so Flutter ignores them.
 * Recruiter-only; each doc is stamped with the caller's uid as `recruiterId`.
 */
invitesRouter.post('/', ah(async (req, res) => {
  const auth = requireAuth(req)
  const body = req.body as CreateInvitesRequest

  const mode = body?.mode
  const role = (body?.role ?? '').trim()
  const source = body?.source
  if (!mode || !MODE_LABEL[mode]) throw new HttpError(400, 'A valid interview mode is required')
  if (!role) throw new HttpError(400, 'A candidate role is required')
  // Two-way Interview is a live recruiter-led call — there's no scripted question
  // source to choose (no tailor-per-résumé generation, no saved question set).
  if (mode !== 'two_way' && source !== 'tailor' && source !== 'set')
    throw new HttpError(400, 'source must be "tailor" or "set"')

  // Valid, de-duplicated candidates.
  const seen = new Set<string>()
  const candidates = (Array.isArray(body?.candidates) ? body.candidates : [])
    .map((c) => ({ email: (c?.email ?? '').trim(), role: (c?.role ?? role).trim() || role }))
    .filter((c) => c.email && isValidEmail(c.email) && !seen.has(c.email.toLowerCase()) && seen.add(c.email.toLowerCase()))
  if (candidates.length === 0) throw new HttpError(400, 'No valid candidate emails to invite')

  // Question source → the `questions` array stored on each interview.
  let questions: string[] = []
  if (source === 'set') {
    if (!body.questionSetId) throw new HttpError(400, 'A question set must be selected')
    const set = db.questionSets.get(body.questionSetId)
    if (!set) throw new HttpError(404, 'Question set not found')
    questions = set.questions.map((q) => q.text).filter(Boolean)
  }
  // 'tailor' → questions stay empty; they're generated per candidate after they upload their résumé.

  // Recruiter display name (best-effort) for the "from …" line.
  let recruiterName: string | undefined
  try { recruiterName = (await adminFirestore().collection('users').doc(auth.uid).get()).get('name') || undefined } catch { /* noop */ }
  const fromName = recruiterName || auth.email || 'A recruiter'

  const testId = randomUUID()
  const now = FieldValue.serverTimestamp()
  const col = adminFirestore().collection('interviews')
  const origin = (typeof body.origin === 'string' && body.origin) || ''

  // Resolve the configurable invite email (or null → legacy built-in email).
  const emailTpl = resolveInviteEmail(body, auth)
  // Enforce the locked interview-link token server-side: a configured template
  // MUST keep {{interview_link}} (functionally required by the assigned-email auth
  // model). The backend also always appends the "exact email" note + link fallback.
  if (emailTpl) {
    const v = validateLockedTokens(emailTpl.subject, emailTpl.bodyHtml)
    if (!v.ok) throw new HttpError(400, `Invite email is missing required token(s): ${v.missing.join(', ')}`)
  }
  const company = emailTpl?.branding?.companyName || 'TalbotIQ'
  const deadline = emailTpl?.deadlineText || ''
  const sendEmails = body.sendEmails !== false

  const created: CreateInvitesResult['created'] = []
  let emailed = 0
  let anyDryRun = false

  for (const c of candidates) {
    const doc = {
      // ── APPLICATION_FLOW.md interviews schema (exact field names) ──
      testId,
      recruiterId: auth.uid,
      recruiterEmail: auth.email,
      recruiterName: recruiterName ?? null,
      candidateEmail: c.email,
      candidateEmailLower: c.email.toLowerCase(),
      candidateName: null,
      type: typeForMode(mode),
      title: `${role} — ${MODE_LABEL[mode]} interview`,
      prompt: '',
      questions,
      durationMinutes: 20,
      status: 'assigned',
      keyOverrides: {},
      maxAttempts: 1,
      attemptsUsed: 0,
      resultPublished: false,
      createdAt: now,
      updatedAt: now,
      // ── Web-only, additive (Flutter ignores unknown fields) ──
      mode,
      role: c.role,
      screening: {
        // Firestore rejects `undefined` field values — two_way invites carry no
        // source at all (see the mode !== 'two_way' check above), so omit the key
        // entirely rather than writing `source: undefined`.
        ...(source ? { source } : {}),
        ...(source === 'tailor' && body.config ? {
          style: body.config.style,
          techCount: body.config.techCount,
          nonTechCount: body.config.nonTechCount,
          difficulty: body.config.difficulty,
          domains: Array.isArray(body.config.domains) ? body.config.domains : [],
          model: body.config.model,
        } : {}),
        ...(source === 'set' ? { questionSetId: body.questionSetId } : {}),
      },
    }
    const ref = await col.add(doc)
    const link = origin ? `${origin}/take/${ref.id}` : `/take/${ref.id}`
    const row: CreateInvitesResult['created'][number] = { id: ref.id, email: c.email, link }

    // Render the email: configured template (per-candidate merge) or legacy built-in.
    const { subject, html } = emailTpl
      ? buildInviteEmailHtml(
          emailTpl,
          renderVarsFor({ email: c.email, role: c.role || role }, { recruiterName: fromName, company, deadline }),
          { interviewLink: link, candidateEmail: c.email },
        )
      : inviteEmail(c.role || role, fromName, link, c.email)

    if (sendEmails) {
      try {
        const r = await sendMail({ to: c.email, subject, html, ...senderFields(emailTpl, ref.id) })
        row.sent = r.sent
        if (r.sent) {
          emailed++
          row.status = 'accepted'
        } else {
          anyDryRun = anyDryRun || Boolean(r.dryRun)
          row.status = 'failed'
          row.error = r.dryRun ? 'Mailer not configured (dry-run)' : 'Not sent'
        }
        const invite: InviteSendStatus = {
          status: row.status ?? 'failed',
          messageId: r.messageId,
          sentAt: new Date().toISOString(),
          attempts: 1,
          ...(row.error ? { error: row.error } : {}),
        }
        await ref.update({ invite }).catch(() => {})
      } catch (err) {
        console.error('[invites] email failed for', c.email, err)
        row.sent = false
        row.status = 'failed'
        row.error = err instanceof Error ? err.message : String(err)
        const invite: InviteSendStatus = {
          status: 'failed',
          attempts: 1,
          sentAt: new Date().toISOString(),
          error: row.error,
        }
        await ref.update({ invite }).catch(() => {})
      }
    }
    created.push(row)
  }

  const dryRun = sendEmails ? emailed === 0 && anyDryRun : !mailerReady()
  const result: CreateInvitesResult = { testId, created, emailed, dryRun }
  res.status(201).json(result)
}))

/**
 * Upload a recruiter's invite-email logo and return a PUBLIC, email-safe URL.
 * The Admin SDK write bypasses Storage rules; the returned tokenised
 * firebasestorage URL is publicly fetchable (so Gmail/Outlook can load it) without
 * exposing the bucket. Hotlinking arbitrary/private/localhost URLs doesn't work in
 * email — this hosts the image for the recruiter.
 */
invitesRouter.post('/logo', upload.single('file'), ah(async (req, res) => {
  const auth = requireAuth(req)
  const file = (req as typeof req & { file?: { buffer: Buffer; mimetype: string; originalname: string } }).file
  if (!file) throw new HttpError(400, 'No image uploaded')
  if (!/^image\//.test(file.mimetype)) throw new HttpError(400, 'Logo must be an image (PNG, JPG, SVG, …)')
  if (file.buffer.length > 2 * 1024 * 1024) throw new HttpError(400, 'Logo must be under 2 MB')

  const ext = (file.originalname.split('.').pop() || 'png').toLowerCase().replace(/[^a-z0-9]/g, '') || 'png'
  const token = randomUUID()
  const objectPath = `invite_email_logos/${auth.uid}/${randomUUID()}.${ext}`
  const bucket = adminBucket()
  await bucket.file(objectPath).save(file.buffer, {
    resumable: false,
    contentType: file.mimetype,
    metadata: {
      contentType: file.mimetype,
      cacheControl: 'public, max-age=31536000',
      metadata: { firebaseStorageDownloadTokens: token },
    },
  })
  const url = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`
  res.json({ url })
}))

/**
 * Brevo verified senders for the sender picker. Server-side key only. Returns an
 * empty list (never an error) when BREVO_API_KEY is unset so the UI can fall back
 * to manual entry + surface domain/SPF/DKIM verification guidance.
 */
invitesRouter.get('/senders', ah(async (req, res) => {
  requireAuth(req)
  if (!brevoReady()) {
    const out: InviteSendersResult = { senders: [], brevoReady: false }
    return res.json(out)
  }
  try {
    const senders = await listVerifiedSenders()
    const out: InviteSendersResult = { senders, brevoReady: true }
    res.json(out)
  } catch (err) {
    console.error('[invites] Brevo senders lookup failed:', err)
    throw new HttpError(502, err instanceof Error ? err.message : 'Brevo senders lookup failed')
  }
}))

/**
 * Send ONE test invite email to the recruiter's own verified address, using the
 * chosen template/config with SAMPLE merge values — so they can preview the real
 * rendered email before the batch. Never creates an interview doc.
 */
invitesRouter.post('/test', ah(async (req, res) => {
  const auth = requireAuth(req)
  const body = (req.body ?? {}) as TestInviteEmailRequest
  const to = auth.email
  if (!to) throw new HttpError(400, 'Your account has no email address to send a test to')

  const emailTpl = resolveInviteEmail(body, auth)
  if (emailTpl) {
    const v = validateLockedTokens(emailTpl.subject, emailTpl.bodyHtml)
    if (!v.ok) throw new HttpError(400, `Invite email is missing required token(s): ${v.missing.join(', ')}`)
  }
  const role = (body.role || 'the role').trim()
  const origin = (typeof body.origin === 'string' && body.origin) || ''
  const sampleLink = origin ? `${origin}/take/sample-preview-link` : '/take/sample-preview-link'

  let recruiterName: string | undefined
  try { recruiterName = (await adminFirestore().collection('users').doc(auth.uid).get()).get('name') || undefined } catch { /* noop */ }
  const fromName = recruiterName || auth.email || 'A recruiter'

  const { subject, html } = emailTpl
    ? buildInviteEmailHtml(
        emailTpl,
        renderVarsFor({ email: to, role }, {
          recruiterName: fromName,
          company: emailTpl.branding?.companyName || 'TalbotIQ',
          deadline: emailTpl.deadlineText || '',
        }),
        { interviewLink: sampleLink, candidateEmail: to },
      )
    : inviteEmail(role, fromName, sampleLink, to)

  try {
    const r = await sendMail({ to, subject: `[TEST] ${subject}`, html, ...senderFields(emailTpl, 'test') })
    const out: TestInviteEmailResult = { sent: r.sent, dryRun: r.dryRun, to }
    res.json(out)
  } catch (err) {
    const out: TestInviteEmailResult = { sent: false, to, error: err instanceof Error ? err.message : String(err) }
    res.status(502).json(out)
  }
}))

/**
 * Retry sending the invite for a single interview the recruiter owns (after a
 * failure). Re-renders from the stored doc + the provided template/config.
 */
invitesRouter.post('/:interviewId/retry', ah(async (req, res) => {
  const auth = requireAuth(req)
  const body = (req.body ?? {}) as TestInviteEmailRequest
  const ref = adminFirestore().collection('interviews').doc(req.params.interviewId)
  const snap = await ref.get()
  if (!snap.exists) throw new HttpError(404, 'Interview not found')
  const data = snap.data() as Record<string, any>
  if (data.recruiterId !== auth.uid && !auth.admin) throw new HttpError(404, 'Interview not found')

  const emailTpl = resolveInviteEmail(body, auth)
  const origin = (typeof body.origin === 'string' && body.origin) || ''
  const link = origin ? `${origin}/take/${ref.id}` : `/take/${ref.id}`
  const candidateEmail = String(data.candidateEmail || '')
  const role = String(data.role || body.role || 'the role')
  const fromName = String(data.recruiterName || auth.email || 'A recruiter')

  const { subject, html } = emailTpl
    ? buildInviteEmailHtml(
        emailTpl,
        renderVarsFor({ email: candidateEmail, role }, {
          recruiterName: fromName,
          company: emailTpl.branding?.companyName || 'TalbotIQ',
          deadline: emailTpl.deadlineText || '',
        }),
        { interviewLink: link, candidateEmail },
      )
    : inviteEmail(role, fromName, link, candidateEmail)

  const prevAttempts = Number(data.invite?.attempts || 0)
  try {
    const r = await sendMail({ to: candidateEmail, subject, html, ...senderFields(emailTpl, ref.id) })
    const invite: InviteSendStatus = {
      status: r.sent ? 'accepted' : 'failed',
      messageId: r.messageId,
      sentAt: new Date().toISOString(),
      attempts: prevAttempts + 1,
      ...(r.sent ? {} : { error: r.dryRun ? 'Mailer not configured (dry-run)' : 'Not sent' }),
    }
    await ref.update({ invite }).catch(() => {})
    res.json({ id: ref.id, email: candidateEmail, sent: r.sent, status: invite.status, error: invite.error })
  } catch (err) {
    const error = err instanceof Error ? err.message : String(err)
    const invite: InviteSendStatus = { status: 'failed', attempts: prevAttempts + 1, sentAt: new Date().toISOString(), error }
    await ref.update({ invite }).catch(() => {})
    res.status(502).json({ id: ref.id, email: candidateEmail, sent: false, status: 'failed', error })
  }
}))
