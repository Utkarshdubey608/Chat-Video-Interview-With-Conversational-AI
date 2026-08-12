/**
 * Client side of the replica-preview cache (server/routes/faceCache.ts).
 *
 * cachedFaceUrl() points a <video> at our server's local copy of a Tavus preview
 * instead of the remote CDN, and warmFaceCache() pre-downloads every preview
 * into that server cache in the background as soon as the replica list is known
 * — so by the time the picker opens, playback is instant and stays instant.
 */

const BASE = '/api/avatar/face-cache'

/** Local-cache URL for a preview. Media elements can't send the Authorization
 *  header, so the bearer token rides in the query (same pattern as the WS
 *  connections). With no token yet, fall back to the CDN URL unchanged. */
export function cachedFaceUrl(src: string, token: string | null): string {
  if (!token) return src
  return `${BASE}?url=${encodeURIComponent(src)}&token=${encodeURIComponent(token)}`
}

/** URLs already warmed this session — never re-request them. */
const warmed = new Set<string>()

/**
 * Fire-and-forget: HEAD each preview through the cache route (3 at a time) so
 * the server downloads-and-persists them without the browser transferring any
 * video bytes. Auth comes from the global fetch interceptor.
 */
export function warmFaceCache(urls: (string | undefined)[]): void {
  const todo = urls.filter((u): u is string => !!u && !warmed.has(u))
  if (!todo.length) return
  todo.forEach((u) => warmed.add(u))
  let i = 0
  const next = (): void => {
    const u = todo[i++]
    if (!u) return
    fetch(`${BASE}?url=${encodeURIComponent(u)}`, { method: 'HEAD' })
      .catch(() => { /* cache warm is best-effort */ })
      .finally(next)
  }
  for (let lane = 0; lane < 3; lane++) next()
}
