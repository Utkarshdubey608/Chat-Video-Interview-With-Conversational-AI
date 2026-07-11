import { useCallback, useEffect, useRef, useState } from 'react'
import { sessionsApi, ApiError } from '@/lib/api'
import type { CandidateSessionState, TrackType } from '@shared/types'

/**
 * Drives the candidate interview. The SERVER is the source of truth for phase
 * and remaining time; we poll `/state` and interpolate locally between polls
 * for a smooth countdown. When the local clock crosses zero we immediately
 * re-fetch so the authoritative transition (incl. auto-submit) is reflected.
 */
export function useInterviewClock(sessionId: string) {
  const [state, setState] = useState<CandidateSessionState | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  // Local interpolation baseline (server remaining + the moment we received it).
  const base = useRef<{ remaining: number; at: number } | null>(null)
  const [remaining, setRemaining] = useState(0)
  const fetching = useRef(false)

  const apply = useCallback((s: CandidateSessionState) => {
    setState(s)
    setError(null)
    setLoading(false)
    if (s.status === 'in_progress' && s.phase) {
      base.current = { remaining: s.remainingSeconds, at: performance.now() }
      setRemaining(s.remainingSeconds)
    } else {
      base.current = null
      setRemaining(0)
    }
  }, [])

  const refresh = useCallback(async () => {
    if (fetching.current) return
    fetching.current = true
    try {
      apply(await sessionsApi.state(sessionId))
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not load the interview')
      setLoading(false)
    } finally {
      fetching.current = false
    }
  }, [sessionId, apply])

  // Initial load + periodic drift-correcting poll.
  useEffect(() => {
    refresh()
    const id = setInterval(refresh, 5000)
    return () => clearInterval(id)
  }, [refresh])

  // Local 200ms tick — interpolate the countdown and re-sync at the boundary.
  useEffect(() => {
    const id = setInterval(() => {
      const b = base.current
      if (!b) return
      const rem = Math.max(0, b.remaining - (performance.now() - b.at) / 1000)
      setRemaining(rem)
      if (rem <= 0) {
        base.current = null // prevent repeated fires; refresh gets the next phase
        refresh()
      }
    }, 200)
    return () => clearInterval(id)
  }, [refresh])

  const action = useCallback(
    async (fn: () => Promise<CandidateSessionState>) => {
      setBusy(true)
      try {
        apply(await fn())
      } catch (e) {
        setError(e instanceof ApiError ? e.message : 'Something went wrong')
        // re-sync to recover from a stale-question race
        refresh()
      } finally {
        setBusy(false)
      }
    },
    [apply, refresh],
  )

  const setTrack = (t: TrackType) => action(() => sessionsApi.setTrack(sessionId, t))
  const systemCheck = () => action(() => sessionsApi.systemCheck(sessionId))
  const uploadResume = (file: File) => action(() => sessionsApi.uploadResume(sessionId, file))
  const begin = () => action(() => sessionsApi.begin(sessionId))
  const skipPrep = () => action(() => sessionsApi.skipPrep(sessionId))
  const completeNow = () => action(() => sessionsApi.complete(sessionId))

  const submit = (answerText: string) => {
    const qid = state?.question?.id
    if (!qid) return Promise.resolve()
    return action(() => sessionsApi.submitAnswer(sessionId, { questionId: qid, answerText }))
  }

  const saveDraft = useCallback(
    async (draft: string) => {
      const qid = state?.question?.id
      if (!qid) return
      try {
        await sessionsApi.saveDraft(sessionId, { questionId: qid, draft })
      } catch {
        /* draft saves are best-effort */
      }
    },
    [sessionId, state?.question?.id],
  )

  return {
    state,
    loading,
    error,
    busy,
    remaining, // fractional, for the ring
    secondsLeft: Math.ceil(remaining),
    setTrack,
    systemCheck,
    uploadResume,
    begin,
    skipPrep,
    submit,
    saveDraft,
    completeNow,
    refresh,
  }
}

export type InterviewClock = ReturnType<typeof useInterviewClock>
