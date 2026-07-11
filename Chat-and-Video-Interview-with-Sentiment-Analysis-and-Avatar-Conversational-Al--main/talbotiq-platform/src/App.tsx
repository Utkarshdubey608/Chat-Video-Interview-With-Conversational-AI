import { BrowserRouter, Routes, Route, Navigate, Outlet } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'react-hot-toast'
import { Nav } from '@/components/layout/Nav'
import SetupPage from '@/pages/SetupPage'
import InterviewPage from '@/pages/InterviewPage'
import ResultsPage from '@/pages/ResultsPage'
import ReplicasPage from '@/pages/ReplicasPage'
import PersonasPage from '@/pages/PersonasPage'
import AnalyticsPage from '@/pages/AnalyticsPage'
import SettingsPage from '@/pages/SettingsPage'
import TemplatesPage from '@/features/recruiter/TemplatesPage'
import TemplateEditorPage from '@/features/recruiter/TemplateEditorPage'
import QuestionSetsPage from '@/features/recruiter/QuestionSetsPage'
import SessionsPage from '@/features/recruiter/SessionsPage'
import ReportPage from '@/features/recruiter/ReportPage'
import TakeInterviewPage from '@/features/interview/TakeInterviewPage'

const qc = new QueryClient({ defaultOptions: { queries: { retry: 1, staleTime: 15_000 } } })

/** Recruiter app chrome — top nav + routed content. */
function RecruiterShell() {
  return (
    <div className="min-h-screen bg-background font-sans">
      <Nav />
      <main>
        <Outlet />
      </main>
    </div>
  )
}

export default function App() {
  return (
    <QueryClientProvider client={qc}>
      <BrowserRouter>
        <Routes>
          {/* Candidate experience — chrome-minimal, no recruiter nav */}
          <Route path="/take/:sessionId" element={<TakeInterviewPage />} />

          {/* Recruiter app */}
          <Route element={<RecruiterShell />}>
            <Route path="/" element={<Navigate to="/setup" replace />} />
            <Route path="/setup" element={<SetupPage />} />
            <Route path="/interview" element={<InterviewPage />} />
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
            <Route path="/sessions/:id/report" element={<ReportPage />} />
          </Route>
        </Routes>
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
          success: { iconTheme: { primary: '#0d5c3a', secondary: '#fff' } },
          error: { iconTheme: { primary: '#dc2626', secondary: '#fff' } },
          loading: { iconTheme: { primary: '#0d5c3a', secondary: '#fff' } },
        }}
      />
    </QueryClientProvider>
  )
}
