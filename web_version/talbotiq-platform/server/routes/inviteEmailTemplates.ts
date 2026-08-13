/**
 * Invite-email templates — owned per recruiter, mirroring the Sessions isolation
 * pattern (the ONLY genuine per-recruiter model in this app). `recruiterId` is
 * stamped SERVER-SIDE from the verified token and never accepted from the client;
 * list is filtered by owner and single-item reads 404 on cross-owner access so the
 * response never reveals another recruiter's template exists.
 *
 * Storage is the in-memory Express/JSON store (server/store/db.ts) — NOT Firestore,
 * matching how templates/question-sets/sessions already persist here.
 */
import { Router } from 'express'
import { randomUUID } from 'node:crypto'
import { db } from '../store/db'
import { ah, HttpError } from '../util/ah'
import { requireAuth } from '../middleware/auth'
import { defaultTemplateFor, kindOf } from '../../shared/inviteEmail'
import type { AuthContext, EmailKind, InviteEmailTemplate } from '../../shared/types'

export const inviteEmailTemplatesRouter = Router()

/** Owner check — admins (recruiter + admin overlay) may see every template. */
const owns = (t: InviteEmailTemplate, auth: AuthContext) => auth.admin || t.recruiterId === auth.uid

const EMAIL_KINDS: EmailKind[] = ['invite', 'advance', 'selected', 'rejection']
const parseKind = (v: unknown): EmailKind =>
  (EMAIL_KINDS as string[]).includes(String(v)) ? (v as EmailKind) : 'invite'

/** Load a template the caller owns, or 404 (no existence leak). */
function loadOwned(id: string, auth: AuthContext): InviteEmailTemplate {
  const t = db.inviteEmailTemplates.get(id)
  if (!t || !owns(t, auth)) throw new HttpError(404, 'Invite email template not found')
  return t
}

/** Sanitise + coerce an incoming template body into stored shape (server owns id/owner/timestamps). */
function normalize(
  body: unknown,
  fallbackKind: EmailKind = 'invite',
): Omit<InviteEmailTemplate, 'id' | 'recruiterId' | 'createdAt' | 'updatedAt'> {
  const b = (body ?? {}) as Record<string, any>
  const kind = parseKind(b.kind ?? fallbackKind)
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

/** Seed one owned default for a recruiter who has none yet, for the given kind. */
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

// List (owner-filtered, kind-filtered). Auto-seeds a default the first time a recruiter has none of that kind.
// No `kind` query param → defaults to 'invite', matching pre-kind-support behaviour exactly.
inviteEmailTemplatesRouter.get('/', ah((req, res) => {
  const auth = requireAuth(req)
  const kind = parseKind(req.query.kind)
  let mine = [...db.inviteEmailTemplates.values()].filter((t) => owns(t, auth) && kindOf(t) === kind)
  if (mine.length === 0) mine = [seedDefault(auth, kind)]
  res.json(mine.sort((a, b) => Number(b.isDefault) - Number(a.isDefault) || a.name.localeCompare(b.name)))
}))

inviteEmailTemplatesRouter.get('/:id', ah((req, res) => {
  const auth = requireAuth(req)
  res.json(loadOwned(req.params.id, auth))
}))

inviteEmailTemplatesRouter.post('/', ah((req, res) => {
  const auth = requireAuth(req)
  const now = new Date().toISOString()
  const tpl: InviteEmailTemplate = {
    id: randomUUID(),
    recruiterId: auth.uid, // OWNER — server-stamped, never from client
    createdAt: now,
    updatedAt: now,
    ...normalize(req.body),
  }
  db.inviteEmailTemplates.set(tpl.id, tpl)
  db.scheduleSave()
  res.status(201).json(tpl)
}))

inviteEmailTemplatesRouter.put('/:id', ah((req, res) => {
  const auth = requireAuth(req)
  const existing = loadOwned(req.params.id, auth)
  const updated: InviteEmailTemplate = {
    ...existing,
    ...normalize(req.body, kindOf(existing)),
    id: existing.id,
    recruiterId: existing.recruiterId, // owner is immutable
    createdAt: existing.createdAt,
    updatedAt: new Date().toISOString(),
  }
  db.inviteEmailTemplates.set(updated.id, updated)
  db.scheduleSave()
  res.json(updated)
}))

inviteEmailTemplatesRouter.post('/:id/duplicate', ah((req, res) => {
  const auth = requireAuth(req)
  const src = loadOwned(req.params.id, auth)
  const now = new Date().toISOString()
  const copy: InviteEmailTemplate = {
    ...src,
    id: randomUUID(),
    recruiterId: auth.uid,
    name: `${src.name} (copy)`,
    isDefault: false,
    createdAt: now,
    updatedAt: now,
  }
  db.inviteEmailTemplates.set(copy.id, copy)
  db.scheduleSave()
  res.status(201).json(copy)
}))

inviteEmailTemplatesRouter.delete('/:id', ah((req, res) => {
  const auth = requireAuth(req)
  loadOwned(req.params.id, auth) // 404 if not owner — no cross-tenant delete
  db.inviteEmailTemplates.delete(req.params.id)
  db.scheduleSave()
  res.status(204).end()
}))

/** Internal helpers exposed for deterministic unit tests (see *.test.ts). */
export const __test = { owns, normalize, loadOwned, seedDefault }
