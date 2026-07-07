import { useState } from 'react'
import { useParams } from 'react-router-dom'
import { AnimatePresence } from 'framer-motion'
import { Loader2, AlertTriangle } from 'lucide-react'
import { useInterviewClock } from './useInterviewClock'
import { useIntegrityMonitor } from './useIntegrityMonitor'
import { InterviewShell } from './components/InterviewShell'
import { TrackSelect } from './screens/TrackSelect'
import { Welcome } from './screens/Welcome'
import { SystemCheck } from './screens/SystemCheck'
import { ResumeUpload } from './screens/ResumeUpload'
import { QuestionStage } from './screens/QuestionStage'
import { ChatbotStage } from './screens/ChatbotStage'
import { AvatarStage } from './screens/AvatarStage'
import { Completion } from './screens/Completion'
import type { BrandingConfig } from '@shared/types'

const FALLBACK_BRANDING: BrandingConfig = { companyName: 'TalbotIQ', accentColor: '#0d5c3a' }

type PreStep = 'track' | 'welcome' | 'resume' | 'systemcheck'

export default function TakeInterviewPage() {
  const { sessionId = '' } = useParams()
  const clock = useInterviewClock(sessionId)
  const [preStep, setPreStep] = useState<PreStep>('track')
  const [chatbotStarted, setChatbotStarted] = useState(false)
  // Hooks must run unconditionally (before the early returns below).
  const integrity = useIntegrityMonitor(sessionId, clock.state?.integrity, clock.state?.status === 'in_progress')

  // Initial load
  if (clock.loading && !clock.state) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <Loader2 className="animate-spin text-primary-700" size={28} />
      </div>
    )
  }

  // Hard error (e.g. bad link)
  if (clock.error && !clock.state) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-5">
        <div className="max-w-sm rounded-2xl border border-border bg-white p-8 text-center shadow-sm">
          <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-danger-bg text-danger">
            <AlertTriangle size={22} />
          </span>
          <h1 className="mt-4 text-xl font-bold text-neutral-900">Interview not found</h1>
          <p className="mt-2 text-sm text-neutral-500">{clock.error}. Please double-check your invite link.</p>
        </div>
      </div>
    )
  }

  const s = clock.state!
  const branding = s.branding ?? FALLBACK_BRANDING

  if (s.status === 'completed' || s.status === 'expired') {
    return (
      <InterviewShell branding={branding}>
        <Completion branding={branding} />
      </InterviewShell>
    )
  }

  // Conversational tracks run their own full-screen experience (engine-driven).
  if (s.track === 'chatbot' && (chatbotStarted || s.status === 'in_progress')) {
    return <ChatbotStage sessionId={sessionId} branding={branding} onIntegrity={integrity.post} />
  }
  if (s.track === 'video_avatar' && (chatbotStarted || s.status === 'in_progress')) {
    return <AvatarStage sessionId={sessionId} branding={branding} onIntegrity={integrity.post} />
  }

  if (s.status === 'in_progress') {
    return (
      <InterviewShell branding={branding} progress={s.progress} live>
        <AnimatePresence mode="wait">
          <QuestionStage
            key={s.question?.id ?? 'q'}
            state={s}
            remaining={clock.remaining}
            secondsLeft={clock.secondsLeft}
            busy={clock.busy}
            onSkipPrep={clock.skipPrep}
            onSubmit={clock.submit}
            onSaveDraft={clock.saveDraft}
            onIntegrity={integrity.post}
          />
        </AnimatePresence>
      </InterviewShell>
    )
  }

  // status: created | system_check → pre-interview screens.
  // The chatbot track's format is fixed by the template, so skip "choose format".
  const conversational = s.track === 'chatbot' || s.track === 'video_avatar'
  const step: PreStep = conversational && preStep === 'track' ? 'welcome' : preStep
  return (
    <InterviewShell branding={branding}>
      <AnimatePresence mode="wait">
        {step === 'track' && (
          <TrackSelect
            key="track"
            branding={branding}
            defaultTrack={s.track}
            busy={clock.busy}
            onChoose={async (t) => {
              await clock.setTrack(t)
              setPreStep('welcome')
            }}
          />
        )}
        {step === 'welcome' && (
          <Welcome
            key="welcome"
            branding={branding}
            timing={s.timing}
            onContinue={() => {
              if (s.awaitingResume) { setPreStep('resume') }
              else { clock.systemCheck(); setPreStep('systemcheck') }
            }}
          />
        )}
        {step === 'resume' && (
          <ResumeUpload
            key="resume"
            branding={branding}
            busy={clock.busy}
            onUpload={async (file) => { await clock.uploadResume(file); clock.systemCheck(); setPreStep('systemcheck') }}
          />
        )}
        {step === 'systemcheck' && (
          <SystemCheck
            key="check"
            branding={branding}
            track={s.track}
            busy={clock.busy}
            onBegin={() => {
              integrity.enterFullscreen()
              if (conversational) setChatbotStarted(true)
              else clock.begin()
            }}
          />
        )}
      </AnimatePresence>
    </InterviewShell>
  )
}
