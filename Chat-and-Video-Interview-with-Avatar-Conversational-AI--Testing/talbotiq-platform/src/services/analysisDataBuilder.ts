// src/services/analysisDataBuilder.ts
// Builds a GeminiAnalysisInput from this app's real store data:
//  - Deepgram transcript entries (already tagged with questionIdx at capture time)
//  - Hume batch result (per-question prosody summaries + session top emotions)
//  - Live metrics (WPM, filler count)

import { FILLER_WORDS, countFillers, type TranscriptEntry } from '@/services/deepgram'
import type { HumeSessionResult } from '@/types/hume.types'
import type { FacialSessionSummary } from '@/types/rekognition.types'
import type { GeminiAnalysisInput, QuestionAnswerInput } from '@/services/geminiAnalysis'

export interface BuilderInput {
  candidateName: string
  jobRole: string
  questions: string[]
  transcript: TranscriptEntry[]      // store.sessionTranscript
  humeResult: HumeSessionResult | null
  wpm: number                        // store.metrics.wpm
  totalFillers: number               // store.metrics.fillers
  facialSummary?: FacialSessionSummary | null  // optional AWS Rekognition facial signal
}

function extractFillerWords(text: string): string[] {
  const words = text.toLowerCase().replace(/[.,!?;:]/g, '').split(/\s+/)
  return [...new Set(words.filter(w => FILLER_WORDS.has(w)))]
}

export function buildGeminiInput(input: BuilderInput): GeminiAnalysisInput {
  const candidateEntries = input.transcript.filter(e => e.role === 'candidate')

  // Interview duration from transcript timestamps (first → last candidate utterance)
  const timestamps = candidateEntries.map(e => e.timestamp).filter(Boolean)
  const interviewDurationSeconds = timestamps.length >= 2
    ? Math.max(0, (Math.max(...timestamps) - Math.min(...timestamps)) / 1000)
    : 0

  const overallTranscript = candidateEntries.map(e => e.text).join(' ').trim()
  const overallFillers = input.totalFillers || candidateEntries.reduce((a, e) => a + countFillers(e.text), 0)
  const overallFillerRate = interviewDurationSeconds > 0
    ? (overallFillers / interviewDurationSeconds) * 60
    : 0

  const hasHumeData = !!input.humeResult && input.humeResult.perQuestion.length > 0

  // Session-level top emotions from Hume
  const humeTopEmotions = (input.humeResult?.overallTopEmotions ?? [])
    .slice(0, 15)
    .map(e => ({ name: e.name, score: e.score }))

  // Per-question answers — group transcript by questionIdx, enrich with Hume per-question prosody
  const questions: QuestionAnswerInput[] = input.questions.map((questionText, idx) => {
    const entries = candidateEntries.filter(e => e.questionIdx === idx)
    const answerTranscript = entries.map(e => e.text).join(' ').trim()
    const wordCount = answerTranscript ? answerTranscript.split(/\s+/).filter(Boolean).length : 0
    const fillerWords = extractFillerWords(answerTranscript)
    const fillerCount = entries.reduce((a, e) => a + countFillers(e.text), 0)

    const humeQ = input.humeResult?.perQuestion.find(q => q.questionIdx === idx)
    const topEmotions = (humeQ?.topEmotions ?? []).slice(0, 8).map(e => ({ name: e.name, score: e.score }))

    return {
      questionIdx: idx,
      questionText,
      answerTranscript,
      wordCount,
      fillerCount,
      fillerWords,
      topEmotions,
      dominantEmotion: humeQ?.dominant,
      hasEmotionData: !!humeQ && topEmotions.length > 0,
    }
  })

  return {
    candidateName: input.candidateName,
    jobRole: input.jobRole,
    interviewDurationSeconds,
    questions,
    overallTranscript,
    overallWPM: input.wpm,
    overallFillers,
    overallFillerRate,
    humeTopEmotions,
    humeCompositeScore: input.humeResult?.compositeScore ?? null,
    hasHumeData,
    facialSummary: input.facialSummary ?? null,
  }
}
