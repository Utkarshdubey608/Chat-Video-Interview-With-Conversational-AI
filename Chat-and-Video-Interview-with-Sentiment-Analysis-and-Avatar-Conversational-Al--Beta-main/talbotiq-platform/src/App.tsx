import { useEffect } from 'react'
import { BrowserRouter, Routes, Route, Outlet } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'react-hot-toast'
import { Nav } from '@/components/layout/Nav'
import { refreshServiceStatus } from '@/store/useAppStore'
import { AuthProvider } from '@/features/auth/AuthProvider'
import { RequireRecruiter, RequireCandidate, HomeRedirect } from '@/features/auth/guards'
import LoginPage from '@/features/auth/LoginPage'
import AccessDenied from '@/features/auth/AccessDenied'
import CandidateHome from '@/features/candidate/CandidateHome'
import MimicSite from '@/features/marketing/MimicSite'
import MarketingPage from '@/features/marketing/MarketingPage'
import SetupPage from '@/pages/SetupPage'
import AvatarScreeningGate from '@/features/avatar-screening/AvatarScreeningGate'
import ResultsPage from '@/pages/ResultsPage'
import ReplicasPage from '@/pages/ReplicasPage'
import PersonasPage from '@/pages/PersonasPage'
import AnalyticsPage from '@/pages/AnalyticsPage'
import SettingsPage from '@/pages/SettingsPage'
import TemplatesPage from '@/features/recruiter/TemplatesPage'
import TemplateEditorPage from '@/features/recruiter/TemplateEditorPage'
import QuestionSetsPage from '@/features/recruiter/QuestionSetsPage'
import SessionsPage from '@/features/recruiter/SessionsPage'
import PipelinesPage from '@/features/recruiter/PipelinesPage'
import PipelineBoardPage from '@/features/recruiter/PipelineBoardPage'
import InviteWizard from '@/features/recruiter/InviteWizard'
import ReportPage from '@/features/recruiter/ReportPage'
import LiveInterviewPage from '@/features/recruiter/LiveInterviewPage'
import TakeInterviewPage from '@/features/interview/TakeInterviewPage'
import MimicGuide from '@/features/guide/MimicGuide'
import { IntroFaceSync } from '@/features/intro/IntroFaceSync'

const qc = new QueryClient({ defaultOptions: { queries: { retry: 1, staleTime: 15_000 } } })

/** Recruiter app chrome — top nav + routed content. Mounts only for an
 *  authenticated recruiter, so this is where we (re)load the server-side
 *  service-configuration flags now that the request carries the ID token. */
function RecruiterShell() {
  useEffect(() => { refreshServiceStatus() }, [])
  return (
    <div className="min-h-screen bg-background font-sans">
      <Nav />
      <main>
        <Outlet />
      </main>
      {/* Background, one-time sync of real replica thumbnails into the intro's
          face cache (IndexedDB). Renders nothing; no extra Tavus call. */}
      <IntroFaceSync />
    </div>
  )
}

export default function App() {
  return (
    <QueryClientProvider client={qc}>
      <AuthProvider>
        <BrowserRouter>
          <Routes>
            {/* Public */}
            <Route path="/login" element={<LoginPage />} />
            <Route path="/access-denied" element={<AccessDenied />} />
            {/* Public marketing site (pre-login). Additive; existing routes/auth untouched. */}
            <Route path="/mimic" element={<MimicSite />} />
            <Route path="/mimic/*" element={<MarketingPage />} />

            {/* Candidate-only — assigned-session list + the interview itself */}
            <Route element={<RequireCandidate />}>
              <Route path="/candidate" element={<CandidateHome />} />
              <Route path="/take/:sessionId" element={<TakeInterviewPage />} />
            </Route>

            {/* Recruiter-only — the full recruiter app */}
            <Route element={<RequireRecruiter />}>
              {/* Live Two-way Interview host room — full-bleed dark call UI
                  (mirrors the candidate's TwoWayStage), so it deliberately
                  sits OUTSIDE RecruiterShell (no Nav chrome on a live call). */}
              <Route path="/live/:id" element={<LiveInterviewPage />} />
              <Route element={<RecruiterShell />}>
                <Route path="/setup" element={<SetupPage />} />
                {/* Face-fit pre-flight runs first, then hands off to the
                    (unchanged) InterviewPage — see AvatarScreeningGate. */}
                <Route path="/interview" element={<AvatarScreeningGate />} />
                {/* AI Avatar Screening results (Tavus + Deepgram + Hume + Rekognition +
                    Gemini). Distinct from the recruiter per-session report at
                    /sessions/:id/report, which is unchanged. */}
                <Route path="/results" element={<ResultsPage />} />
                <Route path="/replicas" element={<ReplicasPage />} />
                <Route path="/personas" element={<PersonasPage />} />
                <Route path="/analytics" element={<AnalyticsPage />} />
                <Route path="/settings" element={<SettingsPage />} />

                {/* AI Interview module */}
                <Route path="/templates" element={<TemplatesPage />} />
                <Route path="/templates/:id" element={<TemplateEditorPage />} />
                <Route path="/question-sets" element={<QuestionSetsPage />} />
                <Route path="/sessions" element={<SessionsPage />} />
                <Route path="/sessions/new" element={<InviteWizard />} />
                <Route path="/sessions/:id/report" element={<ReportPage />} />
                <Route path="/pipelines" element={<PipelinesPage />} />
                <Route path="/pipelines/:id" element={<PipelineBoardPage />} />
              </Route>
            </Route>

            {/* Root + unknown → route to the signed-in user's home (or login) */}
            <Route path="/" element={<HomeRedirect />} />
            <Route path="*" element={<HomeRedirect />} />
          </Routes>

          {/* Global in-app help assistant. Inside the router so its deep-links
              navigate; renders only for signed-in users (recruiter or candidate). */}
          <MimicGuide />
        </BrowserRouter>

        <Toaster
          position="bottom-right"
          gutter={8}
          toastOptions={{
            duration: 4000,
            style: {
              background: '#fff',
              color: '#0f172a',
              border: '1px solid #e2e8f0',
              borderRadius: '10px',
              padding: '12px 16px',
              fontSize: '13px',
              fontFamily: 'Inter, system-ui, sans-serif',
              fontWeight: '500',
              boxShadow: '0 4px 12px rgba(0,0,0,0.08)',
              maxWidth: '380px',
            },
            success: { iconTheme: { primary: '#6B2BE0', secondary: '#fff' } },
            error: { iconTheme: { primary: '#dc2626', secondary: '#fff' } },
            loading: { iconTheme: { primary: '#6B2BE0', secondary: '#fff' } },
          }}
        />
      </AuthProvider>
    </QueryClientProvider>
  )
}
