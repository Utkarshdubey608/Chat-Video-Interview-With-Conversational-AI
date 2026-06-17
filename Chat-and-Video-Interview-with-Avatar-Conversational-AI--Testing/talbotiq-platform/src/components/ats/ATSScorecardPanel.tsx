// src/components/ats/ATSScorecardPanel.tsx
// Displays the Gemini ATS scorecard — LIGHT theme, matching the current ResultsPage
// (white cards, primary green #0d5c3a, amber #d97706, red #dc2626).

import { Card, SectionTitle } from '@/components/ui'
import type { ATSScorecard, ScoredDimension, EvidenceLevel } from '@/services/geminiAnalysis'

interface Props {
  scorecard: ATSScorecard | null
  status: 'idle' | 'analyzing' | 'complete' | 'error'
  error: string | null
  onRetry?: () => void
}

const evidenceStyle: Record<EvidenceLevel, { bg: string; text: string; border: string }> = {
  strong:       { bg: '#f0faf5', text: '#0d5c3a', border: '#b3e9cd' },
  moderate:     { bg: '#eff6ff', text: '#2563eb', border: '#bfdbfe' },
  weak:         { bg: '#fffbeb', text: '#d97706', border: '#fde68a' },
  insufficient: { bg: '#fef2f2', text: '#dc2626', border: '#fecaca' },
}

const recStyle: Record<string, { bg: string; text: string; border: string }> = {
  'Advance':           { bg: '#f0faf5', text: '#0d5c3a', border: '#b3e9cd' },
  'Hold':              { bg: '#fffbeb', text: '#b45309', border: '#fde68a' },
  'Decline':           { bg: '#fef2f2', text: '#dc2626', border: '#fecaca' },
  'Insufficient Data': { bg: '#f8fafc', text: '#64748b', border: '#e2e8f0' },
}

function Badge({ level, children }: { level: EvidenceLevel; children: React.ReactNode }) {
  const s = evidenceStyle[level]
  return (
    <span className="text-[10px] font-semibold px-2 py-0.5 rounded-full border"
      style={{ background: s.bg, color: s.text, borderColor: s.border }}>
      {children}
    </span>
  )
}

function barColor(score: number) {
  return score >= 7 ? '#0d5c3a' : score >= 4 ? '#d97706' : '#dc2626'
}

function DimensionRow({ label, dim }: { label: string; dim: ScoredDimension }) {
  if (!dim) return null
  if (dim.cannotAssess) {
    return (
      <div className="flex items-start gap-3 py-3 border-b border-border last:border-0">
        <div className="w-32 text-sm text-neutral-600 flex-shrink-0">{label}</div>
        <div className="flex-1">
          <Badge level="insufficient">Cannot Assess</Badge>
          {dim.cannotAssessReason && <p className="text-xs text-neutral-400 mt-1">{dim.cannotAssessReason}</p>}
        </div>
      </div>
    )
  }
  return (
    <div className="py-3 border-b border-border last:border-0">
      <div className="flex items-center gap-3 mb-1">
        <div className="w-32 text-sm text-neutral-700 flex-shrink-0">{label}</div>
        <div className="flex-1 h-2 bg-neutral-100 rounded-full overflow-hidden">
          <div className="h-full rounded-full transition-all duration-700"
            style={{ width: `${(dim.score / 10) * 100}%`, background: barColor(dim.score) }} />
        </div>
        <div className="w-10 text-right text-sm font-mono font-bold" style={{ color: barColor(dim.score) }}>
          {dim.score}/10
        </div>
        <Badge level={dim.evidenceLevel}>{dim.evidenceLevel}</Badge>
      </div>
      {dim.evidenceSummary && <p className="text-xs text-neutral-500 ml-32 pl-3">{dim.evidenceSummary}</p>}
      {dim.quotes?.length > 0 && (
        <div className="ml-32 pl-3 mt-1 space-y-0.5">
          {dim.quotes.map((q, i) => <p key={i} className="text-xs text-neutral-400 italic">"{q}"</p>)}
        </div>
      )}
      {dim.flags?.length > 0 && (
        <div className="ml-32 pl-3 mt-1 flex flex-wrap gap-1">
          {dim.flags.map((f, i) => (
            <span key={i} className="text-[10px] px-1.5 py-0.5 rounded bg-neutral-100 text-neutral-500">{f}</span>
          ))}
        </div>
      )}
    </div>
  )
}

export function ATSScorecardPanel({ scorecard, status, error, onRetry }: Props) {
  if (status === 'idle') return null

  if (status === 'analyzing') {
    return (
      <Card className="p-6">
        <div className="flex items-center gap-2 mb-1">
          <span className="w-2 h-2 rounded-full bg-primary-600 animate-pulse" />
          <h3 className="text-sm font-semibold text-neutral-800">Gemini ATS Analysis running…</h3>
        </div>
        <p className="text-xs text-neutral-400">
          Reasoning over the transcript, emotion signals, and communication quality. This takes 10–25 seconds.
        </p>
      </Card>
    )
  }

  if (status === 'error' || (error && !scorecard)) {
    return (
      <Card className="p-6 border-danger-border">
        <h3 className="text-sm font-semibold text-danger mb-1">ATS Analysis Error</h3>
        <p className="text-xs text-neutral-600">{error}</p>
        {onRetry && (
          <button onClick={onRetry} className="mt-3 text-xs font-semibold text-primary-700 underline">
            Retry analysis
          </button>
        )}
      </Card>
    )
  }

  if (!scorecard) return null

  const rec = recStyle[scorecard.hiringRecommendation] ?? recStyle['Insufficient Data']

  return (
    <div className="space-y-5">
      {/* Overall */}
      <Card className="p-6">
        <div className="flex items-start justify-between mb-4">
          <div>
            <SectionTitle>ATS Analysis Report</SectionTitle>
            <p className="text-xs text-neutral-400 mt-1">Gemini · Deepgram Nova-3 · Hume AI</p>
          </div>
          <span className="px-3 py-1.5 rounded-lg border text-sm font-semibold"
            style={{ background: rec.bg, color: rec.text, borderColor: rec.border }}>
            {scorecard.hiringRecommendation}
          </span>
        </div>
        <div className="flex items-center gap-6">
          <div className="text-center flex-shrink-0">
            <div className="text-5xl font-mono font-bold text-neutral-900">{scorecard.overallFitScore ?? '—'}</div>
            <div className="text-neutral-400 text-xs mt-1">Overall Fit</div>
          </div>
          <div className="flex-1">
            <div className="flex items-center gap-2 mb-2 flex-wrap">
              <span className="text-neutral-700 text-sm font-medium">{scorecard.overallFitLabel}</span>
              <Badge level={scorecard.overallConfidenceLevel}>{scorecard.overallConfidenceLevel} confidence</Badge>
            </div>
            <p className="text-neutral-500 text-sm leading-relaxed">{scorecard.hiringRecommendationRationale}</p>
          </div>
        </div>
        {scorecard.inputDataQuality !== 'high' && (
          <div className="mt-4 p-3 rounded-lg bg-warning-bg border border-warning-border">
            <p className="text-amber-800 text-xs">
              ⚠ Input data quality: <strong>{scorecard.inputDataQuality}</strong> — {scorecard.transcriptReliabilityNote}
            </p>
          </div>
        )}
      </Card>

      {/* Dimension scores */}
      <Card className="p-6">
        <SectionTitle>Gemini Dimension Scores</SectionTitle>
        <div className="mt-3">
          <DimensionRow label="Communication" dim={scorecard.communicationScore} />
          <DimensionRow label="Technical Depth" dim={scorecard.technicalDepthScore} />
          <DimensionRow label="Problem Solving" dim={scorecard.problemSolvingScore} />
          <DimensionRow label="Engagement" dim={scorecard.engagementScore} />
          <DimensionRow label="Consistency" dim={scorecard.consistencyScore} />
        </div>
      </Card>

      {/* Per-question */}
      {scorecard.perQuestionAnalysis?.length > 0 && (
        <Card className="p-6">
          <SectionTitle>Per-Question Analysis</SectionTitle>
          <div className="space-y-3 mt-3">
            {scorecard.perQuestionAnalysis.map(qa => {
              const tq: EvidenceLevel = qa.transcriptQuality === 'high' ? 'strong' : qa.transcriptQuality === 'medium' ? 'moderate' : 'weak'
              return (
                <div key={qa.questionIdx} className="p-4 rounded-xl bg-neutral-50 border border-border">
                  <div className="flex items-start justify-between gap-2 mb-2">
                    <p className="text-sm font-medium text-neutral-800">Q{qa.questionIdx + 1}: {qa.questionText}</p>
                    <span className="flex-shrink-0"><Badge level={tq}>transcript: {qa.transcriptQuality}</Badge></span>
                  </div>
                  <p className="text-xs text-neutral-500 mb-3">{qa.answerSummary}</p>
                  <div className="grid grid-cols-3 gap-2 mb-3">
                    {[
                      { label: 'Relevance', dim: qa.relevanceScore },
                      { label: 'Clarity', dim: qa.clarityScore },
                      { label: 'Depth', dim: qa.depthScore },
                    ].map(({ label, dim }) => (
                      <div key={label} className="text-center p-2 rounded-lg bg-white border border-border">
                        <div className="text-lg font-mono font-bold" style={{ color: dim?.cannotAssess ? '#94a3b8' : barColor(dim?.score ?? 0) }}>
                          {dim?.cannotAssess ? '—' : dim?.score}
                        </div>
                        <div className="text-[10px] text-neutral-400">{label}</div>
                      </div>
                    ))}
                  </div>
                  {qa.dominantEmotions?.length > 0 && (
                    <div className="mb-2 flex flex-wrap gap-1">
                      {qa.dominantEmotions.slice(0, 3).map(e => (
                        <span key={e.name} className="text-[10px] px-2 py-0.5 rounded-full"
                          style={{ background: '#fffbeb', color: '#b45309', border: '1px solid #fde68a' }}>
                          {e.name} {(e.score * 100).toFixed(0)}%
                        </span>
                      ))}
                    </div>
                  )}
                  {qa.redFlags?.map((f, i) => <p key={i} className="text-xs text-danger">⚑ {f}</p>)}
                  {qa.strengths?.map((s, i) => <p key={i} className="text-xs text-primary-700">✓ {s}</p>)}
                </div>
              )
            })}
          </div>
        </Card>
      )}

      {/* Strengths & concerns */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
        <Card className="p-6">
          <h3 className="text-sm font-semibold text-primary-700 mb-3">Top Strengths</h3>
          <ul className="space-y-2">
            {scorecard.topStrengths?.length > 0
              ? scorecard.topStrengths.map((s, i) => (
                  <li key={i} className="text-sm text-neutral-600 flex gap-2"><span className="text-primary-600 flex-shrink-0">✓</span>{s}</li>
                ))
              : <li className="text-sm text-neutral-400">Insufficient data to identify strengths</li>}
          </ul>
        </Card>
        <Card className="p-6">
          <h3 className="text-sm font-semibold text-amber-700 mb-3">Top Concerns</h3>
          <ul className="space-y-2">
            {scorecard.topConcerns?.length > 0
              ? scorecard.topConcerns.map((c, i) => (
                  <li key={i} className="text-sm text-neutral-600 flex gap-2"><span className="text-amber-600 flex-shrink-0">⚑</span>{c}</li>
                ))
              : <li className="text-sm text-neutral-400">No significant concerns identified</li>}
          </ul>
        </Card>
      </div>

      {/* Follow-up questions */}
      {scorecard.recommendedFollowUpQuestions?.length > 0 && (
        <Card className="p-6">
          <SectionTitle>Recommended Follow-up Questions</SectionTitle>
          <ul className="space-y-2 mt-3">
            {scorecard.recommendedFollowUpQuestions.map((q, i) => (
              <li key={i} className="text-sm text-neutral-600 flex gap-2"><span className="text-primary-600 font-semibold flex-shrink-0">{i + 1}.</span>{q}</li>
            ))}
          </ul>
        </Card>
      )}

      {/* Limitations — always shown for transparency */}
      <Card className="p-6 border-warning-border">
        <h3 className="text-sm font-semibold text-amber-700 mb-3">Analysis Limitations & Caveats</h3>
        <ul className="space-y-1">
          {scorecard.dataLimitations?.map((l, i) => <li key={i} className="text-xs text-neutral-500">• {l}</li>)}
          {scorecard.biasWarnings?.map((w, i) => <li key={`b${i}`} className="text-xs text-amber-700">⚠ {w}</li>)}
        </ul>
        <p className="text-[11px] text-neutral-400 mt-3">
          This analysis is one data point. Human judgment must be applied before any hiring decision.
          Emotion data reflects vocal prosody only, not facial expression, intent, or personality.
        </p>
      </Card>
    </div>
  )
}
