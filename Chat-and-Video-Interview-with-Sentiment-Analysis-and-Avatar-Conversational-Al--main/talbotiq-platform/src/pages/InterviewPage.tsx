import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import toast from 'react-hot-toast'
import { useConversation, useUpdateConversation, useEndConversation } from '@/hooks/useTavus'
import { useAppStore } from '@/store/useAppStore'
import { Badge, Button, Card } from '@/components/ui'
import { cn } from '@/components/ui'

function MetricBar({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className="flex flex-col gap-1">
      <div className="flex justify-between text-xs">
        <span className="text-brand-gray uppercase tracking-wide font-semibold">{label}</span>
        <span style={{ color }} className="font-head font-bold">{value}%</span>
      </div>
      <div className="h-1.5 bg-brand-border rounded-full overflow-hidden">
        <div className="h-full rounded-full transition-all duration-700" style={{ width: `${value}%`, background: color }} />
      </div>
    </div>
  )
}

type SideTab = 'questions' | 'live' | 'transcript'

export default function InterviewPage() {
  const navigate = useNavigate()
  const store = useAppStore()
  const conv = store.currentConversation
  const { data: liveConv } = useConversation(conv?.conversation_id ?? '', true)
  const updateConv = useUpdateConversation()
  const endConv = useEndConversation()

  const [sideTab, setSideTab] = useState<SideTab>('questions')
  const [overrideText, setOverrideText] = useState('')
  const [transcript, setTranscript] = useState<{ role: 'ai' | 'candidate'; text: string }[]>([])
  const [isFullscreen, setIsFullscreen] = useState(false)
  const panelRef = useRef<HTMLDivElement>(null)
  const transcriptRef = useRef<HTMLDivElement>(null)
  const metricIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const metrics = store.metrics
  const questions = store.questions.filter(Boolean)
  const currentQ = store.currentQuestionIdx

  // Start metric simulation when interview is active
  useEffect(() => {
    if (!store.interviewActive) return
    metricIntervalRef.current = setInterval(() => {
      const jitter = (v: number) => Math.max(0, Math.min(100, v + (Math.random() - 0.5) * 10))
      store.updateMetrics({
        confidence: Math.round(jitter(metrics.confidence)),
        anxiety: Math.round(Math.max(0, Math.min(50, metrics.anxiety + (Math.random() - 0.5) * 6))),
        wpm: Math.round(110 + Math.random() * 50),
        fillers: Math.round(Math.random() * 8),
        engagement: Math.round(jitter(metrics.engagement)),
      })
    }, 2500)
    return () => { if (metricIntervalRef.current) clearInterval(metricIntervalRef.current) }
  }, [store.interviewActive])

  // Auto-scroll transcript
  useEffect(() => { transcriptRef.current?.scrollTo({ top: transcriptRef.current.scrollHeight, behavior: 'smooth' }) }, [transcript])

  // Detect conversation ended via polling
  useEffect(() => {
    if (liveConv?.status === 'ended' && store.interviewActive) {
      store.setInterviewActive(false)
      toast.success('Interview ended — generating scorecard')
      setTimeout(() => navigate('/results'), 1500)
    }
  }, [liveConv?.status])

  // Redirect if no conversation
  useEffect(() => {
    if (!conv) { toast('No active interview — go to Setup'); navigate('/setup') }
  }, [])

  function sendOverride() {
    if (!conv || !overrideText.trim()) return
    updateConv.mutate(
      { id: conv.conversation_id, data: { conversational_context: overrideText } },
      {
        onSuccess: () => { toast.success('Override sent'); setOverrideText('') },
        onError: (e: any) => toast.error(e.message),
      },
    )
  }

  function handleEndInterview() {
    if (!confirm('End the interview now?')) return
    if (conv) {
      endConv.mutate(conv.conversation_id, {
        onSuccess: () => { store.setInterviewActive(false); navigate('/results') },
        onError: () => { store.setInterviewActive(false); navigate('/results') },
      })
    } else {
      store.setInterviewActive(false)
      navigate('/results')
    }
  }

  function nextQuestion() {
    const next = currentQ + 1
    if (next < questions.length) store.setCurrentQuestionIdx(next)
    else handleEndInterview()
  }

  function enterFs() { panelRef.current?.classList.add('fs-active') as any; setIsFullscreen(true) }
  function exitFs() { panelRef.current?.classList.remove('fs-active') as any; setIsFullscreen(false) }
  useEffect(() => { const h = (e: KeyboardEvent) => { if (e.key === 'Escape') exitFs() }; window.addEventListener('keydown', h); return () => window.removeEventListener('keydown', h) }, [])

  if (!conv) return null

  const confColor = metrics.confidence > 70 ? '#3db36b' : metrics.confidence > 50 ? '#f0c040' : '#ef4444'

  return (
    <div className="flex h-[calc(100vh-56px)]">
      {/* Avatar / video panel */}
      <div ref={panelRef} className={cn('relative flex-1 bg-[#080808] flex flex-col items-center justify-center overflow-hidden', isFullscreen && 'fixed inset-0 z-[9999]')}>
        {/* Exit fullscreen button */}
        {isFullscreen && (
          <button onClick={exitFs} className="fixed top-4 right-4 z-[10000] w-10 h-10 rounded-full bg-black/70 border border-white/20 text-white flex items-center justify-center text-xl hover:bg-white/10 transition-all">×</button>
        )}

        {/* Progress bar */}
        <div className="absolute top-0 left-0 right-0 h-1 bg-brand-border z-10">
          <div className="h-full bg-gradient-to-r from-brand-green to-brand-gold transition-all duration-500" style={{ width: `${((currentQ + 1) / Math.max(questions.length, 1)) * 100}%` }} />
        </div>

        {/* Full Screen button (outside iframe) */}
        <button onClick={isFullscreen ? exitFs : enterFs} className="absolute top-4 right-4 z-10 flex items-center gap-1.5 px-3 py-1.5 bg-black/70 border border-brand-gold/40 rounded-full text-brand-gold text-xs font-semibold hover:bg-brand-gold/10 transition-all">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"/></svg>
          {isFullscreen ? 'Exit Full Screen' : 'Full Screen'}
        </button>

        {/* Tavus iframe or placeholder */}
        <div className={cn('rounded-2xl overflow-hidden bg-[#111] border border-brand-border shadow-2xl transition-all', isFullscreen ? 'fixed inset-0 rounded-none border-none bottom-[72px]' : 'w-72 h-96 mb-5')}>
          {conv.conversation_url ? (
            <iframe
              src={conv.conversation_url}
              width="100%" height="100%"
              style={{ border: 'none' }}
              allow="camera;microphone;autoplay;display-capture;fullscreen"
              allowFullScreen
            />
          ) : (
            <div className="w-full h-full flex flex-col items-center justify-center gap-3 bg-gradient-to-b from-[#111] to-[#0d1a12]">
              <div className="w-20 h-20 rounded-full bg-gradient-to-br from-brand-green to-[#1a5c35] flex items-center justify-center border-2 border-brand-green-light/40" style={{ animation: 'pulse 3s ease-in-out infinite' }}>
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="1.5"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
              </div>
              <p className="font-head font-bold text-white">Demo Mode</p>
              <p className="text-xs text-brand-gray text-center px-4">Live avatar appears here when connected to Tavus API</p>
            </div>
          )}
        </div>

        {/* Controls bar */}
        <div className={cn('flex items-center gap-3 z-10', isFullscreen && 'fixed bottom-0 left-0 right-0 h-[72px] bg-black/90 justify-center border-t border-white/10')}>
          {[
            { label: '⏮', title: 'Skip question', action: nextQuestion },
            { label: '⏹', title: 'End interview', action: handleEndInterview, cls: 'border-red-500/40 bg-red-500/10 text-red-400' },
          ].map(b => (
            <button key={b.label} title={b.title} onClick={b.action}
              className={cn('w-11 h-11 rounded-full border border-brand-border bg-white/5 text-white flex items-center justify-center hover:bg-white/10 transition-all', b.cls)}>
              {b.label}
            </button>
          ))}
        </div>

        {/* Question overlay */}
        <div className={cn('absolute left-0 right-0 bg-gradient-to-t from-black/90 to-transparent px-8 pb-6 pt-12 z-5', isFullscreen ? 'fixed bottom-[72px]' : 'bottom-0')}>
          <p className="text-xs font-bold text-brand-gold uppercase tracking-widest mb-2">Question {currentQ + 1} of {questions.length}</p>
          <p className="text-white font-light text-sm leading-relaxed">{questions[currentQ] ?? 'Interview complete'}</p>
        </div>
      </div>

      {/* Sidebar */}
      {!isFullscreen && (
        <div className="w-80 flex flex-col border-l border-brand-border bg-brand-black">
          <div className="flex border-b border-brand-border">
            {(['questions', 'live', 'transcript'] as SideTab[]).map(t => (
              <button key={t} onClick={() => setSideTab(t)}
                className={cn('flex-1 py-3 text-xs font-bold uppercase tracking-wider transition-all', sideTab === t ? 'text-brand-gold border-b-2 border-brand-gold' : 'text-brand-gray hover:text-white')}>
                {t === 'live' ? 'Live AI' : t.charAt(0).toUpperCase() + t.slice(1)}
              </button>
            ))}
          </div>

          <div className="flex-1 overflow-y-auto p-4">
            {/* Questions panel */}
            {sideTab === 'questions' && (
              <div className="space-y-2">
                {questions.map((q, i) => (
                  <button key={i} onClick={() => store.setCurrentQuestionIdx(i)}
                    className={cn('w-full flex gap-3 items-start p-3 rounded-xl text-left transition-all border', i === currentQ ? 'bg-brand-gold/10 border-brand-gold/30' : i < currentQ ? 'opacity-50 border-transparent' : 'border-transparent hover:bg-brand-card')}>
                    <span className={cn('w-5 h-5 rounded text-xs font-black flex items-center justify-center flex-shrink-0 mt-0.5', i === currentQ ? 'bg-brand-gold text-brand-black' : i < currentQ ? 'bg-brand-green text-white' : 'bg-brand-border text-brand-gray')}>
                      {i < currentQ ? '✓' : i + 1}
                    </span>
                    <span className="text-xs text-white leading-relaxed">{q}</span>
                  </button>
                ))}
              </div>
            )}

            {/* Live AI panel */}
            {sideTab === 'live' && (
              <div className="space-y-3">
                <MetricBar label="Confidence" value={metrics.confidence} color={confColor} />
                <MetricBar label="Anxiety" value={metrics.anxiety} color="#ef4444" />
                <MetricBar label="Engagement" value={metrics.engagement} color="#3db36b" />
                <div className="grid grid-cols-2 gap-3 mt-2">
                  {[['WPM', metrics.wpm.toString(), '#3db36b'], ['Fillers', metrics.fillers.toString(), '#8a8a8a']].map(([l, v, c]) => (
                    <div key={l} className="bg-brand-card border border-brand-border rounded-xl p-3">
                      <p className="text-xs text-brand-gray uppercase tracking-wide mb-1">{l}</p>
                      <p className="font-head font-black text-2xl" style={{ color: c }}>{v}</p>
                    </div>
                  ))}
                </div>
                <div className="flex flex-wrap gap-1.5 mt-2">
                  <Badge variant={metrics.confidence > 70 ? 'success' : 'warning'}>{metrics.confidence > 70 ? 'Confident' : 'Moderate'}</Badge>
                  <Badge variant={metrics.anxiety < 15 ? 'success' : 'warning'}>{metrics.anxiety < 15 ? 'Calm' : 'Some Anxiety'}</Badge>
                  <Badge variant={metrics.engagement > 70 ? 'success' : 'neutral'}>Engaged</Badge>
                </div>

                {/* Override input */}
                {liveConv?.properties?.apply_conversation_override && (
                  <div className="mt-4 border-t border-brand-border pt-4">
                    <p className="text-xs text-brand-gold font-semibold uppercase tracking-wide mb-2">Override (say this now)</p>
                    <div className="flex gap-2">
                      <input value={overrideText} onChange={e => setOverrideText(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') sendOverride() }} placeholder="Type text for avatar to say…" className="flex-1 bg-brand-card border border-brand-border rounded-lg px-3 py-2 text-xs text-white outline-none focus:border-brand-gold" />
                      <button onClick={sendOverride} className="px-3 py-2 bg-brand-gold text-brand-black text-xs font-bold rounded-lg hover:bg-yellow-300">Send</button>
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* Transcript panel */}
            {sideTab === 'transcript' && (
              <div ref={transcriptRef} className="space-y-3 overflow-y-auto">
                {!transcript.length && (
                  <p className="text-xs text-brand-gray text-center py-8">Transcript will appear here as the interview progresses.</p>
                )}
                {transcript.map((t, i) => (
                  <div key={i} className={cn('p-3 rounded-xl text-xs leading-relaxed', t.role === 'ai' ? 'bg-brand-green/10 border border-brand-green/20 rounded-tl-sm' : 'bg-brand-card border border-brand-border rounded-tr-sm')}>
                    <p className="text-brand-gray/60 uppercase tracking-wide font-bold mb-1 text-[10px]">{t.role === 'ai' ? 'AI Interviewer' : 'Candidate'}</p>
                    {t.text}
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Status bar */}
          <div className="p-3 border-t border-brand-border flex items-center justify-between">
            <Badge variant={liveConv?.status === 'active' ? 'success' : 'neutral'}>{liveConv?.status ?? 'connecting'}</Badge>
            <button onClick={handleEndInterview} className="text-xs text-red-400 hover:text-red-300 font-semibold">End Interview</button>
          </div>
        </div>
      )}
    </div>
  )
}
