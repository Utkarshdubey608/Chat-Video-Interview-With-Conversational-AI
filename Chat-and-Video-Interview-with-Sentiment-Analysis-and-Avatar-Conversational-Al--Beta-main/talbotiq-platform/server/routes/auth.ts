import { Router } from 'express'
import { authenticate, requireAuth } from '../middleware/auth'
import { getUser } from '../services/users'
import type { AppUser } from '../../shared/types'

/**
 * Auth surface. Every request carries a Firebase ID token; `authenticate`
 * verifies it and attaches `req.auth` (uid, email, role-from-Firestore, admin).
 *
 * Role is NOT decided here — it lives on Firestore `users/{uid}.role` (written by
 * the client at sign-up, read live by the client and per-request by the server).
 * There is no /session endpoint and no custom-claim write: nothing the client
 * sends to this router can change its role.
 */
export const authRouter = Router()

authRouter.use(authenticate)

/** GET /api/auth/me — the current user's record (role sourced from Firestore). */
authRouter.get('/me', (req, res) => {
  const auth = requireAuth(req)
  const stored = getUser(auth.uid)
  if (stored) return res.json(stored)
  const now = new Date().toISOString()
  const user: AppUser = {
    uid: auth.uid,
    email: auth.email,
    role: auth.role,
    admin: auth.admin,
    emailVerified: auth.emailVerified,
    status: 'active',
    createdAt: now,
    updatedAt: now,
  }
  res.json(user)
})
