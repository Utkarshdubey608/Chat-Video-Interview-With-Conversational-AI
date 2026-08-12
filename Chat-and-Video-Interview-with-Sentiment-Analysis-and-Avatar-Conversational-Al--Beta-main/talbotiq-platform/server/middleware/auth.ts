import type { Request, Response, NextFunction, RequestHandler } from 'express'
import type { IncomingMessage } from 'node:http'
import { HttpError } from '../util/ah'
import { verifyIdToken, getUserRole } from '../services/firebaseAdmin'
import { isAdminEmail } from '../services/users'
import type { AuthContext, InterviewSession } from '../../shared/types'

/* ─── token extraction ──────────────────────────────────────────────────── */

/** Pull a Firebase ID token from the Authorization header (`Bearer <token>`). */
export function bearerToken(req: Request): string | null {
  const h = req.headers.authorization || ''
  const m = /^Bearer\s+(.+)$/i.exec(h)
  return m ? m[1].trim() : null
}

/**
 * Build the AuthContext from a verified token. Identity comes from the Firebase
 * ID token; the ROLE comes from Firestore `users/{uid}.role` — the same document
 * the client reads and writes — so client and server can never disagree. A
 * missing/unreadable doc resolves to `candidate` (least privilege). `admin` is an
 * optional server-only overlay (ADMIN_EMAILS) and is never taken from the client.
 */
export async function contextFromToken(idToken: string): Promise<AuthContext> {
  const decoded = await verifyIdToken(idToken)
  const email = (decoded.email ?? '').toLowerCase()
  const role = await getUserRole(decoded.uid)
  return {
    uid: decoded.uid,
    email,
    emailVerified: decoded.email_verified === true,
    role,
    admin: role === 'recruiter' && isAdminEmail(email),
  }
}

/**
 * Verify the identity for a WebSocket upgrade. Browsers can't set headers on a
 * WS handshake, so the ID token rides in the query string (?token=… ; also
 * accepts ?access_token=…). Returns null on any missing/invalid token or when
 * auth isn't configured — the caller then rejects the upgrade.
 */
export async function contextFromUpgrade(req: IncomingMessage): Promise<AuthContext | null> {
  try {
    const url = new URL(req.url ?? '', 'http://localhost')
    const token = url.searchParams.get('token') || url.searchParams.get('access_token')
    if (!token) return null
    return await contextFromToken(token)
  } catch {
    return null
  }
}

/* ─── middleware ────────────────────────────────────────────────────────── */

/** Verify the ID token on every request and attach req.auth. 401 if missing/invalid. */
export const authenticate: RequestHandler = (req: Request, _res: Response, next: NextFunction) => {
  Promise.resolve()
    .then(async () => {
      const token = bearerToken(req)
      if (!token) throw new HttpError(401, 'Authentication required')
      req.auth = await contextFromToken(token)
      next()
    })
    .catch(next)
}

/** Require the recruiter role (authenticate must run first). */
export const requireRecruiter: RequestHandler = (req, _res, next) => {
  if (!req.auth) return next(new HttpError(401, 'Authentication required'))
  if (req.auth.role !== 'recruiter') return next(new HttpError(403, 'Recruiter access required'))
  next()
}

/** Require an admin (a recruiter with the admin claim). */
export const requireAdmin: RequestHandler = (req, _res, next) => {
  if (!req.auth) return next(new HttpError(401, 'Authentication required'))
  if (!req.auth.admin) return next(new HttpError(403, 'Admin access required'))
  next()
}

/* ─── authorization helpers (used inside session handlers) ──────────────── */

/** The verified identity, or a 401. */
export function requireAuth(req: Request): AuthContext {
  if (!req.auth) throw new HttpError(401, 'Authentication required')
  return req.auth
}

/** Does this recruiter own the session? Admins are treated as owning every session. */
export function ownsSession(session: InterviewSession, auth: AuthContext): boolean {
  if (auth.role !== 'recruiter') return false
  if (auth.admin) return true
  return !!session.recruiterId && session.recruiterId === auth.uid
}

/** Is this the candidate the session is assigned to (by verified email)? */
export function isAssignedCandidate(session: InterviewSession, auth: AuthContext): boolean {
  const assigned = (session.candidate?.email ?? '').trim().toLowerCase()
  return !!assigned && !!auth.email && assigned === auth.email
}

/**
 * Recruiter-read guard. Cross-tenant access is reported as 404 (not 403) so the
 * response never reveals that another recruiter's session exists.
 */
export function assertOwner(session: InterviewSession, auth: AuthContext): void {
  if (!ownsSession(session, auth)) throw new HttpError(404, 'Session not found')
}

/**
 * Candidate-lifecycle guard: the assigned candidate (own verified email) OR the
 * owning recruiter (so an owner can preview/test their own interview). Anyone
 * else gets 404 — no existence leak.
 */
export function assertSessionParticipant(session: InterviewSession, auth: AuthContext): void {
  if (isAssignedCandidate(session, auth) || ownsSession(session, auth)) return
  throw new HttpError(404, 'Session not found')
}
