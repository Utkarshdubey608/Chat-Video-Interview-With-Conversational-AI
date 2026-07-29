import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/components/ui'
import { cachedFaceUrl, warmFaceCache } from '@/lib/faceCache'
import { getIdTokenOrNull } from '@/lib/firebase'
import type { TavusReplica } from '@/types/tavus.types'

/**
 * ReplicaPicker — a visual avatar/face selector.
 *
 * Replaces the plain text `<Select>` of replica names with a picker that shows
 * the actual Tavus replica *face*. Each face is a still frame at rest and plays
 * its preview video when the cursor hovers it (desktop), so recruiters pick a
 * face by looking at it rather than reading an ID. On touch devices — where
 * there is no hover — the visible faces auto-play instead.
 */

interface ReplicaPickerProps {
  replicas: TavusReplica[]
  /** Selected replica_id ('' = none). */
  value: string
  onChange: (replicaId: string) => void
  label?: string
  hint?: string
  /** Show a "None" tile (e.g. demo mode / inherit defaults). */
  includeNone?: boolean
  noneLabel?: string
  loading?: boolean
}

/* ── Bearer token for media URLs (video tags can't send auth headers) ────────── */
function useMediaToken() {
  const [token, setToken] = useState<string | null>(null)
  useEffect(() => {
    let alive = true
    getIdTokenOrNull().then((t) => { if (alive) setToken(t) }).catch(() => {})
    return () => { alive = false }
  }, [])
  return token
}

/* ── Does this device have a real hovering pointer (mouse) vs. touch? ────────── */
function useCanHover() {
  const [canHover, setCanHover] = useState(true)
  useEffect(() => {
    if (typeof window === 'undefined' || !window.matchMedia) return
    const mq = window.matchMedia('(hover: hover) and (pointer: fine)')
    const sync = () => setCanHover(mq.matches)
    sync()
    mq.addEventListener?.('change', sync)
    return () => mq.removeEventListener?.('change', sync)
  }, [])
  return canHover
}

/* ── Placeholder shown when a replica has no preview video ──────────────────── */
function PlaceholderFace() {
  return (
    <div className="w-full h-full bg-gradient-to-br from-neutral-100 to-neutral-50 flex items-center justify-center text-neutral-300">
      <svg width="40%" height="40%" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <circle cx="12" cy="8" r="4" />
        <path d="M4 20c0-4 3.6-7 8-7s8 3 8 7" />
      </svg>
    </div>
  )
}

/**
 * The face media itself — a still frame that plays when `play` is true.
 * - Serves from the SERVER's local preview cache (warmed in the background when
 *   the replica list loads), so painting and playback are instant instead of
 *   buffering from the Tavus CDN. If the cache route ever fails, the tile falls
 *   back to the original CDN URL.
 * - Attaches its video source ONLY while near the viewport and RELEASES it when
 *   scrolled away. Without this, a long face list latched every tile's <video>
 *   on permanently, piling up dozens of buffering videos until the tab crashed
 *   (out of memory). Now the number of live videos is capped to what's visible —
 *   and re-attaching on scroll-back is free because the media is local.
 * - Plays after a short hover-intent delay so quickly sweeping the grid never
 *   kicks off a storm of playbacks.
 */
function FaceMedia({ replica, play, token }: { replica: TavusReplica; play: boolean; token: string | null }) {
  const ref = useRef<HTMLVideoElement>(null)
  const [inView, setInView] = useState(false) // currently within (or near) the viewport
  const [failed, setFailed] = useState(false) // cache route failed → use the CDN directly

  // Observe visibility: attach the source when in view, release it when it
  // leaves so off-screen tiles hold no media.
  useEffect(() => {
    const v = ref.current
    if (!v) return
    if (typeof IntersectionObserver === 'undefined') { setInView(true); return }
    const io = new IntersectionObserver(
      ([e]) => setInView(!!e?.isIntersecting),
      { rootMargin: '300px' }, // generous pre-attach margin — local media is cheap
    )
    io.observe(v)
    return () => io.disconnect()
  }, [])

  // Play / pause. Deferred by 120ms so a mere sweep-over never triggers playback.
  useEffect(() => {
    const v = ref.current
    if (!v) return
    if (play && inView) {
      const t = setTimeout(() => { v.play().catch(() => {}) }, 120)
      return () => clearTimeout(t)
    }
    v.pause()
    try { v.currentTime = 0.1 } catch { /* noop */ }
  }, [play, inView, replica.thumbnail_video_url])

  const raw = replica.thumbnail_video_url
  if (!raw) return <PlaceholderFace />
  const src = failed ? raw : cachedFaceUrl(raw, token)

  return (
    <video
      ref={ref}
      // Only near the viewport → keeps the live-video count bounded.
      src={inView ? src : undefined}
      muted
      loop
      playsInline
      // Local cache makes full preload cheap — buffered before the first hover.
      preload="auto"
      // Seek a hair past 0 so a real face frame paints while the video is paused.
      onLoadedMetadata={(e) => { try { e.currentTarget.currentTime = 0.1 } catch { /* noop */ } }}
      onError={() => { if (!failed) setFailed(true) }}
      className="w-full h-full object-cover"
    />
  )
}

/* ── One selectable face tile ───────────────────────────────────────────────── */
function FaceTile({
  replica,
  selected,
  canHover,
  onSelect,
  token,
}: {
  replica: TavusReplica
  selected: boolean
  canHover: boolean
  onSelect: (id: string) => void
  token: string | null
}) {
  const [hover, setHover] = useState(false)
  // Only surface a status chip for states that AREN'T usable yet. A trained
  // replica ('ready'/'completed') gets no badge — the old code stamped every
  // completed face with a "COMPLETED" chip.
  const showStatus = replica.status === 'training' || replica.status === 'error'
  const isStock = replica.replica_type === 'stock'
  // Desktop: play on hover. Touch (no hover): auto-play the faces in view.
  const play = canHover ? hover : true

  return (
    <button
      type="button"
      title={`${replica.replica_name} · ${replica.replica_id}`}
      onClick={() => onSelect(replica.replica_id)}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      onFocus={() => setHover(true)}
      onBlur={() => setHover(false)}
      className={cn(
        'group relative rounded-xl overflow-hidden border-2 text-left transition-all duration-150',
        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-700 focus-visible:ring-offset-1',
        selected
          ? 'border-primary-700 shadow-primary-sm'
          : 'border-transparent hover:border-primary-300',
      )}
    >
      <div className="relative aspect-[4/3] w-full overflow-hidden bg-neutral-100">
        <div className={cn('absolute inset-0 transition-transform duration-300', hover && 'scale-[1.06]')}>
          <FaceMedia replica={replica} play={play} token={token} />
        </div>

        {/* Name overlay */}
        <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/75 via-black/25 to-transparent px-2.5 pt-6 pb-2">
          <p className="text-xs font-semibold text-white truncate drop-shadow-sm">{replica.replica_name}</p>
        </div>

        {/* Top-left status / stock chip */}
        {showStatus ? (
          <span className="absolute top-1.5 left-1.5 text-[9px] font-bold uppercase tracking-wide bg-white/90 text-amber-700 px-1.5 py-0.5 rounded">
            {replica.status}
          </span>
        ) : isStock ? (
          <span className="absolute top-1.5 left-1.5 text-[9px] font-bold uppercase tracking-wide bg-white/85 text-neutral-600 px-1.5 py-0.5 rounded">
            Stock
          </span>
        ) : null}

        {/* Selected check */}
        {selected && (
          <span className="absolute top-1.5 right-1.5 w-5 h-5 rounded-full bg-primary-700 text-white flex items-center justify-center shadow-sm">
            <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.5"><polyline points="20 6 9 17 4 12" /></svg>
          </span>
        )}
      </div>
    </button>
  )
}

/* ── Grouped section within the popover ─────────────────────────────────────── */
function Section({ title, count, children }: { title: string; count: number; children: React.ReactNode }) {
  return (
    <div>
      <div className="flex items-center gap-2 mb-2 px-0.5">
        <span className="text-[11px] font-bold uppercase tracking-wide text-neutral-500">{title}</span>
        <span className="text-[11px] text-neutral-400">{count}</span>
      </div>
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-2.5">{children}</div>
    </div>
  )
}

export function ReplicaPicker({
  replicas,
  value,
  onChange,
  label,
  hint,
  includeNone = false,
  noneLabel = 'None',
  loading = false,
}: ReplicaPickerProps) {
  const [open, setOpen] = useState(false)
  const [rect, setRect] = useState<DOMRect | null>(null)
  const rootRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)
  const popoverRef = useRef<HTMLDivElement>(null)
  const canHover = useCanHover()
  const mediaToken = useMediaToken()

  // Pre-download every preview into the server's local cache the moment the
  // replica list is known — the first picker open then plays instantly.
  useEffect(() => {
    if (replicas.length) warmFaceCache(replicas.map((r) => r.thumbnail_video_url))
  }, [replicas])

  // Track the trigger's viewport rect so the (portalled) popover can be
  // positioned with `fixed` — this escapes any `overflow` ancestor (e.g. the
  // Personas modal's scroll column) that would otherwise clip it.
  useEffect(() => {
    if (!open) return
    const update = () => setRect(triggerRef.current?.getBoundingClientRect() ?? null)
    update()
    window.addEventListener('resize', update)
    window.addEventListener('scroll', update, true) // capture: catch inner scroll containers too
    return () => {
      window.removeEventListener('resize', update)
      window.removeEventListener('scroll', update, true)
    }
  }, [open])

  // Dismiss on outside click / Escape (the popover lives in a portal, so check both).
  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => {
      const t = e.target as Node
      if (rootRef.current?.contains(t)) return
      if (popoverRef.current?.contains(t)) return
      setOpen(false)
    }
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false) }
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  const selected = replicas.find((r) => r.replica_id === value)
  const custom = replicas.filter((r) => r.replica_type !== 'stock')
  const stock = replicas.filter((r) => r.replica_type === 'stock')
  const isCustomId = !!value && !selected // a manually-typed ID not in the list

  const pick = (id: string) => { onChange(id); setOpen(false) }

  return (
    <div className="flex flex-col gap-1.5" ref={rootRef}>
      {label && <label className="field-label">{label}</label>}

      <div className="relative">
        {/* ── Trigger ── */}
        <button
          ref={triggerRef}
          type="button"
          onClick={() => setOpen((o) => !o)}
          aria-haspopup="listbox"
          aria-expanded={open}
          className={cn(
            'w-full flex items-center gap-3 text-left rounded-lg border-[1.5px] bg-white px-2.5 py-2 min-h-[44px] cursor-pointer',
            'transition-colors focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-primary-700/10',
            open ? 'border-primary-700' : 'border-border hover:border-primary-200',
          )}
        >
          <div className="w-9 h-9 rounded-lg overflow-hidden bg-neutral-100 flex-shrink-0 border border-border">
            {selected ? <FaceMedia replica={selected} play={false} token={mediaToken} /> : <PlaceholderFace />}
          </div>

          <div className="min-w-0 flex-1">
            {selected ? (
              <>
                <p className="text-sm font-medium text-neutral-800 truncate leading-tight">{selected.replica_name}</p>
                <p className="text-[11px] text-neutral-400 font-mono truncate">{selected.replica_id}</p>
              </>
            ) : isCustomId ? (
              <>
                <p className="text-sm font-medium text-neutral-800 truncate leading-tight">Custom replica ID</p>
                <p className="text-[11px] text-neutral-400 font-mono truncate">{value}</p>
              </>
            ) : (
              <p className="text-sm text-neutral-400">{includeNone ? noneLabel : 'Select a face…'}</p>
            )}
          </div>

          <svg
            className={cn('text-neutral-400 flex-shrink-0 transition-transform', open && 'rotate-180')}
            width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"
          >
            <polyline points="6 9 12 15 18 9" />
          </svg>
        </button>

        {/* ── Popover (portalled + fixed so it never gets clipped by a scroll ancestor) ── */}
        {open && rect && createPortal(
          <div
            ref={popoverRef}
            style={{
              position: 'fixed',
              top: rect.bottom + 8,
              left: rect.left,
              width: rect.width,
              maxHeight: `calc(100vh - ${rect.bottom + 24}px)`,
            }}
            className="z-[60] min-w-[280px] rounded-xl border border-border bg-white shadow-xl animate-slide-up overflow-hidden flex flex-col"
          >
            <div className="px-3.5 py-2.5 border-b border-border flex items-center justify-between flex-shrink-0">
              <span className="text-xs font-semibold text-neutral-700">Choose a face</span>
              <span className="text-[11px] text-neutral-400">{canHover ? 'Hover to preview ✨' : 'Tap to select'}</span>
            </div>

            <div className="overflow-y-auto p-3 space-y-4">
              {loading ? (
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2.5">
                  {[...Array(6)].map((_, i) => (
                    <div key={i} className="aspect-[4/3] rounded-xl bg-neutral-100 animate-pulse" />
                  ))}
                </div>
              ) : custom.length + stock.length === 0 ? (
                <p className="text-sm text-neutral-400 text-center py-8">
                  No replicas found.<br />Add your Tavus API key in Settings.
                </p>
              ) : (
                <>
                  {includeNone && (
                    <button
                      type="button"
                      onClick={() => pick('')}
                      className={cn(
                        'w-full flex items-center gap-3 px-3 py-2.5 rounded-lg border transition-all',
                        !value
                          ? 'border-primary-700 bg-primary-50'
                          : 'border-border hover:border-primary-300 hover:bg-neutral-50',
                      )}
                    >
                      <span className="w-8 h-8 rounded-lg bg-neutral-100 flex items-center justify-center text-neutral-400 flex-shrink-0 text-sm">∅</span>
                      <span className="text-sm font-medium text-neutral-700">{noneLabel}</span>
                    </button>
                  )}

                  {custom.length > 0 && (
                    <Section title="Your replicas" count={custom.length}>
                      {custom.map((r) => (
                        <FaceTile key={r.replica_id} replica={r} selected={r.replica_id === value} canHover={canHover} onSelect={pick} token={mediaToken} />
                      ))}
                    </Section>
                  )}

                  {stock.length > 0 && (
                    <Section title="Stock replicas" count={stock.length}>
                      {stock.map((r) => (
                        <FaceTile key={r.replica_id} replica={r} selected={r.replica_id === value} canHover={canHover} onSelect={pick} token={mediaToken} />
                      ))}
                    </Section>
                  )}
                </>
              )}
            </div>
          </div>,
          document.body,
        )}
      </div>

      {hint && <p className="text-xs text-neutral-400">{hint}</p>}
    </div>
  )
}

export default ReplicaPicker
