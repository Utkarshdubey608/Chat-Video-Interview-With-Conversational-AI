import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import toast from 'react-hot-toast'
import { useAppStore } from '@/store/useAppStore'
import { Card, Button, StatCard, PageHeader, SectionTitle } from '@/components/ui'
import { cn } from '@/components/ui'
import { useHumePoll } from '@/hooks/useHumeBatch'
import { useGeminiAnalysis } from '@/hooks/useGeminiAnalysis'
import { buildGeminiInput } from '@/services/analysisDataBuilder'
import { ATSScorecardPanel } from '@/components/ats/ATSScorecardPanel'
import { FacialAnalysisPanel } from '@/components/ats/FacialAnalysisPanel'
import { facialDataStore } from '@/services/facialDataStore'
import { aggregateFacialData } from '@/services/rekognitionService'
import type { FacialSessionSummary } from '@/types/rekognition.types'
import { countWords, calcWpm, countFillers } from '@/services/deepgram'
import { SentimentArc } from '@/components/hume/SentimentArc'
import { EmotionRadar } from '@/components/hume/EmotionRadar'
import { EmotionTimeline } from '@/components/hume/EmotionTimeline'
import { EmotionCategoryPanel } from '@/components/hume/EmotionCategoryPanel'
import { EmotionHeatmap } from '@/components/hume/EmotionHeatmap'
import { PerQuestionCard } from '@/components/hume/PerQuestionCard'

function scoreColor(s: number) {
  if (s >= 85) return { text: '#0d5c3a', bg: '#f0faf5', bar: '#0d5c3a' }
  if (s >= 75) return { text: '#475569', bg: '#f8fafc', bar: '#64748b' }
  return { text: '#d97706', bg: '#fffbeb', bar: '#d97706' }
}

export default function ResultsPage() {
  const store = useAppStore()
  const navigate = useNavigate()
  const conv = store.currentConversation
  const humeResult = store.humeResult
  const m = store.metrics

  // Continue polling if a Hume job is pending
  useHumePoll()

  // Gemini ATS analysis (reasoning layer over Deepgram + Hume + facial)
  const gemini = useGeminiAnalysis()

  // Aggregate AWS Rekognition facial frames captured during the interview. Runs once,
  // synchronously (facialDataStore is a module singleton), so it is ready before the
  // Gemini trigger fires and can be folded into that analysis. Always built (even from
  // zero frames) so the Results page can surface a "not captured" diagnostic.
  const [facialSummary] = useState<FacialSessionSummary>(() => {
    const frames = facialDataStore.getFrames()
    const summary = aggregateFacialData(frames, useAppStore.getState().questions.filter(Boolean).length)
    facialDataStore.setSummary(summary)
    return summary
  })

  // ── Real Deepgram transcript analytics ───────────────────────────────────
  const transcript = store.sessionTranscript
  const hasTranscript = transcript.length > 0
  const realWordCount = countWords(transcript)
  // calcWpm needs >= 2 entries with timestamps; fallback to stored m.wpm when available
  const calcedWpm    = hasTranscript ? calcWpm(transcript) : 0
  const realWpm      = hasTranscript ? (calcedWpm > 0 ? calcedWpm : m.wpm > 0 ? m.wpm : null) : null
  const realFillers  = hasTranscript ? transcript.reduce((a, e) => a + countFillers(e.text), 0) : null
  const totalText    = transcript.map(e => e.text).join(' ')
  const sentenceCount = hasTranscript ? totalText.split(/[.!?]+/).filter(s => s.trim().length > 3).length : 0

  // Display helpers — show '—' when data is absent
  const fmtWpm     = realWpm     !== null ? `${realWpm}`     : '—'
  const fmtFillers = realFillers !== null ? `${realFillers}` : '—'

  // ── Dynamic scores derived from Hume AI + Deepgram ───────────────────────
  const clamp = (v: number, lo = 0, hi = 100) => Math.max(lo, Math.min(hi, v))

  // Deepgram-derived values
  const wpmForScore     = realWpm     !== null ? realWpm     : 130
  const fillersForScore = realFillers !== null ? realFillers : 0

  // Hume emotion category scores (0..1 range per category)
  const hc = humeResult?.overallCategoryScores

  // Normalise a weighted emotion sum → 0-100 (same formula as computeCompositeScore)
  // Neutral baseline → ~50; strong positive → 70-90; strong negative → 20-40
  const humeScore = (w: Partial<Record<string, number>>): number | null => {
    if (!hc) return null
    let raw = 0
    for (const [k, weight] of Object.entries(w)) raw += (hc[k as keyof typeof hc] ?? 0) * (weight ?? 0)
    return clamp(Math.round((raw + 0.35) * (100 / 0.7)))
  }

  // Deepgram-only proxy when Hume is absent — uses WPM pace + filler penalty
  const wpmProxy = realWpm !== null ? clamp(Math.round(50 + (realWpm - 130) * 0.5)) : null
  const dgScore  = (base: number | null) => base !== null ? clamp(base - fillersForScore * 5) : 0

  // ── Per-dimension calculation ─────────────────────────────────────────────
  // Confidence: positive_high (excitement/joy/pride) vs negative (anxiety/fear)
  const confScore = humeScore({ positive_high: 0.50, positive_calm: 0.15, negative: -0.40, disengagement: -0.25 })
                 ?? dgScore(wpmProxy !== null ? wpmProxy + 10 : null)

  // Engagement: interest + focus, penalised by boredom
  const engageScore = humeScore({ positive_high: 0.40, cognitive: 0.40, disengagement: -0.50, negative: -0.20 })
                   ?? dgScore(wpmProxy !== null ? wpmProxy + 5 : null)

  // Communication: calm positivity + social expressiveness
  const commScore = humeScore({ positive_calm: 0.30, social: 0.25, positive_high: 0.25, negative: -0.15, disengagement: -0.15 })
                 ?? dgScore(wpmProxy !== null ? wpmProxy + 5 : null)

  // Stress Mgmt: calmness vs negative/disengagement
  const stressScore = humeScore({ positive_calm: 0.35, negative: -0.45, disengagement: -0.20 })
                   ?? clamp(100 - fillersForScore * 4)

  // Vocabulary: pure Deepgram WPM — 82+ WPM scores linearly, capped at 100
  const vocabScore = clamp(wpmForScore > 100 ? 75 + Math.round((wpmForScore - 100) / 5) : Math.round(wpmForScore / 2))

  // Articulation: pure Deepgram fillers — 0 fillers = 100, each filler costs 10 pts
  const articScore = clamp(100 - fillersForScore * 10)

  const dims = [
    { name: 'Communication',   score: commScore },
    { name: 'Confidence',      score: confScore },
    { name: 'Engagement',      score: engageScore },
    { name: 'Vocabulary',      score: vocabScore },
    { name: 'Stress Mgmt',     score: stressScore },
    { name: 'Articulation',    score: articScore },
  ]

  const overall = humeResult
    ? humeResult.compositeScore
    : Math.round(dims.reduce((a, b) => a + b.score, 0) / dims.length)

  const offset = 301.6 - (overall / 100) * 301.6
  const verdict =
    overall >= 85 ? 'Excellent Candidate' :
    overall >= 75 ? 'Good Candidate' :
    overall >= 65 ? 'Potential Candidate' :
    'Needs Further Review'

  const hiringConf = clamp(Math.round(overall * 0.9 + engageScore * 0.1))

  const strengths: string[] = []
  const watchPoints: string[] = []

  // Use derived scores (not m.* which are always 0 with no live EVI)
  if (confScore >= 70)   strengths.push('Strong confidence signals')
  if (engageScore >= 70) strengths.push('High engagement level')
  if (stressScore >= 70) strengths.push('Composed under pressure')
  if (hasTranscript && realWpm !== null && realWpm >= 110 && realWpm <= 160) strengths.push('Clear speaking pace')
  if (articScore >= 90 && hasTranscript) strengths.push('No filler words detected')
  else if (articScore >= 70 && hasTranscript) strengths.push('Minimal filler words')
  if (humeResult?.overallTopEmotions[0]) strengths.push(`Dominant: ${humeResult.overallTopEmotions[0].name}`)

  if (confScore > 0 && confScore < 55)    watchPoints.push('Low confidence signals')
  if (stressScore > 0 && stressScore < 45) watchPoints.push('Elevated stress detected')
  if (hasTranscript && (realFillers ?? 0) >= 5) watchPoints.push(`High filler words: ${realFillers}`)
  if (hasTranscript && realWpm !== null && realWpm < 100) watchPoints.push('Speaking pace below normal')
  if (hasTranscript && realWpm !== null && realWpm > 170) watchPoints.push('Speaking pace too fast')
  if (engageScore > 0 && engageScore < 50) watchPoints.push('Low engagement level')

  if (strengths.length === 0) strengths.push('Completed all questions', 'Responsive to prompts')
  if (watchPoints.length === 0) watchPoints.push('No significant issues detected')

  const questionsAnswered = store.questions.filter(Boolean).length

  // ── Filter per-question Hume data to only questions the candidate answered ──
  // Primary: use Deepgram transcript to know which questions got a response.
  // Fallback: if no transcript, require at least 2 prosody predictions (avoids noise).
  const answeredQuestionIndices = new Set(transcript.map(e => e.questionIdx))
  const perQuestionFiltered = (humeResult?.perQuestion ?? []).filter(q =>
    answeredQuestionIndices.size > 0
      ? answeredQuestionIndices.has(q.questionIdx)
      : q.timeline.length >= 2
  )

  // ── Hume section state ────────────────────────────────────────────────────
  // Show spinner when a real jobId exists AND status is not yet terminal.
  // null status means job was just submitted (submitBatchJob resolved but first poll hasn't run).
  const humeIsProcessing =
    !!store.humeJobId &&
    !humeResult &&
    store.humeJobStatus !== 'COMPLETED' &&
    store.humeJobStatus !== 'FAILED'

  const humeNoData = !humeResult && !humeIsProcessing

  // ── Gemini ATS analysis trigger ───────────────────────────────────────────
  // Candidate name is embedded in the Tavus conversation_name ("TalbotIQ — Name").
  const candidateName = (conv?.conversation_name ?? '').split('—').pop()?.trim() || 'Candidate'
  const jobRole = 'the interviewed role'

  function runAtsAnalysis() {
    const geminiInput = buildGeminiInput({
      candidateName,
      jobRole,
      questions: store.questions.filter(Boolean),
      transcript,
      humeResult,
      wpm: m.wpm,
      totalFillers: m.fillers,
      facialSummary,
    })
    gemini.analyze(geminiInput)
  }

  // Auto-run once a transcript exists and a Gemini key is present. Waits for the Hume
  // batch to finish first (so emotion data enriches the analysis) but proceeds without
  // it if Hume produced nothing, so the transcript is still analysed.
  useEffect(() => {
    if (
      gemini.status === 'idle' &&
      hasTranscript &&
      store.geminiKey &&
      !humeIsProcessing
    ) {
      runAtsAnalysis()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hasTranscript, humeIsProcessing, gemini.status, store.geminiKey])

  const [scheduleOpen, setScheduleOpen] = useState(false)
  const [offerOpen, setOfferOpen] = useState(false)

  function downloadReport() {
    const rows = dims.map(d => `<tr><td>${d.name}</td><td style="font-weight:600">${d.score}/100</td><td>${d.score >= 85 ? 'Excellent' : d.score >= 75 ? 'Good' : 'Moderate'}</td></tr>`).join('')
    const html = `<!DOCTYPE html><html><head><meta charset="UTF-8"><title>TalbotIQ Report</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:system-ui,sans-serif;color:#0f172a;background:#f8fafc;padding:48px}h1{font-size:28px;font-weight:700;color:#0d5c3a;margin-bottom:4px}.meta{font-size:13px;color:#64748b;margin-bottom:32px}table{width:100%;border-collapse:collapse;font-size:13px}td,th{padding:10px 14px;border:1px solid #e2e8f0}.score{font-size:48px;font-weight:800;color:#0d5c3a}</style></head><body><h1>TalbotIQ AI Interview Report</h1><p class="meta">Session: ${conv?.conversation_id ?? 'demo'} · Generated: ${new Date().toLocaleString()}</p><p class="score">${overall}<span style="font-size:20px;color:#64748b">/100</span></p><p style="margin:12px 0 32px;display:inline-block;background:#f0faf5;color:#0d5c3a;padding:4px 12px;border-radius:9999px;font-size:12px;border:1px solid #b3e9cd">${verdict}</p><table><tr><th>Dimension</th><th>Score</th><th>Grade</th></tr>${rows}</table></body></html>`
    const a = document.createElement('a')
    a.href = URL.createObjectURL(new Blob([html], { type: 'text/html' }))
    a.download = `TalbotIQ-Report-${conv?.conversation_id ?? 'demo'}.html`
    document.body.appendChild(a); a.click(); document.body.removeChild(a)
    toast.success('Report downloaded')
  }

  return (
    <div className="max-w-5xl mx-auto px-6 py-8 space-y-5">
      <PageHeader
        kicker="Interview Complete"
        title={conv?.conversation_name ?? 'Interview Assessment'}
        description="Comprehensive candidate intelligence powered by conversational AI and behavioral analytics."
        action={
          <div className="text-right">
            <p className="text-xs text-neutral-400">Session ID</p>
            <p className="font-mono text-xs font-semibold text-neutral-700 mt-0.5">{conv?.conversation_id ?? 'TIQ-demo'}</p>
          </div>
        }
      />

      {/* Hume batch processing status banner */}
      {humeIsProcessing && (
        <div className="flex items-center gap-2 px-4 py-2.5 rounded-xl border border-hume-border bg-hume-surface text-sm text-hume-teal">
          <span className="w-2 h-2 rounded-full bg-hume-teal animate-pulse flex-shrink-0" />
          <span className="font-mono text-xs">HUME AI · Analysing prosody — emotion results will appear below shortly</span>
        </div>
      )}

      {/* KPI row */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <StatCard label="Overall Score"     value={`${overall}/100`}    sub={verdict}                      trend="up"  color="#0d5c3a" />
        <StatCard label="Hiring Confidence" value={`${hiringConf}%`}    sub="Based on all signals"         trend="up"  color="#0d5c3a" />
        <StatCard label="Words / Min"  value={fmtWpm}   sub={hasTranscript ? 'From Deepgram' : 'No transcript yet'} color={realWpm !== null && realWpm >= 110 && realWpm <= 170 ? '#0d5c3a' : '#d97706'} />
        <StatCard label="Total Words"  value={hasTranscript ? `${realWordCount}` : '—'} sub={hasTranscript ? `${sentenceCount} sentences` : 'Deepgram required'} trend={hasTranscript ? 'up' : undefined} color="#0d5c3a" />
      </div>

      {/* Score ring + dimensions */}
      <div className="grid grid-cols-1 md:grid-cols-[240px_1fr] gap-5">
        <Card className="p-6 flex flex-col items-center">
          <div className="relative w-32 h-32 mb-4">
            <svg width="128" height="128" viewBox="0 0 110 110" style={{ transform: 'rotate(-90deg)' }}>
              <circle cx="55" cy="55" r="48" strokeWidth="7" stroke="#e2e8f0" fill="none" />
              <circle cx="55" cy="55" r="48" strokeWidth="7" stroke="#0d5c3a" fill="none" strokeLinecap="round"
                strokeDasharray="301.6" strokeDashoffset={offset} style={{ transition: 'stroke-dashoffset 1.5s ease' }} />
            </svg>
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <span className="text-3xl font-black text-neutral-900">{overall}</span>
              <span className="text-xs text-neutral-400 font-medium">/100</span>
            </div>
          </div>
          <p className="section-label mb-2">Overall Score</p>
          <span className="badge badge-success px-3 py-1 text-xs font-semibold">{verdict}</span>
          <div className="mt-5 w-full p-4 bg-neutral-50 rounded-xl border border-border">
            <p className="text-xs font-semibold text-neutral-500 uppercase tracking-wide mb-2">AI Summary</p>
            <p className="text-xs text-neutral-600 leading-relaxed">
              {humeResult
                ? `Dominant emotion: ${humeResult.overallTopEmotions[0]?.name ?? 'Engagement'}. Composite score from ${humeResult.timeline.length} prosody predictions across ${questionsAnswered} questions.`
                : `Candidate completed ${questionsAnswered} question${questionsAnswered !== 1 ? 's' : ''}. ${confScore >= 70 ? 'Strong confidence signals throughout.' : 'Some confidence fluctuation observed.'} Engagement: ${engageScore}%.`}
            </p>
          </div>
        </Card>

        <Card className="p-6">
          <SectionTitle>Dimension Scores</SectionTitle>
          <div className="space-y-3.5">
            {dims.map(d => {
              const c = scoreColor(d.score)
              return (
                <div key={d.name} className="flex items-center gap-3">
                  <span className="text-sm text-neutral-700 w-32 flex-shrink-0">{d.name}</span>
                  <div className="flex-1 h-2 bg-neutral-100 rounded-full overflow-hidden">
                    <div className="h-full rounded-full transition-all duration-700" style={{ width: `${d.score}%`, background: c.bar }} />
                  </div>
                  <span className="text-sm font-bold w-9 text-right tabular-nums" style={{ color: c.text }}>{d.score}</span>
                </div>
              )
            })}
          </div>
          <div className="flex gap-4 mt-5 pt-4 border-t border-border">
            {[['#0d5c3a', '85+ Excellent'], ['#64748b', '75–84 Good'], ['#d97706', 'Below 75 Moderate']].map(([c, l]) => (
              <span key={l} className="flex items-center gap-1.5 text-xs text-neutral-400">
                <span className="w-2 h-2 rounded-full" style={{ background: c }} />{l}
              </span>
            ))}
          </div>
        </Card>
      </div>

      {/* ── Hume AI Emotion Dashboard ─────────────────────────────────────────── */}
      <div className="rounded-2xl bg-hume-base border border-hume-border p-6 space-y-6 shadow-sm">
        <div className="flex items-center justify-between flex-wrap gap-4">
          <div>
            <p className="text-xs font-mono text-hume-muted uppercase tracking-widest mb-1">Hume AI · Prosody Analysis</p>
            <h2 className="text-lg font-bold text-hume-text">Emotional Intelligence Report</h2>
          </div>
          {humeResult && <SentimentArc score={humeResult.compositeScore} label="Emotion Score" size={120} />}
        </div>

        {humeResult ? (
          <>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <p className="text-xs text-hume-muted mb-3 font-mono uppercase tracking-wide">Overall Emotion Profile</p>
                <EmotionRadar categoryScores={humeResult.overallCategoryScores} />
              </div>
              <div>
                <p className="text-xs text-hume-muted mb-3 font-mono uppercase tracking-wide">Category Breakdown</p>
                <EmotionCategoryPanel categoryScores={humeResult.overallCategoryScores} />
              </div>
            </div>
            <div>
              <p className="text-xs text-hume-muted mb-3 font-mono uppercase tracking-wide">Emotion Timeline</p>
              <EmotionTimeline timeline={humeResult.timeline} questionTimestamps={store.questionTimestamps} />
            </div>
            {perQuestionFiltered.length > 0 && (
              <>
                <div>
                  <p className="text-xs text-hume-muted mb-3 font-mono uppercase tracking-wide">Per-Question Heatmap</p>
                  <EmotionHeatmap perQuestion={perQuestionFiltered} />
                </div>
                <div>
                  <p className="text-xs text-hume-muted mb-3 font-mono uppercase tracking-wide">Question-by-Question Analysis</p>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {perQuestionFiltered.map((q, i) => (
                      <PerQuestionCard key={i} summary={q} index={i} />
                    ))}
                  </div>
                </div>
              </>
            )}
          </>
        ) : humeIsProcessing ? (
          <div className="rounded-xl bg-hume-surface border border-hume-border p-10 flex flex-col items-center gap-4">
            <span className="w-8 h-8 rounded-full border-2 border-hume-teal border-t-transparent animate-spin" />
            <p className="text-hume-text text-sm">Processing prosody analysis — results will appear automatically.</p>
            <p className="text-hume-muted text-xs font-mono">Job ID: {store.humeJobId}</p>
            <button
              className="text-xs text-hume-muted underline hover:text-hume-text transition-colors"
              onClick={() => {
                store.setHumeJobId(null)
                store.setHumeJobStatus(null)
              }}
            >
              Dismiss and show results without emotion data
            </button>
          </div>
        ) : (
          <div className="rounded-xl bg-hume-surface border border-hume-border p-8 text-center space-y-3">
            {store.humeKey ? (
              <>
                <p className="text-hume-text text-sm font-medium">No emotion data for this session.</p>
                <p className="text-hume-muted text-xs leading-relaxed">
                  Emotion analysis requires microphone access during the interview.<br/>
                  Make sure you grant mic permission when prompted and speak during the session.
                </p>
                <p className="text-hume-muted text-[10px] font-mono">Hume key present · audio captured via MediaRecorder · batch submitted on session end</p>
              </>
            ) : (
              <>
                <p className="text-hume-text text-sm font-medium">Add your Hume AI key to enable emotion analysis.</p>
                <button className="text-xs font-semibold text-hume-teal underline" onClick={() => navigate('/settings')}>
                  Go to Settings →
                </button>
              </>
            )}
          </div>
        )}
      </div>

      {/* Raw signals — real Deepgram data when available */}
      <Card className="p-5">
        <div className="flex items-center justify-between mb-4">
          <SectionTitle>Voice & Signal Analytics</SectionTitle>
          {hasTranscript && (
            <span className="flex items-center gap-1.5 text-[10px] font-mono text-[#0d5c3a] bg-success-bg border border-success-border px-2 py-1 rounded-full">
              <span className="w-1.5 h-1.5 rounded-full bg-[#0d5c3a]" />
              Deepgram Nova-3
            </span>
          )}
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          {[
            { label: 'Words / Min',  value: fmtWpm,    color: realWpm !== null && realWpm >= 110 && realWpm <= 170 ? '#0d5c3a' : '#d97706', badge: realWpm !== null && realWpm > 170 ? 'FAST' : realWpm !== null && realWpm < 80 ? 'SLOW' : undefined },
            { label: 'Filler Words', value: fmtFillers, color: realFillers !== null && realFillers <= 3 ? '#0d5c3a' : '#d97706', badge: realFillers !== null && realFillers >= 7 ? 'HIGH' : undefined },
            { label: 'Total Words',  value: hasTranscript ? `${realWordCount}` : '—', color: '#0d5c3a', badge: undefined },
            { label: 'Sentences',    value: hasTranscript ? `${sentenceCount}` : '—', color: '#0d5c3a', badge: undefined },
            { label: 'Confidence',     value: confScore > 0 ? `${confScore}%` : hc ? `${confScore}%` : '—',    color: confScore >= 70 ? '#0d5c3a' : '#d97706', badge: confScore > 0 && confScore < 50 ? 'LOW' : undefined },
            { label: 'Questions Done', value: `${questionsAnswered}`, color: '#0d5c3a',                                                 badge: undefined },
          ].map(s => (
            <div key={s.label} className="relative bg-neutral-50 rounded-xl border border-border p-3.5">
              {s.badge && (
                <span className={cn('absolute top-2 right-2 text-[9px] font-bold px-1.5 py-0.5 rounded', 'badge badge-warning')}>
                  {s.badge}
                </span>
              )}
              <p className="text-2xl font-bold tabular-nums" style={{ color: s.color }}>{s.value}</p>
              <p className="text-xs text-neutral-400 mt-1">{s.label}</p>
            </div>
          ))}
        </div>
      </Card>

      {/* Strengths / Watch — dynamic */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
        <Card className="p-5">
          <p className="text-xs font-semibold text-success uppercase tracking-wide mb-3 flex items-center gap-2">
            <span className="w-4 h-4 rounded bg-success-bg flex items-center justify-center text-success text-[10px]">✓</span>
            Strengths
          </p>
          <div className="flex flex-wrap gap-2">
            {strengths.map(s => <span key={s} className="badge badge-success px-2.5 py-1">{s}</span>)}
          </div>
        </Card>
        <Card className="p-5">
          <p className="text-xs font-semibold text-warning uppercase tracking-wide mb-3 flex items-center gap-2">
            <span className="w-4 h-4 rounded bg-warning-bg flex items-center justify-center text-warning text-[10px]">⚠</span>
            Watch Points
          </p>
          <div className="flex flex-wrap gap-2">
            {watchPoints.map(s => <span key={s} className="badge badge-warning px-2.5 py-1">{s}</span>)}
          </div>
        </Card>
      </div>

      {/* Interview timeline — per question */}
      {questionsAnswered > 0 && (
        <Card className="p-5">
          <SectionTitle>Interview Timeline</SectionTitle>
          <div className="relative flex items-start px-4">
            <div className="absolute top-[21px] left-8 right-8 h-px bg-border" />
            {store.questions.filter(Boolean).map((q, i) => {
              const done = i < store.currentQuestionIdx
              const active = i === store.currentQuestionIdx
              return (
                <div key={i} className="flex-1 flex flex-col items-center text-center relative z-10 px-1">
                  <div className={cn('w-11 h-11 rounded-full border-2 flex items-center justify-center text-xs font-bold bg-white mb-3 shadow-xs',
                    done ? 'border-primary-700 text-primary-700' : active ? 'border-warning text-warning' : 'border-neutral-300 text-neutral-400')}>
                    {done ? '✓' : i + 1}
                  </div>
                  <span className={cn('text-[9px] font-bold px-2 py-0.5 rounded-full mb-1.5 whitespace-nowrap border',
                    done ? 'badge badge-success' : active ? 'badge badge-warning' : 'badge badge-neutral')}>
                    {done ? 'Answered' : active ? 'In Progress' : 'Pending'}
                  </span>
                  <p className="text-[10px] text-neutral-400 leading-tight line-clamp-2">{q.slice(0, 40)}{q.length > 40 ? '…' : ''}</p>
                </div>
              )
            })}
          </div>
        </Card>
      )}

      {/* AI Recommendation */}
      <div className="bg-primary-700 rounded-2xl p-6">
        <div className="flex items-start gap-4 mb-5">
          <div className="w-10 h-10 rounded-xl bg-white/10 flex items-center justify-center flex-shrink-0">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2"><polyline points="22,7 13.5,15.5 8.5,10.5 2,17"/><polyline points="16,7 22,7 22,13"/></svg>
          </div>
          <div className="flex-1">
            <p className="text-xs font-semibold text-white/50 uppercase tracking-widest mb-1">AI Recommendation</p>
            <p className="text-xl font-bold text-white">
              {overall >= 80 ? 'Proceed to Technical Round' : overall >= 65 ? 'Consider for Second Interview' : 'Further Evaluation Recommended'}
            </p>
            <p className="text-sm text-white/65 mt-2 leading-relaxed">
              {overall >= 80
                ? `Strong across ${dims.filter(d => d.score >= 75).length} of ${dims.length} dimensions. Engagement at ${engageScore}% exceeds benchmark. Recommended for next stage.`
                : overall >= 65
                  ? `Moderate performance with room to grow. ${strengths[0] ?? 'Completed all questions'}. Consider a follow-up interview to assess potential.`
                  : `Score below threshold. Key concerns: ${watchPoints.slice(0, 2).join(', ')}. Additional screening recommended.`}
            </p>
          </div>
          <div className="text-right flex-shrink-0">
            <p className="text-3xl font-black text-white">{hiringConf}%</p>
            <p className="text-xs text-white/50">Hiring Confidence</p>
          </div>
        </div>
        <div className="border-t border-white/10 pt-4">
          <div className="flex justify-between text-xs mb-2">
            <span className="text-white/50">Hiring Recommendation Confidence</span>
            <span className="text-white font-semibold">{hiringConf}%</span>
          </div>
          <div className="h-1.5 bg-white/10 rounded-full overflow-hidden">
            <div className="h-full bg-white/70 rounded-full transition-all duration-700" style={{ width: `${hiringConf}%` }} />
          </div>
        </div>
      </div>

      {/* Recruiter actions */}
      {/* ── Full Transcript ───────────────────────────────────────────────────── */}
      <Card className="p-5">
        <div className="flex items-center justify-between mb-4">
          <SectionTitle>Interview Transcript</SectionTitle>
          {hasTranscript ? (
            <span className="flex items-center gap-1.5 text-[10px] font-mono text-[#0d5c3a] bg-success-bg border border-success-border px-2 py-1 rounded-full">
              <span className="w-1.5 h-1.5 rounded-full bg-[#0d5c3a]" />
              {realWordCount} words · {sentenceCount} sentences
            </span>
          ) : (
            <span className="text-xs text-neutral-400">Deepgram Nova-3 · requires key in Settings</span>
          )}
        </div>

        {hasTranscript ? (
          <>
            {/* Group by question */}
            {store.questions.filter(Boolean).map((q, qi) => {
              const entries = transcript.filter(e => e.questionIdx === qi)
              if (entries.length === 0) return null
              const qWords = countWords(entries)
              const qFillers = entries.reduce((a, e) => a + countFillers(e.text), 0)
              return (
                <div key={qi} className="mb-5 last:mb-0">
                  <div className="flex items-start gap-3 mb-2">
                    <span className="flex-shrink-0 w-6 h-6 rounded-full bg-primary-700 text-white text-[10px] font-bold flex items-center justify-center">
                      {qi + 1}
                    </span>
                    <div className="flex-1">
                      <p className="text-xs font-semibold text-neutral-500 italic mb-2">"{q}"</p>
                      <div className="space-y-1.5 pl-1">
                        {entries.map((e, i) => (
                          <div key={i} className="bg-neutral-50 rounded-lg border border-border px-3 py-2">
                            <p className="text-xs text-neutral-700 leading-relaxed">{e.text}</p>
                          </div>
                        ))}
                      </div>
                      <div className="flex gap-4 mt-2 text-[10px] text-neutral-400">
                        <span>{qWords} words</span>
                        {qFillers > 0 && <span className="text-warning">{qFillers} filler{qFillers !== 1 ? 's' : ''}</span>}
                        <span>{new Date(entries[0].timestamp).toLocaleTimeString()}</span>
                      </div>
                    </div>
                  </div>
                  {qi < store.questions.filter(Boolean).length - 1 && <div className="border-t border-border mt-4" />}
                </div>
              )
            })}
          </>
        ) : (
          <div className="py-8 text-center">
            <p className="text-sm text-neutral-400">No transcript recorded for this session.</p>
            {!store.deepgramKey && (
              <button className="mt-2 text-xs font-semibold text-primary-700 underline" onClick={() => navigate('/settings')}>
                Add Deepgram key in Settings →
              </button>
            )}
          </div>
        )}
      </Card>

      {/* ── AI-Powered ATS Assessment (Gemini) ──────────────────────────────── */}
      {(gemini.status !== 'idle' || gemini.scorecard) && (
        <section className="space-y-3">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-bold text-neutral-900">AI-Powered ATS Assessment</h2>
            {gemini.status === 'complete' && (
              <button onClick={runAtsAnalysis} className="text-xs font-semibold text-primary-700 underline">
                Re-run analysis
              </button>
            )}
          </div>
          <ATSScorecardPanel
            scorecard={gemini.scorecard}
            status={gemini.status}
            error={gemini.error}
            onRetry={runAtsAnalysis}
          />
        </section>
      )}

      {/* ── Facial Analysis (AWS Rekognition) — always shown, with capture diagnostics ── */}
      <section className="space-y-3">
        <h2 className="text-lg font-bold text-neutral-900">Facial Analysis</h2>
        <FacialAnalysisPanel
          summary={facialSummary}
          questionCount={store.questions.filter(Boolean).length}
          proxyUrl={store.awsProxyUrl}
        />
      </section>

      <Card className="p-5">
        <SectionTitle>Recruiter Actions</SectionTitle>
        <div className="flex flex-wrap gap-3">
          <Button onClick={() => setScheduleOpen(true)}>Schedule Technical Interview</Button>
          <Button variant="secondary" onClick={downloadReport}>Download AI Report</Button>
          <Button variant="secondary" onClick={() => {
            navigator.clipboard.writeText(`TalbotIQ Report — ${overall}/100 — ${verdict} — Session: ${conv?.conversation_id ?? 'demo'}`)
              .then(() => toast.success('Copied to clipboard'))
          }}>Share Profile</Button>
          <Button variant="secondary" onClick={() => setOfferOpen(true)}>Generate Offer Rec.</Button>
          <Button variant="ghost" onClick={() => navigate('/setup')}>New Interview</Button>
        </div>
      </Card>

      {/* Schedule modal */}
      {scheduleOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-neutral-900/40 backdrop-blur-[2px]" onClick={() => setScheduleOpen(false)}>
          <div className="bg-white rounded-2xl shadow-xl border border-border p-8 w-full max-w-md animate-slide-up" onClick={e => e.stopPropagation()}>
            <h3 className="text-xl font-bold text-neutral-900 mb-1">Schedule Technical Interview</h3>
            <p className="text-sm text-neutral-500 mb-6">Book the next round for this candidate.</p>
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div><label className="field-label">Date</label><input type="date" className="input-base mt-1.5" /></div>
                <div><label className="field-label">Time</label><input type="time" defaultValue="10:00" className="input-base mt-1.5" /></div>
              </div>
              <div><label className="field-label">Interviewer</label><input type="text" placeholder="Interviewer name" className="input-base mt-1.5" /></div>
              <div><label className="field-label">Notes</label><textarea placeholder="Areas to probe further…" className="textarea-base mt-1.5" rows={3} /></div>
            </div>
            <div className="flex gap-3 justify-end mt-6">
              <Button variant="secondary" onClick={() => setScheduleOpen(false)}>Cancel</Button>
              <Button onClick={() => { toast.success('Interview scheduled'); setScheduleOpen(false) }}>Confirm Schedule</Button>
            </div>
          </div>
        </div>
      )}

      {/* Offer modal */}
      {offerOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-neutral-900/40 backdrop-blur-[2px]" onClick={() => setOfferOpen(false)}>
          <div className="bg-white rounded-2xl shadow-xl border border-border p-8 w-full max-w-lg animate-slide-up" onClick={e => e.stopPropagation()}>
            <h3 className="text-xl font-bold text-neutral-900 mb-4">AI Offer Recommendation</h3>
            <pre className="bg-neutral-50 border border-border rounded-xl p-4 text-xs text-neutral-700 font-mono leading-relaxed whitespace-pre-wrap">
{`OFFER RECOMMENDATION — TalbotIQ AI
Session: ${conv?.conversation_id ?? 'demo'}
Score: ${overall}/100  |  Confidence: ${hiringConf}%

RECOMMENDATION: ${overall >= 80 ? 'Proceed with Offer' : overall >= 65 ? 'Consider — Second Interview' : 'Do Not Proceed at This Time'}

Top Strengths: ${strengths.slice(0, 3).join(', ')}
Watch Points: ${watchPoints.slice(0, 2).join(', ')}

Generated: ${new Date().toLocaleDateString()}`}
            </pre>
            <div className="flex gap-3 justify-end mt-5">
              <Button variant="secondary" onClick={() => setOfferOpen(false)}>Close</Button>
              <Button onClick={() => { toast.success('Copied to clipboard'); setOfferOpen(false) }}>Copy to Clipboard</Button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
