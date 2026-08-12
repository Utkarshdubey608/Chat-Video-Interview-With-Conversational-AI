import { useEffect, useRef, useState } from 'react'
import { motion, useReducedMotion, AnimatePresence } from 'framer-motion'
import { AlertTriangle, Circle, Send, FastForward, Loader2, Camera } from 'lucide-react'
import { CircularCountdown } from '../components/CircularCountdown'
import { useAnswerRecorder } from '../useAnswerRecorder'
import { sessionsApi } from '@/lib/api'
import type { CandidateSessionState } from '@shared/types'

interface Props {
  sessionId: string
  state: CandidateSessionState
  remaining: number
  secondsLeft: number
  busy: boolean
  rec: ReturnType<typeof useAnswerRecorder>
  onSkipPrep: () => void
  onSubmitText: (answerText: string) => Promise<boolean>
  onIntegrity?: (type: string) => void
}

/**
 * Video Interview answer screen. Runs on the shared timed engine: 30s prep
 * (camera preview live) → answer phase auto-starts live transcription off the
 * shared stream's audio track (Deepgram relay) → the candidate submits (or a
 * small client buffer before the server deadline auto-submits), which stops
 * transcribing and submits the accumulated transcript as the answer text. No
 * video is recorded/uploaded.
 */
export function VideoStage({ sessionId, state, remaining, secondsLeft, busy, rec, onSkipPrep, onSubmitText, onIntegrity }: Props) {
  const reduce = useReducedMotion()
  const { phase, timing, question, branding } = state
  const videoEl = useRef<HTMLVideoElement>(null)
  const [uploading, setUploading] = useState(false)
  const [submitFailed, setSubmitFailed] = useState(false)
  const submittingRef = useRef(false)
  const facialDoneRef = useRef(false)
  const isAnswer = phase === 'answer'
  const warning = isAnswer && secondsLeft <= timing.warningThresholdSeconds
  const total = state.progress.total

  // Acquire the camera once, attach the live preview.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { void rec.acquire().catch(() => onIntegrity?.('camera_denied')) }, [])            // acquire once
  useEffect(() => { if (rec.ready && videoEl.current) rec.attachPreview(videoEl.current) }, [rec.ready])

  // Start live transcription when the answer phase opens.
  useEffect(() => { if (isAnswer && rec.ready && !rec.recording) rec.startTranscribing() }, [isAnswer, rec.ready, rec.recording])

  // Facial capture (Task 7): start once the camera is ready (startFacial is
  // idempotent, so this is safe across VideoStage remounts per question), and
  // keep it pointed at the current question for per-question bucketing.
  useEffect(() => { if (rec.ready && !facialDoneRef.current) rec.startFacial(sessionId, total) }, [rec, rec.ready, sessionId, total])
  useEffect(() => { rec.setFacialQuestion(Math.max(0, state.progress.current - 1)) }, [rec, state.progress.current])

  const doSubmit = async () => {
    if (submittingRef.current || !question) return
    submittingRef.current = true
    setUploading(true)                         // reuse as a brief "submitting" state
    try {
      const transcript = await rec.stopTranscribing()
      const ok = await onSubmitText(transcript)
      if (!ok) setSubmitFailed(true)
    } catch (err) {
      console.error('[video] submit failed', err)
      setSubmitFailed(true)
    } finally {
      // Last question: stop facial capture and upload the aggregated summary.
      // Its own try/catch, run regardless of whether the video upload/submit
      // above threw — otherwise a failure on the LAST question would lose the
      // facial summary AND leave the Rekognition capture loop running.
      if (state.progress.current >= total) {
        try {
          const summary = rec.stopFacial(total)
          facialDoneRef.current = true
          if (summary) await sessionsApi.facial(sessionId, summary)
        } catch (err) { console.error('[video] facial upload failed', err) }
      }
      setUploading(false)
      submittingRef.current = false
    }
  }

  // Client-side pre-emptive submit ~3s before the server deadline so the transcript
  // is submitted before the engine's own empty auto-submit advances the question.
  useEffect(() => {
    if (isAnswer && secondsLeft <= 3 && !submittingRef.current) void doSubmit()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isAnswer, secondsLeft])

  if (!question) return null

  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, x: 24 }}
      animate={{ opacity: 1, x: 0 }}
      exit={reduce ? undefined : { opacity: 0, x: -24 }}
      transition={{ duration: 0.25 }}
      className="space-y-6"
    >
      <div className="flex items-start justify-between gap-6">
        <div className="min-w-0">
          <span className={`text-xs font-bold uppercase tracking-widest ${isAnswer ? 'text-success' : 'text-neutral-400'}`}>
            {isAnswer ? 'Recording answer' : 'Preparation'}
          </span>
          <h2 className="mt-2 text-2xl font-bold leading-snug tracking-tight text-neutral-900">{question.text}</h2>
        </div>
        <div className="flex-shrink-0">
          <CircularCountdown
            remaining={remaining}
            total={state.totalPhaseSeconds}
            phase={phase ?? 'prep'}
            warningThreshold={timing.warningThresholdSeconds}
            accentColor={branding.accentColor}
          />
        </div>
      </div>

      {/* Camera stage */}
      <div className="relative aspect-video w-full overflow-hidden rounded-xl border border-border bg-neutral-900">
        <video ref={videoEl} autoPlay muted playsInline className="h-full w-full object-cover" />
        {rec.recording ? (
          <span className="absolute left-3 top-3 flex items-center gap-1.5 rounded-full bg-black/60 px-2.5 py-1 text-[11px] font-bold uppercase tracking-wider text-white">
            <Circle size={9} className="animate-pulse fill-red-500 text-red-500" /> Rec
          </span>
        ) : (
          <span className="absolute left-3 top-3 flex items-center gap-1.5 rounded-full bg-black/50 px-2.5 py-1 text-[11px] font-medium text-white/80">
            <Camera size={12} /> {rec.ready ? 'Preview' : 'Starting camera…'}
          </span>
        )}
        {!isAnswer && (
          <div className="absolute inset-0 flex items-center justify-center bg-black/40 text-center text-sm text-white/90">
            <span className="max-w-xs px-4">Read the question and get ready. Answer aloud — the timer starts your response.</span>
          </div>
        )}
        {uploading && (
          <div className="absolute inset-0 flex items-center justify-center gap-2 bg-black/60 text-sm font-medium text-white">
            <Loader2 size={18} className="animate-spin" /> Saving your answer…
          </div>
        )}
      </div>

      {submitFailed && (
        <div className="flex items-center gap-2 rounded-lg border border-danger-border bg-danger-bg px-3 py-2 text-sm font-medium text-danger">
          <AlertTriangle size={15} /> Your answer may not have been submitted. If the interview advanced, that question could be missing its transcript.
        </div>
      )}
      {rec.error && (
        <div className="flex items-center gap-2 rounded-lg border border-danger-border bg-danger-bg px-3 py-2 text-sm font-medium text-danger">
          <AlertTriangle size={15} /> {rec.error}
        </div>
      )}
      {warning && !uploading && (
        <div className="flex items-center gap-2 rounded-lg border border-danger-border bg-danger-bg px-3 py-2 text-sm font-medium text-danger">
          <AlertTriangle size={15} /> {secondsLeft}s left — your answer submits automatically.
        </div>
      )}

      <div className="flex items-center justify-between gap-3">
        <p className="text-xs text-neutral-400">
          {isAnswer ? 'You can’t return to this question once you continue.' : 'Read the question and gather your thoughts.'}
        </p>
        <div className="flex gap-2">
          {!isAnswer && timing.allowSkipPrep && (
            <button onClick={onSkipPrep} disabled={busy || !rec.ready}
              className="inline-flex h-10 items-center gap-2 rounded-lg border-2 px-4 text-sm font-semibold transition-all disabled:opacity-50"
              style={{ borderColor: branding.accentColor, color: branding.accentColor }}>
              <FastForward size={16} /> Start recording now
            </button>
          )}
          {isAnswer && timing.allowEarlySubmit && (
            <button onClick={() => void doSubmit()} disabled={busy || uploading}
              className="inline-flex h-10 items-center gap-2 rounded-lg px-5 text-sm font-semibold text-white transition-all disabled:opacity-50"
              style={{ background: branding.accentColor }}>
              <Send size={16} /> Submit &amp; continue
            </button>
          )}
        </div>
      </div>
    </motion.div>
  )
}

interface VideoInterviewProps {
  sessionId: string
  state: CandidateSessionState
  remaining: number
  secondsLeft: number
  busy: boolean
  onSkipPrep: () => void
  onSubmitText: (answerText: string) => Promise<boolean>
  onIntegrity?: (type: string) => void
}

/** Stable owner of the camera stream for the whole video interview. VideoStage
 *  remounts per question (for the slide transition); the stream persists here. */
export function VideoInterview(props: VideoInterviewProps) {
  const rec = useAnswerRecorder()
  return (
    <AnimatePresence mode="wait">
      <VideoStage key={props.state.question?.id ?? 'q'} rec={rec} {...props} />
    </AnimatePresence>
  )
}
