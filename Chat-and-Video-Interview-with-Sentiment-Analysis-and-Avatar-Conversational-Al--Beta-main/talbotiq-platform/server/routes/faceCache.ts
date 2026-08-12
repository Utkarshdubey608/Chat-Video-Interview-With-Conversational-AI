import { Router } from 'express'
import { createHash } from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { ah, HttpError } from '../util/ah'
import { bearerToken, contextFromToken } from '../middleware/auth'

/**
 * Replica-preview cache — makes the face picker instant.
 *
 * Tavus replica previews are MP4s on a remote CDN, so every tile used to buffer
 * over the network the moment it scrolled into view. This route downloads each
 * preview ONCE, persists it under server/data/face-cache/ (survives restarts;
 * the dir is gitignored), and serves it from local disk with immutable cache
 * headers thereafter. The client warms the cache in the background right after
 * the replica list loads, so the first picker open is already local-fast.
 *
 * Not an open proxy: https-only, and the upstream host must match a small
 * allowlist (Tavus + its CDNs; extend via FACE_CACHE_HOSTS). Auth: recruiter
 * only — accepts the bearer header or ?token= because <video> tags cannot send
 * headers (same pattern as the WebSocket upgrades).
 */

const here = path.dirname(fileURLToPath(import.meta.url))
const CACHE_DIR = path.join(here, '..', 'data', 'face-cache')

const DEFAULT_HOSTS = ['tavus.io', 'tavusapi.com', 'tavus.video', 'cloudfront.net', 'amazonaws.com']
function allowedHost(hostname: string): boolean {
  const extra = (process.env.FACE_CACHE_HOSTS ?? '')
    .split(/[\s,]+/).map((s) => s.trim().toLowerCase()).filter(Boolean)
  const h = hostname.toLowerCase()
  return [...DEFAULT_HOSTS, ...extra].some((d) => h === d || h.endsWith(`.${d}`))
}

// Some Tavus stock previews exceed 40 MB (observed on cdn.replica.tavus.io), so
// the cap is generous — instant playback is worth the disk. Still bounded so a
// mistaken URL can't fill the drive.
const MAX_BYTES = 150 * 1024 * 1024

/** In-flight downloads keyed by cache key, so N tiles asking for the same video
 *  while it's still downloading share one upstream fetch. */
const inflight = new Map<string, Promise<string>>()

async function ensureCached(url: string): Promise<string> {
  const key = createHash('sha1').update(url).digest('hex')
  const file = path.join(CACHE_DIR, `${key}.mp4`)
  if (fs.existsSync(file)) return file
  const running = inflight.get(key)
  if (running) return running

  const download = (async () => {
    fs.mkdirSync(CACHE_DIR, { recursive: true })
    const r = await fetch(url, { redirect: 'follow', signal: AbortSignal.timeout(30_000) })
    if (!r.ok) throw new HttpError(502, `Upstream fetch failed (${r.status})`)
    const declared = Number(r.headers.get('content-length') ?? 0)
    if (declared > MAX_BYTES) throw new HttpError(502, 'Preview too large to cache')
    const buf = Buffer.from(await r.arrayBuffer())
    if (buf.byteLength > MAX_BYTES) throw new HttpError(502, 'Preview too large to cache')
    // Atomic write: never leave a half-downloaded file where sendFile can find it.
    const tmp = `${file}.${process.pid}.${Date.now()}.tmp`
    fs.writeFileSync(tmp, buf)
    fs.renameSync(tmp, file)
    return file
  })().finally(() => inflight.delete(key))

  inflight.set(key, download)
  return download
}

export const faceCacheRouter = Router()

// Recruiter auth via header OR ?token= (media elements can't set headers).
faceCacheRouter.use((req, _res, next) => {
  Promise.resolve()
    .then(async () => {
      const token = bearerToken(req) ?? (typeof req.query.token === 'string' ? req.query.token : null)
      if (!token) throw new HttpError(401, 'Authentication required')
      const ctx = await contextFromToken(token)
      if (ctx.role !== 'recruiter') throw new HttpError(403, 'Recruiter access required')
      req.auth = ctx
      next()
    })
    .catch(next)
})

// GET /api/avatar/face-cache?url=<https CDN url> → the cached MP4 (Range-capable).
// HEAD warms the cache without transferring the body (used by the client warmer).
faceCacheRouter.get('/', ah(async (req, res) => {
  const url = typeof req.query.url === 'string' ? req.query.url : ''
  let parsed: URL
  try { parsed = new URL(url) } catch { throw new HttpError(400, 'Invalid url') }
  if (parsed.protocol !== 'https:' || !allowedHost(parsed.hostname))
    throw new HttpError(400, 'Host not allowed')

  try {
    const file = await ensureCached(url)
    res.sendFile(file, { maxAge: '365d', immutable: true })
  } catch (err) {
    // Graceful degradation: if the download fails, send the browser straight to
    // the CDN so the picker still shows the face (just not from cache).
    console.warn('[face-cache] falling back to CDN for', parsed.hostname, '-', err instanceof Error ? err.message : err)
    res.redirect(302, url)
  }
}))
