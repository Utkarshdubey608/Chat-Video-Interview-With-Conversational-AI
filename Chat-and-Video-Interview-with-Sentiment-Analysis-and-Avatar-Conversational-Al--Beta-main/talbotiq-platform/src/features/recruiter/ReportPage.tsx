import { useEffect, useRef, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import {
  Radar, RadarChart, PolarGrid, PolarAngleAxis, PolarRadiusAxis, ResponsiveContainer,
} from 'recharts'
import {
  ArrowLeft, Download, ChevronDown, AlertTriangle, Clock, Zap, ShieldAlert, Loader2, Star,
} from 'lucide-react'
import { PageHeader, Card, Button, Textarea, Badge, Skeleton, cn } from '@/components/ui'
import { sessionsApi } from '@/lib/api'
import { exportElementToPdf } from '@/lib/pdf'
import { FacialAnalysisPanel } from '@/components/ats/FacialAnalysisPanel'
import type { Recommendation, SessionReportView, SpeechMetrics, SentimentSignals } from '@shared/types'
import type { FacialSessionSummary } from '@/types/rekognition.types'

const REC: Record<Recommendation, { label: string; cls: string }> = {
  strong_yes: { label: 'Strong Yes', cls: 'bg-success-bg text-success border-success-border' },
  yes:        { label: 'Yes',        cls: 'bg-primary-50 text-primary-700 border-primary-200' },
  maybe:      { label: 'Maybe',      cls: 'bg-warning-bg text-warning border-warning-border' },
  no:         { label: 'No',         cls: 'bg-danger-bg text-danger border-danger-border' },
}

const TRACK_LABEL: Record<string, string> = {
  chat: 'Timed Q&A',
  chatbot: 'Chatbot',
  voice: 'Voice',
  video_avatar: 'Video Avatar',
  video: 'Video Interview',
  two_way: 'Two-way Interview',
}

const scoreColor = (s: number) => (s >= 75 ? '#16a34a' : s >= 55 ? '#d97706' : '#dc2626')

/**
 * Two-way Interview is recruiter-scored (in addition to the Gemini scorecard,
 * which reuses the conversation-scoring path over the transcribed recording).
 * This card lets the interviewer leave a 0–5 star rating + private notes,
 * persisted via POST /sessions/:id/twoway/review (server mirrors it onto both
 * session.manualReview — the source of truth — and report.manualReview, so a
 * refetch of this same report query shows it back immediately).
 */
function ManualReviewCard({
  sessionId,
  manualReview,
}: {
  sessionId: string
  manualReview?: { rating: number; notes: string; by?: string; at: string }
}) {
  const qc = useQueryClient()
  const [rating, setRating] = useState(manualReview?.rating ?? 0)
  const [notes, setNotes] = useState(manualReview?.notes ?? '')

  // Re-sync local draft if the server copy changes underneath us (e.g. another
  // recruiter saved a review, or our own save round-trips through a refetch).
  useEffect(() => {
    setRating(manualReview?.rating ?? 0)
    setNotes(manualReview?.notes ?? '')
  }, [manualReview?.rating, manualReview?.notes])

  const save = useMutation({
    mutationFn: () => sessionsApi.twowayReview(sessionId, { rating, notes }),
    onSuccess: () => {
      toast.success('Review saved')
      qc.invalidateQueries({ queryKey: ['report', sessionId] })
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Could not save the review'),
  })

  return (
    <Card className="p-5">
      <h3 className="text-sm font-bold uppercase tracking-wide text-neutral-500">Interviewer review</h3>
      {manualReview?.at && (
        <p className="mt-1 text-xs text-neutral-400">
          Last saved {new Date(manualReview.at).toLocaleString()}{manualReview.by ? ` by ${manualReview.by}` : ''}
        </p>
      )}
      <div className="mt-3 flex items-center gap-1">
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            key={n}
            type="button"
            onClick={() => setRating(n === rating ? 0 : n)}
            aria-label={`Rate ${n} star${n === 1 ? '' : 's'}`}
            className="text-neutral-300 transition-colors hover:text-warning"
          >
            <Star size={20} className={n <= rating ? 'fill-warning text-warning' : ''} />
          </button>
        ))}
        {rating > 0 && <span className="ml-2 text-xs font-medium text-neutral-400">{rating}/5</span>}
      </div>
      <Textarea
        className="mt-3"
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
        placeholder="Private notes for your hiring team — not shown to the candidate."
        rows={4}
        charLimit={4000}
      />
      <div className="mt-3 flex justify-end">
        <Button size="sm" loading={save.isPending} onClick={() => save.mutate()}>Save review</Button>
      </div>
    </Card>
  )
}

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
    // Transient blips (token refresh, network) must not kill the page —
    // especially while polling. Retry before surfacing an error.
    retry: 2,
    // Poll while scoring is still in flight.
    refetchInterval: (query) => ((query.state.data as SessionReportView | undefined)?.report ? false : 2500),
  })

  if (q.isLoading) {
    return <div className="max-w-[1100px] mx-auto px-6 py-8 space-y-4"><Skeleton className="h-10 w-64" /><Skeleton className="h-72" /></div>
  }
  // Only a hard failure with NO data at all blocks the page — a failed
  // background refetch keeps showing the last good data instead of erroring.
  if (!q.data) {
    const reason = q.error instanceof Error ? q.error.message : 'Something went wrong while fetching it.'
    return (
      <div className="max-w-[1100px] mx-auto px-6 py-8">
        <Card className="p-0">
          <div className="flex flex-col items-center gap-3 p-10 text-center">
            <AlertTriangle className="text-warning" size={24} />
            <p className="font-semibold text-neutral-700">Couldn’t load this report</p>
            <p className="text-sm text-neutral-400">{reason}</p>
            <div className="flex items-center gap-3">
              <Button onClick={() => void q.refetch()}>Try again</Button>
              <Link to="/sessions" className="text-sm font-medium text-primary-700">Back to sessions</Link>
            </div>
          </div>
        </Card>
      </div>
    )
  }

  const { session, rubric, report, speech, facial } = q.data
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
        description={`${session.templateName} · ${TRACK_LABEL[session.track] ?? session.track} · ${session.completedAt ? new Date(session.completedAt).toLocaleString() : 'in progress'}`}
        action={report ? <Button icon={<Download size={16} />} loading={exporting} onClick={exportPdf}>Export PDF</Button> : undefined}
      />

      {!report ? (
        <div className="space-y-6">
          <Card className="p-0">
            <div className="flex flex-col items-center gap-3 py-16 text-center">
              <Loader2 className="animate-spin text-primary-700" size={26} />
              <p className="font-semibold text-neutral-700">Scoring in progress…</p>
              <p className="text-sm text-neutral-400">This updates automatically when the analysis is ready.</p>
            </div>
          </Card>
          {/* Two-way Interview is recruiter-scored — the recruiter can rate the
              call before the AI scorecard finishes (or even if it never does);
              session.manualReview is the source of truth, independent of report. */}
          {session.track === 'two_way' && (
            <ManualReviewCard sessionId={session.id} manualReview={session.manualReview} />
          )}
        </div>
      ) : (
        <div ref={reportRef} className="space-y-6 bg-background">
          {report.notEvaluated && (
            <div className="flex items-start gap-2 rounded-xl border border-warning-border bg-warning-bg p-3 text-sm text-warning">
              <AlertTriangle size={16} className="mt-0.5 flex-shrink-0" />
              <span>
                <strong>Not evaluated.</strong> No candidate answers were captured for this interview, so
                there are no real scores — the values below are placeholders, not a judgment of the candidate.
                The interview may need to be retaken.
              </span>
            </div>
          )}
          {report.degraded && (
            <div className="flex items-start gap-2 rounded-xl border border-warning-border bg-warning-bg p-3 text-sm text-warning">
              <AlertTriangle size={16} className="mt-0.5 flex-shrink-0" />
              <span>Heuristic scoring (no <code className="font-mono">GEMINI_API_KEY</code>). Add a key for content-aware analysis.</span>
            </div>
          )}

          {/* summary row */}
          <div className="grid gap-6 md:grid-cols-[200px_1fr]">
            <Card className="flex flex-col items-center justify-center gap-3 p-5">
              {report.notEvaluated ? (
                <div className="flex flex-col items-center justify-center" style={{ width: 160, height: 160 }}>
                  <span className="text-5xl font-bold text-neutral-300">—</span>
                  <span className="mt-1 text-[10px] font-semibold uppercase tracking-widest text-neutral-400">Not evaluated</span>
                </div>
              ) : (
                <Gauge score={report.overallScore} />
              )}
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
                  <Radar dataKey="score" stroke="#6B2BE0" fill="#6B2BE0" fillOpacity={0.25} />
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
                          <p className="text-xs font-semibold uppercase tracking-wide text-neutral-400">
                            {qq.videoUrl ? 'Recorded answer' : 'Answer'}
                          </p>
                          {qq.videoUrl && (
                            <video
                              controls
                              src={qq.videoUrl}
                              className="mt-2 aspect-video w-full max-w-lg overflow-hidden rounded-xl border border-border bg-neutral-900"
                            />
                          )}
                          <p className="mt-2 whitespace-pre-wrap text-sm text-neutral-700">
                            {qq.answerText?.trim()
                              ? <>{qq.videoUrl && <span className="text-xs font-semibold uppercase tracking-wide text-neutral-400">Transcript · </span>}{qq.answerText}</>
                              : <span className="italic text-neutral-400">{qq.videoUrl ? 'No speech was transcribed for this clip.' : 'No answer provided.'}</span>}
                          </p>
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
              {session.questions.length === 0 && (
                <div className="p-8 text-center text-sm text-neutral-400">
                  No questions were recorded for this interview.
                </div>
              )}
            </div>
          </Card>

          {/* call recording (Two-way Interview) */}
          {session.recordingUrl && (
            <Card className="p-5">
              <h3 className="mb-2 text-sm font-bold uppercase tracking-wide text-neutral-500">Call recording</h3>
              <video
                controls
                src={session.recordingUrl}
                className="aspect-video w-full max-w-2xl overflow-hidden rounded-xl border border-border bg-neutral-900"
              />
            </Card>
          )}

          {/* interviewer manual review (Two-way Interview — recruiter-scored) */}
          {session.track === 'two_way' && (
            <ManualReviewCard sessionId={session.id} manualReview={report.manualReview} />
          )}

          {/* full transcript (conversation tracks) */}
          {session.transcript && (
            <Card className="p-0">
              <h3 className="border-b border-border px-5 py-4 text-sm font-bold uppercase tracking-wide text-neutral-500">
                Interview transcript
              </h3>
              {session.transcript.length === 0 ? (
                <div className="p-8 text-center text-sm text-neutral-400">
                  No transcript was captured for this interview.
                </div>
              ) : (
                <div className="max-h-[420px] space-y-3 overflow-y-auto p-5">
                  {session.transcript.map((t, i) => (
                    <div key={i} className="flex gap-3">
                      <span className={cn(
                        'w-24 flex-shrink-0 text-xs font-bold uppercase tracking-wide',
                        t.role === 'interviewer' ? 'text-primary-700' : 'text-neutral-500',
                      )}>
                        {t.role === 'interviewer' ? 'Interviewer' : 'Candidate'}
                      </span>
                      <p className="whitespace-pre-wrap text-sm text-neutral-700">{t.content}</p>
                    </div>
                  ))}
                </div>
              )}
            </Card>
          )}

          {/* facial analysis (video track, AWS Rekognition) */}
          {session.track === 'video' && facial && (
            <FacialAnalysisPanel summary={facial as unknown as FacialSessionSummary} questionCount={session.questions.length} />
          )}

          {/* signal analytics — real transcript-derived metrics + text sentiment */}
          <SignalAnalytics track={session.track} speech={speech} sentiment={report.sentiment} />
        </div>
      )}
    </div>
  )
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="rounded-lg border border-border bg-white px-3 py-2">
      <div className="text-lg font-bold tabular-nums text-neutral-800">{value}</div>
      <div className="text-[11px] uppercase tracking-wide text-neutral-400">{label}</div>
    </div>
  )
}

function SignalBar({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex items-center gap-3">
      <span className="w-24 text-xs text-neutral-600">{label}</span>
      <div className="h-2.5 flex-1 overflow-hidden rounded-full bg-neutral-100">
        <div className="h-full rounded-full" style={{ width: `${value}%`, background: scoreColor(value) }} />
      </div>
      <span className="w-8 text-right text-xs font-bold tabular-nums" style={{ color: scoreColor(value) }}>{value}</span>
    </div>
  )
}

const SENTIMENT_STYLE: Record<SentimentSignals['overall'], string> = {
  positive: 'bg-success-bg text-success border-success-border',
  mixed: 'bg-warning-bg text-warning border-warning-border',
  neutral: 'bg-neutral-100 text-neutral-600 border-border',
  negative: 'bg-danger-bg text-danger border-danger-border',
}

/**
 * Real signal analytics for conversation tracks: delivery metrics computed from
 * the stored transcript, and a text-based communication/sentiment read. Acoustic
 * pitch/energy prosody and facial analysis genuinely need the raw audio/video
 * (only captured in the live recruiter room), so those stay honest empty states.
 */
function SignalAnalytics({
  track,
  speech,
  sentiment,
}: {
  track: string
  speech?: SpeechMetrics
  sentiment?: SentimentSignals
}) {
  const spoken = speech?.spoken ?? (track === 'voice' || track === 'video_avatar')

  if (!speech && !sentiment) {
    return (
      <Card className="p-5">
        <h3 className="text-sm font-bold uppercase tracking-wide text-neutral-500">Signal analytics</h3>
        <p className="mt-2 text-sm text-neutral-500">
          Delivery metrics and sentiment are available for voice and conversational interviews with a
          transcript. This interview type doesn’t produce one.
        </p>
      </Card>
    )
  }

  return (
    <div className="grid gap-6 md:grid-cols-2">
      {/* Delivery metrics (from the transcript) */}
      <Card className="p-5">
        <h3 className="text-sm font-bold uppercase tracking-wide text-neutral-500">
          {spoken ? 'Speech metrics' : 'Response metrics'}
        </h3>
        {speech ? (
          <>
            <div className="mt-3 grid grid-cols-3 gap-2">
              <Stat label="Words" value={speech.words} />
              <Stat label="Answers" value={speech.answers} />
              <Stat label="Avg words" value={speech.avgWordsPerAnswer} />
              {spoken && <Stat label="Fillers" value={speech.fillerCount} />}
              {spoken && <Stat label="Fillers /100" value={speech.fillerPer100} />}
              <Stat label="Vocabulary" value={`${speech.vocabularyPct}%`} />
              {typeof speech.avgResponseSeconds === 'number' && (
                <Stat label="Avg reply" value={`${speech.avgResponseSeconds}s`} />
              )}
            </div>
            <p className="mt-3 text-xs text-neutral-400">
              Computed from the interview transcript.
              {spoken
                ? ' Fillers depend on how the transcription captured speech; acoustic pace/pitch needs the live room.'
                : ''}
            </p>
          </>
        ) : (
          <p className="mt-2 text-sm text-neutral-400">No transcript was captured for this interview.</p>
        )}
      </Card>

      {/* Communication & sentiment (text-based) */}
      <Card className="p-5">
        <h3 className="text-sm font-bold uppercase tracking-wide text-neutral-500">Communication &amp; sentiment</h3>
        {sentiment ? (
          <>
            <div className="mt-2 flex items-center gap-2">
              <span className={cn('rounded-full border px-2.5 py-0.5 text-xs font-bold capitalize', SENTIMENT_STYLE[sentiment.overall])}>
                {sentiment.overall}
              </span>
              <span className="text-xs text-neutral-400">overall tone</span>
            </div>
            <div className="mt-3 space-y-2">
              <SignalBar label="Confidence" value={sentiment.confidence} />
              <SignalBar label="Clarity" value={sentiment.clarity} />
              <SignalBar label="Positivity" value={sentiment.positivity} />
            </div>
            <p className="mt-3 text-sm text-neutral-600">{sentiment.summary}</p>
            <p className="mt-2 text-xs text-neutral-400">
              From the transcript — reflects what the words convey, not audio tone.
            </p>
          </>
        ) : (
          <p className="mt-2 text-sm text-neutral-400">
            Sentiment analysis needs a Gemini API key. Add one in Settings to enable it.
          </p>
        )}
      </Card>
    </div>
  )
}
