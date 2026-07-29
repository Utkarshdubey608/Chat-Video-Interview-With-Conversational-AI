/**
 * Classifies a failed candidate `sessionsApi.twowayJoin` request so a *live*
 * candidate is never dropped to a dead-end hard error by a merely TRANSIENT
 * backend blip.
 *
 * Three outcomes:
 *  - 'waiting-host' — the recruiter hasn't opened the room yet (409 "…has not
 *    started…"). Keep knocking on the interval, indefinitely; the recruiter may
 *    take minutes to join.
 *  - 'transient'    — the backend was momentarily unreachable and will recover:
 *    a dev `tsx watch` restart surfaces through the Vite proxy as a body-less
 *    500 (→ ApiError message "Request failed (500)"); a prod deploy/restart
 *    surfaces through the reverse proxy as 502/503/504; a bare connection
 *    failure (no response at all) reaches us as a fetch reject with `null`
 *    status. All self-heal, so retry on the interval (capped by the caller).
 *  - 'fatal'        — a definite client-side error (401/403/404, wrong track,
 *    or 409 "already ended"). Surface the hard error; retrying won't help.
 *
 * `status` is the HTTP status, or `null` when `fetch` itself rejected (no
 * response ever reached the browser).
 */
export type JoinFailureKind = 'waiting-host' | 'transient' | 'fatal'

export function classifyJoinFailure(status: number | null, message: string): JoinFailureKind {
  if (status === 409 && /has not started/i.test(message)) return 'waiting-host'
  if (status === null || status >= 500) return 'transient'
  return 'fatal'
}
