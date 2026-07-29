/**
 * Brevo transactional delivery webhook — PUBLIC endpoint (Brevo has no bearer
 * token), so it is verified by a shared secret: the configured BREVO_WEBHOOK_SECRET
 * must match the `?token=` query param (or the `x-webhook-token` header). It updates
 * the matching `interviews/{id}.invite` status from delivery events.
 *
 * Correlation: each invite is sent with an `X-Mailin-custom` header carrying the
 * interview id, which Brevo echoes back in the webhook payload. We parse it to find
 * the doc; failing that we fall back to the most recent invite for that email.
 *
 * NOTE: webhooks require a PUBLICLY reachable URL. On localhost the events never
 * arrive (send-time accepted/failed + retry still work); use a tunnel or a deployed
 * environment to exercise delivered/opened/bounced. Configure the webhook URL +
 * secret in the Brevo dashboard: https://<host>/api/invites/brevo-webhook?token=<secret>
 */
import { Router } from 'express'
import { ah } from '../util/ah'
import { adminFirestore } from '../services/firebaseAdmin'
import type { InviteSendStatusValue } from '../../shared/types'

export const brevoWebhookRouter = Router()

/** Map a Brevo event name → our invite status. Unknown/ignored events → null. */
export function mapBrevoEvent(event: string): InviteSendStatusValue | null {
  switch ((event || '').toLowerCase()) {
    case 'delivered': return 'delivered'
    case 'hardbounce':
    case 'hard_bounce':
    case 'softbounce':
    case 'soft_bounce': return 'bounced'
    case 'spam': return 'spam'
    case 'blocked':
    case 'invalid':
    case 'error':
    case 'deferred': return 'failed'
    case 'opened':
    case 'uniqueopened':
    case 'unique_opened':
    case 'open': return 'opened'
    case 'click':
    case 'clicked': return 'clicked'
    default: return null // request/sent/unsubscribed/etc. — no status change
  }
}

/** Pull the interview id out of the echoed X-Mailin-custom payload, if present. */
export function interviewIdFromPayload(payload: Record<string, any>): string | null {
  const raw =
    payload['X-Mailin-custom'] ?? payload['x-mailin-custom'] ?? payload.mailincustom ?? payload.tag
  if (!raw) return null
  try {
    const obj = typeof raw === 'string' ? JSON.parse(raw) : raw
    return obj?.interviewId ? String(obj.interviewId) : null
  } catch {
    return null
  }
}

brevoWebhookRouter.post('/', ah(async (req, res) => {
  const secret = (process.env.BREVO_WEBHOOK_SECRET || '').trim()
  const provided = String(req.query.token || req.headers['x-webhook-token'] || '')
  // If a secret is configured it MUST match; if none is configured, reject (fail closed).
  if (!secret || provided !== secret) {
    return res.status(401).json({ ok: false, error: 'Invalid webhook token' })
  }

  const payload = (req.body ?? {}) as Record<string, any>
  const status = mapBrevoEvent(String(payload.event ?? ''))
  // Always ack 200 so Brevo doesn't retry-storm on events we intentionally ignore.
  if (!status) return res.json({ ok: true, ignored: true })

  try {
    const col = adminFirestore().collection('interviews')
    const id = interviewIdFromPayload(payload)
    let ref = id ? col.doc(id) : null
    if (ref) {
      const snap = await ref.get()
      if (!snap.exists) ref = null
    }
    // Fallback: correlate by recipient email (most recent invite for that address).
    if (!ref && payload.email) {
      const q = await col
        .where('candidateEmailLower', '==', String(payload.email).toLowerCase())
        .orderBy('createdAt', 'desc')
        .limit(1)
        .get()
      if (!q.empty) ref = q.docs[0].ref
    }
    if (ref) {
      await ref.update({
        'invite.status': status,
        'invite.lastEventAt': new Date().toISOString(),
      }).catch(() => {})
    }
  } catch (err) {
    console.error('[brevo-webhook] update failed:', err)
    // Still ack — a 500 makes Brevo retry, and the event is non-critical.
  }
  res.json({ ok: true })
}))
