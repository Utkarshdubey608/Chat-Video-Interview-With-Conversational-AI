import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import toast from 'react-hot-toast'
import { useAppStore } from '@/store/useAppStore'
import { Card, Button, Badge, StatCard, PageHeader, SectionTitle } from '@/components/ui'
import { cn } from '@/components/ui'

const DIMS = [
  { name: 'Communication',   score: 84 }, { name: 'Confidence',      score: 71 },
  { name: 'Engagement',      score: 80 }, { name: 'Vocabulary',      score: 88 },
  { name: 'Problem Solving', score: 82 }, { name: 'Leadership',      score: 76 },
]
const TIMELINE = [
  { label: 'Strong Response',   desc: 'Articulated background clearly',      type: 'good' },
  { label: 'Strong Response',   desc: 'Excellent problem decomposition',     type: 'good' },
  { label: 'Confidence Drop',   desc: 'Hesitation detected — AI flagged',   type: 'warn' },
  { label: 'Recovered Well',    desc: 'Strong recovery on scalability',      type: 'neutral' },
  { label: 'Excellent Closing', desc: 'Confident, impactful closing',        type: 'good' },
]

function scoreColor(s: number) {
  if (s >= 85) return { text: '#0d5c3a', bg: '#f0faf5', bar: '#0d5c3a' }
  if (s >= 75) return { text: '#475569', bg: '#f8fafc', bar: '#64748b' }
  return { text: '#d97706', bg: '#fffbeb', bar: '#d97706' }
}

export default function ResultsPage() {
  const store = useAppStore()
  const navigate = useNavigate()
  const conv = store.currentConversation
  const overall = Math.round(DIMS.reduce((a, b) => a + b.score, 0) / DIMS.length)
  const offset = 301.6 - (overall / 100) * 301.6
  const verdict = overall >= 85 ? 'Excellent Candidate' : overall >= 75 ? 'Good Candidate' : overall >= 65 ? 'Potential Candidate' : 'Needs Further Review'
  const [scheduleOpen, setScheduleOpen] = useState(false)
  const [offerOpen, setOfferOpen] = useState(false)

  function downloadReport() {
    const html = `<!DOCTYPE html><html><head><meta charset="UTF-8"><title>TalbotIQ Interview Report</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:Inter,sans-serif;color:#0f172a;background:#f8fafc;padding:48px}h1{font-size:28px;font-weight:700;color:#0d5c3a;margin-bottom:4px}.meta{font-size:13px;color:#64748b;margin-bottom:32px}table{width:100%;border-collapse:collapse;font-size:13px}td,th{padding:10px 14px;border:1px solid #e2e8f0;text-align:left}th{background:#f8fafc;font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:#64748b}.score{font-size:48px;font-weight:800;color:#0d5c3a}.verdict{display:inline-block;background:#f0faf5;color:#0d5c3a;padding:4px 12px;border-radius:9999px;font-size:12px;font-weight:600;border:1px solid #b3e9cd}</style></head><body><h1>TalbotIQ AI Interview Report</h1><p class="meta">Session ID: ${conv?.conversation_id ?? 'demo'} &bull; Generated: ${new Date().toLocaleString()}</p><p class="score">${overall}<span style="font-size:20px;color:#64748b">/100</span></p><p class="verdict" style="margin:12px 0 32px">${verdict}</p><table><tr><th>Dimension</th><th>Score</th><th>Grade</th></tr>${DIMS.map(d => `<tr><td>${d.name}</td><td style="font-weight:600">${d.score}/100</td><td>${d.score >= 85 ? 'Excellent' : d.score >= 75 ? 'Good' : 'Moderate'}</td></tr>`).join('')}</table><div style="margin-top:32px;background:#0d5c3a;color:white;padding:20px;border-radius:12px"><div style="font-size:11px;opacity:.6;text-transform:uppercase;letter-spacing:.08em">AI Recommendation</div><div style="font-size:20px;font-weight:700;margin:6px 0">Proceed to Technical Round</div><div style="font-size:13px;opacity:.8">Candidate demonstrates strong communication skills, excellent engagement, and advanced vocabulary. Hiring confidence: 87%.</div></div></body></html>`
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([html], { type: 'text/html' })); a.download = `TalbotIQ-Report-${conv?.conversation_id ?? 'demo'}.html`
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
            <p className="font-mono text-xs font-semibold text-neutral-700 mt-0.5">{conv?.conversation_id ?? 'TIQ-demo-2024'}</p>
          </div>
        }
      />

      {/* KPI row */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <StatCard label="Overall Score" value={`${overall}/100`} sub={verdict} trend="up" color="#0d5c3a" />
        <StatCard label="Hiring Confidence" value="87%" sub="Proceed to technical" trend="up" color="#0d5c3a" />
        <StatCard label="Words / Min" value="134" sub="Normal range (120–160)" color="#d97706" />
        <StatCard label="Face Engagement" value="81%" sub="Above benchmark" trend="up" color="#0d5c3a" />
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
            <p className="text-xs text-neutral-600 leading-relaxed">Strong communicator with good technical articulation. Minor confidence fluctuation under pressure. Vocabulary and engagement exceed benchmark expectations.</p>
          </div>
        </Card>

        <Card className="p-6">
          <SectionTitle>Dimension Scores</SectionTitle>
          <div className="space-y-3.5">
            {DIMS.map(d => {
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
            {[['#0d5c3a', '85+ Excellent'], ['#64748b', '75–84 Good'], ['#d97706', '65–74 Moderate']].map(([c, l]) => (
              <span key={l} className="flex items-center gap-1.5 text-xs text-neutral-400">
                <span className="w-2 h-2 rounded-full" style={{ background: c }} />{l}
              </span>
            ))}
          </div>
        </Card>
      </div>

      {/* Raw signals */}
      <Card className="p-5">
        <SectionTitle>Raw Signal Analytics</SectionTitle>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          {[
            { label: 'Words/min', value: '134', color: '#0d5c3a', badge: undefined },
            { label: 'Filler words', value: '12', color: '#d97706', badge: 'WARN' },
            { label: 'Longest pause', value: '2.1s', color: '#dc2626', badge: 'ALERT' },
            { label: 'Confident tone', value: '72%', color: '#d97706', badge: undefined },
            { label: 'Anxiety level', value: '8%', color: '#0d5c3a', badge: undefined },
            { label: 'Engagement', value: '81%', color: '#0d5c3a', badge: undefined },
          ].map(s => (
            <div key={s.label} className="relative bg-neutral-50 rounded-xl border border-border p-3.5">
              {s.badge && <span className={cn('absolute top-2 right-2 text-[9px] font-bold px-1.5 py-0.5 rounded', s.badge === 'WARN' ? 'badge badge-warning' : 'badge badge-danger')}>{s.badge}</span>}
              <p className="text-2xl font-bold tabular-nums" style={{ color: s.color }}>{s.value}</p>
              <p className="text-xs text-neutral-400 mt-1">{s.label}</p>
            </div>
          ))}
        </div>
      </Card>

      {/* Strengths / Watch */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
        <Card className="p-5">
          <p className="text-xs font-semibold text-success uppercase tracking-wide mb-3 flex items-center gap-2">
            <span className="w-4 h-4 rounded bg-success-bg flex items-center justify-center text-success text-[10px]">✓</span>
            Strengths
          </p>
          <div className="flex flex-wrap gap-2">
            {['Clear sentence structure', 'Strong vocabulary range', 'Good eye contact', 'Technical clarity', 'Positive communication'].map(s => (
              <span key={s} className="badge badge-success px-2.5 py-1">{s}</span>
            ))}
          </div>
        </Card>
        <Card className="p-5">
          <p className="text-xs font-semibold text-warning uppercase tracking-wide mb-3 flex items-center gap-2">
            <span className="w-4 h-4 rounded bg-warning-bg flex items-center justify-center text-warning text-[10px]">⚠</span>
            Watch Points
          </p>
          <div className="flex flex-wrap gap-2">
            {['Confidence dip at Q3', 'Filler words detected', 'Minor hesitation', 'Stress indicators'].map(s => (
              <span key={s} className="badge badge-warning px-2.5 py-1">{s}</span>
            ))}
          </div>
        </Card>
      </div>

      {/* AI Observation */}
      <Card className="p-5 border-warning-border bg-warning-bg">
        <div className="flex items-center gap-3 mb-3">
          <div className="w-7 h-7 rounded-lg bg-amber-100 flex items-center justify-center flex-shrink-0">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#d97706" strokeWidth="2.5"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
          </div>
          <p className="text-sm font-semibold text-neutral-800">AI Observation — Flagged Question</p>
        </div>
        <div className="bg-white rounded-lg border border-amber-100 px-4 py-2.5 mb-3 text-sm text-neutral-700 italic">
          "{store.questions[2] ?? 'How do you handle database query optimisation under load?'}"
        </div>
        <ul className="space-y-1.5">
          {['Confidence dropped significantly during this response.', 'Voice hesitation detected at multiple points.', 'Pause duration increased by 1.4 seconds above baseline.'].map(p => (
            <li key={p} className="flex items-start gap-2 text-xs text-amber-800">
              <span className="w-1.5 h-1.5 rounded-full bg-amber-500 flex-shrink-0 mt-1" />{p}
            </li>
          ))}
        </ul>
      </Card>

      {/* Interview timeline */}
      <Card className="p-5">
        <SectionTitle>Interview Timeline</SectionTitle>
        <div className="relative flex items-start px-4">
          <div className="absolute top-[21px] left-8 right-8 h-px bg-border" />
          {TIMELINE.slice(0, Math.max(store.questions.filter(Boolean).length, 1)).map((r, i) => {
            const isWarn = r.type === 'warn'; const isGood = r.type === 'good' || r.type === 'excellent'
            return (
              <div key={i} className="flex-1 flex flex-col items-center text-center relative z-10 px-1">
                <div className={cn('w-11 h-11 rounded-full border-2 flex items-center justify-center text-xs font-bold bg-white mb-3 shadow-xs', isWarn ? 'border-warning text-warning' : isGood ? 'border-primary-700 text-primary-700' : 'border-neutral-300 text-neutral-400')}>
                  Q{i + 1}
                </div>
                <span className={cn('text-[9px] font-bold px-2 py-0.5 rounded-full mb-1.5 whitespace-nowrap border', isWarn ? 'badge badge-warning' : isGood ? 'badge badge-success' : 'badge badge-neutral')}>
                  {r.label}
                </span>
                <p className="text-[10px] text-neutral-400 leading-tight">{r.desc}</p>
              </div>
            )
          })}
        </div>
      </Card>

      {/* AI Recommendation */}
      <div className="bg-primary-700 rounded-2xl p-6">
        <div className="flex items-start gap-4 mb-5">
          <div className="w-10 h-10 rounded-xl bg-white/10 flex items-center justify-center flex-shrink-0">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2"><polyline points="22,7 13.5,15.5 8.5,10.5 2,17"/><polyline points="16,7 22,7 22,13"/></svg>
          </div>
          <div className="flex-1">
            <p className="text-xs font-semibold text-white/50 uppercase tracking-widest mb-1">AI Recommendation</p>
            <p className="text-xl font-bold text-white">Proceed to Technical Round</p>
            <p className="text-sm text-white/65 mt-2 leading-relaxed">Candidate demonstrates strong communication skills, excellent engagement, and advanced vocabulary. Confidence fluctuates slightly during high-pressure questions but remains within acceptable range.</p>
          </div>
          <div className="text-right flex-shrink-0">
            <p className="text-3xl font-black text-white">87%</p>
            <p className="text-xs text-white/50">Hiring Confidence</p>
          </div>
        </div>
        <div className="border-t border-white/10 pt-4">
          <div className="flex justify-between text-xs mb-2"><span className="text-white/50">Hiring Recommendation Confidence</span><span className="text-white font-semibold">87%</span></div>
          <div className="h-1.5 bg-white/10 rounded-full overflow-hidden"><div className="h-full bg-white/70 rounded-full" style={{ width: '87%' }} /></div>
          <div className="flex justify-between text-[10px] text-white/25 mt-1.5"><span>0%</span><span>50%</span><span>100%</span></div>
        </div>
      </div>

      {/* Recruiter actions */}
      <Card className="p-5">
        <SectionTitle>Recruiter Actions</SectionTitle>
        <div className="flex flex-wrap gap-3">
          <Button onClick={() => setScheduleOpen(true)}>Schedule Technical Interview</Button>
          <Button variant="secondary" onClick={downloadReport}>Download AI Report</Button>
          <Button variant="secondary" onClick={() => { navigator.clipboard.writeText(`TalbotIQ Report — ${overall}/100 — ${verdict} — Session: ${conv?.conversation_id ?? 'demo'}`).then(() => toast.success('Copied to clipboard')) }}>Share Profile</Button>
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
Score: ${overall}/100  |  Confidence: 87%

RECOMMENDATION: Proceed with Offer

Candidate demonstrates strong communication
skills, technical clarity, and engagement
above benchmark expectations.

Suggested Band: Mid-Senior Level
Next Steps: Technical Round → HR Screening

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
