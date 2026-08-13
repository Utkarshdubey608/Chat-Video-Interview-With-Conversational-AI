import { Type } from '@google/genai'
import { geminiClient, geminiEnabled, modelName } from './gemini'
import type { InterviewSession, SentimentSignals, SpeechMetrics } from '../../shared/types'

/**
 * Transcript-derived interview signals for the conversation tracks (voice,
 * chatbot, video_avatar). Everything here comes from data we actually store —
 * the candidate's transcript and per-answer timing — so nothing is fabricated.
 * Acoustic prosody (pitch/energy) needs the raw audio, which candidate sessions
 * don't persist, so we deliberately do NOT invent it; sentiment is a text read.
 */

// Conservative filler set — only unambiguous fillers, so we never over-penalise
// ordinary words like "so"/"like"/"well" that have legitimate uses.
const FILLER_SINGLE = ['um', 'umm', 'uh', 'uhh', 'er', 'erm', 'ah', 'hmm', 'mmm']
const FILLER_MULTI = ['you know', 'i mean', 'kind of', 'sort of', 'you see']

function candidateAnswers(session: InterviewSession): string[] {
  return (session.transcript ?? [])
    .filter((t) => t.role === 'candidate')
    .map((t) => t.content.trim())
    .filter(Boolean)
}

function countWords(text: string): number {
  const m = text.trim().match(/\S+/g)
  return m ? m.length : 0
}

/** Average candidate response time (seconds) from per-answer timing, if present.
 *  Only the chatbot track records answerStartedAt→submittedAt on its interviewer
 *  turns; voice stamps all turns at finalize time, so this returns undefined. */
function avgResponseSeconds(session: InterviewSession): number | undefined {
  const spans: number[] = []
  for (const t of session.transcript ?? []) {
    if (t.answerStartedAt && t.submittedAt) {
      const ms = new Date(t.submittedAt).getTime() - new Date(t.answerStartedAt).getTime()
      if (ms > 0 && ms < 60 * 60 * 1000) spans.push(ms / 1000)
    }
  }
  if (spans.length === 0) return undefined
  return Math.round(spans.reduce((a, b) => a + b, 0) / spans.length)
}

/** Pure, transcript-derived delivery metrics. Returns null when the candidate
 *  said/typed nothing (nothing meaningful to measure). */
export function computeSpeechMetrics(session: InterviewSession): SpeechMetrics | null {
  const spoken = session.track === 'voice' || session.track === 'video_avatar' || session.track === 'video' || session.track === 'two_way'
  const answers = candidateAnswers(session)
  if (answers.length === 0) return null

  const joined = answers.join(' ')
  const words = countWords(joined)
  if (words === 0) return null

  const lower = ` ${joined.toLowerCase().replace(/[^\p{L}\s']/gu, ' ').replace(/\s+/g, ' ')} `
  let fillerCount = 0
  for (const f of FILLER_SINGLE) {
    const m = lower.match(new RegExp(`\\s${f}\\s`, 'g'))
    if (m) fillerCount += m.length
  }
  for (const f of FILLER_MULTI) {
    const m = lower.match(new RegExp(`\\s${f}\\s`, 'g'))
    if (m) fillerCount += m.length
  }

  const tokens = lower.trim().split(/\s+/).filter(Boolean)
  const unique = new Set(tokens).size
  const vocabularyPct = tokens.length ? Math.round((unique / tokens.length) * 100) : 0

  return {
    words,
    answers: answers.length,
    avgWordsPerAnswer: Math.round(words / answers.length),
    fillerCount,
    fillerPer100: words ? Math.round((fillerCount / words) * 1000) / 10 : 0,
    vocabularyPct,
    avgResponseSeconds: avgResponseSeconds(session),
    spoken,
  }
}

const SENTIMENT_SCHEMA = {
  type: Type.OBJECT,
  properties: {
    overall: { type: Type.STRING, enum: ['positive', 'neutral', 'negative', 'mixed'] },
    confidence: { type: Type.NUMBER },
    clarity: { type: Type.NUMBER },
    positivity: { type: Type.NUMBER },
    summary: { type: Type.STRING },
  },
  required: ['overall', 'confidence', 'clarity', 'positivity', 'summary'],
} as const

const clamp = (n: unknown): number =>
  Math.max(0, Math.min(100, Math.round(typeof n === 'number' && Number.isFinite(n) ? n : 0)))

/**
 * Text-based communication/sentiment read over the candidate's answers. This is
 * NOT acoustic emotion — it's what the words convey (confidence, clarity, tone).
 * Returns null when there's no key or nothing to analyse.
 */
export async function analyzeSentiment(session: InterviewSession): Promise<SentimentSignals | null> {
  if (!geminiEnabled()) return null
  const answers = candidateAnswers(session)
  if (answers.length === 0) return null

  const transcript = answers.map((a, i) => `Answer ${i + 1}: ${a}`).join('\n').slice(0, 12000)
  const prompt =
    `You are analysing ONLY the candidate's answers from an interview transcript to gauge how they COMMUNICATED ` +
    `(not whether the answers are technically correct). Judge from the words alone.\n\n` +
    `Return:\n` +
    `- overall: the dominant sentiment/tone (positive, neutral, negative, or mixed)\n` +
    `- confidence (0-100): how self-assured and decisive the wording is\n` +
    `- clarity (0-100): how clear, structured and articulate the responses are\n` +
    `- positivity (0-100): how positive and constructive the tone is\n` +
    `- summary: one or two sentences on their communication style.\n\n` +
    `CANDIDATE ANSWERS:\n"""\n${transcript}\n"""`

  try {
    const res = await geminiClient().models.generateContent({
      model: modelName(),
      contents: prompt,
      config: { responseMimeType: 'application/json', responseSchema: SENTIMENT_SCHEMA, temperature: 0.2 },
    })
    const raw = JSON.parse(res.text ?? '{}') as Partial<SentimentSignals>
    const overall =
      raw.overall === 'positive' || raw.overall === 'negative' || raw.overall === 'mixed'
        ? raw.overall
        : 'neutral'
    return {
      overall,
      confidence: clamp(raw.confidence),
      clarity: clamp(raw.clarity),
      positivity: clamp(raw.positivity),
      summary: typeof raw.summary === 'string' && raw.summary.trim() ? raw.summary.trim() : 'No summary returned.',
    }
  } catch (err) {
    console.error('[signals] sentiment analysis failed:', err instanceof Error ? err.message : err)
    return null
  }
}
