import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import toast from 'react-hot-toast'
import DailyIframe from '@daily-co/daily-js'
import { useConversation, useUpdateConversation, useEndConversation } from '@/hooks/useTavus'
import { useAppStore } from '@/store/useAppStore'
import { useAudioAnalysis } from '@/hooks/useAudioAnalysis'
import { useFacialCapture } from '@/hooks/useFacialCapture'
import { useHumePoll } from '@/hooks/useHumeBatch'
import { humeService } from '@/services/hume'
import { HumeStatusIndicator } from '@/components/hume/HumeStatusIndicator'
import { LiveEmotionBar } from '@/components/hume/LiveEmotionBar'
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
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [revealedIdx, setRevealedIdx] = useState(-1)   // which question index is currently revealed
  const [avatarSpeaking, setAvatarSpeaking] = useState(false)
  const [autoAdvance, setAutoAdvance] = useState(true)
  const speakingTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const iframeRef = useRef<HTMLIFrameElement>(null)
  const panelRef = useRef<HTMLDivElement>(null)
  const transcriptRef = useRef<HTMLDivElement>(null)
  const metricIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null)
  // Turn tracking — drives auto-advance based on who is speaking
  const avatarTurnsRef = useRef(0)
  const candidateSpokeRef = useRef(false)
  const autoAdvanceRef = useRef(true)
  const lastAvatarTurnTimeRef = useRef(0)
  const localIdRef = useRef<string | undefined>(undefined)
  const avatarPeerIdRef = useRef<string | undefined>(undefined)

  // Unified audio capture — single mic stream for Deepgram + Hume EVI + Hume batch
  const { interimText, dgConnected, sealAndGetBlob } = useAudioAnalysis(store.interviewActive)
  // Optional facial analysis (AWS Rekognition) — separate video-only capture, additive
  const facialCapture = useFacialCapture()
  // ResultsPage polls for completion; keep the hook here too so it fires if user navigates back
  useHumePoll()

  const metrics = store.metrics
  const questions = store.questions.filter(Boolean)
  const currentQ = store.currentQuestionIdx
  // Question text is only shown once the avatar has reached this question
  const questionRevealed = revealedIdx === currentQ

  useEffect(() => { autoAdvanceRef.current = autoAdvance }, [autoAdvance])

  // Track when each question starts for per-question emotion analysis
  useEffect(() => {
    if (store.interviewActive) store.pushQuestionTimestamp(Date.now())
  }, [currentQ]) // eslint-disable-line react-hooks/exhaustive-deps

  // Optional facial capture: start when the interview goes active, stop (and persist
  // frames to facialDataStore) on cleanup / interview end. No-op if no AWS proxy is set.
  useEffect(() => {
    if (store.interviewActive) facialCapture.startCapture()
    return () => { facialCapture.stopCapture() }
  }, [store.interviewActive]) // eslint-disable-line react-hooks/exhaustive-deps

  // Keep the facial capture's "current question" in sync for per-question aggregation
  useEffect(() => {
    facialCapture.updateQuestion(currentQ)
  }, [currentQ]) // eslint-disable-line react-hooks/exhaustive-deps

  // After any question change (manual or auto), wait for the candidate to answer
  // again before the next avatar turn is treated as "move to next question".
  useEffect(() => { candidateSpokeRef.current = false }, [currentQ])

  // Mark a speaking turn for the current question (reveals it + flags the pulse)
  function markAvatarSpeaking() {
    setAvatarSpeaking(true)
    setRevealedIdx(useAppStore.getState().currentQuestionIdx)
    if (speakingTimeoutRef.current) clearTimeout(speakingTimeoutRef.current)
    speakingTimeoutRef.current = setTimeout(() => setAvatarSpeaking(false), 3000)
  }

  // Avatar moved on to the next question → advance the index and reveal it
  function advanceToNext() {
    const s = useAppStore.getState()
    const total = s.questions.filter(Boolean).length
    const next = s.currentQuestionIdx + 1
    if (next >= total) return                 // stay on the last question; don't auto-end
    s.setCurrentQuestionIdx(next)
    setRevealedIdx(next)
    setAvatarSpeaking(true)
    if (speakingTimeoutRef.current) clearTimeout(speakingTimeoutRef.current)
    speakingTimeoutRef.current = setTimeout(() => setAvatarSpeaking(false), 3000)
  }

  // Wrap the Tavus (Daily.co) iframe and follow the turn-taking conversation.
  // Tavus runs on Daily.co prebuilt, so the embedded call exposes active-speaker-change.
  // Pattern: avatar asks Q → candidate answers → avatar asks next Q (auto-advance).
  useEffect(() => {
    if (!conv?.conversation_url) return
    const iframe = iframeRef.current
    if (!iframe) return

    let call: any = null

    const handleAvatarTurn = () => {
      const now = Date.now()
      const gap = now - lastAvatarTurnTimeRef.current
      // Advance if candidate spoke OR avatar was silent 5+ seconds (candidate had time to respond)
      const shouldAdvance = avatarTurnsRef.current > 0 && autoAdvanceRef.current &&
        (candidateSpokeRef.current || gap > 5000)
      if (shouldAdvance) {
        candidateSpokeRef.current = false
        advanceToNext()
      } else {
        markAvatarSpeaking()
      }
      lastAvatarTurnTimeRef.current = now
      avatarTurnsRef.current += 1
    }

    const onActiveSpeaker = (ev: any) => {
      const peerId = ev?.activeSpeaker?.peerId
      if (!peerId) return
      // Cache local + avatar IDs on first opportunity
      if (!localIdRef.current) {
        try { localIdRef.current = call?.participants?.()?.local?.session_id } catch {}
      }
      // Accurate avatar identification: use tracked avatar peer ID when available
      let isAvatar: boolean
      if (avatarPeerIdRef.current) {
        isAvatar = peerId === avatarPeerIdRef.current
      } else {
        isAvatar = peerId !== 'local' && (!localIdRef.current || peerId !== localIdRef.current)
      }
      if (isAvatar) handleAvatarTurn()
      else candidateSpokeRef.current = true
    }

    const onAppMessage = (ev: any) => {
      const d = ev?.data ?? {}
      const t = String(d.event_type ?? d.message_type ?? d.type ?? '')
      if (/replica|agent|assistant/i.test(t) && /speak|utter|start/i.test(t)) handleAvatarTurn()
      else if (/user|candidate|listening/i.test(t)) candidateSpokeRef.current = true
    }

    let cleanup = () => {}
    const timer = setTimeout(() => {
      try {
        call = (DailyIframe as any).getCallInstance?.() ?? null
        if (!call) call = DailyIframe.wrap(iframe)
        call.on('joined-meeting', (ev: any) => {
          localIdRef.current = ev?.participants?.local?.session_id ??
            call?.participants?.()?.local?.session_id
          // Identify avatar from any remote participants already in the room
          const parts = ev?.participants ?? {}
          for (const key of Object.keys(parts)) {
            if (key !== 'local' && !parts[key]?.local) {
              avatarPeerIdRef.current = parts[key]?.session_id ?? key
              break
            }
          }
        })
        call.on('participant-joined', (ev: any) => {
          // First remote participant to join is the avatar
          if (!ev?.participant?.local && !avatarPeerIdRef.current) {
            avatarPeerIdRef.current = ev?.participant?.session_id
          }
        })
        call.on('active-speaker-change', onActiveSpeaker)
        call.on('app-message', onAppMessage)
        cleanup = () => {
          try {
            call.off('active-speaker-change', onActiveSpeaker)
            call.off('app-message', onAppMessage)
          } catch {}
        }
      } catch (e) {
        console.warn('[interview] Daily wrap unavailable — using fallback reveal timer', e)
      }
    }, 1500)

    return () => { clearTimeout(timer); cleanup() }
  }, [conv?.conversation_url])

  // Safety net: never leave a question stuck on "waiting". If no speaking event
  // arrives, reveal after a delay (live: 9s gives the avatar time to greet+ask; demo: 4s).
  useEffect(() => {
    if (!store.interviewActive) return
    if (revealedIdx === currentQ) return
    const delay = conv?.conversation_url ? 9000 : 4000
    const t = setTimeout(() => setRevealedIdx(currentQ), delay)
    return () => clearTimeout(t)
  }, [currentQ, revealedIdx, conv?.conversation_url, store.interviewActive])

  // Timer-based auto-advance fallback: if the question has been shown for 90s and Auto is on,
  // advance regardless of whether Daily.co events fired. Resets every time the question changes.
  useEffect(() => {
    if (!store.interviewActive || !autoAdvance || revealedIdx !== currentQ) return
    const t = setTimeout(() => {
      if (!autoAdvanceRef.current) return
      const s = useAppStore.getState()
      const next = s.currentQuestionIdx + 1
      if (next < s.questions.filter(Boolean).length) {
        s.setCurrentQuestionIdx(next)
        setRevealedIdx(next)
      }
    }, 90_000)
    return () => clearTimeout(t)
  }, [currentQ, revealedIdx, store.interviewActive, autoAdvance])

  // Jitter simulation (only runs when Hume stream is not active as fallback)
  useEffect(() => {
    if (!store.interviewActive || store.humeStreamActive) return
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
  }, [store.interviewActive, store.humeStreamActive])

  // Auto-scroll transcript on new entries
  useEffect(() => {
    transcriptRef.current?.scrollTo({ top: transcriptRef.current.scrollHeight, behavior: 'smooth' })
  }, [store.sessionTranscript.length])

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

  async function handleEndInterview() {
    if (!confirm('End the interview now?')) return

    // Flush final audio chunk and seal before stopping the stream
    let blob: Blob | null = null
    try {
      blob = await Promise.race([
        sealAndGetBlob(),
        new Promise<null>(resolve => setTimeout(() => resolve(null), 3000)),
      ])
    } catch { blob = null }

    // Submit Hume batch job — non-blocking; ResultsPage polls via useHumePoll
    const humeKey = store.humeKey || humeService.getKey()
    if (blob && blob.size > 100 && humeKey) {
      humeService.setKey(humeKey)
      toast.loading('Submitting voice analysis…', { id: 'hume-submit' })
      humeService.submitBatchJob(blob)
        .then(jobId => {
          store.setHumeJobId(jobId)
          store.setHumeJobStatus('QUEUED')
          toast.success('Voice analysis queued — processing emotions', { id: 'hume-submit', duration: 4000 })
        })
        .catch(err => {
          console.error('[Interview] Hume batch submit failed:', err)
          toast.error(`Voice analysis failed: ${err?.message ?? 'check Hume key in Settings'}`, { id: 'hume-submit', duration: 8000 })
        })
    } else if (humeKey && (!blob || blob.size <= 100)) {
      console.warn('[Interview] Hume batch skipped — blob size:', blob?.size ?? 'null')
      toast.error('No audio captured for analysis — mic may not have been active', { duration: 5000 })
    }

    store.setInterviewActive(false)

    if (conv) {
      endConv.mutate(conv.conversation_id, {
        onSuccess: () => navigate('/results'),
        onError:   () => navigate('/results'),
      })
    } else {
      navigate('/results')
    }
  }

  function prevQuestion() {
    if (currentQ > 0) {
      const prev = currentQ - 1
      store.setCurrentQuestionIdx(prev)
      setRevealedIdx(prev)
    }
  }

  async function nextQuestion() {
    const next = currentQ + 1
    if (next < questions.length) {
      store.setCurrentQuestionIdx(next)
      setRevealedIdx(next)
    } else await handleEndInterview()
  }

  function enterFs() { panelRef.current?.classList.add('fs-active') as any; setIsFullscreen(true) }
  function exitFs() { panelRef.current?.classList.remove('fs-active') as any; setIsFullscreen(false) }
  useEffect(() => { const h = (e: KeyboardEvent) => { if (e.key === 'Escape') exitFs() }; window.addEventListener('keydown', h); return () => window.removeEventListener('keydown', h) }, [])

  if (!conv) return null

  const confColor = metrics.confidence > 70 ? '#3db36b' : metrics.confidence > 50 ? '#f0c040' : '#ef4444'

  return (
    <div className="flex h-[calc(100vh-100px)]">
      {/* Avatar / video panel */}
      <div ref={panelRef} className={cn('relative flex-1 bg-[#0c1a2e] flex flex-col items-center justify-center overflow-hidden', isFullscreen && 'fixed inset-0 z-[9999]')}>
        {/* Exit fullscreen button */}
        {isFullscreen && (
          <button onClick={exitFs} className="fixed top-4 right-4 z-[10000] flex items-center gap-1.5 px-4 py-2 rounded-full bg-white/10 border border-white/20 text-white text-sm font-semibold backdrop-blur-sm hover:bg-white/20 transition-all">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"/></svg>
            Exit Full Screen
          </button>
        )}

        {/* Progress bar */}
        <div className="absolute top-0 left-0 right-0 h-[3px] bg-white/10 z-10">
          <div className="h-full bg-gradient-to-r from-[#0d5c3a] to-[#f0c040] transition-all duration-500" style={{ width: `${((currentQ + 1) / Math.max(questions.length, 1)) * 100}%` }} />
        </div>

        {/* Full Screen button */}
        <button onClick={isFullscreen ? exitFs : enterFs} className="absolute top-4 right-4 z-10 flex items-center gap-1.5 px-4 py-2 bg-white/10 border border-white/20 rounded-full text-white text-xs font-semibold backdrop-blur-sm hover:bg-white/20 transition-all">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"/></svg>
          {isFullscreen ? 'Exit Full Screen' : 'Full Screen'}
        </button>

        {/* Tavus iframe or placeholder */}
        <div className={cn('overflow-hidden shadow-2xl transition-all', isFullscreen ? 'fixed inset-0 rounded-none border-none bottom-[88px]' : 'w-[90%] max-w-[960px] h-[calc(100vh-320px)] min-h-[400px] mb-0 rounded-2xl border border-white/10')}>
          {conv.conversation_url ? (
            <iframe
              ref={iframeRef}
              src={conv.conversation_url}
              width="100%" height="100%"
              style={{ border: 'none' }}
              allow="camera;microphone;autoplay;display-capture;fullscreen"
              allowFullScreen
            />
          ) : (
            <div className="w-full h-full flex flex-col items-center justify-center gap-4 bg-gradient-to-b from-[#152035] to-[#0c1a2e]">
              <div className="w-20 h-20 rounded-full bg-gradient-to-br from-[#0d5c3a] to-[#1a8050] flex items-center justify-center border-2 border-white/20 shadow-lg" style={{ animation: 'pulse 3s ease-in-out infinite' }}>
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="1.5"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
              </div>
              <p className="font-semibold text-white text-lg">Demo Mode</p>
              <p className="text-sm text-white/50 text-center px-8 max-w-xs">Live avatar appears here when connected to Tavus API</p>
            </div>
          )}
        </div>

        {/* Question bar + controls — clean strip, no gradient */}
        <div className={cn('w-full flex items-center justify-between px-8 z-10 bg-[#091525] border-t border-white/10', isFullscreen ? 'fixed bottom-0 left-0 right-0 h-[88px]' : 'h-[88px] flex-shrink-0')}>
          <div className="flex-1 min-w-0 pr-6">
            <div className="flex items-center gap-2 mb-1">
              <p className="text-[10px] font-bold text-[#f0c040] uppercase tracking-widest">Question {currentQ + 1} of {questions.length}</p>
              {avatarSpeaking && (
                <span className="flex items-center gap-1 text-[10px] text-[#3db36b] font-semibold">
                  <span className="w-1.5 h-1.5 rounded-full bg-[#3db36b] animate-pulse" />
                  Avatar speaking
                </span>
              )}
            </div>
            <div className="flex items-center gap-3 min-h-[20px]">
              {questionRevealed ? (
                <p className="text-white/90 text-sm leading-snug truncate animate-fade-in">
                  {questions[currentQ] ?? 'Interview complete'}
                </p>
              ) : (
                <div className="flex items-center gap-3">
                  <p className="text-white/25 text-sm italic">Waiting for avatar to ask…</p>
                  <button
                    onClick={() => setRevealedIdx(currentQ)}
                    className="flex items-center gap-1.5 text-[10px] px-2.5 py-1 rounded-full border border-white/15 text-white/40 hover:text-white/70 hover:border-white/30 transition-all"
                  >
                    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                    Show now
                  </button>
                </div>
              )}
            </div>
          </div>
          <div className="flex items-center gap-3 flex-shrink-0">
            {/* Auto-advance toggle */}
            <button
              onClick={() => setAutoAdvance(v => !v)}
              title={autoAdvance ? 'Auto-advance ON — follows the avatar to the next question' : 'Auto-advance OFF — advance questions manually'}
              className={cn('flex items-center gap-1.5 px-3 h-10 rounded-full border text-[11px] font-semibold transition-all',
                autoAdvance ? 'border-[#3db36b]/50 bg-[#3db36b]/15 text-[#3db36b]' : 'border-white/20 bg-white/5 text-white/40 hover:text-white/70')}>
              <span className={cn('w-1.5 h-1.5 rounded-full', autoAdvance ? 'bg-[#3db36b] animate-pulse' : 'bg-white/40')} />
              Auto
            </button>
            <div className="w-px h-6 bg-white/10" />
            {[
              { label: '⏮', title: 'Previous question', action: prevQuestion, disabled: currentQ === 0 },
              { label: '⏹', title: 'End interview', action: handleEndInterview, cls: 'border-red-400/50 bg-red-500/15 text-red-400 hover:bg-red-500/25' },
              { label: '⏭', title: 'Next question', action: nextQuestion, disabled: false },
            ].map(b => (
              <button key={b.label} title={b.title} onClick={b.action} disabled={b.disabled}
                className={cn('w-10 h-10 rounded-full border border-white/20 bg-white/10 text-white flex items-center justify-center hover:bg-white/20 transition-all disabled:opacity-30 disabled:cursor-not-allowed', b.cls)}>
                {b.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Sidebar */}
      {!isFullscreen && (
        <div className="w-80 flex flex-col border-l border-white/10 bg-[#0a1628]">
          <div className="flex border-b border-white/10">
            {(['questions', 'live', 'transcript'] as SideTab[]).map(t => (
              <button key={t} onClick={() => setSideTab(t)}
                className={cn('flex-1 py-3 text-xs font-bold uppercase tracking-wider transition-all', sideTab === t ? 'text-[#f0c040] border-b-2 border-[#f0c040]' : 'text-white/40 hover:text-white/80')}>
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
                    className={cn('w-full flex gap-3 items-start p-3 rounded-xl text-left transition-all border', i === currentQ ? 'bg-[#f0c040]/10 border-[#f0c040]/30' : i < currentQ ? 'opacity-40 border-transparent' : 'border-transparent hover:bg-white/5')}>
                    <span className={cn('w-5 h-5 rounded text-xs font-black flex items-center justify-center flex-shrink-0 mt-0.5', i === currentQ ? 'bg-[#f0c040] text-[#0c1a2e]' : i < currentQ ? 'bg-[#0d5c3a] text-white' : 'bg-white/10 text-white/50')}>
                      {i < currentQ ? '✓' : i + 1}
                    </span>
                    <span className={cn('text-xs leading-relaxed transition-all duration-500', i === currentQ && !questionRevealed ? 'text-white/20 blur-[3px] select-none' : 'text-white/80')}>{q}</span>
                  </button>
                ))}
              </div>
            )}

            {/* Live AI panel */}
            {sideTab === 'live' && (
              <div className="space-y-4">
                {/* Hume status + emotion bars */}
                <div className="rounded-xl bg-hume-card border border-hume-border p-3 space-y-3">
                  <div className="flex items-center justify-between">
                    <p className="text-2xs font-mono text-hume-muted uppercase tracking-widest">Emotion Analysis</p>
                    <HumeStatusIndicator />
                  </div>
                  <LiveEmotionBar />
                  {/* Facial capture status (AWS Rekognition) — additive, status only */}
                  {facialCapture.status === 'active' && (
                    <div className="flex items-center gap-2 pt-1">
                      <span className="w-1.5 h-1.5 rounded-full bg-[#3db36b] animate-pulse" />
                      <span className="text-white/40 text-2xs">Facial: {facialCapture.frameCount} frames captured</span>
                    </div>
                  )}
                  {facialCapture.status === 'requesting_permission' && (
                    <div className="flex items-center gap-2 pt-1">
                      <span className="w-1.5 h-1.5 rounded-full bg-[#f0c040] animate-pulse" />
                      <span className="text-white/40 text-2xs">Facial: requesting camera…</span>
                    </div>
                  )}
                  {facialCapture.status === 'unavailable' && (
                    <div className="flex items-center gap-2 pt-1">
                      <span className="w-1.5 h-1.5 rounded-full bg-white/20" />
                      <span className="text-white/30 text-2xs">Facial: unavailable</span>
                    </div>
                  )}
                </div>

                {/* Legacy speech metrics — always shown */}
                <div className="grid grid-cols-2 gap-3">
                  {[['WPM', metrics.wpm.toString(), '#3db36b'], ['Fillers', metrics.fillers.toString(), '#8a8a8a']].map(([l, v, c]) => (
                    <div key={l} className="bg-white/5 border border-white/10 rounded-xl p-3">
                      <p className="text-xs text-white/40 uppercase tracking-wide mb-1">{l}</p>
                      <p className="font-head font-black text-2xl" style={{ color: c }}>{v}</p>
                    </div>
                  ))}
                </div>

                {/* Override input */}
                {liveConv?.properties?.apply_conversation_override && (
                  <div className="border-t border-white/10 pt-4">
                    <p className="text-xs text-[#f0c040] font-semibold uppercase tracking-wide mb-2">Override (say this now)</p>
                    <div className="flex gap-2">
                      <input value={overrideText} onChange={e => setOverrideText(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') sendOverride() }} placeholder="Type text for avatar to say…" className="flex-1 bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-xs text-white outline-none focus:border-[#f0c040]/60 placeholder-white/30" />
                      <button onClick={sendOverride} className="px-3 py-2 bg-[#f0c040] text-[#0c1a2e] text-xs font-bold rounded-lg hover:bg-yellow-300">Send</button>
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* Transcript panel */}
            {sideTab === 'transcript' && (
              <div className="space-y-3">
                {/* Deepgram status */}
                <div className="flex items-center justify-between text-[10px] pb-1 border-b border-white/10">
                  <span className="text-white/30 uppercase tracking-widest font-semibold">Deepgram Nova-3</span>
                  <span className={cn('flex items-center gap-1.5 font-semibold', dgConnected ? 'text-[#00ff9d]' : 'text-white/30')}>
                    <span className={cn('w-1.5 h-1.5 rounded-full', dgConnected ? 'bg-[#00ff9d] animate-pulse' : 'bg-white/20')} />
                    {dgConnected ? 'LIVE' : store.deepgramKey ? 'Connecting…' : 'No key'}
                  </span>
                </div>

                {/* Transcript entries */}
                <div ref={transcriptRef} className="space-y-2 max-h-[calc(100vh-380px)] overflow-y-auto">
                  {store.sessionTranscript.length === 0 && !interimText && (
                    <p className="text-xs text-white/25 text-center py-8 italic">
                      {dgConnected ? 'Listening — transcript will appear as you speak…' : 'Transcript requires a Deepgram API key in Settings.'}
                    </p>
                  )}
                  {store.sessionTranscript.map((t, i) => (
                    <div key={i} className="p-3 rounded-xl text-xs leading-relaxed bg-white/5 border border-white/10">
                      <div className="flex items-center justify-between mb-1">
                        <p className="text-[#f0c040] uppercase tracking-wide font-bold text-[9px]">Q{t.questionIdx + 1} · Candidate</p>
                        <p className="text-white/20 text-[9px] font-mono">{new Date(t.timestamp).toLocaleTimeString()}</p>
                      </div>
                      <p className="text-white/80">{t.text}</p>
                    </div>
                  ))}

                  {/* Live interim text */}
                  {interimText && (
                    <div className="p-3 rounded-xl text-xs leading-relaxed bg-white/5 border border-white/10 border-dashed opacity-60">
                      <p className="text-[#f0c040] uppercase tracking-wide font-bold text-[9px] mb-1">Typing…</p>
                      <p className="text-white/60 italic">{interimText}</p>
                    </div>
                  )}
                </div>

                {/* Stats strip */}
                {store.sessionTranscript.length > 0 && (
                  <div className="flex gap-4 pt-2 border-t border-white/10 text-[10px] text-white/30">
                    <span>{store.sessionTranscript.reduce((a, e) => a + e.text.split(/\s+/).filter(Boolean).length, 0)} words</span>
                    <span>{store.metrics.wpm} wpm</span>
                    <span>{store.metrics.fillers} fillers</span>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Status bar */}
          <div className="p-3 border-t border-white/10 flex items-center justify-between bg-[#091525]">
            <Badge variant={liveConv?.status === 'active' ? 'success' : 'neutral'}>{liveConv?.status ?? 'connecting'}</Badge>
            <button onClick={handleEndInterview} className="text-xs text-red-400 hover:text-red-300 font-semibold transition-colors">End Interview</button>
          </div>
        </div>
      )}
    </div>
  )
}
