import { useEffect, useRef, useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { Send, Loader2, Video, AlertTriangle, CheckCircle2, Mic } from 'lucide-react'
import type { BrandingConfig } from '@shared/types'
import { useChatbotSession } from '../useChatbotSession'
import { useTavusConversation } from '../useTavusConversation'

interface Props {
  sessionId: string
  branding: BrandingConfig
  onIntegrity?: (type: string) => void
}

/**
 * Video-avatar interview. The conversation engine (same as chatbot) decides each
 * question; the Tavus avatar SPEAKS it (echo mode); the candidate answers aloud
 * (transcribed) and/or edits the text before submitting — the text box is a
 * robust fallback so the flow works even if live captions are flaky.
 */
export function AvatarStage({ sessionId, branding, onIntegrity }: Props) {
  const chat = useChatbotSession(sessionId)
  const reduce = useReducedMotion()
  const s = chat.state
  const accent = branding.accentColor || '#0d5c3a'

  const [containerEl, setContainerEl] = useState<HTMLDivElement | null>(null)
  const [answer, setAnswer] = useState('')
  const spokenRef = useRef<string | null>(null)

  const currentQ = s?.transcript.find((t) => t.id === s.currentTurnId)?.content ?? ''

  const avatar = useTavusConversation({
    enabled: !!s && s.status === 'in_progress',
    container: containerEl,
    conversationalContext:
      'You are a professional interviewer. Speak only the questions provided to you; do not add your own.',
    onTranscript: (text) => setAnswer((prev) => (prev ? prev + ' ' : '') + text),
  })

  // Speak each new question exactly once, once the avatar is live.
  useEffect(() => {
    if (avatar.status === 'live' && s?.currentTurnId && currentQ && spokenRef.current !== s.currentTurnId) {
      spokenRef.current = s.currentTurnId
      setAnswer('')
      avatar.speak(currentQ)
    }
  }, [avatar.status, s?.currentTurnId, currentQ, avatar])

  // End the Tavus call when the interview finishes.
  useEffect(() => {
    if (s?.finished) avatar.end()
  }, [s?.finished, avatar])

  const submit = () => {
    if (!answer.trim() || chat.sending || s?.status !== 'in_progress') return
    const a = answer
    setAnswer('')
    chat.send(a)
  }

  if (chat.loading && !s) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <Loader2 className="animate-spin" size={26} style={{ color: accent }} />
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
            Your interview with {branding.companyName} is complete. You can close this window.
          </p>
        </motion.div>
      </div>
    )
  }

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <div className="sticky top-0 z-10 border-b border-border bg-white/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
          <span className="truncate font-bold" style={{ color: accent }}>{branding.companyName}</span>
          <span className="rounded-full bg-neutral-100 px-3 py-1 text-xs font-semibold text-neutral-600">
            Question {s?.progress.current} of {s?.progress.total}
          </span>
        </div>
      </div>

      <div className="mx-auto grid w-full max-w-6xl flex-1 gap-4 p-4 lg:grid-cols-[1.3fr_1fr]">
        {/* avatar */}
        <div className="relative overflow-hidden rounded-2xl border border-border bg-neutral-900" style={{ minHeight: 360 }}>
          <div ref={setContainerEl} className="absolute inset-0" />
          {avatar.status !== 'live' && (
            <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 text-center text-neutral-300">
              {avatar.status === 'error' ? (
                <>
                  <AlertTriangle size={26} className="text-amber-400" />
                  <p className="max-w-xs px-4 text-sm">{avatar.error}</p>
                  <p className="text-xs text-neutral-500">You can still answer using the box on the right.</p>
                </>
              ) : (
                <>
                  <Loader2 size={26} className="animate-spin" />
                  <p className="text-sm">Connecting your interviewer…</p>
                </>
              )}
            </div>
          )}
          <span className="absolute left-3 top-3 flex items-center gap-1.5 rounded-full bg-black/50 px-2.5 py-1 text-xs font-medium text-white">
            <Video size={12} /> AI Interviewer
          </span>
        </div>

        {/* question + answer */}
        <div className="flex flex-col gap-3">
          <div className="rounded-2xl border border-border bg-white p-4">
            <p className="text-xs font-semibold uppercase tracking-wide text-neutral-400">Current question</p>
            <p className="mt-1 text-sm leading-relaxed text-neutral-800">{currentQ || '…'}</p>
          </div>

          <div className="flex flex-1 flex-col rounded-2xl border border-border bg-white p-4">
            <p className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-neutral-400">
              <Mic size={13} /> Your answer <span className="font-normal normal-case text-neutral-400">— speak, or type/edit here</span>
            </p>
            <textarea
              value={answer}
              onChange={(e) => setAnswer(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); submit() } }}
              onPaste={(e) => { if (s?.integrity.disablePasteInAnswers) { e.preventDefault(); onIntegrity?.('paste_blocked') } }}
              onCopy={(e) => { if (s?.integrity.disableCopy) { e.preventDefault(); onIntegrity?.('copy_blocked') } }}
              placeholder="Your spoken words appear here — review or edit, then submit."
              className="mt-2 flex-1 resize-none rounded-xl border border-border p-3 text-sm text-neutral-800 outline-none focus:border-neutral-300"
              style={{ minHeight: 160 }}
              aria-label="Your answer"
            />
            <div className="mt-3 flex items-center justify-between">
              <span className="text-xs text-neutral-400">⌘/Ctrl + Enter to submit</span>
              <button
                onClick={submit}
                disabled={!answer.trim() || chat.sending || s?.status !== 'in_progress'}
                className="inline-flex h-10 items-center gap-2 rounded-lg px-5 text-sm font-semibold text-white transition-all disabled:cursor-not-allowed disabled:opacity-40"
                style={{ background: accent }}
              >
                {chat.sending ? <Loader2 size={16} className="animate-spin" /> : <Send size={16} />}
                Submit answer
              </button>
            </div>
            {chat.error && <p className="mt-1.5 text-xs text-danger">{chat.error}</p>}
          </div>
        </div>
      </div>
    </div>
  )
}
