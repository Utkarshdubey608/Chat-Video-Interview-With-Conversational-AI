import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { Send, Loader2, CheckCircle2 } from 'lucide-react'
import type { BrandingConfig } from '@shared/types'
import { useChatbotSession } from '../useChatbotSession'
import { CircularCountdown } from '../components/CircularCountdown'

interface Props {
  sessionId: string
  branding: BrandingConfig
  onIntegrity?: (type: string) => void
}

/** Claude-style "Thinking…" indicator — pulsing dots (or a static label under
 *  reduced motion). Its ≥3s minimum lifetime is enforced by the session hook. */
function ThinkingIndicator({ reduce }: { reduce: boolean | null }) {
  return (
    <div className="flex justify-start">
      <div
        className="flex items-center gap-2 rounded-2xl rounded-bl-md border border-border bg-white px-4 py-3 shadow-xs"
        role="status"
        aria-live="polite"
        aria-label="Interviewer is thinking"
      >
        {reduce ? (
          <span className="text-sm font-medium text-neutral-500">Thinking…</span>
        ) : (
          <>
            {[0, 1, 2].map((i) => (
              <motion.span
                key={i}
                className="h-1.5 w-1.5 rounded-full bg-neutral-400"
                animate={{ opacity: [0.3, 1, 0.3] }}
                transition={{ duration: 1, repeat: Infinity, delay: i * 0.18 }}
              />
            ))}
            <span className="text-xs font-medium text-neutral-400">Thinking…</span>
          </>
        )}
      </div>
    </div>
  )
}

export function ChatbotStage({ sessionId, branding, onIntegrity }: Props) {
  const chat = useChatbotSession(sessionId)
  const reduce = useReducedMotion()
  const [text, setText] = useState('')
  // Readiness break: when the candidate isn't ready, offer a short timed pause.
  const [breakStage, setBreakStage] = useState<'none' | 'choosing' | 'counting'>('none')
  const [breakRemaining, setBreakRemaining] = useState(0)
  const scrollRef = useRef<HTMLDivElement>(null)
  const accent = branding.accentColor || '#0d5c3a'
  const s = chat.state
  const visibleTranscript = chat.visibleTranscript
  const turnId = s?.currentTurnId ?? null

  const READY_NO = 'No, I need a moment.'

  // The interviewer is "thinking" whenever a begin/answer turn is in flight or
  // being held behind the minimum think-time floor (including the initial load,
  // so the opening greeting is preceded by the indicator too).
  const interviewerThinking = chat.sending || (chat.loading && !s)

  useLayoutEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: reduce ? 'auto' : 'smooth' })
  }, [visibleTranscript.length, interviewerThinking, chat.pendingAnswer, reduce])

  // Reset composer to the server draft when the current turn changes.
  useEffect(() => { setText(s?.draft ?? ''); setBreakStage('none') }, [turnId]) // eslint-disable-line react-hooks/exhaustive-deps

  // Readiness break countdown → auto-start when it reaches zero.
  useEffect(() => {
    if (breakStage !== 'counting') return
    if (breakRemaining <= 0) { beginAfterBreak(); return }
    const id = setTimeout(() => setBreakRemaining((r) => r - 1), 1000)
    return () => clearTimeout(id)
  }, [breakStage, breakRemaining]) // eslint-disable-line react-hooks/exhaustive-deps

  // Debounced draft auto-save (secondary backstop — the composer submits the live
  // text on expiry below, so this only matters if the tab is backgrounded).
  useEffect(() => {
    if (!turnId) return
    const id = setTimeout(() => chat.saveDraft(text), 800)
    return () => clearTimeout(id)
  }, [text, turnId]) // eslint-disable-line react-hooks/exhaustive-deps

  const inThinkingPhase = s?.phase === 'thinking' // optional timed prep sub-window
  const inProgress = s?.status === 'in_progress'
  // The opening "are you ready?" turn takes a simple Yes/No dropdown, not free text.
  const currentTurn = s?.transcript.find((t) => t.id === turnId)
  const isReadiness = currentTurn?.turnType === 'greeting'
  const canSend = !!turnId && !chat.sending && !inThinkingPhase && inProgress && text.trim().length > 0

  // Keep the live composer text in a ref so the expiry auto-submit captures exactly
  // what's typed (not the debounced draft, which could be stale/empty).
  const textRef = useRef(text)
  useEffect(() => { textRef.current = text }, [text])

  // When the answer timer hits zero, auto-submit whatever the candidate has typed.
  // This preserves the typed content AND advances via the normal reveal flow, which
  // arms the NEXT question's timer. Guarded per-turn so it fires exactly once.
  const autoSubmittedTurn = useRef<string | null>(null)
  useEffect(() => {
    if (s?.phase !== 'answer' || !turnId || !inProgress || chat.sending) return
    if (chat.secondsLeft > 0 || autoSubmittedTurn.current === turnId) return
    autoSubmittedTurn.current = turnId
    const typed = textRef.current
    setText('')
    chat.send(typed)
  }, [chat.secondsLeft, s?.phase, turnId, inProgress, chat.sending]) // eslint-disable-line react-hooks/exhaustive-deps

  const submit = () => {
    if (!canSend) return
    const t = text
    setText('')
    chat.send(t)
  }

  // Readiness Send: "Yes" starts immediately; "No" opens the timed break.
  const submitReadiness = () => {
    if (!canSend) return
    if (text === READY_NO) { setBreakStage('choosing'); setText('') }
    else { const t = text; setText(''); chat.send(t) }
  }
  const startBreak = (seconds: number) => { setBreakRemaining(seconds); setBreakStage('counting') }
  const beginAfterBreak = () => {
    if (breakStage === 'none') return
    setBreakStage('none')
    setBreakRemaining(0)
    chat.send('Okay, I’m ready now, thank you.')
  }
  const mmss = (s: number) => `${Math.floor(s / 60)}:${String(Math.max(0, s) % 60).padStart(2, '0')}`

  if (s?.finished) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-4">
        <motion.div
          initial={reduce ? false : { opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          className="max-w-md rounded-2xl border border-border bg-white p-10 text-center shadow-sm"
        >
          <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl" style={{ background: `${accent}14` }}>
            <CheckCircle2 size={28} style={{ color: accent }} />
          </div>
          <h1 className="text-2xl font-bold text-neutral-900">All done, thank you!</h1>
          <p className="mt-2 text-sm leading-relaxed text-neutral-500">
            Your responses were submitted to {branding.companyName}. You can close this window; the hiring team will be in touch.
          </p>
        </motion.div>
      </div>
    )
  }

  return (
    <div className="flex min-h-screen flex-col bg-background">
      {/* header */}
      <div className="sticky top-0 z-10 border-b border-border bg-white/80 backdrop-blur">
        <div className="mx-auto flex max-w-3xl items-center justify-between px-4 py-3">
          <div className="flex items-center gap-2 min-w-0">
            {branding.logoUrl
              ? <img src={branding.logoUrl} alt={branding.companyName} className="h-7 w-auto" />
              : <span className="truncate font-bold" style={{ color: accent }}>{branding.companyName}</span>}
          </div>
          <div className="flex items-center gap-3">
            {/* Countdown ring — shown ONLY while a timed question turn is armed
                (never during greeting/readiness/thinking-indicator/wrap-up). */}
            {s?.phase && (
              <CircularCountdown
                remaining={chat.remaining}
                total={s.totalPhaseSeconds}
                phase={s.phase === 'thinking' ? 'prep' : 'answer'}
                warningThreshold={s.timing.warningThresholdSeconds}
                accentColor={accent}
                size={60}
              />
            )}
          </div>
        </div>
      </div>

      {/* transcript */}
      <div ref={scrollRef} className="mx-auto w-full max-w-3xl flex-1 space-y-4 overflow-y-auto px-4 py-6">
        {visibleTranscript.map((t) => (
          <motion.div
            key={t.id}
            initial={reduce ? false : { opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            className={t.role === 'candidate' ? 'flex justify-end' : 'flex justify-start'}
          >
            <div
              className={
                t.role === 'candidate'
                  ? 'max-w-[80%] rounded-2xl rounded-br-md px-4 py-2.5 text-sm text-white'
                  : 'max-w-[80%] rounded-2xl rounded-bl-md border border-border bg-white px-4 py-2.5 text-sm text-neutral-800 shadow-xs'
              }
              style={t.role === 'candidate' ? { background: accent } : undefined}
            >
              <p className="whitespace-pre-wrap leading-relaxed">{t.content}</p>
            </div>
          </motion.div>
        ))}

        {/* Optimistic candidate bubble — keeps their answer on screen while the
            interviewer "thinks" (the real turn replaces it on reveal). */}
        {chat.pendingAnswer && chat.pendingAnswer.trim() !== '' && (
          <div className="flex justify-end">
            <div className="max-w-[80%] rounded-2xl rounded-br-md px-4 py-2.5 text-sm text-white opacity-90" style={{ background: accent }}>
              <p className="whitespace-pre-wrap leading-relaxed">{chat.pendingAnswer}</p>
            </div>
          </div>
        )}

        {interviewerThinking && <ThinkingIndicator reduce={reduce} />}
      </div>

      {/* composer */}
      <div className="sticky bottom-0 border-t border-border bg-white">
        <div className="mx-auto w-full max-w-3xl px-4 py-3">
          {inThinkingPhase && s && (
            <div className="mb-2 flex items-center justify-between rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-700">
              <span>Preparation time — read the question and structure your answer (Situation, Task, Action, Result).</span>
              {s.timing.allowSkipThinking && (
                <button onClick={() => chat.skipThinking()} className="ml-3 flex-shrink-0 font-semibold underline hover:no-underline">
                  Start answering now
                </button>
              )}
            </div>
          )}
          {isReadiness && breakStage === 'choosing' ? (
            /* Candidate isn't ready — offer a short break with auto-start. */
            <div className="rounded-2xl border border-border bg-white p-4 text-center">
              <p className="text-sm font-medium text-neutral-700">No problem — take your time. I’ll begin automatically in:</p>
              <div className="mt-3 flex flex-wrap items-center justify-center gap-2">
                {[30, 45, 60].map((sec) => (
                  <button
                    key={sec}
                    onClick={() => startBreak(sec)}
                    className="rounded-xl border-2 px-4 py-2 text-sm font-semibold transition-all hover:bg-neutral-50"
                    style={{ borderColor: accent, color: accent }}
                  >
                    {sec === 60 ? '1 minute' : `${sec} seconds`}
                  </button>
                ))}
              </div>
              <button onClick={beginAfterBreak} className="mt-3 text-xs font-medium text-neutral-500 underline hover:no-underline">
                Actually, I’m ready now
              </button>
            </div>
          ) : isReadiness && breakStage === 'counting' ? (
            /* Break countdown — auto-starts at zero; can start early. */
            <div className="flex items-center justify-between gap-3 rounded-2xl border border-border bg-white p-3">
              <span className="flex items-center gap-2 text-sm text-neutral-600" aria-live="polite">
                <span className="tabular-nums text-2xl font-bold" style={{ color: accent }}>{mmss(breakRemaining)}</span>
                until we begin…
              </span>
              <button
                onClick={beginAfterBreak}
                disabled={chat.sending}
                className="flex h-10 items-center gap-1.5 rounded-xl px-4 text-sm font-semibold text-white transition-all disabled:opacity-40"
                style={{ background: accent }}
              >
                {chat.sending ? <Loader2 size={16} className="animate-spin" /> : <Send size={16} />} Start now
              </button>
            </div>
          ) : isReadiness ? (
            /* Opening "are you ready?" turn: a simple Yes/No dropdown, not free text. */
            <div className="flex items-center gap-2 rounded-2xl border border-border bg-white p-1.5">
              <select
                value={text}
                onChange={(e) => setText(e.target.value)}
                disabled={chat.sending || !inProgress}
                className="flex-1 rounded-xl bg-transparent px-2 py-2 text-sm text-neutral-800 outline-none disabled:opacity-60"
                aria-label="Are you ready to begin?"
                autoFocus
              >
                <option value="">Select an option…</option>
                <option value="Yes, I'm ready to begin.">Yes, I'm ready</option>
                <option value="No, I need a moment.">No, not yet</option>
              </select>
              <button
                onClick={submitReadiness}
                disabled={!canSend}
                className="flex h-10 items-center gap-1.5 rounded-xl px-4 text-sm font-semibold text-white transition-all disabled:cursor-not-allowed disabled:opacity-40"
                style={{ background: accent }}
                aria-label="Send"
              >
                {chat.sending ? <Loader2 size={16} className="animate-spin" /> : <Send size={16} />} Send
              </button>
            </div>
          ) : (
            <div className="flex items-end gap-2 rounded-2xl border border-border bg-white p-1.5 focus-within:border-neutral-300">
              <textarea
                value={text}
                onChange={(e) => setText(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit() } }}
                onPaste={(e) => { if (s?.integrity.disablePasteInAnswers) { e.preventDefault(); onIntegrity?.('paste_blocked') } }}
                onCopy={(e) => { if (s?.integrity.disableCopy) { e.preventDefault(); onIntegrity?.('copy_blocked') } }}
                disabled={inThinkingPhase || chat.sending || !inProgress}
                placeholder={
                  interviewerThinking
                    ? 'Your interviewer is thinking…'
                    : inThinkingPhase
                      ? 'Answering unlocks when preparation ends…'
                      : 'Type your answer…  (Enter to send · Shift+Enter for a new line)'
                }
                rows={2}
                className="max-h-40 flex-1 resize-none bg-transparent px-2 py-1.5 text-sm text-neutral-800 outline-none placeholder:text-neutral-400 disabled:opacity-60"
                aria-label="Your answer"
                autoFocus
              />
              <button
                onClick={submit}
                disabled={!canSend}
                className="mb-0.5 flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-xl text-white transition-all disabled:cursor-not-allowed disabled:opacity-40"
                style={{ background: accent }}
                aria-label="Send answer"
              >
                {chat.sending ? <Loader2 size={18} className="animate-spin" /> : <Send size={18} />}
              </button>
            </div>
          )}
          {chat.error && <p className="mt-1.5 text-xs text-danger">{chat.error}</p>}
        </div>
      </div>
    </div>
  )
}
