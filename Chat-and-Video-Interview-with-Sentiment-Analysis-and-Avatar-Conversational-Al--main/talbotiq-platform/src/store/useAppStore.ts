import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import { tavus } from '@/services/tavus'
import type { TavusConversation } from '@/types/tavus.types'

interface AppState {
  // API keys
  tavusKey: string
  deepgramKey: string
  humeKey: string
  awsKey: string
  anthropicKey: string
  webhookUrl: string

  // Defaults
  defaultReplicaId: string
  defaultPersonaId: string

  // Active interview session
  currentConversation: TavusConversation | null
  questions: string[]
  currentQuestionIdx: number
  interviewActive: boolean

  // Live metrics (simulated or Hume-sourced)
  metrics: {
    confidence: number
    anxiety: number
    wpm: number
    fillers: number
    engagement: number
  }

  // Actions
  setTavusKey: (k: string) => void
  setDeepgramKey: (k: string) => void
  setHumeKey: (k: string) => void
  setAwsKey: (k: string) => void
  setAnthropicKey: (k: string) => void
  setWebhookUrl: (k: string) => void
  setDefaultReplicaId: (id: string) => void
  setDefaultPersonaId: (id: string) => void
  setCurrentConversation: (c: TavusConversation | null) => void
  setQuestions: (q: string[]) => void
  setCurrentQuestionIdx: (i: number) => void
  setInterviewActive: (v: boolean) => void
  updateMetrics: (m: Partial<AppState['metrics']>) => void
  reset: () => void
}

export const useAppStore = create<AppState>()(
  persist(
    (set) => ({
      tavusKey: '',
      deepgramKey: '',
      humeKey: '',
      awsKey: '',
      anthropicKey: '',
      webhookUrl: '',
      defaultReplicaId: '',
      defaultPersonaId: '',
      currentConversation: null,
      questions: [
        'Tell me about yourself and your background.',
        'Describe a challenging problem you solved recently.',
        'How do you handle pressure and tight deadlines?',
        'Where do you see yourself in 3 years?',
        'Do you have any questions for us?',
      ],
      currentQuestionIdx: 0,
      interviewActive: false,
      metrics: { confidence: 72, anxiety: 8, wpm: 134, fillers: 3, engagement: 81 },

      setTavusKey: (k) => {
        set({ tavusKey: k })
        tavus.setKey(k)
      },
      setDeepgramKey: (k) => set({ deepgramKey: k }),
      setHumeKey: (k) => set({ humeKey: k }),
      setAwsKey: (k) => set({ awsKey: k }),
      setAnthropicKey: (k) => set({ anthropicKey: k }),
      setWebhookUrl: (k) => set({ webhookUrl: k }),
      setDefaultReplicaId: (id) => set({ defaultReplicaId: id }),
      setDefaultPersonaId: (id) => set({ defaultPersonaId: id }),
      setCurrentConversation: (c) => set({ currentConversation: c }),
      setQuestions: (q) => set({ questions: q }),
      setCurrentQuestionIdx: (i) => set({ currentQuestionIdx: i }),
      setInterviewActive: (v) => set({ interviewActive: v }),
      updateMetrics: (m) => set((s) => ({ metrics: { ...s.metrics, ...m } })),
      reset: () => set({
        currentConversation: null,
        currentQuestionIdx: 0,
        interviewActive: false,
        metrics: { confidence: 72, anxiety: 8, wpm: 134, fillers: 3, engagement: 81 },
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
        webhookUrl: s.webhookUrl,
        defaultReplicaId: s.defaultReplicaId,
        defaultPersonaId: s.defaultPersonaId,
        questions: s.questions,
      }),
      onRehydrateStorage: () => (state) => {
        if (state?.tavusKey) tavus.setKey(state.tavusKey)
      },
    },
  ),
)
