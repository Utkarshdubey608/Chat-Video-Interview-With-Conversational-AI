import { useCallback, useEffect, useRef, useState } from 'react'
import { chatbotApi, ApiError } from '@/lib/api'
import type { ChatbotSessionState } from '@shared/types'

/**
 * Drives the conversational chatbot interview. Turns advance on submit; in
 * TIMED mode the server is authoritative for thinking/answer windows and we
 * poll + interpolate a local countdown, re-syncing at each boundary.
 */
export function useChatbotSession(sessionId: string) {
  const [state, setState] = useState<ChatbotSessionState | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [sending, setSending] = useState(false) // true while the interviewer is "typing"

  const base = useRef<{ remaining: number; at: number } | null>(null)
  const [remaining, setRemaining] = useState(0)
  const started = useRef(false)

  const apply = useCallback((s: ChatbotSessionState) => {
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

  const load = useCallback(async () => {
    try {
      apply(await chatbotApi.state(sessionId))
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not load the interview')
      setLoading(false)
    }
  }, [sessionId, apply])

  const action = useCallback(
    async (fn: () => Promise<ChatbotSessionState>) => {
      setSending(true)
      try {
        apply(await fn())
      } catch (e) {
        setError(e instanceof ApiError ? e.message : 'Something went wrong')
        load()
      } finally {
        setSending(false)
      }
    },
    [apply, load],
  )

  // Begin the conversation once (idempotent server-side), then load state.
  useEffect(() => {
    if (started.current) return
    started.current = true
    action(() => chatbotApi.begin(sessionId))
  }, [sessionId, action])

  // TIMED mode: periodic drift-correcting poll.
  useEffect(() => {
    if (state?.timing.mode !== 'timed') return
    const id = setInterval(load, 5000)
    return () => clearInterval(id)
  }, [state?.timing.mode, load])

  // TIMED mode: local 200ms countdown; re-sync at the boundary (server advances).
  useEffect(() => {
    if (state?.timing.mode !== 'timed') return
    const id = setInterval(() => {
      const b = base.current
      if (!b) return
      const rem = Math.max(0, b.remaining - (performance.now() - b.at) / 1000)
      setRemaining(rem)
      if (rem <= 0) {
        base.current = null
        load() // server transitions thinking→answer, or auto-submits on answer expiry
      }
    }, 200)
    return () => clearInterval(id)
  }, [state?.timing.mode, load])

  const send = (text: string) => {
    const turnId = state?.currentTurnId
    if (!turnId) return Promise.resolve()
    return action(() => chatbotApi.answer(sessionId, { turnId, answerText: text }))
  }
  const skipThinking = () => action(() => chatbotApi.skipThinking(sessionId))

  const saveDraft = useCallback(
    async (draft: string) => {
      const turnId = state?.currentTurnId
      if (!turnId) return
      try {
        await chatbotApi.saveDraft(sessionId, { turnId, draft })
      } catch {
        /* best-effort */
      }
    },
    [sessionId, state?.currentTurnId],
  )

  return {
    state,
    loading,
    error,
    sending,
    remaining,
    secondsLeft: Math.ceil(remaining),
    send,
    skipThinking,
    saveDraft,
    refresh: load,
  }
}
