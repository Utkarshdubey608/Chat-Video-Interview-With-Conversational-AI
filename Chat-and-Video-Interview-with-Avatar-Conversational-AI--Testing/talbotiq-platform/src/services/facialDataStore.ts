// src/services/facialDataStore.ts
// Module-level singleton — same pattern as audioStore. Survives the
// InterviewPage → ResultsPage navigation (not React state, no re-renders).

import type { FacialFrame, FacialSessionSummary } from '@/types/rekognition.types'

let _frames: FacialFrame[] = []
let _summary: FacialSessionSummary | null = null

export const facialDataStore = {
  setFrames: (frames: FacialFrame[]) => { _frames = frames },
  getFrames: () => _frames,
  setSummary: (summary: FacialSessionSummary) => { _summary = summary },
  getSummary: () => _summary,
  clear: () => { _frames = []; _summary = null },
}
