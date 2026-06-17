// src/components/ats/FacialAnalysisPanel.tsx
// Displays AWS Rekognition facial analysis — LIGHT theme, matching the current ResultsPage.

import { useState } from 'react'
import { Card, SectionTitle } from '@/components/ui'
import type { FacialSessionSummary, RekognitionEmotionType, FacialFrame } from '@/types/rekognition.types'

// Emotion text colors that read on a white background
const EMOTION_COLOR: Record<RekognitionEmotionType, string> = {
  CALM: '#2563eb',
  HAPPY: '#16a34a',
  CONFUSED: '#d97706',
  SURPRISED: '#7c3aed',
  FEAR: '#dc2626',
  SAD: '#3b82f6',
  ANGRY: '#b91c1c',
  DISGUSTED: '#ea580c',
}

function emotionChipStyle(type: RekognitionEmotionType) {
  const c = EMOTION_COLOR[type] ?? '#64748b'
  return { color: c, background: `${c}14`, borderColor: `${c}33` } // 14/33 = ~8%/20% alpha hex
}

function barColor(pct: number) {
  return pct >= 80 ? '#0d5c3a' : pct >= 60 ? '#d97706' : '#dc2626'
}

function AttentionBar({ score, label }: { score: number; label: string }) {
  const pct = Math.round(Math.max(0, Math.min(1, score)) * 100)
  return (
    <div className="flex items-center gap-3">
      <span className="text-neutral-500 text-xs w-32 flex-shrink-0">{label}</span>
      <div className="flex-1 h-1.5 bg-neutral-100 rounded-full overflow-hidden">
        <div className="h-full rounded-full transition-all duration-700" style={{ width: `${pct}%`, background: barColor(pct) }} />
      </div>
      <span className="text-neutral-600 text-xs w-10 text-right font-mono">{pct}%</span>
    </div>
  )
}

function EmotionChip({ type, conf }: { type: RekognitionEmotionType; conf: number }) {
  return (
    <span className="text-xs px-2 py-0.5 rounded-full border font-medium" style={emotionChipStyle(type)}>
      {type} <span className="opacity-60">{conf.toFixed(0)}%</span>
    </span>
  )
}

const qualityBadge: Record<string, { bg: string; text: string; border: string }> = {
  high:         { bg: '#f0faf5', text: '#0d5c3a', border: '#b3e9cd' },
  medium:       { bg: '#fffbeb', text: '#b45309', border: '#fde68a' },
  low:          { bg: '#fef2f2', text: '#dc2626', border: '#fecaca' },
  insufficient: { bg: '#fef2f2', text: '#dc2626', border: '#fecaca' },
}

// Human-readable outcome for one captured frame — the key debugging signal.
function outcomeLabel(f: FacialFrame): string {
  if (f.frameQuality === 'good') return 'Good (face + quality OK)'
  if (f.frameQuality === 'multiple_faces') return 'Multiple faces detected'
  if (f.frameQuality === 'low_confidence') return 'Low face-detection confidence'
  if (f.frameQuality === 'low_brightness') return 'Too dark'
  if (f.frameQuality === 'low_sharpness') return 'Too blurry'
  if (f.frameQuality === 'no_face') {
    return f.frameQualityNote?.toLowerCase().includes('capture failed')
      ? 'Capture failed (proxy / network)'
      : 'No face detected'
  }
  return f.frameQuality
}

function frameOutcomes(frames: FacialFrame[]) {
  const map = new Map<string, { count: number; note: string }>()
  for (const f of frames) {
    const label = outcomeLabel(f)
    const cur = map.get(label)
    if (cur) cur.count++
    else map.set(label, { count: 1, note: f.frameQualityNote })
  }
  return Array.from(map.entries())
    .map(([label, v]) => ({ label, count: v.count, note: v.note }))
    .sort((a, b) => b.count - a.count)
}

function CaptureDiagnostics({ summary, proxyUrl }: { summary: FacialSessionSummary; proxyUrl?: string }) {
  const outcomes = frameOutcomes(summary.frames)
  return (
    <div className="mt-3 rounded-lg bg-neutral-50 border border-border p-3">
      <p className="text-xs font-semibold text-neutral-600 mb-2">Capture diagnostics</p>
      <div className="space-y-1 text-xs text-neutral-500">
        <div className="flex justify-between gap-3"><span>Proxy URL</span><span className="font-mono truncate">{proxyUrl || 'not set'}</span></div>
        <div className="flex justify-between"><span>Frames attempted</span><span className="font-mono">{summary.totalFrames}</span></div>
        <div className="flex justify-between"><span>Usable frames</span><span className="font-mono">{summary.usableFrames}</span></div>
      </div>
      {outcomes.length > 0 && (
        <div className="mt-2 pt-2 border-t border-border space-y-1">
          <p className="text-2xs text-neutral-400 uppercase tracking-wide">Per-frame outcomes</p>
          {outcomes.map(o => (
            <div key={o.label} className="flex items-center justify-between gap-2 text-xs">
              <span className="text-neutral-600">{o.label}</span>
              <span className="font-mono text-neutral-500 flex-shrink-0">{o.count}</span>
            </div>
          ))}
          <p className="text-2xs text-neutral-400 mt-1 italic">latest: "{outcomes[0].note}"</p>
        </div>
      )}
    </div>
  )
}

interface Props {
  summary: FacialSessionSummary | null
  questionCount: number
  proxyUrl?: string
}

export function FacialAnalysisPanel({ summary, proxyUrl }: Props) {
  const [expanded, setExpanded] = useState<number | null>(null)

  if (!summary) return null

  // Nothing captured at all — tell the user clearly + why, so they can debug.
  if (summary.totalFrames === 0) {
    return (
      <Card className="p-6 border-warning-border">
        <div className="flex items-center gap-3 mb-1">
          <h3 className="text-sm font-semibold text-amber-700">Facial Analysis</h3>
          <span className="text-xs px-2 py-0.5 rounded-full" style={{ background: '#fffbeb', color: '#b45309', border: '1px solid #fde68a' }}>
            Not Captured
          </span>
        </div>
        <p className="text-neutral-500 text-sm">No facial frames were captured during this interview.</p>
        <ul className="text-neutral-400 text-xs mt-2 space-y-1 list-disc pl-4">
          <li>{proxyUrl
            ? <>Proxy URL is set — confirm the proxy is actually running at <span className="font-mono">{proxyUrl}</span>.</>
            : <>No proxy URL configured — set it in Settings → AWS Rekognition Proxy URL.</>}</li>
          <li>Camera permission must be granted when the interview starts.</li>
          <li>Facial capture only runs while the interview is active (≈1 frame / 8s).</li>
        </ul>
        <CaptureDiagnostics summary={summary} proxyUrl={proxyUrl} />
      </Card>
    )
  }

  // Frames were captured but too few were usable — show the breakdown so the cause is visible.
  if (summary.dataQuality === 'insufficient') {
    return (
      <Card className="p-6 border-warning-border">
        <div className="flex items-center gap-3 mb-1">
          <h3 className="text-sm font-semibold text-amber-700">Facial Analysis</h3>
          <span className="text-xs px-2 py-0.5 rounded-full" style={{ background: '#fffbeb', color: '#b45309', border: '1px solid #fde68a' }}>
            Insufficient Data
          </span>
        </div>
        <p className="text-neutral-500 text-sm">{summary.dataQualityNote}</p>
        <p className="text-neutral-400 text-xs mt-2">
          Captured {summary.totalFrames} frame(s), {summary.usableFrames} usable. The breakdown below shows why frames were dropped.
        </p>
        <CaptureDiagnostics summary={summary} proxyUrl={proxyUrl} />
      </Card>
    )
  }

  const q = qualityBadge[summary.dataQuality] ?? qualityBadge.low

  return (
    <div className="space-y-5">
      {/* Session overview */}
      <Card className="p-6">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <SectionTitle>Facial Analysis</SectionTitle>
            <span className="text-xs px-2 py-0.5 rounded-full border font-medium"
              style={{ background: q.bg, color: q.text, borderColor: q.border }}>
              {summary.dataQuality} quality · {summary.usableFrames} frames
            </span>
          </div>
          <span className="text-neutral-400 text-xs">AWS Rekognition</span>
        </div>

        <div className="space-y-2 mb-4">
          <AttentionBar score={summary.sessionAvgAttention} label="Camera attention" />
          <AttentionBar score={1 - summary.overallLookingAwayPercent / 100} label="On-camera focus" />
          <AttentionBar score={summary.sessionAvgSmile} label="Positive expression" />
        </div>

        {summary.sessionDominantEmotions.length > 0 && (
          <div>
            <p className="text-neutral-400 text-xs mb-2">Dominant facial emotions (session avg)</p>
            <div className="flex flex-wrap gap-1.5">
              {summary.sessionDominantEmotions.slice(0, 5).map(e => (
                <EmotionChip key={e.type} type={e.type} conf={e.avgConfidence} />
              ))}
            </div>
          </div>
        )}

        {summary.dataQuality !== 'high' && (
          <div className="mt-4 p-3 rounded-lg bg-warning-bg border border-warning-border">
            <p className="text-amber-800 text-xs">⚠ {summary.dataQualityNote}</p>
          </div>
        )}
      </Card>

      {/* Flags requiring human review */}
      {(summary.integrityFlags.length > 0 || summary.concernFlags.length > 0) && (
        <Card className="p-6 border-danger-border">
          <h3 className="text-sm font-semibold text-danger mb-3">Flags Requiring Human Review</h3>
          <div className="space-y-1">
            {summary.integrityFlags.map((f, i) => <p key={`i${i}`} className="text-xs text-danger flex gap-2"><span className="flex-shrink-0">⚑</span>{f}</p>)}
            {summary.concernFlags.map((f, i) => <p key={`c${i}`} className="text-xs text-amber-700 flex gap-2"><span className="flex-shrink-0">⚠</span>{f}</p>)}
          </div>
          <p className="text-neutral-400 text-xs mt-3">These are signals only — human judgment must determine their significance.</p>
        </Card>
      )}

      {/* Engagement signals */}
      {summary.engagementFlags.length > 0 && (
        <Card className="p-6">
          <h3 className="text-sm font-semibold text-primary-700 mb-2">Engagement Signals</h3>
          {summary.engagementFlags.map((f, i) => <p key={i} className="text-xs text-primary-700 flex gap-2"><span>✓</span>{f}</p>)}
        </Card>
      )}

      {/* Per-question breakdown */}
      <Card className="p-6">
        <SectionTitle>Per-Question Facial Breakdown</SectionTitle>
        <div className="space-y-2 mt-3">
          {summary.perQuestion.map(qa => (
            <div key={qa.questionIdx} className="border border-border rounded-lg overflow-hidden">
              <button
                className="w-full flex items-center justify-between p-3 text-left hover:bg-neutral-50 transition-colors"
                onClick={() => setExpanded(expanded === qa.questionIdx ? null : qa.questionIdx)}
              >
                <div className="flex items-center gap-3">
                  <span className="text-neutral-700 text-sm font-medium">Q{qa.questionIdx + 1}</span>
                  {qa.usableFrameCount > 0 && qa.dominantEmotions[0]
                    ? <EmotionChip type={qa.dominantEmotions[0].type} conf={qa.dominantEmotions[0].avgConfidence} />
                    : <span className="text-xs text-neutral-300">no usable frames</span>}
                </div>
                <div className="flex items-center gap-3">
                  <span className="text-neutral-400 text-xs">{(qa.avgAttentionScore * 100).toFixed(0)}% attention</span>
                  <span className="text-neutral-300 text-xs">{expanded === qa.questionIdx ? '▲' : '▼'}</span>
                </div>
              </button>
              {expanded === qa.questionIdx && (
                <div className="px-3 pb-3 space-y-2 border-t border-border">
                  <div className="pt-2 space-y-1.5">
                    <AttentionBar score={qa.avgAttentionScore} label="Attention score" />
                    <AttentionBar score={1 - qa.lookingAwayPercent / 100} label="On-camera" />
                    <AttentionBar score={qa.avgSmileScore} label="Positive expression" />
                  </div>
                  {qa.dominantEmotions.length > 0 && (
                    <div className="flex flex-wrap gap-1 pt-1">
                      {qa.dominantEmotions.slice(0, 4).map(e => <EmotionChip key={e.type} type={e.type} conf={e.avgConfidence} />)}
                    </div>
                  )}
                  {qa.qualityNote && <p className="text-amber-700 text-xs">⚠ {qa.qualityNote}</p>}
                  <p className="text-neutral-400 text-xs">
                    {qa.usableFrameCount} of {qa.frameCount} frames usable · Head variance: {qa.headPoseVariance.toFixed(1)}
                  </p>
                </div>
              )}
            </div>
          ))}
        </div>
      </Card>

      {/* Mandatory disclaimer */}
      <div className="p-4 rounded-xl bg-neutral-50 border border-border">
        <p className="text-neutral-400 text-xs leading-relaxed">
          Facial analysis is a supplementary signal only. AWS Rekognition detects facial expressions —
          it does not measure honesty, intelligence, or character. All facial signals must be reviewed by a
          human recruiter before influencing any hiring decision. Camera angle, lighting, and individual
          expression patterns significantly affect results.
        </p>
      </div>
    </div>
  )
}
