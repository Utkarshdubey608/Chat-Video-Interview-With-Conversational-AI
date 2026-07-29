import { useState } from 'react'
import { motion, useReducedMotion, AnimatePresence } from 'framer-motion'
import { Mic, MicOff, PhoneOff, Loader2, AlertTriangle, CheckCircle2, Captions, Radio } from 'lucide-react'
import type { BrandingConfig, VoicePhase } from '@shared/types'
import { useVoiceSession } from '../useVoiceSession'

interface Props {
  sessionId: string
  branding: BrandingConfig
  personaName?: string
}

const PHASE_LABEL: Record<VoicePhase, string> = {
  connecting: 'Connecting…',
  greeting: 'Interviewer is speaking',
  speaking: 'Interviewer is speaking',
  listening: 'Listening…',
  thinking: 'One moment…',
  ended: 'Interview complete',
  error: 'Something went wrong',
}

/** Reactive orb: expands/ripples while the agent speaks, gently pulses while listening. */
function Orb({ phase, accent, reduce }: { phase: VoicePhase; accent: string; reduce: boolean | null }) {
  const speaking = phase === 'speaking' || phase === 'greeting'
  const listening = phase === 'listening'
  const color = listening ? '#16a34a' : accent
  return (
    <div className="relative flex h-56 w-56 items-center justify-center">
      {!reduce && (speaking || listening) && [0, 1, 2].map((i) => (
        <motion.span
          key={i}
          className="absolute rounded-full"
          style={{ background: `${color}22`, width: 140, height: 140 }}
          animate={{ scale: [1, 1.9], opacity: [0.45, 0] }}
          transition={{ duration: speaking ? 1.8 : 2.4, repeat: Infinity, delay: i * (speaking ? 0.6 : 0.8), ease: 'easeOut' }}
        />
      ))}
      <motion.div
        className="relative flex h-32 w-32 items-center justify-center rounded-full shadow-lg"
        style={{ background: `linear-gradient(135deg, ${color}, ${color}cc)` }}
        animate={reduce ? undefined : speaking ? { scale: [1, 1.06, 1] } : listening ? { scale: [1, 1.03, 1] } : { scale: 1 }}
        transition={{ duration: speaking ? 0.9 : 1.6, repeat: Infinity }}
      >
        <Radio size={38} className="text-white/90" />
      </motion.div>
    </div>
  )
}

export function VoiceStage({ sessionId, branding, personaName = 'AI Interviewer' }: Props) {
  const reduce = useReducedMotion()
  const v = useVoiceSession(sessionId)
  const accent = branding.accentColor || '#0d5c3a'
  const [showCaptions, setShowCaptions] = useState(false)
  const [gestured, setGestured] = useState(false)

  // Start gate — getUserMedia needs a user gesture, and it sets a calm tone.
  if (!gestured) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-4">
        <motion.div initial={reduce ? false : { opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }}
          className="max-w-md rounded-2xl border border-border bg-white p-10 text-center shadow-sm">
          <div className="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-2xl" style={{ background: `${accent}14` }}>
            <Mic size={30} style={{ color: accent }} />
          </div>
          <h1 className="text-2xl font-bold text-neutral-900">Voice interview with {branding.companyName}</h1>
          <p className="mt-2 text-sm leading-relaxed text-neutral-500">
            You’ll have a spoken conversation with {personaName}. Find a quiet spot — when you’re ready, we’ll ask for your microphone and begin.
          </p>
          <button
            onClick={() => { setGestured(true); void v.start() }}
            className="mt-6 inline-flex h-12 items-center gap-2 rounded-lg px-8 text-base font-semibold text-white transition-all"
            style={{ background: accent }}
          >
            <Mic size={18} /> Start voice interview
          </button>
        </motion.div>
      </div>
    )
  }

  if (v.phase === 'ended') {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-4">
        <motion.div initial={reduce ? false : { opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }}
          className="max-w-md rounded-2xl border border-border bg-white p-10 text-center shadow-sm">
          {v.endedGraceful ? (
            <>
              <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl" style={{ background: `${accent}14` }}>
                <CheckCircle2 size={28} style={{ color: accent }} />
              </div>
              <h1 className="text-2xl font-bold text-neutral-900">All done, thank you!</h1>
              <p className="mt-2 text-sm leading-relaxed text-neutral-500">
                Your voice interview with {branding.companyName} is complete. You can close this window; the hiring team will be in touch about next steps.
              </p>
            </>
          ) : (
            <>
              <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-amber-50 text-amber-600">
                <AlertTriangle size={26} />
              </div>
              <h1 className="text-2xl font-bold text-neutral-900">Interview interrupted</h1>
              <p className="mt-2 text-sm leading-relaxed text-neutral-500">
                The connection dropped before the interview finished, so it ended early. Please reach out to the {branding.companyName} hiring team and we’ll help you complete it.
              </p>
            </>
          )}
        </motion.div>
      </div>
    )
  }

  if (v.phase === 'error') {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-4">
        <div className="max-w-md rounded-2xl border border-border bg-white p-10 text-center shadow-sm">
          <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-danger-bg text-danger">
            <AlertTriangle size={24} />
          </div>
          <h1 className="text-xl font-bold text-neutral-900">{v.permissionDenied ? 'Microphone blocked' : 'Connection problem'}</h1>
          <p className="mt-2 text-sm text-neutral-500">{v.error}</p>
          {v.permissionDenied && (
            <p className="mt-2 text-xs text-neutral-400">Allow microphone access in your browser’s address bar, then reload this page.</p>
          )}
        </div>
      </div>
    )
  }

  const connecting = v.phase === 'connecting'
  const statusLabel = v.reconnecting ? 'Reconnecting…' : PHASE_LABEL[v.phase]

  return (
    <div className="flex min-h-screen flex-col bg-background">
      {/* header */}
      <div className="border-b border-border bg-white/80 backdrop-blur">
        <div className="mx-auto flex max-w-3xl items-center justify-between px-4 py-3">
          <span className="truncate font-bold" style={{ color: accent }}>{branding.companyName}</span>
          <span className="flex items-center gap-1.5 text-xs font-medium text-neutral-500" aria-live="polite">
            <span className={`h-2 w-2 rounded-full ${connecting ? 'bg-amber-400 animate-pulse' : 'bg-[#16a34a]'}`} />
            {v.reconnecting ? 'Reconnecting' : connecting ? 'Connecting' : 'Live'}
          </span>
        </div>
      </div>

      {/* stage */}
      <div className="flex flex-1 flex-col items-center justify-center px-4">
        <Orb phase={v.phase} accent={accent} reduce={reduce} />
        <p className="mt-2 text-lg font-semibold text-neutral-800">{personaName}</p>
        <p className="mt-1 flex items-center gap-2 text-sm text-neutral-500" aria-live="polite">
          {connecting && <Loader2 size={14} className="animate-spin" />}
          {statusLabel}
        </p>
        {v.reconnecting && (
          <p className="mt-1 text-xs text-neutral-400">Connection hiccup — your interview is saved and will resume in a moment.</p>
        )}

        {/* captions */}
        {showCaptions && (
          <div className="mt-6 max-h-48 w-full max-w-xl overflow-y-auto rounded-xl border border-border bg-white p-4 text-sm">
            {v.captions.length === 0 ? (
              <p className="text-center text-neutral-400">Captions will appear here as you talk.</p>
            ) : (
              <div className="space-y-2">
                <AnimatePresence initial={false}>
                  {v.captions.slice(-12).map((c, i) => (
                    <motion.p key={i} initial={reduce ? false : { opacity: 0 }} animate={{ opacity: 1 }}
                      className={c.role === 'candidate' ? 'text-right text-neutral-800' : 'text-left text-neutral-600'}>
                      <span className="text-[10px] font-bold uppercase tracking-wider text-neutral-400">
                        {c.role === 'candidate' ? 'You' : personaName}
                      </span>
                      <br />
                      {c.text}
                    </motion.p>
                  ))}
                </AnimatePresence>
              </div>
            )}
          </div>
        )}
      </div>

      {/* controls */}
      <div className="border-t border-border bg-white">
        <div className="mx-auto flex max-w-3xl items-center justify-center gap-4 px-4 py-5">
          <button
            onClick={v.toggleMute}
            disabled={connecting}
            aria-pressed={v.muted}
            className="flex h-14 w-14 items-center justify-center rounded-full border-2 border-border bg-white text-neutral-700 transition-all hover:bg-neutral-50 disabled:opacity-40"
            aria-label={v.muted ? 'Unmute microphone' : 'Mute microphone'}
          >
            {v.muted ? <MicOff size={22} className="text-danger" /> : <Mic size={22} />}
          </button>
          <button
            onClick={v.end}
            className="flex h-16 w-16 items-center justify-center rounded-full bg-danger text-white shadow-md transition-transform hover:scale-105"
            aria-label="End interview"
          >
            <PhoneOff size={24} />
          </button>
          <button
            onClick={() => setShowCaptions((s) => !s)}
            aria-pressed={showCaptions}
            className={`flex h-14 w-14 items-center justify-center rounded-full border-2 transition-all ${showCaptions ? 'text-white' : 'border-border bg-white text-neutral-700 hover:bg-neutral-50'}`}
            style={showCaptions ? { background: accent, borderColor: accent } : undefined}
            aria-label="Toggle captions"
          >
            <Captions size={22} />
          </button>
        </div>
      </div>
    </div>
  )
}
