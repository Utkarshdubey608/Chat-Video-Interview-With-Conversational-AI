import { useRef, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import {
  Radar, RadarChart, PolarGrid, PolarAngleAxis, PolarRadiusAxis, ResponsiveContainer,
} from 'recharts'
import {
  ArrowLeft, Download, ChevronDown, AlertTriangle, Clock, Zap, ShieldAlert, Loader2,
} from 'lucide-react'
import { PageHeader, Card, Button, Badge, Skeleton, cn } from '@/components/ui'
import { sessionsApi } from '@/lib/api'
import { exportElementToPdf } from '@/lib/pdf'
import type { Recommendation, SessionReportView } from '@shared/types'

const REC: Record<Recommendation, { label: string; cls: string }> = {
  strong_yes: { label: 'Strong Yes', cls: 'bg-success-bg text-success border-success-border' },
  yes:        { label: 'Yes',        cls: 'bg-primary-50 text-primary-700 border-primary-200' },
  maybe:      { label: 'Maybe',      cls: 'bg-warning-bg text-warning border-warning-border' },
  no:         { label: 'No',         cls: 'bg-danger-bg text-danger border-danger-border' },
}

const scoreColor = (s: number) => (s >= 75 ? '#16a34a' : s >= 55 ? '#d97706' : '#dc2626')

function Gauge({ score }: { score: number }) {
  const R = 64
  const C = 2 * Math.PI * R
  const color = scoreColor(score)
  return (
    <div className="relative flex items-center justify-center" style={{ width: 160, height: 160 }}>
      <svg width="160" height="160" viewBox="0 0 160 160" className="-rotate-90">
        <circle cx="80" cy="80" r={R} fill="none" stroke="#e2e8f0" strokeWidth="12" />
        <circle cx="80" cy="80" r={R} fill="none" stroke={color} strokeWidth="12" strokeLinecap="round" strokeDasharray={C} strokeDashoffset={C * (1 - score / 100)} />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-4xl font-bold tabular-nums" style={{ color }}>{score}</span>
        <span className="text-[10px] font-semibold uppercase tracking-widest text-neutral-400">Overall</span>
      </div>
    </div>
  )
}

export default function ReportPage() {
  const { id = '' } = useParams()
  const reportRef = useRef<HTMLDivElement>(null)
  const [open, setOpen] = useState<string | null>(null)
  const [exporting, setExporting] = useState(false)

  const q = useQuery({
    queryKey: ['report', id],
    queryFn: () => sessionsApi.report(id),
    // Poll while scoring is still in flight.
    refetchInterval: (query) => ((query.state.data as SessionReportView | undefined)?.report ? false : 2500),
  })

  if (q.isLoading) {
    return <div className="max-w-[1100px] mx-auto px-6 py-8 space-y-4"><Skeleton className="h-10 w-64" /><Skeleton className="h-72" /></div>
  }
  if (q.isError || !q.data) {
    return <div className="max-w-[1100px] mx-auto px-6 py-8"><Card className="p-0"><div className="p-10 text-center text-neutral-500">Couldn’t load this report. <Link to="/sessions" className="text-primary-700">Back to sessions</Link></div></Card></div>
  }

  const { session, rubric, report } = q.data
  const kpiLabel = (kid: string) => rubric.kpis.find((k) => k.id === kid)?.label ?? kid

  const exportPdf = async () => {
    if (!reportRef.current) return
    setExporting(true)
    try {
      await exportElementToPdf(reportRef.current, `TalbotIQ-${session.candidate.name.replace(/\s+/g, '-')}-report.pdf`)
    } catch {
      toast.error('PDF export failed')
    } finally {
      setExporting(false)
    }
  }

  return (
    <div className="max-w-[1100px] mx-auto px-6 py-8">
      <Link to="/sessions" className="mb-3 inline-flex items-center gap-1.5 text-sm font-medium text-neutral-500 hover:text-neutral-800">
        <ArrowLeft size={15} /> Sessions
      </Link>
      <PageHeader
        kicker="Candidate Report"
        title={session.candidate.name}
        description={`${session.templateName} · ${session.track === 'video_avatar' ? 'Video Avatar' : 'Chat'} · ${session.completedAt ? new Date(session.completedAt).toLocaleString() : 'in progress'}`}
        action={report ? <Button icon={<Download size={16} />} loading={exporting} onClick={exportPdf}>Export PDF</Button> : undefined}
      />

      {!report ? (
        <Card className="p-0">
          <div className="flex flex-col items-center gap-3 py-16 text-center">
            <Loader2 className="animate-spin text-primary-700" size={26} />
            <p className="font-semibold text-neutral-700">Scoring in progress…</p>
            <p className="text-sm text-neutral-400">This updates automatically when the analysis is ready.</p>
          </div>
        </Card>
      ) : (
        <div ref={reportRef} className="space-y-6 bg-background">
          {report.degraded && (
            <div className="flex items-start gap-2 rounded-xl border border-warning-border bg-warning-bg p-3 text-sm text-warning">
              <AlertTriangle size={16} className="mt-0.5 flex-shrink-0" />
              <span>Heuristic scoring (no <code className="font-mono">GEMINI_API_KEY</code>). Add a key for content-aware analysis.</span>
            </div>
          )}

          {/* summary row */}
          <div className="grid gap-6 md:grid-cols-[200px_1fr]">
            <Card className="flex flex-col items-center justify-center gap-3 p-5">
              <Gauge score={report.overallScore} />
              {report.recommendation && (
                <span className={cn('rounded-full border px-3 py-1 text-sm font-bold', REC[report.recommendation].cls)}>
                  {REC[report.recommendation].label}
                </span>
              )}
            </Card>
            <Card className="p-5">
              <h3 className="text-sm font-bold uppercase tracking-wide text-neutral-500">AI Summary</h3>
              <p className="mt-2 text-sm leading-relaxed text-neutral-700">{report.summary}</p>
              {(report.strengths?.length || report.improvements?.length) ? (
                <div className="mt-4 grid gap-4 sm:grid-cols-2">
                  {report.strengths?.length ? (
                    <div>
                      <p className="text-xs font-semibold uppercase tracking-wide text-success">Strengths</p>
                      <ul className="mt-1.5 space-y-1">
                        {report.strengths.map((str, i) => (
                          <li key={i} className="flex gap-2 text-sm text-neutral-700"><span className="text-success">+</span>{str}</li>
                        ))}
                      </ul>
                    </div>
                  ) : null}
                  {report.improvements?.length ? (
                    <div>
                      <p className="text-xs font-semibold uppercase tracking-wide text-warning">Areas to improve</p>
                      <ul className="mt-1.5 space-y-1">
                        {report.improvements.map((str, i) => (
                          <li key={i} className="flex gap-2 text-sm text-neutral-700"><span className="text-warning">→</span>{str}</li>
                        ))}
                      </ul>
                    </div>
                  ) : null}
                </div>
              ) : null}
            </Card>
          </div>

          {/* radar + bars */}
          <div className="grid gap-6 md:grid-cols-2">
            <Card className="p-5">
              <h3 className="mb-2 text-sm font-bold uppercase tracking-wide text-neutral-500">KPI Profile</h3>
              <ResponsiveContainer width="100%" height={260}>
                <RadarChart data={rubric.kpis.filter((k) => k.enabled).map((k) => ({ kpi: k.label, score: report.kpiAverages[k.id] ?? 0 }))}>
                  <PolarGrid stroke="#e2e8f0" />
                  <PolarAngleAxis dataKey="kpi" tick={{ fontSize: 10, fill: '#64748b' }} />
                  <PolarRadiusAxis domain={[0, 100]} tick={false} axisLine={false} />
                  <Radar dataKey="score" stroke="#0d5c3a" fill="#0d5c3a" fillOpacity={0.25} />
                </RadarChart>
              </ResponsiveContainer>
            </Card>
            <Card className="p-5">
              <h3 className="mb-3 text-sm font-bold uppercase tracking-wide text-neutral-500">KPI Scores</h3>
              <div className="space-y-2.5">
                {Object.entries(report.kpiAverages)
                  .sort((a, b) => b[1] - a[1])
                  .map(([kid, score]) => (
                    <div key={kid} className="flex items-center gap-3">
                      <span className="w-40 truncate text-xs text-neutral-600">{kpiLabel(kid)}</span>
                      <div className="h-2.5 flex-1 overflow-hidden rounded-full bg-neutral-100">
                        <div className="h-full rounded-full" style={{ width: `${score}%`, background: scoreColor(score) }} />
                      </div>
                      <span className="w-8 text-right text-xs font-bold tabular-nums" style={{ color: scoreColor(score) }}>{score}</span>
                    </div>
                  ))}
              </div>
            </Card>
          </div>

          {/* integrity */}
          {(session.integrityEvents.length > 0 || session.tabSwitchCount > 0) && (
            <Card className="p-5">
              <h3 className="mb-2 flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-neutral-500">
                <ShieldAlert size={15} /> Integrity
              </h3>
              <div className="flex flex-wrap gap-2">
                <Badge variant={session.tabSwitchCount > 0 ? 'warning' : 'neutral'}>{session.tabSwitchCount} tab switches</Badge>
                {session.integrityEvents.length > 0 && <Badge variant="neutral">{session.integrityEvents.length} events logged</Badge>}
              </div>
            </Card>
          )}

          {/* per-question accordion */}
          <Card className="p-0">
            <h3 className="border-b border-border px-5 py-4 text-sm font-bold uppercase tracking-wide text-neutral-500">
              Per-question breakdown
            </h3>
            <div>
              {session.questions.map((qq, i) => {
                const pq = report.perQuestion.find((p) => p.questionId === qq.id)
                const isOpen = open === qq.id
                return (
                  <div key={qq.id} className="border-b border-border last:border-0">
                    <button onClick={() => setOpen(isOpen ? null : qq.id)} className="flex w-full items-center gap-3 px-5 py-4 text-left hover:bg-neutral-50">
                      <span className="text-xs font-bold text-neutral-300 tabular-nums">{i + 1}</span>
                      <span className="min-w-0 flex-1 truncate text-sm font-medium text-neutral-800">{qq.text}</span>
                      {qq.category && <Badge variant="neutral">{qq.category}</Badge>}
                      {qq.autoSubmitted && <span className="flex items-center gap-1 text-[11px] font-semibold text-amber-600"><Zap size={12} /> auto</span>}
                      {typeof qq.timeUsedSeconds === 'number' && <span className="flex items-center gap-1 text-[11px] text-neutral-400"><Clock size={12} /> {qq.timeUsedSeconds}s</span>}
                      <ChevronDown size={16} className={cn('text-neutral-400 transition-transform', isOpen && 'rotate-180')} />
                    </button>
                    {isOpen && (
                      <div className="space-y-4 bg-neutral-50/60 px-5 pb-5 pt-1">
                        <div>
                          <p className="text-xs font-semibold uppercase tracking-wide text-neutral-400">Answer</p>
                          <p className="mt-1 whitespace-pre-wrap text-sm text-neutral-700">{qq.answerText?.trim() || <span className="italic text-neutral-400">No answer provided.</span>}</p>
                        </div>
                        {pq && (
                          <>
                            <div className="flex flex-wrap gap-2">
                              {Object.entries(pq.kpiScores).map(([kid, score]) => (
                                <span key={kid} className="rounded-lg border border-border bg-white px-2.5 py-1 text-xs">
                                  <span className="text-neutral-500">{kpiLabel(kid)}</span>{' '}
                                  <span className="font-bold tabular-nums" style={{ color: scoreColor(score) }}>{score}</span>
                                </span>
                              ))}
                            </div>
                            <div>
                              <p className="text-xs font-semibold uppercase tracking-wide text-neutral-400">Feedback</p>
                              <p className="mt-1 text-sm text-neutral-600">{pq.feedback}</p>
                            </div>
                          </>
                        )}
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
