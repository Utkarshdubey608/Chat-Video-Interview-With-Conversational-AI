// ── Emotion primitives ────────────────────────────────────────────────────────

export interface HumeEmotion {
  name: string
  score: number
}

export type EmotionCategory =
  | 'positive_high'
  | 'positive_calm'
  | 'cognitive'
  | 'social'
  | 'negative'
  | 'disengagement'

export const EMOTION_CATEGORY_MAP: Record<EmotionCategory, string[]> = {
  positive_high: [
    'Admiration', 'Amusement', 'Excitement', 'Elation', 'Enthusiasm',
    'Pride', 'Triumph', 'Joy', 'Ecstasy',
  ],
  positive_calm: [
    'Calmness', 'Contentment', 'Satisfaction', 'Serenity', 'Awe',
    'Aesthetic Appreciation', 'Contemplation', 'Adoration', 'Interest',
  ],
  cognitive: [
    'Concentration', 'Contemplation', 'Curiosity', 'Determination',
    'Realization', 'Surprise (positive)', 'Surprise (negative)',
  ],
  social: [
    'Empathic Pain', 'Sympathy', 'Romance', 'Desire', 'Envy',
    'Jealousy', 'Nostalgia', 'Longing',
  ],
  negative: [
    'Anger', 'Anxiety', 'Confusion', 'Contempt', 'Disappointment',
    'Disgust', 'Distress', 'Embarrassment', 'Fear', 'Guilt',
    'Horror', 'Shame', 'Sadness', 'Tiredness', 'Pain',
  ],
  disengagement: [
    'Boredom', 'Doubt', 'Awkwardness', 'Sickness',
  ],
}

export function categorizeEmotion(name: string): EmotionCategory {
  for (const [cat, names] of Object.entries(EMOTION_CATEGORY_MAP)) {
    if (names.some(n => n.toLowerCase() === name.toLowerCase())) {
      return cat as EmotionCategory
    }
  }
  return 'cognitive'
}

// ── EVI WebSocket types ───────────────────────────────────────────────────────

export interface EviSessionSettings {
  type: 'session_settings'
  audio: {
    encoding: 'linear16'
    sample_rate: number
    channels: number
  }
}

export interface EviAudioInput {
  type: 'audio_input'
  data: string // base64 PCM
}

export interface EviUserMessage {
  type: 'user_message'
  message: { role: 'user'; content: string }
  models: {
    prosody?: {
      predictions: Array<{
        time: { begin: number; end: number }
        emotions: HumeEmotion[]
      }>
    }
  }
}

export interface EviAssistantMessage {
  type: 'assistant_message'
  message: { role: 'assistant'; content: string }
}

export interface EviError {
  type: 'error'
  code: string
  message: string
}

export type EviInboundMessage = EviUserMessage | EviAssistantMessage | EviError | { type: string }

// ── Batch API types ───────────────────────────────────────────────────────────

export type BatchJobStatus = 'QUEUED' | 'IN_PROGRESS' | 'COMPLETED' | 'FAILED'

export interface BatchJob {
  job_id: string
  status: BatchJobStatus
  created_at: number
  completed_at?: number
}

export interface BatchPrediction {
  source: { type: string; filename: string }
  results: {
    predictions: Array<{
      file: string
      models: {
        prosody?: {
          grouped_predictions: Array<{
            id: string
            predictions: Array<{
              time: { begin: number; end: number }
              emotions: HumeEmotion[]
            }>
          }>
        }
        face?: {
          grouped_predictions: Array<{
            id: string
            predictions: Array<{
              frame: number
              time: number
              emotions: HumeEmotion[]
            }>
          }>
        }
      }
    }>
    errors: Array<{ file: string; message: string }>
  }
}

// ── Aggregated / processed types ──────────────────────────────────────────────

export interface EmotionSnapshot {
  timestamp: number
  emotions: HumeEmotion[]
  categoryScores: Record<EmotionCategory, number>
  dominant: string
}

export interface QuestionEmotionSummary {
  questionIdx: number
  questionText: string
  avgCategoryScores: Record<EmotionCategory, number>
  dominant: string
  timeline: EmotionSnapshot[]
  topEmotions: HumeEmotion[]
}

export interface HumeSessionResult {
  jobId: string
  status: BatchJobStatus
  overallCategoryScores: Record<EmotionCategory, number>
  overallTopEmotions: HumeEmotion[]
  perQuestion: QuestionEmotionSummary[]
  timeline: EmotionSnapshot[]
  compositeScore: number
}

// ── Store slice types ─────────────────────────────────────────────────────────

export interface HumeStoreSlice {
  humeApiKey: string
  humeJobId: string | null
  humeJobStatus: BatchJobStatus | null
  humeResult: HumeSessionResult | null
  questionTimestamps: number[]
  liveEmotions: HumeEmotion[]
  humeStreamActive: boolean
  setHumeApiKey: (key: string) => void
  setHumeJobId: (id: string | null) => void
  setHumeJobStatus: (s: BatchJobStatus | null) => void
  setHumeResult: (r: HumeSessionResult | null) => void
  pushQuestionTimestamp: (ts: number) => void
  resetQuestionTimestamps: () => void
  setLiveEmotions: (e: HumeEmotion[]) => void
  setHumeStreamActive: (v: boolean) => void
}
