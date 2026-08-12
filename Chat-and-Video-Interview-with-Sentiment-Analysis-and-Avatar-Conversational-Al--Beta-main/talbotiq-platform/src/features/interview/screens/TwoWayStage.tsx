import { useCallback, useEffect, useRef, useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { Mic, MicOff, Video, VideoOff, PhoneOff, Loader2, AlertTriangle } from 'lucide-react'
import type { BrandingConfig } from '@shared/types'
import { sessionsApi, ApiError } from '@/lib/api'
import { useDailyCall } from '../useDailyCall'
import { classifyJoinFailure } from '../twowayJoinError'
import { DailyVideoTile } from '@/components/interview/DailyVideoTile'
import { Completion } from './Completion'

interface Props {
  sessionId: string
  branding: BrandingConfig
}

const RETRY_MS = 4000
// A 'transient' join failure (backend momentarily unreachable — a dev restart
// or a prod deploy) retries silently, but only so many times: past this a
// genuinely broken backend surfaces the hard error instead of spinning forever.
// ~40s of retries at RETRY_MS. (A 'waiting-host' 409 retries indefinitely — the
// recruiter may take minutes — and is NOT bounded by this.)
const MAX_TRANSIENT_RETRIES = 10

/**
 * Candidate side of the live Two-way Interview. Joins the Daily room the
 * recruiter hosts (LiveInterviewPage, T6) with a non-owner/knocking token, so
 * Daily holds the candidate in a waiting room until the recruiter admits
 * them — `useDailyCall().join()`'s promise simply doesn't resolve (callState
 * stays 'joining') until that happens.
 *
 * Two distinct "waiting" reasons, both shown as the same full-screen lobby:
 *  - the recruiter hasn't opened the room yet (`sessionsApi.twowayJoin`
 *    404/409s with "has not started this interview yet" until their `twoway/
 *    host` call has run) — retried on an interval, not a hard error;
 *  - the room exists and we've knocked, but haven't been admitted yet.
 *
 * Full-screen dark room shell (AvatarStage) + circular controls (VoiceStage).
 * No client recording here — the recruiter's side records and uploads (see
 * useDailyCall's docstring); on end we just mark the session complete (no
 * recordingUrl) and hand off to the shared Completion screen.
 */
export function TwoWayStage({ sessionId, branding }: Props) {
  const reduce = useReducedMotion()
  const accent = branding.accentColor || '#0d5c3a'
  const dc = useDailyCall()

  const [joinError, setJoinError] = useState<string | null>(null) // hard (non-retryable) join failure
  const [waitingForHost, setWaitingForHost] = useState(true) // recruiter hasn't opened the room yet
  const [reconnecting, setReconnecting] = useState(false) // backend blip; retrying the join silently
  const [attempt, setAttempt] = useState(0) // bump to retry the whole flow after a hard error
  const [completed, setCompleted] = useState(false)

  const completingRef = useRef(false)
  // Consecutive 'transient' join failures in the current join cycle (reset on
  // any success or a clean 'waiting-host' response). Bounds the silent retry.
  const transientRetriesRef = useRef(0)
  // Tracks whether the interviewer's tile has ever shown up on this join
  // cycle, so a momentary drop (remote goes null again while still `joined`)
  // reads as "reconnecting" rather than the pre-admit "waiting to be let in"
  // copy below.
  const hadRemoteRef = useRef(false)

  const finish = useCallback(async () => {
    if (completingRef.current) return
    completingRef.current = true
    // Best-effort — the recruiter's own twoway/complete call (with the
    // recording) is the authoritative one; this just closes out the
    // candidate's session promptly if theirs is slow/fails.
    try { await sessionsApi.twowayComplete(sessionId) } catch { /* best-effort */ }
    setCompleted(true)
  }, [sessionId])

  // Acquire the room + a knocking token, then hand off to Daily.
  //
  // `cancelled` is a per-invocation local (captured in this effect's closure),
  // NOT a shared ref — under StrictMode's dev-only mount→cleanup→remount, a
  // shared ref reset at the top of the effect body would be clobbered by the
  // second invocation, un-cancelling the first invocation's in-flight
  // `twowayJoin` promise and orphaning its retry timer (same pattern as
  // AvatarStage's effect 1 above).
  useEffect(() => {
    let cancelled = false
    let retryTimer: ReturnType<typeof setTimeout> | undefined
    setJoinError(null)
    setWaitingForHost(true)
    setReconnecting(false)
    transientRetriesRef.current = 0
    hadRemoteRef.current = false

    const attemptJoin = async () => {
      try {
        const { roomUrl, token } = await sessionsApi.twowayJoin(sessionId)
        if (cancelled) return
        transientRetriesRef.current = 0
        setReconnecting(false)
        setWaitingForHost(false)
        await dc.join(roomUrl, token)
      } catch (e) {
        if (cancelled) return
        // dc.join() never throws (it surfaces call errors via dc.callState),
        // so anything caught here is a failed twowayJoin HTTP request. Classify
        // it: a definite client error is fatal; a recruiter-not-started 409 or a
        // transient backend blip stays in the lobby and retries on the interval.
        const status = e instanceof ApiError ? e.status : null
        const message = e instanceof Error ? e.message : ''
        const kind = classifyJoinFailure(status, message)

        if (kind === 'fatal') {
          setJoinError(message || 'Could not join the interview')
          return
        }
        if (kind === 'transient') {
          transientRetriesRef.current += 1
          if (transientRetriesRef.current > MAX_TRANSIENT_RETRIES) {
            setJoinError(message || 'We couldn’t reach the interview server. Please try again.')
            return
          }
          setReconnecting(true)
        } else {
          // 'waiting-host' — the server IS responding (just not started yet), so
          // the transient budget resets and we show the waiting-for-host copy.
          transientRetriesRef.current = 0
          setReconnecting(false)
        }
        retryTimer = setTimeout(() => { if (!cancelled) void attemptJoin() }, RETRY_MS)
      }
    }
    void attemptJoin()

    return () => {
      cancelled = true
      clearTimeout(retryTimer)
    }
    // dc.join has a stable identity for the lifetime of this hook instance.
  }, [sessionId, attempt, dc.join])

  // The call ending — whether the candidate hit Leave, the recruiter ended
  // it, or the connection dropped — always lands on callState 'left'; either
  // way, complete the session (no recordingUrl; the recruiter uploads it).
  useEffect(() => {
    if (dc.callState === 'left') void finish()
  }, [dc.callState, finish])

  const handleEnd = useCallback(() => {
    if (!window.confirm('End the interview now? You can’t rejoin afterwards.')) return
    void dc.leave()
  }, [dc.leave])

  const remote = dc.participants[0] ?? null
  if (remote) hadRemoteRef.current = true

  /* ── finished ── */
  if (completed) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-4">
        <Completion branding={branding} />
      </div>
    )
  }

  /* ── hard error — join failed for a reason that won't resolve on its own ── */
  if (joinError) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-4">
        <div className="max-w-md rounded-2xl border border-border bg-white p-10 text-center shadow-sm">
          <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-danger-bg text-danger">
            <AlertTriangle size={22} />
          </span>
          <h1 className="mt-4 text-xl font-bold text-neutral-900">We couldn’t join your interview</h1>
          <p className="mt-2 text-sm leading-relaxed text-neutral-500">{joinError}</p>
          <button
            onClick={() => setAttempt((a) => a + 1)}
            className="mt-5 rounded-full px-5 py-2 text-sm font-semibold text-white"
            style={{ background: accent }}
          >
            Try again
          </button>
          <p className="mt-3 text-xs text-neutral-400">If this keeps happening, contact your recruiter.</p>
        </div>
      </div>
    )
  }

  /* ── Daily call error (device/connection) — surfaced from useDailyCall ── */
  if (dc.callState === 'error') {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-4">
        <div className="max-w-md rounded-2xl border border-border bg-white p-10 text-center shadow-sm">
          <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-danger-bg text-danger">
            <AlertTriangle size={22} />
          </span>
          <h1 className="mt-4 text-xl font-bold text-neutral-900">Connection problem</h1>
          <p className="mt-2 text-sm leading-relaxed text-neutral-500">
            {dc.error ?? 'The call hit a connection problem.'}
          </p>
          <button
            onClick={() => setAttempt((a) => a + 1)}
            className="mt-5 rounded-full px-5 py-2 text-sm font-semibold text-white"
            style={{ background: accent }}
          >
            Try again
          </button>
        </div>
      </div>
    )
  }

  /* ── wrapping up — callState just hit 'left' (our Leave, the recruiter's End,
        or a dropped connection); finish() is completing the session above ── */
  if (dc.callState === 'left') {
    return (
      <div className="flex h-screen flex-col items-center justify-center gap-3 bg-neutral-950 text-neutral-300">
        <Loader2 size={26} className="animate-spin" />
        <p className="text-sm">Wrapping up…</p>
      </div>
    )
  }

  /* ── lobby — waiting for the recruiter to start the room / admit the knock ── */
  if (waitingForHost || dc.callState !== 'joined' || !remote) {
    return (
      <div className="flex h-screen flex-col overflow-hidden bg-neutral-950">
        <div className="flex h-[56px] flex-shrink-0 items-center border-b border-white/10 bg-neutral-950 px-4">
          <span className="truncate font-bold text-white">{branding.companyName}</span>
        </div>
        <div className="flex flex-1 flex-col items-center justify-center gap-4 px-4 text-center">
          <motion.div
            animate={reduce ? undefined : { scale: [1, 1.08, 1] }}
            transition={{ duration: 1.8, repeat: Infinity }}
            className="flex h-16 w-16 items-center justify-center rounded-full"
            style={{ background: `${accent}33` }}
          >
            <Loader2 size={26} className="animate-spin text-white" />
          </motion.div>
          <p className="text-lg font-semibold text-white">
            {reconnecting
              ? 'Reconnecting…' // backend briefly unreachable (restart/deploy); retrying automatically
              : waitingForHost
                ? 'Waiting for the interviewer to start the interview…'
                : dc.callState === 'joined' && hadRemoteRef.current
                  ? 'Reconnecting…' // was live; the interviewer's tile just dropped momentarily
                  : 'Waiting for the interviewer to admit you…'}
          </p>
          <p className="max-w-sm text-sm text-neutral-400">
            {reconnecting
              ? 'We briefly lost the connection to the interview server — reconnecting automatically. No need to do anything.'
              : 'Your camera and mic are ready — you’ll be connected the moment the interviewer lets you in.'}
          </p>
        </div>
      </div>
    )
  }

  /* ── the live room — full-viewport, interviewer big, self small ── */
  return (
    <div className="flex h-screen flex-col overflow-hidden bg-neutral-950">
      <div className="flex h-[56px] flex-shrink-0 items-center justify-between gap-3 border-b border-white/10 bg-neutral-950 px-4">
        <span className="flex items-center gap-2 truncate font-bold text-white">
          {branding.companyName}
          <span className="flex items-center gap-1.5 rounded-full bg-white/10 px-2.5 py-0.5 text-[11px] font-bold uppercase tracking-wider text-emerald-300">
            <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400" /> Live
          </span>
        </span>
        <button
          onClick={handleEnd}
          className="inline-flex items-center gap-1.5 rounded-full bg-red-500/15 px-4 py-1.5 text-sm font-semibold text-red-300 transition-colors hover:bg-red-500/25"
        >
          <PhoneOff size={15} /> End interview
        </button>
      </div>

      <div className="relative flex-1 p-4">
        <div className="mx-auto h-full max-w-4xl">
          <DailyVideoTile participant={remote} label="Interviewer" />
        </div>
        {dc.localParticipant && (
          <div className="absolute bottom-4 right-6 w-40 shadow-lg sm:w-52">
            <DailyVideoTile participant={dc.localParticipant} label="You" />
          </div>
        )}
      </div>

      <div className="border-t border-white/10 bg-neutral-950">
        <div className="mx-auto flex max-w-3xl items-center justify-center gap-4 px-4 py-5">
          <button
            onClick={dc.toggleMic}
            aria-pressed={dc.muted}
            className="flex h-14 w-14 items-center justify-center rounded-full border-2 border-white/15 bg-white/5 text-white transition-all hover:bg-white/10"
            aria-label={dc.muted ? 'Unmute microphone' : 'Mute microphone'}
          >
            {dc.muted ? <MicOff size={22} className="text-red-400" /> : <Mic size={22} />}
          </button>
          <button
            onClick={handleEnd}
            className="flex h-16 w-16 items-center justify-center rounded-full bg-danger text-white shadow-md transition-transform hover:scale-105"
            aria-label="End interview"
          >
            <PhoneOff size={24} />
          </button>
          <button
            onClick={dc.toggleCam}
            aria-pressed={dc.camOff}
            className="flex h-14 w-14 items-center justify-center rounded-full border-2 border-white/15 bg-white/5 text-white transition-all hover:bg-white/10"
            aria-label={dc.camOff ? 'Turn camera on' : 'Turn camera off'}
          >
            {dc.camOff ? <VideoOff size={22} className="text-red-400" /> : <Video size={22} />}
          </button>
        </div>
      </div>
    </div>
  )
}
