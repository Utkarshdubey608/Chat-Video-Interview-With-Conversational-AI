import type {
  AnalyticsFilters,
  AnalyticsSummary,
  InterviewSession,
  InterviewTemplate,
  ResultReport,
  TrackType,
} from '../../shared/types'
import { db } from '../store/db'
import { answerTimeUsed } from './timing'

const at = (iso?: string) => (iso ? Date.parse(iso) : NaN)

/** Inclusive date-range test on an ISO timestamp. Date-only bounds (YYYY-MM-DD)
 *  expand to full-day start/end so `dateTo` includes the whole day. */
function inRange(iso: string | undefined, from?: string, to?: string): boolean {
  if (!iso) return !from // no timestamp → only excluded when a lower bound is set
  const t = Date.parse(iso)
  if (from) { const f = Date.parse(from.length <= 10 ? `${from}T00:00:00.000Z` : from); if (!(t >= f)) return false }
  if (to)   { const e = Date.parse(to.length <= 10 ? `${to}T23:59:59.999Z` : to);   if (!(t <= e)) return false }
  return true
}

const BUCKETS = ['0-20', '21-40', '41-60', '61-80', '81-100'] as const
function bucketOf(score: number): (typeof BUCKETS)[number] {
  if (score <= 20) return '0-20'
  if (score <= 40) return '21-40'
  if (score <= 60) return '41-60'
  if (score <= 80) return '61-80'
  return '81-100'
}

const mean = (xs: number[]) => (xs.length ? Math.round(xs.reduce((a, b) => a + b, 0) / xs.length) : 0)

/** One scored row = a completed session that has a stored report. */
interface Row {
  session: InterviewSession
  template: InterviewTemplate | undefined
  report: ResultReport
}

/** Per-session average answer time: real per-question timing for the Timed Q&A
 *  track; otherwise total duration / number of scored questions. */
function avgTimePerQuestion(row: Row): number | undefined {
  const { session, report } = row
  if (session.track === 'chat' || session.track === 'video') {
    const times = session.questions.map(answerTimeUsed).filter((n): n is number => typeof n === 'number')
    if (times.length) return times.reduce((a, b) => a + b, 0) / times.length
  }
  const dur = at(session.completedAt) - at(session.startedAt)
  const qCount = report.perQuestion.length
  if (Number.isFinite(dur) && dur > 0 && qCount > 0) return dur / 1000 / qCount
  return undefined
}

/**
 * Aggregate every stored ResultReport (joined with its session + template) into
 * the dashboard summary. Pure over the current db state — safe to call per
 * request. Score stats include only scored sessions; the funnel counts all.
 */
export function computeAnalytics(filters: AnalyticsFilters = {}, generatedAt = new Date().toISOString(), ownerId?: string): AnalyticsSummary {
  const role = filters.role?.trim()

  // Cohort: sessions passing the filters, keyed by createdAt for the date range.
  // When ownerId is set (a non-admin recruiter), the cohort is restricted to
  // sessions that recruiter owns — tenant isolation for aggregate metrics.
  const sessions = [...db.sessions.values()].filter((s) => {
    const template = db.templates.get(s.templateId)
    if (ownerId && s.recruiterId !== ownerId) return false
    if (filters.track && s.track !== filters.track) return false
    if (filters.templateId && s.templateId !== filters.templateId) return false
    if (role && (template?.role?.trim() || '(unspecified)') !== role) return false
    return inRange(s.createdAt, filters.dateFrom, filters.dateTo)
  })

  const created = sessions.length
  const started = sessions.filter((s) => !!s.startedAt || s.status !== 'created').length
  const completed = sessions.filter((s) => s.status === 'completed').length

  const rows: Row[] = sessions
    .map((session) => ({ session, template: db.templates.get(session.templateId), report: db.reports.get(session.id)! }))
    .filter((r) => !!r.report)
  const scored = rows.length

  const overalls = rows.map((r) => r.report.overallScore)
  const averageOverall = mean(overalls)

  // Score distribution — always all five buckets (stable chart), zero-filled.
  const distMap = new Map<string, number>(BUCKETS.map((b) => [b, 0]))
  for (const o of overalls) distMap.set(bucketOf(o), (distMap.get(bucketOf(o)) ?? 0) + 1)
  const scoreDistribution = BUCKETS.map((bucket) => ({ bucket, count: distMap.get(bucket) ?? 0 }))

  // Per-KPI aggregation BY ID across mixed rubrics, with coverage + a label.
  const kpiAgg = new Map<string, { sum: number; count: number; label: string }>()
  for (const r of rows) {
    const rubric = r.template?.rubric
    for (const [kpiId, val] of Object.entries(r.report.kpiAverages)) {
      if (typeof val !== 'number') continue
      const label = rubric?.kpis.find((k) => k.id === kpiId)?.label || kpiId
      const cur = kpiAgg.get(kpiId) ?? { sum: 0, count: 0, label }
      cur.sum += val; cur.count += 1
      if (!cur.label || cur.label === kpiId) cur.label = label
      kpiAgg.set(kpiId, cur)
    }
  }
  const kpiAverages = [...kpiAgg.entries()]
    .map(([kpiId, v]) => ({ kpiId, label: v.label, average: Math.round(v.sum / v.count), coverage: scored ? v.count / scored : 0 }))
    .sort((a, b) => b.average - a.average)

  // By track — count/completionRate over the cohort, averageOverall over scored.
  const trackSet = new Set<TrackType>(sessions.map((s) => s.track))
  const byTrack = [...trackSet].map((track) => {
    const inTrack = sessions.filter((s) => s.track === track)
    const scoredInTrack = rows.filter((r) => r.session.track === track)
    const comp = inTrack.filter((s) => s.status === 'completed').length
    return {
      track,
      count: inTrack.length,
      averageOverall: mean(scoredInTrack.map((r) => r.report.overallScore)),
      completionRate: inTrack.length ? comp / inTrack.length : 0,
    }
  }).sort((a, b) => b.count - a.count)

  // By role (from the template).
  const roleMap = new Map<string, { count: number; scores: number[] }>()
  for (const s of sessions) {
    const r = db.templates.get(s.templateId)?.role?.trim() || '(unspecified)'
    const cur = roleMap.get(r) ?? { count: 0, scores: [] }
    cur.count += 1
    const rep = db.reports.get(s.id)
    if (rep) cur.scores.push(rep.overallScore)
    roleMap.set(r, cur)
  }
  const byRole = [...roleMap.entries()]
    .map(([role, v]) => ({ role, count: v.count, averageOverall: mean(v.scores) }))
    .sort((a, b) => b.count - a.count)

  // By template.
  const tplMap = new Map<string, { name: string; count: number; scores: number[] }>()
  for (const s of sessions) {
    const t = db.templates.get(s.templateId)
    const cur = tplMap.get(s.templateId) ?? { name: t?.name ?? '(deleted template)', count: 0, scores: [] }
    cur.count += 1
    const rep = db.reports.get(s.id)
    if (rep) cur.scores.push(rep.overallScore)
    tplMap.set(s.templateId, cur)
  }
  const byTemplate = [...tplMap.entries()]
    .map(([templateId, v]) => ({ templateId, name: v.name, count: v.count, averageOverall: mean(v.scores) }))
    .sort((a, b) => b.count - a.count)

  // Trend by completion day (UTC).
  const trendMap = new Map<string, number[]>()
  for (const r of rows) {
    const done = r.session.completedAt ?? r.report.generatedAt
    const day = new Date(at(done)).toISOString().slice(0, 10)
    ;(trendMap.get(day) ?? trendMap.set(day, []).get(day)!).push(r.report.overallScore)
  }
  const trend = [...trendMap.entries()]
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([date, scores]) => ({ date, count: scores.length, averageOverall: mean(scores) }))

  // Time stats.
  const durations = rows
    .map((r) => (at(r.session.completedAt) - at(r.session.startedAt)) / 1000)
    .filter((d) => Number.isFinite(d) && d > 0)
  const perQ = rows.map(avgTimePerQuestion).filter((n): n is number => typeof n === 'number')
  const timeStats = {
    avgDurationSeconds: durations.length ? Math.round(durations.reduce((a, b) => a + b, 0) / durations.length) : 0,
    avgTimePerQuestionSeconds: perQ.length ? Math.round(perQ.reduce((a, b) => a + b, 0) / perQ.length) : 0,
  }

  // Recommendation distribution.
  const recMap = new Map<string, number>()
  for (const r of rows) {
    const rec = r.report.recommendation ?? 'unknown'
    recMap.set(rec, (recMap.get(rec) ?? 0) + 1)
  }
  const recommendationDistribution = [...recMap.entries()].map(([recommendation, count]) => ({ recommendation, count }))

  // Integrity flag rate (scored sessions with ≥1 logged event).
  const flagged = rows.filter((r) => (r.session.integrityEvents?.length ?? 0) > 0).length
  const integrityFlagRate = scored ? flagged / scored : 0

  // Top candidates by overall score.
  const topCandidates = [...rows]
    .sort((a, b) => b.report.overallScore - a.report.overallScore)
    .slice(0, 10)
    .map((r) => ({
      sessionId: r.session.id,
      name: r.session.candidate?.name ?? 'Candidate',
      role: r.template?.role?.trim() || undefined,
      overallScore: r.report.overallScore,
    }))

  return {
    totals: { created, started, completed, scored },
    completionRate: created ? completed / created : 0,
    averageOverall,
    scoreDistribution,
    kpiAverages,
    byTrack,
    byRole,
    byTemplate,
    trend,
    timeStats,
    recommendationDistribution,
    integrityFlagRate,
    topCandidates,
    generatedAt,
  }
}
