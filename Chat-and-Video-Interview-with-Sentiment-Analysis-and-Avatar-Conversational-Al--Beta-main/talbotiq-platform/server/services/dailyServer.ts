import { HttpError } from '../util/ah'

/**
 * Server-side Daily client for the Two-way Interview. The DAILY_API_KEY stays
 * here; the browser only ever receives a room URL + a short-lived meeting token
 * (mirrors tavusServer.ts's server-held-key pattern). Recruiter joins as owner;
 * candidate joins non-owner with knocking (Daily's waiting room = the source's
 * lobby/admit).
 */
const DAILY_BASE = 'https://api.daily.co/v1'
const ROOM_TTL_SEC = 4 * 60 * 60 // room self-expires 4h after creation
const TOKEN_TTL_SEC = 3 * 60 * 60 // token valid 3h

export function dailyConfigured(): boolean {
  return Boolean((process.env.DAILY_API_KEY ?? '').trim())
}
function key(): string {
  const k = (process.env.DAILY_API_KEY ?? '').trim()
  if (!k) throw new HttpError(503, 'The two-way interview is not configured — set DAILY_API_KEY on the server.')
  return k
}
async function daily<T>(path: string, init: RequestInit): Promise<T> {
  const res = await fetch(`${DAILY_BASE}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${key()}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) },
  })
  if (!res.ok) {
    const err = (await res.json().catch(() => null)) as { info?: string; error?: string } | null
    throw new HttpError(502, err?.info ?? err?.error ?? `Daily error (HTTP ${res.status})`)
  }
  return res.json() as Promise<T>
}

/** Room properties — knocking on so the recruiter (owner) admits the candidate. */
export function buildRoomProperties(nowSec: number): Record<string, unknown> {
  return {
    enable_knocking: true,
    enable_screenshare: true,
    eject_at_room_exp: true,
    exp: nowSec + ROOM_TTL_SEC,
    start_video_off: false,
    start_audio_off: false,
  }
}

/** Idempotent: create the room if absent, else return the existing one. */
export async function ensureRoom(roomName: string): Promise<{ name: string; url: string }> {
  const res = await fetch(`${DAILY_BASE}/rooms/${roomName}`, { headers: { Authorization: `Bearer ${key()}` } })
  if (res.ok) return res.json() as Promise<{ name: string; url: string }>
  if (res.status !== 404) {
    const err = (await res.json().catch(() => null)) as { info?: string; error?: string } | null
    throw new HttpError(502, err?.info ?? err?.error ?? `Daily error (HTTP ${res.status})`)
  }
  // 404 → room doesn't exist yet → create it (idempotent)
  const now = Math.floor(Date.now() / 1000)
  return daily('/rooms', {
    method: 'POST',
    body: JSON.stringify({ name: roomName, privacy: 'private', properties: buildRoomProperties(now) }),
  })
}

/** Meeting-token properties — owner (recruiter) gets cloud recording; candidate does not. */
export function buildTokenProperties(
  opts: { roomName: string; isOwner: boolean; userName: string },
  nowSec: number,
): Record<string, unknown> {
  return {
    room_name: opts.roomName,
    is_owner: opts.isOwner,
    user_name: opts.userName.slice(0, 60),
    exp: nowSec + TOKEN_TTL_SEC,
    ...(opts.isOwner ? { enable_recording: 'cloud' } : {}),
  }
}

export async function mintToken(opts: { roomName: string; isOwner: boolean; userName: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const r = await daily<{ token: string }>('/meeting-tokens', {
    method: 'POST',
    body: JSON.stringify({ properties: buildTokenProperties(opts, now) }),
  })
  return r.token
}

export async function deleteRoom(roomName: string): Promise<void> {
  try {
    await daily(`/rooms/${roomName}`, { method: 'DELETE' })
  } catch (err) {
    console.error('[twoway] room delete failed', roomName, err)
  }
}
