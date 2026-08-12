import type { TavusReplica } from '@/types/tavus.types'
import { cachedFaceUrl } from '@/lib/faceCache'

/**
 * Real-replica face cache for the intro.
 *
 * The animation must show the ACTUAL Tavus replica faces (the ones in the
 * picker) — but it must NEVER call Tavus on mount. So we extract one still
 * frame per replica ONCE, from the server's already-local preview cache
 * (`/api/avatar/face-cache`, same-origin → canvas-readable, no CORS taint), and
 * persist the JPEGs in IndexedDB. The intro reads only from here.
 *
 * `syncReplicaFaces()` runs from an authenticated recruiter context (it is given
 * the replica list the app already loaded — no extra Tavus call). `getCachedFaces()`
 * is what the (provider-less) intro overlay calls.
 */

const DB_NAME = 'mimic-intro'
const DB_VERSION = 1
const STORE = 'faces'
const META = 'meta'
const META_KEY = 'sync'
// Bump to force existing clients to re-extract (e.g. when the capture size or
// quality changes) — IntroFaceSync re-syncs when the stored version differs.
export const CACHE_VERSION = 2
// Max 4:3 still size. We capture at the video's NATIVE resolution (never
// upscaling), capped here, so faces stay as crisp as the source allows.
export const FACE_MAX_W = 512
export const FACE_MAX_H = 384

export type CachedFace = { replica_id: string; name: string; blob: Blob }
export type SyncMeta = { syncedAt: number; count: number; version: number }

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION)
    req.onupgradeneeded = () => {
      const db = req.result
      if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE, { keyPath: 'replica_id' })
      if (!db.objectStoreNames.contains(META)) db.createObjectStore(META)
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

function tx<T>(db: IDBDatabase, store: string, mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    const t = db.transaction(store, mode)
    const req = fn(t.objectStore(store))
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

/** All cached faces (the intro's only data source). Empty array on any failure. */
export async function getCachedFaces(): Promise<CachedFace[]> {
  try {
    const db = await openDb()
    const all = await tx<CachedFace[]>(db, STORE, 'readonly', (s) => s.getAll() as IDBRequest<CachedFace[]>)
    db.close()
    return Array.isArray(all) ? all.filter((f) => f && f.blob instanceof Blob) : []
  } catch {
    return []
  }
}

export async function getSyncMeta(): Promise<SyncMeta | null> {
  try {
    const db = await openDb()
    const meta = await tx<SyncMeta | undefined>(db, META, 'readonly', (s) => s.get(META_KEY) as IDBRequest<SyncMeta | undefined>)
    db.close()
    return meta ?? null
  } catch {
    return null
  }
}

async function putFace(db: IDBDatabase, face: CachedFace): Promise<void> {
  await tx(db, STORE, 'readwrite', (s) => s.put(face))
}
async function putMeta(db: IDBDatabase, meta: SyncMeta): Promise<void> {
  await tx(db, META, 'readwrite', (s) => s.put(meta, META_KEY))
}

/**
 * Capture one still frame from a preview MP4 into a square JPEG blob.
 * Uses the same-origin cached URL so the canvas stays untainted and readable.
 */
function extractFrame(videoUrl: string): Promise<Blob | null> {
  return new Promise((resolve) => {
    const v = document.createElement('video')
    v.crossOrigin = 'anonymous'
    v.muted = true
    v.playsInline = true
    v.preload = 'auto'
    let settled = false
    const finish = (b: Blob | null) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      try {
        v.removeAttribute('src')
        v.load()
      } catch {
        /* noop */
      }
      resolve(b)
    }
    const grab = () => {
      const vw = v.videoWidth
      const vh = v.videoHeight
      if (!vw || !vh) return finish(null)
      try {
        // Output 4:3 at the source's NATIVE resolution (never upscale), capped.
        let outW = Math.min(FACE_MAX_W, vw)
        let outH = Math.round((outW * 3) / 4)
        if (outH > vh) {
          outH = Math.min(FACE_MAX_H, vh)
          outW = Math.round((outH * 4) / 3)
        }
        const c = document.createElement('canvas')
        c.width = outW
        c.height = outH
        const ctx = c.getContext('2d')
        if (!ctx) return finish(null)
        ctx.imageSmoothingQuality = 'high'
        // Cover-fit (center crop) into the 4:3 card — never stretched.
        const scale = Math.max(outW / vw, outH / vh)
        const dw = vw * scale
        const dh = vh * scale
        ctx.drawImage(v, (outW - dw) / 2, (outH - dh) / 2, dw, dh)
        c.toBlob((b) => finish(b), 'image/jpeg', 0.92)
      } catch {
        finish(null)
      }
    }
    v.addEventListener('seeked', grab, { once: true })
    v.addEventListener(
      'loadeddata',
      () => {
        try {
          v.currentTime = 0.2
        } catch {
          grab()
        }
      },
      { once: true },
    )
    v.addEventListener('error', () => finish(null), { once: true })
    const timer = setTimeout(() => finish(null), 12_000)
    v.src = videoUrl
  })
}

/** True when a replica is trained/usable and has a preview to sample. */
function isUsable(r: TavusReplica): boolean {
  return Boolean(r.thumbnail_video_url) && (r.status === 'ready' || r.status === 'completed' || r.status === undefined)
}

export type SyncOptions = {
  token: string | null
  /** Cap how many faces to cache (perf). Default 96. */
  max?: number
  /** Parallel extractions. Default 4. */
  concurrency?: number
  onProgress?: (done: number, total: number) => void
  signal?: AbortSignal
}

/**
 * Extract + persist a still for each replica. Idempotent and incremental:
 * skips replicas already cached this run's set. Returns the number now cached.
 * Never throws — best-effort.
 */
export async function syncReplicaFaces(replicas: TavusReplica[], opts: SyncOptions): Promise<number> {
  const { token, max = 96, concurrency = 4, onProgress, signal } = opts
  let db: IDBDatabase
  try {
    db = await openDb()
  } catch {
    return 0
  }

  const usable = replicas.filter(isUsable).slice(0, max)
  const total = usable.length
  let done = 0
  let cached = 0
  let cursor = 0

  const worker = async (): Promise<void> => {
    while (cursor < usable.length) {
      if (signal?.aborted) return
      const r = usable[cursor++]
      const url = cachedFaceUrl(r.thumbnail_video_url as string, token)
      const blob = await extractFrame(url)
      if (blob) {
        try {
          await putFace(db, { replica_id: r.replica_id, name: r.replica_name, blob })
          cached++
        } catch {
          /* skip */
        }
      }
      done++
      onProgress?.(done, total)
    }
  }

  await Promise.all(Array.from({ length: Math.max(1, concurrency) }, () => worker()))
  try {
    await putMeta(db, { syncedAt: Date.now(), count: cached, version: CACHE_VERSION })
  } catch {
    /* noop */
  }
  db.close()
  return cached
}
