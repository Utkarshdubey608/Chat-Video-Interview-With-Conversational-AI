import type {
  InterviewSession,
  InterviewTemplate,
  KpiRubric,
  ResultReport,
  PerQuestionResult,
  Recommendation,
} from '../../shared/types'
import { scoreWithGemini, scoreConversationWithGemini, geminiEnabled, type RawScore } from './gemini'
import { primaryQuestionGroups } from './conversation'
import { analyzeSentiment } from './signals'

/** Attach the text-based communication/sentiment read to a conversation report
 *  (best-effort — scoring never fails because sentiment couldn't be produced). */
async function withSentiment(session: InterviewSession, report: ResultReport): Promise<ResultReport> {
  const sentiment = await analyzeSentiment(session).catch(() => null)
  if (sentiment) report.sentiment = sentiment
  return report
}

const RECS: Recommendation[] = ['strong_yes', 'yes', 'maybe', 'no']
const clamp = (n: number) => Math.max(0, Math.min(100, Math.round(n)))

/**
 * Weighted overall — computed in OUR code, never trusted to the model.
 * Enabled-KPI weights are normalized, then applied to the per-KPI averages.
 */
export function weightedOverall(rubric: KpiRubric, kpiAverages: Record<string, number>): number {
  const enabled = rubric.kpis.filter((k) => k.enabled && k.weight > 0)
  const totalWeight = enabled.reduce((s, k) => s + k.weight, 0)
  if (totalWeight === 0) return 0
  let sum = 0
  for (const k of enabled) sum += ((kpiAverages[k.id] ?? 0) * k.weight) / totalWeight
  return Math.round(sum)
}

export function averageKpis(rubric: KpiRubric, perQuestion: PerQuestionResult[]): Record<string, number> {
  const out: Record<string, number> = {}
  for (const k of rubric.kpis.filter((k) => k.enabled)) {
    const vals = perQuestion
      .map((p) => p.kpiScores[k.id])
      .filter((v): v is number => typeof v === 'number')
    out[k.id] = vals.length ? Math.round(vals.reduce((a, b) => a + b, 0) / vals.length) : 0
  }
  return out
}

export function recommendationFor(overall: number): Recommendation {
  if (overall >= 80) return 'strong_yes'
  if (overall >= 65) return 'yes'
  if (overall >= 50) return 'maybe'
  return 'no'
}

/* ─── Public entry: Gemini if configured, heuristic fallback otherwise ───── */

export async function scoreSession(
  session: InterviewSession,
  template: InterviewTemplate,
): Promise<ResultReport> {
  if (session.track === 'chatbot' || session.track === 'video_avatar' || session.track === 'voice' || session.track === 'video' || session.track === 'two_way')
    return scoreConversation(session, template)

  if (geminiEnabled()) {
    try {
      const raw = await scoreWithGemini(session, template)
      return assembleFromGemini(session, template, raw)
    } catch (err) {
      console.error('[scoring] Gemini scoring failed, using heuristic fallback:', err)
    }
  }
  return heuristicReport(session, template)
}

/* ─── Conversational (chatbot) scoring ──────────────────────────────────── */

async function scoreConversation(
  session: InterviewSession,
  template: InterviewTemplate,
): Promise<ResultReport> {
  // No candidate answers at all → do NOT ask the model to "evaluate" an empty
  // transcript (it returns a misleading "No transcript was provided" summary
  // with 0/No scores that read like a real judgment). Produce an honest
  // not-evaluated report instead.
  const answered =
    primaryQuestionGroups(session).some((g) => g.answer.trim()) ||
    (session.transcript ?? []).some((t) => t.role === 'candidate' && t.content.trim())
  if (!answered) return notEvaluatedReport(session, template)

  if (geminiEnabled()) {
    try {
      const raw = await scoreConversationWithGemini(session, template)
      const enabledIds = new Set(template.rubric.kpis.filter((k) => k.enabled).map((k) => k.id))
      const perQuestion: PerQuestionResult[] = primaryQuestionGroups(session).map((g) => {
        const match = raw.perQuestion?.find((p) => p.questionIndex === g.index)
        const kpiScores: Record<string, number> = {}
        for (const s of match?.scores ?? []) if (enabledIds.has(s.kpiId)) kpiScores[s.kpiId] = clamp(s.score)
        return { questionId: `q${g.index}`, kpiScores, feedback: match?.feedback ?? 'No feedback returned.' }
      })
      const kpiAverages = averageKpis(template.rubric, perQuestion)
      const overallScore = weightedOverall(template.rubric, kpiAverages)
      return withSentiment(session, {
        sessionId: session.id,
        perQuestion,
        kpiAverages,
        overallScore,
        summary: raw.summary || 'No summary returned.',
        strengths: Array.isArray(raw.strengths) ? raw.strengths : [],
        improvements: Array.isArray(raw.improvements) ? raw.improvements : [],
        recommendation: RECS.includes(raw.recommendation as Recommendation)
          ? (raw.recommendation as Recommendation)
          : recommendationFor(overallScore),
        generatedAt: new Date().toISOString(),
      })
    } catch (err) {
      console.error('[scoring] conversation scoring failed, using heuristic fallback:', err)
    }
  }

  // Heuristic fallback over the grouped transcript.
  const enabled = template.rubric.kpis.filter((k) => k.enabled)
  const perQuestion: PerQuestionResult[] = primaryQuestionGroups(session).map((g) => {
    const kpiScores: Record<string, number> = {}
    for (const k of enabled) kpiScores[k.id] = heuristicScore(g.answer, k.id)
    return {
      questionId: `q${g.index}`,
      kpiScores,
      feedback: g.answer.trim() ? 'Heuristic placeholder — add a GEMINI_API_KEY for content-aware feedback.' : 'No answer was provided.',
    }
  })
  const kpiAverages = averageKpis(template.rubric, perQuestion)
  const overallScore = weightedOverall(template.rubric, kpiAverages)
  return withSentiment(session, {
    sessionId: session.id,
    perQuestion,
    kpiAverages,
    overallScore,
    summary: 'Generated by the heuristic fallback (no Gemini key). Scores reflect answer length only.',
    recommendation: recommendationFor(overallScore),
    generatedAt: new Date().toISOString(),
    degraded: true,
  })
}

/**
 * Honest report for a conversation interview where no candidate answers were
 * captured (client transcript bridge failed, call dropped, etc.). Keeps the
 * planned questions visible, hides the recommendation, and flags itself so the
 * UI can say "not evaluated" instead of implying the candidate scored zero.
 */
function notEvaluatedReport(session: InterviewSession, template: InterviewTemplate): ResultReport {
  const perQuestion: PerQuestionResult[] = session.questions.map((_q, i) => ({
    questionId: `q${i}`,
    kpiScores: {},
    feedback: 'No answer was captured for this question.',
  }))
  return {
    sessionId: session.id,
    perQuestion,
    kpiAverages: averageKpis(template.rubric, perQuestion),
    overallScore: 0,
    summary:
      'No candidate answers were captured for this interview, so it was not evaluated. ' +
      'This usually means the interview audio or transcript was not recorded (the call may have ended early, or capture failed). ' +
      'Please ask the candidate to retake the interview, or check the avatar/voice configuration in Settings.',
    generatedAt: new Date().toISOString(),
    notEvaluated: true,
  }
}

function assembleFromGemini(
  session: InterviewSession,
  template: InterviewTemplate,
  raw: RawScore,
): ResultReport {
  const enabledIds = new Set(template.rubric.kpis.filter((k) => k.enabled).map((k) => k.id))

  const perQuestion: PerQuestionResult[] = session.questions.map((q) => {
    const match = raw.perQuestion?.find((p) => p.questionId === q.id)
    const kpiScores: Record<string, number> = {}
    for (const s of match?.scores ?? []) {
      if (enabledIds.has(s.kpiId)) kpiScores[s.kpiId] = clamp(s.score)
    }
    return { questionId: q.id, kpiScores, feedback: match?.feedback ?? 'No feedback returned.' }
  })

  const kpiAverages = averageKpis(template.rubric, perQuestion)
  const overallScore = weightedOverall(template.rubric, kpiAverages)
  const recommendation = RECS.includes(raw.recommendation as Recommendation)
    ? (raw.recommendation as Recommendation)
    : recommendationFor(overallScore)

  return {
    sessionId: session.id,
    perQuestion,
    kpiAverages,
    overallScore,
    summary: raw.summary || 'No summary returned.',
    recommendation,
    generatedAt: new Date().toISOString(),
  }
}

/* ─── Deterministic heuristic fallback (no Gemini key) ──────────────────── */

function hash(s: string): number {
  let h = 2166136261
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return Math.abs(h)
}
function heuristicScore(answer: string, kpiId: string): number {
  const words = answer.trim().split(/\s+/).filter(Boolean).length
  if (words === 0) return 0
  const base = Math.min(90, 45 + Math.round(Math.min(words, 180) / 4))
  const spread = (hash(kpiId + ':' + answer.slice(0, 40)) % 17) - 8
  return clamp(base + spread)
}

export function heuristicReport(session: InterviewSession, template: InterviewTemplate): ResultReport {
  const enabled = template.rubric.kpis.filter((k) => k.enabled)
  const perQuestion: PerQuestionResult[] = session.questions.map((q) => {
    const answer = q.answerText ?? ''
    const kpiScores: Record<string, number> = {}
    for (const k of enabled) kpiScores[k.id] = heuristicScore(answer, k.id)
    return {
      questionId: q.id,
      kpiScores,
      feedback: answer.trim()
        ? 'Heuristic placeholder — add a GEMINI_API_KEY for substantive, content-aware feedback.'
        : 'No answer was provided for this question.',
    }
  })
  const kpiAverages = averageKpis(template.rubric, perQuestion)
  const overallScore = weightedOverall(template.rubric, kpiAverages)
  return {
    sessionId: session.id,
    perQuestion,
    kpiAverages,
    overallScore,
    summary:
      'Generated by the heuristic fallback (no Gemini key configured). Scores reflect answer length only, not content quality.',
    recommendation: recommendationFor(overallScore),
    generatedAt: new Date().toISOString(),
    degraded: true,
  }
}
