// src/hooks/useGeminiAnalysis.ts

import { useState, useCallback } from 'react'
import { GeminiAnalysisService, type ATSScorecard, type GeminiAnalysisInput } from '@/services/geminiAnalysis'
import { useAppStore } from '@/store/useAppStore'

export interface GeminiAnalysisHookState {
  scorecard: ATSScorecard | null
  status: 'idle' | 'analyzing' | 'complete' | 'error'
  error: string | null
  analyze: (input: GeminiAnalysisInput) => Promise<void>
  reset: () => void
}

export function useGeminiAnalysis(): GeminiAnalysisHookState {
  const geminiKey = useAppStore(s => s.geminiKey)
  const [scorecard, setScorecard] = useState<ATSScorecard | null>(null)
  const [status, setStatus] = useState<GeminiAnalysisHookState['status']>('idle')
  const [error, setError] = useState<string | null>(null)

  const analyze = useCallback(async (input: GeminiAnalysisInput) => {
    if (!geminiKey) {
      setError('Gemini API key not found. Add it in Settings (or VITE_GEMINI_KEY in .env.local).')
      setStatus('error')
      return
    }
    setStatus('analyzing')
    setError(null)
    try {
      const service = new GeminiAnalysisService(geminiKey)
      const result = await service.analyze(input)
      setScorecard(result)
      setStatus('complete')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error during analysis')
      setStatus('error')
    }
  }, [geminiKey])

  const reset = useCallback(() => {
    setScorecard(null)
    setStatus('idle')
    setError(null)
  }, [])

  return { scorecard, status, error, analyze, reset }
}
