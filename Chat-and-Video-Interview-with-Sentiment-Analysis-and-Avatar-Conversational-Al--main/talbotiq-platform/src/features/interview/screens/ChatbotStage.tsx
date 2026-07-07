import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { Send, Loader2, Clock, CheckCircle2 } from 'lucide-react'
import type { BrandingConfig } from '@shared/types'
import { useChatbotSession } from '../useChatbotSession'

interface Props {
  sessionId: string
  branding: BrandingConfig
  onIntegrity?: (type: string) => void
}

const fmt = (s: number) => `${Math.floor(s / 60)}:${String(Math.max(0, s) % 60).padStart(2, '0')}`

export function ChatbotStage({ sessionId, branding, onIntegrity }: Props) {
  const chat = useChatbotSession(sessionId)
  const reduce = useReducedMotion()
  const [text, setText] = useState('')
  const scrollRef = useRef<HTMLDivElement>(null)
  const accent = branding.accentColor || '#0d5c3a'
  const s = chat.state
  const turnId = s?.currentTurnId ?? null

  useLayoutEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: reduce ? 'auto' : 'smooth' })
  }, [s?.transcript.length, chat.sending, reduce])

  // Reset composer to the server draft when the current turn changes.
  useEffect(() => { setText(s?.draft ?? '') }, [turnId]) // eslint-disable-line react-hooks/exhaustive-deps

  // Debounced draft auto-save.
  useEffect(() => {
    if (!turnId) return
    const id = setTimeout(() => chat.saveDraft(text), 1200)
    return () => clearTimeout(id)
  }, [text, turnId]) // eslint-disable-line react-hooks/exhaustive-deps

  const timed = s?.timing.mode === 'timed'
  const thinking = timed && s?.phase === 'thinking'
  const inProgress = s?.status === 'in_progress'
  const canSend = !!turnId && !chat.sending && !thinking && inProgress && text.trim().length > 0

  const submit = () => {
    if (!canSend) return
    const t = text
    setText('')
    chat.send(t)
  }

  const warn = timed && s?.phase === 'answer' && chat.secondsLeft <= (s?.timing.warningThresholdSeconds ?? 15)
  const ringColor = warn ? '#dc2626' : s?.phase === 'thinking' ? '#64748b' : accent

  if (chat.loading && !s) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <div className="flex flex-col items-center gap-3 text-neutral-500">
          <Loader2 className="animate-spin" size={26} style={{ color: accent }} />
          <p className="text-sm font-medium">Preparing your interview…</p>
        </div>
      </div>
    )
  }

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
          <h1 className="text-2xl font-bold text-neutral-900">All done — thank you!</h1>
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
          <div className="flex items-center gap-2.5">
            {timed && s?.phase && (
              <span
                className="flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-bold tabular-nums"
                style={{ color: ringColor, background: `${ringColor}14` }}
                aria-live="polite"
              >
                <Clock size={13} /> {s.phase === 'thinking' ? 'Prep' : ''} {fmt(chat.secondsLeft)}
              </span>
            )}
            <span className="rounded-full bg-neutral-100 px-3 py-1 text-xs font-semibold text-neutral-600">
              Question {s?.progress.current} of {s?.progress.total}
            </span>
          </div>
        </div>
      </div>

      {/* transcript */}
      <div ref={scrollRef} className="mx-auto w-full max-w-3xl flex-1 space-y-4 overflow-y-auto px-4 py-6">
        {s?.transcript.map((t) => (
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

        {chat.sending && (
          <div className="flex justify-start">
            <div className="flex items-center gap-1.5 rounded-2xl rounded-bl-md border border-border bg-white px-4 py-3 shadow-xs">
              {[0, 1, 2].map((i) => (
                <motion.span
                  key={i}
                  className="h-1.5 w-1.5 rounded-full bg-neutral-400"
                  animate={reduce ? undefined : { opacity: [0.3, 1, 0.3] }}
                  transition={{ duration: 1, repeat: Infinity, delay: i * 0.18 }}
                />
              ))}
            </div>
          </div>
        )}
      </div>

      {/* composer */}
      <div className="sticky bottom-0 border-t border-border bg-white">
        <div className="mx-auto w-full max-w-3xl px-4 py-3">
          {thinking && s && (
            <div className="mb-2 flex items-center justify-between rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-700">
              <span>Preparation time — read the question and structure your answer (Situation, Task, Action, Result).</span>
              {s.timing.allowSkipThinking && (
                <button onClick={() => chat.skipThinking()} className="ml-3 flex-shrink-0 font-semibold underline hover:no-underline">
                  Start answering now
                </button>
              )}
            </div>
          )}
          <div className="flex items-end gap-2 rounded-2xl border border-border bg-white p-1.5 focus-within:border-neutral-300">
            <textarea
              value={text}
              onChange={(e) => setText(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit() } }}
              onPaste={(e) => { if (s?.integrity.disablePasteInAnswers) { e.preventDefault(); onIntegrity?.('paste_blocked') } }}
              onCopy={(e) => { if (s?.integrity.disableCopy) { e.preventDefault(); onIntegrity?.('copy_blocked') } }}
              disabled={thinking || chat.sending || !inProgress}
              placeholder={thinking ? 'Answering unlocks when preparation ends…' : 'Type your answer…  (Enter to send · Shift+Enter for a new line)'}
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
          {chat.error && <p className="mt-1.5 text-xs text-danger">{chat.error}</p>}
        </div>
      </div>
    </div>
  )
}
