import { useEffect } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'react-hot-toast'
import { Nav } from '@/components/layout/Nav'
import { humeService } from '@/services/hume'
import { deepgramService } from '@/services/deepgram'
import { useAppStore } from '@/store/useAppStore'
import SetupPage from '@/pages/SetupPage'
import InterviewPage from '@/pages/InterviewPage'
import ResultsPage from '@/pages/ResultsPage'
import ReplicasPage from '@/pages/ReplicasPage'
import PersonasPage from '@/pages/PersonasPage'
import AnalyticsPage from '@/pages/AnalyticsPage'
import SettingsPage from '@/pages/SettingsPage'

const qc = new QueryClient({ defaultOptions: { queries: { retry: 1, staleTime: 15_000 } } })

export default function App() {
  // Safety-net: ensure services have keys even if zustand rehydration fires late
  useEffect(() => {
    const s = useAppStore.getState()
    const envHume = import.meta.env.VITE_HUME_KEY ?? ''
    const envDg   = import.meta.env.VITE_DEEPGRAM_KEY ?? ''
    if (envHume && !humeService.getKey()) {
      humeService.setKey(envHume)
      if (!s.humeKey) useAppStore.getState().setHumeKey(envHume)
    }
    if (envDg && !deepgramService.getKey()) {
      deepgramService.setKey(envDg)
      if (!s.deepgramKey) useAppStore.getState().setDeepgramKey(envDg)
    }
  }, [])

  return (
    <QueryClientProvider client={qc}>
      <BrowserRouter>
        <div className="min-h-screen bg-background font-sans">
          <Nav />
          <main>
            <Routes>
              <Route path="/" element={<Navigate to="/setup" replace />} />
              <Route path="/setup"     element={<SetupPage />} />
              <Route path="/interview" element={<InterviewPage />} />
              <Route path="/results"   element={<ResultsPage />} />
              <Route path="/replicas"  element={<ReplicasPage />} />
              <Route path="/personas"  element={<PersonasPage />} />
              <Route path="/analytics" element={<AnalyticsPage />} />
              <Route path="/settings"  element={<SettingsPage />} />
            </Routes>
          </main>
        </div>

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
            error:   { iconTheme: { primary: '#dc2626', secondary: '#fff' } },
            loading: { iconTheme: { primary: '#0d5c3a', secondary: '#fff' } },
          }}
        />
      </BrowserRouter>
    </QueryClientProvider>
  )
}
