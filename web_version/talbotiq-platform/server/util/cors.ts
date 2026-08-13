/**
 * CORS_ORIGINS allowlist. The frontend is on a different origin (Vercel) from
 * this API (Render), so cross-origin requests are the normal case here.
 *
 * Blank/unset deliberately means "allow every origin" — the behaviour this
 * server had before — so a deployment that forgets the var still works rather
 * than failing in a way that looks like an app bug.
 */

const stripTrailingSlash = (v: string) => v.trim().replace(/\/+$/, '')

/** Parse a comma-separated origin list. Returns null for blank input, meaning
 *  "no restriction". */
export function parseAllowedOrigins(raw: string | undefined): string[] | null {
  const list = (raw ?? '').split(',').map(stripTrailingSlash).filter(Boolean)
  return list.length ? list : null
}

/** True when the request's Origin is permitted.
 *  A missing Origin (curl, server-to-server, Render health checks, the Brevo
 *  webhook) is always allowed — CORS only governs browser-initiated calls. */
export function isOriginAllowed(allowed: string[] | null, origin: string | undefined): boolean {
  if (!allowed) return true
  if (!origin) return true
  return allowed.includes(stripTrailingSlash(origin))
}
