import { useState } from 'react'
import { useParams } from 'react-router-dom'
import { AnimatePresence } from 'framer-motion'
import { Loader2, AlertTriangle } from 'lucide-react'
import { useAuth } from '@/features/auth/AuthProvider'
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
import { VoiceStage } from './screens/VoiceStage'
import { TwoWayStage } from './screens/TwoWayStage'
import { VideoInterview } from './screens/VideoStage'
import { Completion } from './screens/Completion'
import type { BrandingConfig } from '@shared/types'

const FALLBACK_BRANDING: BrandingConfig = { companyName: 'TalbotIQ', accentColor: '#0d5c3a' }

type PreStep = 'track' | 'welcome' | 'resume' | 'systemcheck'

export default function TakeInterviewPage() {
  const { sessionId = '' } = useParams()
  const { signOutUser } = useAuth()
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

  // Hard error (bad link, or signed in with a different account than the invite's).
  if (clock.error && !clock.state) {
    const wrongAccount = /different email/i.test(clock.error)
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-5">
        <div className="max-w-sm rounded-2xl border border-border bg-white p-8 text-center shadow-sm">
          <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-danger-bg text-danger">
            <AlertTriangle size={22} />
          </span>
          <h1 className="mt-4 text-xl font-bold text-neutral-900">
            {wrongAccount ? 'Signed in with a different account' : 'Interview not found'}
          </h1>
          <p className="mt-2 text-sm text-neutral-500">
            {clock.error}{wrongAccount ? '' : '. Please double-check your invite link.'}
          </p>
          <button
            onClick={() => { void signOutUser() }}
            className="mt-5 rounded-full bg-[#0d5c3a] px-5 py-2 text-sm font-semibold text-white hover:bg-[#0a4a2f]"
          >
            Sign out &amp; switch account
          </button>
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
    // First entry runs the on-device face-framing pre-flight inside AvatarStage
    // (the Tavus conversation is created in parallel while the candidate frames
    // their face). Reconnects — status already in_progress — skip straight back
    // into the room; never re-gate a refresh mid-call.
    return (
      <AvatarStage
        sessionId={sessionId}
        branding={branding}
        onIntegrity={integrity.post}
        preflight={s.status !== 'in_progress'}
      />
    )
  }
  // Voice track runs its own realtime call screen (WebSocket → Gemini Live).
  if (s.track === 'voice' && (chatbotStarted || s.status === 'in_progress')) {
    return <VoiceStage sessionId={sessionId} branding={branding} />
  }
  // Two-way track is a live recruiter↔candidate Daily call (own full-screen
  // room, not the timed engine) — reconnects (status already in_progress)
  // skip straight back into the lobby/room.
  if (s.track === 'two_way' && (chatbotStarted || s.status === 'in_progress')) {
    // No onIntegrity here: TwoWayStage has no paste/copy fields or camera
    // pre-flight of its own to report on, and tab-switch/fullscreen detection
    // already runs unconditionally in the useIntegrityMonitor hook above
    // (keyed only on `active`, not on which stage is rendered).
    return <TwoWayStage sessionId={sessionId} branding={branding} />
  }

  if (s.status === 'in_progress') {
    if (s.track === 'video') {
      return (
        <InterviewShell branding={branding} progress={s.progress} live>
          <VideoInterview
            sessionId={sessionId}
            state={s}
            remaining={clock.remaining}
            secondsLeft={clock.secondsLeft}
            busy={clock.busy}
            onSkipPrep={clock.skipPrep}
            onSubmitText={clock.submitText}
            onIntegrity={integrity.post}
          />
        </InterviewShell>
      )
    }
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
  // The chatbot/voice track's format is fixed by the template, so skip "choose format".
  const conversational = s.track === 'chatbot' || s.track === 'video_avatar' || s.track === 'voice' || s.track === 'two_way'
  // Video Interview's format is fixed by the invite too — skip "choose format",
  // but it runs on the timed engine (not the conversational full-screen engines).
  const fixedFormat = conversational || s.track === 'video'
  // Video-avatar interviews ALWAYS collect the candidate's full name + résumé
  // first — both are fed to the Tavus avatar (name in the greeting/questions,
  // résumé as its background knowledge). Other tracks only when the question
  // plan needs the résumé.
  const needsIntake = s.awaitingResume || (s.track === 'video_avatar' && !s.hasResume)
  const step: PreStep = fixedFormat && preStep === 'track' ? 'welcome' : preStep
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
              if (needsIntake) { setPreStep('resume') }
              else { clock.systemCheck(); setPreStep('systemcheck') }
            }}
          />
        )}
        {step === 'resume' && (
          <ResumeUpload
            key="resume"
            branding={branding}
            busy={clock.busy}
            onUpload={async (file, fullName) => { await clock.uploadResume(file, fullName); clock.systemCheck(); setPreStep('systemcheck') }}
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
