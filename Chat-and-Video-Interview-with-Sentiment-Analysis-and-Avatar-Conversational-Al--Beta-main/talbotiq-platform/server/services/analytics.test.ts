/**
 * Deterministic unit tests for the analytics aggregation. Run with:
 *   npx tsx server/services/analytics.test.ts
 * Populates the in-memory db directly (no network/Gemini) and asserts the
 * aggregate over a mixed-rubric, mixed-track, partially-completed dataset.
 */
import type { InterviewSession, InterviewTemplate, KpiRubric, ResultReport, SessionQuestion } from '../../shared/types'
import { db } from '../store/db'
import { computeAnalytics } from './analytics'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

const rubric = (kpis: [string, string][]): KpiRubric => ({
  scoreScale: 100,
  kpis: kpis.map(([id, label]) => ({ id, label, description: '', weight: 1, enabled: true })),
})
const tpl = (o: Partial<InterviewTemplate> & Pick<InterviewTemplate, 'id' | 'role' | 'track' | 'rubric'>): InterviewTemplate => ({
  name: o.id, questionSource: 'adaptive',
  timing: { prepSeconds: 30, answerSeconds: 120, allowSkipPrep: true, allowEarlySubmit: true, warningThresholdSeconds: 15 },
  integrity: { enforceFullscreen: false, detectTabSwitch: false, disablePasteInAnswers: false, disableCopy: false, maxTabSwitchWarnings: 3, logEvents: true },
  branding: { companyName: 'X', accentColor: '#000' }, createdAt: '', updatedAt: '', ...o,
})
const sess = (o: Partial<InterviewSession> & Pick<InterviewSession, 'id' | 'templateId' | 'track' | 'status' | 'createdAt'>): InterviewSession => ({
  candidate: { name: o.id, email: '' }, questions: [], currentIndex: 0, integrityEvents: [], tabSwitchCount: 0, ...o,
})
const rep = (sessionId: string, overallScore: number, kpiAverages: Record<string, number>, recommendation: ResultReport['recommendation'], nQ = 3): ResultReport => ({
  sessionId, overallScore, kpiAverages, recommendation, summary: '', generatedAt: '2026-07-03T12:00:00.000Z',
  perQuestion: Array.from({ length: nQ }, (_, i) => ({ questionId: `q${i}`, kpiScores: {}, feedback: '' })),
})

// ── Build the dataset ────────────────────────────────────────────────────
db.templates.clear(); db.sessions.clear(); db.reports.clear()
db.templates.set('tA', tpl({ id: 'tA', role: 'Engineer', track: 'chatbot', rubric: rubric([['comm', 'Communication'], ['depth', 'Depth']]) }))
db.templates.set('tB', tpl({ id: 'tB', role: 'Designer', track: 'chat', rubric: rubric([['comm', 'Communication'], ['creativity', 'Creativity']]) }))

const timedQ = (start: string, secs: number): SessionQuestion => ({
  id: 'q', text: 'q', autoSubmitted: false, answerStartedAt: start, submittedAt: new Date(Date.parse(start) + secs * 1000).toISOString(),
})

db.sessions.set('s1', sess({ id: 's1', templateId: 'tA', track: 'chatbot', status: 'completed', createdAt: '2026-07-01T12:00:00.000Z', startedAt: '2026-07-01T12:00:00.000Z', completedAt: '2026-07-01T12:05:00.000Z' }))
db.sessions.set('s2', sess({ id: 's2', templateId: 'tA', track: 'chatbot', status: 'completed', createdAt: '2026-07-02T12:00:00.000Z', startedAt: '2026-07-02T12:00:00.000Z', completedAt: '2026-07-02T12:04:00.000Z', integrityEvents: [{ type: 'tab_switch', at: '2026-07-02T12:01:00.000Z' }] }))
db.sessions.set('s3', sess({ id: 's3', templateId: 'tB', track: 'chat', status: 'completed', createdAt: '2026-07-03T12:00:00.000Z', startedAt: '2026-07-03T12:00:00.000Z', completedAt: '2026-07-03T12:03:00.000Z', questions: [timedQ('2026-07-03T12:00:00.000Z', 30), timedQ('2026-07-03T12:01:00.000Z', 50)] }))
db.sessions.set('s4', sess({ id: 's4', templateId: 'tB', track: 'chat', status: 'created', createdAt: '2026-07-04T12:00:00.000Z' }))
db.sessions.set('s5', sess({ id: 's5', templateId: 'tA', track: 'chatbot', status: 'in_progress', createdAt: '2026-07-05T12:00:00.000Z', startedAt: '2026-07-05T12:00:00.000Z' }))

db.reports.set('s1', rep('s1', 90, { comm: 88, depth: 92 }, 'strong_yes'))
db.reports.set('s2', rep('s2', 60, { comm: 55, depth: 65 }, 'maybe'))
db.reports.set('s3', rep('s3', 40, { comm: 45, creativity: 35 }, 'no', 2))

// ── 1. Funnel + headline ───────────────────────────────────────────────────
{
  console.log('\n=== 1. Funnel + averages (no filter) ===')
  const a = computeAnalytics({}, '2026-07-06T00:00:00.000Z')
  assert('created=5', a.totals.created === 5, `${a.totals.created}`)
  assert('started=4', a.totals.started === 4, `${a.totals.started}`)
  assert('completed=3', a.totals.completed === 3, `${a.totals.completed}`)
  assert('scored=3', a.totals.scored === 3, `${a.totals.scored}`)
  assert('completionRate=0.6', Math.abs(a.completionRate - 0.6) < 1e-9)
  assert('averageOverall=63 (mean 90/60/40)', a.averageOverall === 63, `${a.averageOverall}`)
  assert('integrityFlagRate=1/3', Math.abs(a.integrityFlagRate - 1 / 3) < 1e-9)
}

// ── 2. Score distribution always 5 buckets, correct counts ─────────────────
{
  console.log('\n=== 2. Score distribution ===')
  const a = computeAnalytics({})
  assert('5 buckets', a.scoreDistribution.length === 5)
  const g = (b: string) => a.scoreDistribution.find((x) => x.bucket === b)?.count
  assert('81-100 = 1 (score 90)', g('81-100') === 1)
  assert('41-60 = 1 (score 60)', g('41-60') === 1)
  assert('21-40 = 1 (score 40)', g('21-40') === 1)
  assert('0-20 = 0', g('0-20') === 0)
}

// ── 3. KPI-by-id aggregation across MIXED rubrics + coverage ───────────────
{
  console.log('\n=== 3. Mixed-rubric KPI aggregation ===')
  const a = computeAnalytics({})
  const comm = a.kpiAverages.find((k) => k.kpiId === 'comm')
  const depth = a.kpiAverages.find((k) => k.kpiId === 'depth')
  const creativity = a.kpiAverages.find((k) => k.kpiId === 'creativity')
  assert('comm avg=63 (88,55,45), coverage=1', comm?.average === 63 && comm?.coverage === 1, JSON.stringify(comm))
  assert('comm label resolved', comm?.label === 'Communication')
  assert('depth avg=79 (92,65), coverage=2/3', depth?.average === 79 && Math.abs((depth?.coverage ?? 0) - 2 / 3) < 1e-9, JSON.stringify(depth))
  assert('creativity avg=35, coverage=1/3 (only tB had it)', creativity?.average === 35 && Math.abs((creativity?.coverage ?? 0) - 1 / 3) < 1e-9, JSON.stringify(creativity))
}

// ── 4. By-track + by-role breakdowns ───────────────────────────────────────
{
  console.log('\n=== 4. Breakdowns ===')
  const a = computeAnalytics({})
  const cb = a.byTrack.find((t) => t.track === 'chatbot')
  const ch = a.byTrack.find((t) => t.track === 'chat')
  assert('chatbot: count=3, avg=75 (90,60), completion=2/3', cb?.count === 3 && cb?.averageOverall === 75 && Math.abs((cb?.completionRate ?? 0) - 2 / 3) < 1e-9, JSON.stringify(cb))
  assert('chat: count=2, avg=40, completion=0.5', ch?.count === 2 && ch?.averageOverall === 40 && ch?.completionRate === 0.5, JSON.stringify(ch))
  const eng = a.byRole.find((r) => r.role === 'Engineer')
  const des = a.byRole.find((r) => r.role === 'Designer')
  assert('Engineer: count=3, avg=75', eng?.count === 3 && eng?.averageOverall === 75, JSON.stringify(eng))
  assert('Designer: count=2, avg=40', des?.count === 2 && des?.averageOverall === 40, JSON.stringify(des))
  const bt = a.byTemplate.find((t) => t.templateId === 'tA')
  assert('byTemplate tA: name, count=3, avg=75', bt?.name === 'tA' && bt?.count === 3 && bt?.averageOverall === 75, JSON.stringify(bt))
  assert('byTemplate tB: count=2, avg=40', a.byTemplate.find((t) => t.templateId === 'tB')?.averageOverall === 40)
}

// ── 5. Trend, recommendations, top candidates, time stats ──────────────────
{
  console.log('\n=== 5. Trend / recs / top / time ===')
  const a = computeAnalytics({})
  assert('trend has 3 days sorted', a.trend.length === 3 && a.trend[0].date === '2026-07-01' && a.trend[2].date === '2026-07-03')
  assert('recommendations counted', a.recommendationDistribution.reduce((s, r) => s + r.count, 0) === 3)
  assert('top candidate is s1 @90', a.topCandidates[0]?.sessionId === 's1' && a.topCandidates[0]?.overallScore === 90)
  assert('top candidate carries role', a.topCandidates[0]?.role === 'Engineer')
  assert('avgDuration > 0', a.timeStats.avgDurationSeconds > 0, `${a.timeStats.avgDurationSeconds}`)
  assert('avgTimePerQuestion > 0 (chat real timing 30/50s)', a.timeStats.avgTimePerQuestionSeconds > 0, `${a.timeStats.avgTimePerQuestionSeconds}`)
}

// ── 6. Filters ─────────────────────────────────────────────────────────────
{
  console.log('\n=== 6. Filters ===')
  assert('track=chat → scored 1, avg 40', (() => { const a = computeAnalytics({ track: 'chat' }); return a.totals.scored === 1 && a.averageOverall === 40 })())
  assert('templateId=tA → scored 2', computeAnalytics({ templateId: 'tA' }).totals.scored === 2)
  assert('role=Designer → scored 1', computeAnalytics({ role: 'Designer' }).totals.scored === 1)
  assert('dateFrom excludes early → created 2 (07-04,07-05)', computeAnalytics({ dateFrom: '2026-07-04' }).totals.created === 2)
  assert('dateTo inclusive of full day 07-02 → created 2', computeAnalytics({ dateTo: '2026-07-02' }).totals.created === 2)
  assert('empty date window → zeros + empty arrays', (() => { const a = computeAnalytics({ dateFrom: '2030-01-01' }); return a.totals.created === 0 && a.averageOverall === 0 && a.kpiAverages.length === 0 && a.topCandidates.length === 0 })())
}

console.log(`\n${failures === 0 ? '✅ ALL ANALYTICS TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
