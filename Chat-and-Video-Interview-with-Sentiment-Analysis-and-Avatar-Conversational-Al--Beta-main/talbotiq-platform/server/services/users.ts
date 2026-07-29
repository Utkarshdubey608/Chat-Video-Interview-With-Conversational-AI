import { db } from '../store/db'
import type { AppUser } from '../../shared/types'

/**
 * User helpers.
 *
 * The ROLE is NOT decided here — it lives on Firestore `users/{uid}.role`, chosen
 * by the user at sign-up and read by both clients and by the server
 * (see firebaseAdmin.getUserRole). This file only holds:
 *   • getUser        — read the optional AppUser mirror (JSON store), for /auth/me
 *   • isAdminEmail   — an OPTIONAL, server-only "admin" overlay
 *
 * ⚠️ Because the role comes from a client-writable Firestore doc, a user can
 * self-select the `recruiter` role at sign-up (this matches the Flutter app and
 * is the agreed interop model). The `admin` overlay below is the one thing that
 * remains server-authoritative and can never be set from the client. To harden
 * the role itself later, move role assignment server-side (Admin SDK) and tighten
 * the Firestore rules so a client can't write its own role. See docs/AUTH.md.
 */

function list(envVar: string): string[] {
  return (process.env[envVar] ?? '')
    .split(/[,\s]+/)
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean)
}

/**
 * OPTIONAL admin overlay: a recruiter with elevated visibility (sees legacy
 * sessions that have no owner). NOT a role, and NEVER taken from the client —
 * it's derived purely from the server-side ADMIN_EMAILS allowlist + the token's
 * verified email. Leave ADMIN_EMAILS blank to disable it entirely.
 */
export function isAdminEmail(email: string | undefined): boolean {
  const e = (email ?? '').trim().toLowerCase()
  return !!e && list('ADMIN_EMAILS').includes(e)
}

/** The optional AppUser mirror record (JSON store), keyed by Firebase uid. */
export function getUser(uid: string): AppUser | undefined {
  return db.users.get(uid)
}
