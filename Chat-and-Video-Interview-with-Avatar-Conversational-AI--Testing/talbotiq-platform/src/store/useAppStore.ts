import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import { tavus } from '@/services/tavus'
import { humeService } from '@/services/hume'
import { deepgramService } from '@/services/deepgram'
import type { TavusConversation, SupportedLanguage, PipelineMode } from '@/types/tavus.types'
import type { HumeEmotion, BatchJobStatus, HumeSessionResult } from '@/types/hume.types'
import type { TranscriptEntry } from '@/services/deepgram'

export type { TranscriptEntry }

export interface DraftForm {
  replica_id: string; persona_id: string; conversation_name: string
  conversational_context: string; custom_greeting: string; callback_url: string
  max_call_duration: number; participant_left_timeout: number; participant_absent_timeout: number
  enable_recording: boolean; enable_transcription: boolean; apply_conversation_override: boolean
  apply_greenscreen: boolean; background_url: string; language: SupportedLanguage
  pipeline_mode: PipelineMode; recording_s3_bucket_name: string
  recording_s3_bucket_region: string; aws_assume_role_arn: string
}

export interface Draft {
  id: string
  name: string
  savedAt: string
  form: DraftForm
  questions: string[]
}

interface AppState {
  // API keys
  tavusKey: string
  deepgramKey: string
  humeKey: string
  awsKey: string
  anthropicKey: string
  geminiKey: string
  awsProxyUrl: string
  webhookUrl: string

  // Defaults
  defaultReplicaId: string
  defaultPersonaId: string

  // Active interview session
  currentConversation: TavusConversation | null
  questions: string[]
  currentQuestionIdx: number
  interviewActive: boolean

  // Saved drafts
  drafts: Draft[]

  // Live metrics
  metrics: {
    confidence: number
    anxiety: number
    wpm: number
    fillers: number
    engagement: number
  }

  // Hume AI
  humeJobId: string | null
  humeJobStatus: BatchJobStatus | null
  humeResult: HumeSessionResult | null
  questionTimestamps: number[]
  liveEmotions: HumeEmotion[]
  humeStreamActive: boolean

  // Deepgram transcript
  sessionTranscript: TranscriptEntry[]
  deepgramConnected: boolean

  // Actions
  setTavusKey: (k: string) => void
  setDeepgramKey: (k: string) => void
  setHumeKey: (k: string) => void
  setAwsKey: (k: string) => void
  setAnthropicKey: (k: string) => void
  setGeminiKey: (k: string) => void
  setAwsProxyUrl: (url: string) => void
  setWebhookUrl: (k: string) => void
  setDefaultReplicaId: (id: string) => void
  setDefaultPersonaId: (id: string) => void
  setCurrentConversation: (c: TavusConversation | null) => void
  setQuestions: (q: string[]) => void
  setCurrentQuestionIdx: (i: number) => void
  setInterviewActive: (v: boolean) => void
  updateMetrics: (m: Partial<AppState['metrics']>) => void
  saveDraft: (name: string, form: DraftForm, questions: string[]) => void
  deleteDraft: (id: string) => void
  setHumeJobId: (id: string | null) => void
  setHumeJobStatus: (s: BatchJobStatus | null) => void
  setHumeResult: (r: HumeSessionResult | null) => void
  pushQuestionTimestamp: (ts: number) => void
  resetQuestionTimestamps: () => void
  setLiveEmotions: (e: HumeEmotion[]) => void
  setHumeStreamActive: (v: boolean) => void
  pushTranscriptEntry: (e: TranscriptEntry) => void
  clearSessionTranscript: () => void
  setDeepgramConnected: (v: boolean) => void
  reset: () => void
}

export const useAppStore = create<AppState>()(
  persist(
    (set) => ({
      tavusKey: '',
      deepgramKey: import.meta.env.VITE_DEEPGRAM_KEY ?? '',
      humeKey: import.meta.env.VITE_HUME_KEY ?? '',
      awsKey: '',
      anthropicKey: '',
      geminiKey: import.meta.env.VITE_GEMINI_KEY ?? '',
      awsProxyUrl: import.meta.env.VITE_REKOGNITION_PROXY_URL ?? '',
      webhookUrl: '',
      defaultReplicaId: '',
      defaultPersonaId: '',
      currentConversation: null,
      drafts: [],
      questions: [
        'Tell me about yourself and your background.',
        'Describe a challenging problem you solved recently.',
        'How do you handle pressure and tight deadlines?',
        'Where do you see yourself in 3 years?',
        'Do you have any questions for us?',
      ],
      currentQuestionIdx: 0,
      interviewActive: false,
      metrics: { confidence: 0, anxiety: 0, wpm: 0, fillers: 0, engagement: 0 },
      humeJobId: null,
      humeJobStatus: null,
      humeResult: null,
      questionTimestamps: [],
      liveEmotions: [],
      humeStreamActive: false,
      sessionTranscript: [],
      deepgramConnected: false,

      setTavusKey: (k) => { set({ tavusKey: k }); tavus.setKey(k) },
      setDeepgramKey: (k) => { set({ deepgramKey: k }); deepgramService.setKey(k) },
      setHumeKey: (k) => { set({ humeKey: k }); humeService.setKey(k) },
      setAwsKey: (k) => set({ awsKey: k }),
      setAnthropicKey: (k) => set({ anthropicKey: k }),
      setGeminiKey: (k) => set({ geminiKey: k }),
      setAwsProxyUrl: (url) => set({ awsProxyUrl: url }),
      setWebhookUrl: (k) => set({ webhookUrl: k }),
      setDefaultReplicaId: (id) => set({ defaultReplicaId: id }),
      setDefaultPersonaId: (id) => set({ defaultPersonaId: id }),
      setCurrentConversation: (c) => set({ currentConversation: c }),
      setQuestions: (q) => set({ questions: q }),
      setCurrentQuestionIdx: (i) => set({ currentQuestionIdx: i }),
      setInterviewActive: (v) => set({ interviewActive: v }),
      updateMetrics: (m) => set((s) => ({ metrics: { ...s.metrics, ...m } })),
      saveDraft: (name, form, questions) => set((s) => ({
        drafts: [
          { id: `draft-${Date.now()}`, name, savedAt: new Date().toISOString(), form, questions },
          ...s.drafts.filter(d => d.name !== name),
        ],
      })),
      deleteDraft: (id) => set((s) => ({ drafts: s.drafts.filter(d => d.id !== id) })),
      setHumeJobId: (id) => set({ humeJobId: id }),
      setHumeJobStatus: (s) => set({ humeJobStatus: s }),
      setHumeResult: (r) => set({ humeResult: r }),
      pushQuestionTimestamp: (ts) => set((s) => ({ questionTimestamps: [...s.questionTimestamps, ts] })),
      resetQuestionTimestamps: () => set({ questionTimestamps: [] }),
      setLiveEmotions: (e) => set({ liveEmotions: e }),
      setHumeStreamActive: (v) => set({ humeStreamActive: v }),
      pushTranscriptEntry: (e) => set((s) => ({ sessionTranscript: [...s.sessionTranscript, e] })),
      clearSessionTranscript: () => set({ sessionTranscript: [] }),
      setDeepgramConnected: (v) => set({ deepgramConnected: v }),
      reset: () => set({
        currentConversation: null,
        currentQuestionIdx: 0,
        interviewActive: false,
        metrics: { confidence: 0, anxiety: 0, wpm: 0, fillers: 0, engagement: 0 },
        humeJobId: null,
        humeJobStatus: null,
        humeResult: null,
        questionTimestamps: [],
        liveEmotions: [],
        humeStreamActive: false,
        sessionTranscript: [],
        deepgramConnected: false,
      }),
    }),
    {
      name: 'talbotiq-store',
      partialize: (s) => ({
        tavusKey: s.tavusKey,
        deepgramKey: s.deepgramKey,
        humeKey: s.humeKey,
        awsKey: s.awsKey,
        anthropicKey: s.anthropicKey,
        geminiKey: s.geminiKey,
        awsProxyUrl: s.awsProxyUrl,
        webhookUrl: s.webhookUrl,
        defaultReplicaId: s.defaultReplicaId,
        defaultPersonaId: s.defaultPersonaId,
        questions: s.questions,
        drafts: s.drafts,
      }),
      onRehydrateStorage: () => (state) => {
        if (state?.tavusKey) tavus.setKey(state.tavusKey)

        const envHume = import.meta.env.VITE_HUME_KEY ?? ''
        const envDg   = import.meta.env.VITE_DEEPGRAM_KEY ?? ''

        // Prefer stored key; fall back to env var when stored value is empty
        const humeKey = (state?.humeKey  && state.humeKey.length  > 0) ? state.humeKey  : envHume
        const dgKey   = (state?.deepgramKey && state.deepgramKey.length > 0) ? state.deepgramKey : envDg

        if (humeKey) humeService.setKey(humeKey)
        if (dgKey)   deepgramService.setKey(dgKey)

        // Patch the persisted state if the stored key was blank so the UI shows it
        if (!state?.humeKey && humeKey) {
          setTimeout(() => useAppStore.setState({ humeKey }), 0)
        }
        if (!state?.deepgramKey && dgKey) {
          setTimeout(() => useAppStore.setState({ deepgramKey: dgKey }), 0)
        }

        // Gemini: prefer stored key; fall back to env var when blank
        const envGemini = import.meta.env.VITE_GEMINI_KEY ?? ''
        if (!state?.geminiKey && envGemini) {
          setTimeout(() => useAppStore.setState({ geminiKey: envGemini }), 0)
        }

        // AWS Rekognition proxy URL: prefer stored; fall back to env var when blank
        const envProxy = import.meta.env.VITE_REKOGNITION_PROXY_URL ?? ''
        if (!state?.awsProxyUrl && envProxy) {
          setTimeout(() => useAppStore.setState({ awsProxyUrl: envProxy }), 0)
        }
      },
    },
  ),
)
