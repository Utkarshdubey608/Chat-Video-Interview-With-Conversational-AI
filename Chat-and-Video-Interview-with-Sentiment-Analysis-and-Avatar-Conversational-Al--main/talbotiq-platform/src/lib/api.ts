import type {
  InterviewTemplate,
  QuestionSet,
  CandidateSessionState,
  CreateSessionRequest,
  SubmitAnswerRequest,
  SaveDraftRequest,
  IntegrityEventRequest,
  SessionListItem,
  SessionReportView,
  TrackType,
  AppSettingsStatus,
  GenerateQuestionSetResult,
  ChatbotSessionState,
  SubmitChatAnswerRequest,
  SaveChatDraftRequest,
} from '@shared/types'

const BASE = '/api'

async function http<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(BASE + path, {
    headers: { 'Content-Type': 'application/json' },
    ...init,
  })
  if (res.status === 204) return undefined as T
  const text = await res.text()
  const data = text ? JSON.parse(text) : undefined
  if (!res.ok) {
    const message = (data && (data.error as string)) || `Request failed (${res.status})`
    throw new ApiError(message, res.status, data)
  }
  return data as T
}

export class ApiError extends Error {
  constructor(message: string, public status: number, public payload?: unknown) {
    super(message)
  }
}

/* ─── Templates ─────────────────────────────────────────────────────────── */
export const templatesApi = {
  list: () => http<InterviewTemplate[]>('/templates'),
  get: (id: string) => http<InterviewTemplate>(`/templates/${id}`),
  create: (body: Partial<InterviewTemplate>) =>
    http<InterviewTemplate>('/templates', { method: 'POST', body: JSON.stringify(body) }),
  update: (id: string, body: Partial<InterviewTemplate>) =>
    http<InterviewTemplate>(`/templates/${id}`, { method: 'PUT', body: JSON.stringify(body) }),
  remove: (id: string) => http<void>(`/templates/${id}`, { method: 'DELETE' }),
}

/* ─── Question Sets ─────────────────────────────────────────────────────── */
export const questionSetsApi = {
  list: () => http<QuestionSet[]>('/question-sets'),
  get: (id: string) => http<QuestionSet>(`/question-sets/${id}`),
  create: (body: Partial<QuestionSet>) =>
    http<QuestionSet>('/question-sets', { method: 'POST', body: JSON.stringify(body) }),
  update: (id: string, body: Partial<QuestionSet>) =>
    http<QuestionSet>(`/question-sets/${id}`, { method: 'PUT', body: JSON.stringify(body) }),
  duplicate: (id: string) =>
    http<QuestionSet>(`/question-sets/${id}/duplicate`, { method: 'POST' }),
  remove: (id: string) => http<void>(`/question-sets/${id}`, { method: 'DELETE' }),
  generateFromResume: async (fd: FormData): Promise<GenerateQuestionSetResult> => {
    const res = await fetch(`${BASE}/question-sets/generate`, { method: 'POST', body: fd })
    const text = await res.text()
    const data = text ? JSON.parse(text) : undefined
    if (!res.ok) throw new ApiError((data && data.error) || `Generation failed (${res.status})`, res.status, data)
    return data as GenerateQuestionSetResult
  },
}

/* ─── Settings (server-side Gemini key) ─────────────────────────────────── */
export const settingsApi = {
  status: () => http<AppSettingsStatus>('/settings'),
  saveGeminiKey: (apiKey: string, model?: string) =>
    http<AppSettingsStatus>('/settings/gemini-key', {
      method: 'PUT',
      body: JSON.stringify({ apiKey, model }),
    }),
  clearGeminiKey: () => http<AppSettingsStatus>('/settings/gemini-key', { method: 'DELETE' }),
}

/* ─── Sessions (candidate + recruiter) ──────────────────────────────────── */
export const sessionsApi = {
  create: (body: CreateSessionRequest) =>
    http<{ id: string }>('/sessions', { method: 'POST', body: JSON.stringify(body) }),
  state: (id: string) => http<CandidateSessionState>(`/sessions/${id}/state`),
  setTrack: (id: string, track: TrackType) =>
    http<CandidateSessionState>(`/sessions/${id}/track`, {
      method: 'POST',
      body: JSON.stringify({ track }),
    }),
  systemCheck: (id: string) =>
    http<CandidateSessionState>(`/sessions/${id}/system-check`, { method: 'POST' }),
  uploadResume: async (id: string, file: File): Promise<CandidateSessionState> => {
    const fd = new FormData()
    fd.append('resume', file)
    const res = await fetch(`${BASE}/sessions/${id}/resume`, { method: 'POST', body: fd })
    const text = await res.text()
    const data = text ? JSON.parse(text) : undefined
    if (!res.ok) throw new ApiError((data && data.error) || `Upload failed (${res.status})`, res.status, data)
    return data as CandidateSessionState
  },
  begin: (id: string) =>
    http<CandidateSessionState>(`/sessions/${id}/begin`, { method: 'POST' }),
  skipPrep: (id: string) =>
    http<CandidateSessionState>(`/sessions/${id}/skip-prep`, { method: 'POST' }),
  saveDraft: (id: string, body: SaveDraftRequest) =>
    http<{ ok: boolean }>(`/sessions/${id}/draft`, {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  submitAnswer: (id: string, body: SubmitAnswerRequest) =>
    http<CandidateSessionState>(`/sessions/${id}/answers`, {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  integrityEvent: (id: string, body: IntegrityEventRequest) =>
    http<{ ok: boolean; tabSwitchWarnings?: number; maxTabSwitchWarnings?: number }>(
      `/sessions/${id}/integrity-event`,
      { method: 'POST', body: JSON.stringify(body) },
    ),
  complete: (id: string) =>
    http<CandidateSessionState>(`/sessions/${id}/complete`, { method: 'POST' }),
  list: () => http<SessionListItem[]>('/sessions'),
  report: (id: string) => http<SessionReportView>(`/sessions/${id}/report`),
}

/* ─── Chatbot (conversational) track ────────────────────────────────────── */
export const chatbotApi = {
  begin: (id: string) => http<ChatbotSessionState>(`/sessions/${id}/chat/begin`, { method: 'POST' }),
  state: (id: string) => http<ChatbotSessionState>(`/sessions/${id}/chat/state`),
  answer: (id: string, body: SubmitChatAnswerRequest) =>
    http<ChatbotSessionState>(`/sessions/${id}/chat/answer`, { method: 'POST', body: JSON.stringify(body) }),
  saveDraft: (id: string, body: SaveChatDraftRequest) =>
    http<{ ok: boolean }>(`/sessions/${id}/chat/draft`, { method: 'POST', body: JSON.stringify(body) }),
  skipThinking: (id: string) =>
    http<ChatbotSessionState>(`/sessions/${id}/chat/skip-thinking`, { method: 'POST' }),
}
