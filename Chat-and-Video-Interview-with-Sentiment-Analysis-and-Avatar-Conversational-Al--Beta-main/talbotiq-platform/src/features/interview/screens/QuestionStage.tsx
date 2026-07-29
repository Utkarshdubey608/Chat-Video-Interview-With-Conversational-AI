import { useEffect, useRef, useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import { AlertTriangle, Lightbulb, Send, FastForward } from 'lucide-react'
import { cn } from '@/components/ui'
import { CircularCountdown } from '../components/CircularCountdown'
import { CameraRecorder } from '../components/CameraRecorder'
import type { CandidateSessionState } from '@shared/types'

interface Props {
  state: CandidateSessionState
  remaining: number
  secondsLeft: number
  busy: boolean
  onSkipPrep: () => void
  onSubmit: (answer: string) => void
  onSaveDraft: (draft: string) => void
  onIntegrity?: (type: string) => void
}

export function QuestionStage({
  state, remaining, secondsLeft, busy, onSkipPrep, onSubmit, onSaveDraft, onIntegrity,
}: Props) {
  const reduce = useReducedMotion()
  const { phase, timing, integrity, question, track } = state
  const isAnswer = phase === 'answer'
  const warning = isAnswer && secondsLeft <= timing.warningThresholdSeconds

  const [text, setText] = useState(state.draft ?? '')
  const textRef = useRef(text)
  textRef.current = text
  const taRef = useRef<HTMLTextAreaElement>(null)

  // Auto-focus the answer box the moment the answer phase opens.
  useEffect(() => {
    if (isAnswer && track === 'chat') taRef.current?.focus()
  }, [isAnswer, track])

  // Debounced draft auto-save + flush on unmount (so a refresh / auto-submit keeps text).
  useEffect(() => {
    const id = setTimeout(() => onSaveDraft(textRef.current), 900)
    return () => clearTimeout(id)
  }, [text, onSaveDraft])
  useEffect(() => () => { onSaveDraft(textRef.current) }, [onSaveDraft])

  if (!question) return null

  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, x: 24 }}
      animate={{ opacity: 1, x: 0 }}
      exit={reduce ? undefined : { opacity: 0, x: -24 }}
      transition={{ duration: 0.25 }}
      className="space-y-6"
    >
      {/* Question + countdown */}
      <div className="flex items-start justify-between gap-6">
        <div className="min-w-0">
          <span
            className={cn(
              'text-xs font-bold uppercase tracking-widest',
              isAnswer ? 'text-success' : 'text-neutral-400',
            )}
          >
            {isAnswer ? 'Answering' : 'Preparation'}
          </span>
          <h2 className="mt-2 text-2xl font-bold leading-snug tracking-tight text-neutral-900">
            {question.text}
          </h2>
        </div>
        <div className="flex-shrink-0">
          <CircularCountdown
            remaining={remaining}
            total={state.totalPhaseSeconds}
            phase={phase ?? 'prep'}
            warningThreshold={timing.warningThresholdSeconds}
            accentColor={state.branding.accentColor}
          />
        </div>
      </div>

      {/* Preparation tip */}
      {!isAnswer && (
        <div className="flex items-start gap-2 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
          <Lightbulb size={16} className="mt-0.5 flex-shrink-0" />
          <span>Tip: structure your answer with <strong>STAR</strong> — Situation, Task, Action, Result.</span>
        </div>
      )}

      {/* Answer surface */}
      {track === 'video_avatar' ? (
        <CameraRecorder active={isAnswer} accentColor={state.branding.accentColor} />
      ) : (
        <div>
          <textarea
            ref={taRef}
            value={text}
            disabled={!isAnswer || busy}
            onChange={(e) => setText(e.target.value)}
            onPaste={(e) => { if (integrity.disablePasteInAnswers) { e.preventDefault(); onIntegrity?.('paste_blocked') } }}
            onCopy={(e) => { if (integrity.disableCopy) { e.preventDefault(); onIntegrity?.('copy_blocked') } }}
            placeholder={isAnswer ? 'Type your answer here…' : 'Your answer box unlocks when the answer timer begins.'}
            aria-label="Your answer"
            className={cn(
              'h-56 w-full resize-none rounded-xl border-2 bg-white p-4 text-[15px] leading-relaxed text-neutral-800 transition-all focus:outline-none',
              isAnswer ? 'border-border focus:border-primary-400' : 'cursor-not-allowed border-dashed border-neutral-200 bg-neutral-50 text-neutral-400',
            )}
          />
          {isAnswer && (
            <p className="mt-1.5 text-right text-xs text-neutral-400 tabular-nums">
              {text.trim().split(/\s+/).filter(Boolean).length} words
            </p>
          )}
        </div>
      )}

      {/* Warning */}
      {warning && (
        <motion.div
          initial={reduce ? false : { opacity: 0 }}
          animate={{ opacity: 1 }}
          className="flex items-center gap-2 rounded-lg border border-danger-border bg-danger-bg px-3 py-2 text-sm font-medium text-danger"
        >
          <AlertTriangle size={15} /> {secondsLeft}s left — your answer will auto-submit at zero.
        </motion.div>
      )}

      {/* Controls */}
      <div className="flex items-center justify-between gap-3">
        <p className="text-xs text-neutral-400">
          {isAnswer ? 'You can’t return to this question once you continue.' : 'Read the question and gather your thoughts.'}
        </p>
        <div className="flex gap-2">
          {!isAnswer && timing.allowSkipPrep && (
            <button
              onClick={onSkipPrep}
              disabled={busy}
              className="inline-flex h-10 items-center gap-2 rounded-lg border-2 px-4 text-sm font-semibold transition-all disabled:opacity-50"
              style={{ borderColor: state.branding.accentColor, color: state.branding.accentColor }}
            >
              <FastForward size={16} /> Start answering now
            </button>
          )}
          {isAnswer && timing.allowEarlySubmit && (
            <button
              onClick={() => onSubmit(text)}
              disabled={busy}
              className="inline-flex h-10 items-center gap-2 rounded-lg px-5 text-sm font-semibold text-white transition-all disabled:opacity-50"
              style={{ background: state.branding.accentColor }}
            >
              <Send size={16} /> Submit &amp; continue
            </button>
          )}
        </div>
      </div>
    </motion.div>
  )
}
