/**
 * Shared domain + API contract — imported by BOTH the Vite client and the
 * Express server. Keep this the single source of truth so the two sides
 * cannot drift. Everything here is type-only (erased at runtime).
 */

/* ─── Core config ───────────────────────────────────────────────────────── */

export type TrackType = 'chat' | 'chatbot' | 'video_avatar'
export type QuestionSource = 'adaptive' | 'fixed'

export interface TimingConfig {
  prepSeconds: number             // default 30
  answerSeconds: number           // default 120
  allowSkipPrep: boolean          // default true
  allowEarlySubmit: boolean       // default true
  warningThresholdSeconds: number // default 15
  numberOfQuestions?: number      // adaptive only; fixed derives from the set
  totalTimeCapSeconds?: number    // optional overall cap
}

export interface KpiDefinition {
  id: string
  label: string
  description: string
  weight: number   // relative weight; auto-normalized at scoring time
  enabled: boolean
}
export interface KpiRubric {
  kpis: KpiDefinition[]
  scoreScale: 100
}

export interface FixedQuestion {
  id: string
  text: string
  category?: string
  idealAnswerNotes?: string
}
export interface QuestionSet {
  id: string
  name: string
  questions: FixedQuestion[]
  createdAt: string
  updatedAt: string
}

export interface BrandingConfig {
  companyName: string
  logoUrl?: string
  accentColor: string
  welcomeMessage?: string
}

export interface IntegrityConfig {
  enforceFullscreen: boolean
  detectTabSwitch: boolean
  disablePasteInAnswers: boolean
  disableCopy: boolean
  maxTabSwitchWarnings: number
  logEvents: boolean
}

/* ─── Chatbot (conversational) track config ─────────────────────────────── */

export type InterviewMode = 'conversational' | 'timed'

/** Adaptive, résumé-grounded conversational settings (chatbot track). */
export interface AdaptiveConfig {
  role: string
  seniority?: string
  difficulty: DifficultyChoice
  style?: QuestionStyle          // 'technical' | 'non_technical' | 'mix'
  numberOfQuestions: number
  technicalCount?: number        // used when style === 'mix'
  nonTechnicalCount?: number     // used when style === 'mix'
  focusTopics?: string[]
  allowFollowUps: boolean
  maxFollowUpsPerQuestion: number
  interviewerTone?: string
  language?: string
}

/** Timing for the chatbot track's TIMED mode — kept separate from TimingConfig. */
export interface ConversationTimingConfig {
  thinkingSeconds: number          // default 30
  perQuestionSeconds: number       // default 120
  totalTimeCapSeconds?: number
  allowSkipThinking: boolean       // default true
  allowEarlySubmit: boolean        // default true
  warningThresholdSeconds: number  // default 15
}

export interface InterviewTemplate {
  id: string
  name: string
  role: string
  seniority?: string
  track: TrackType
  questionSource: QuestionSource
  fixedQuestionSetId?: string
  timing: TimingConfig
  rubric: KpiRubric
  integrity: IntegrityConfig
  branding: BrandingConfig
  // Chatbot track (optional; ignored by the chat / video_avatar tracks)
  mode?: InterviewMode
  adaptive?: AdaptiveConfig
  fixedAllowFollowUps?: boolean
  conversationTiming?: ConversationTimingConfig
  createdAt: string
  updatedAt: string
}

/* ─── Session (server-held; never fully sent to the candidate) ──────────── */

export type InterviewPhase = 'prep' | 'answer'
export type SessionStatus =
  | 'created'       // exists, candidate hasn't begun
  | 'system_check'  // candidate on the system-check screen
  | 'in_progress'   // actively answering
  | 'completed'     // all answers submitted
  | 'expired'

export interface SessionQuestion {
  id: string
  text: string
  category?: string
  idealAnswerNotes?: string // SERVER-ONLY — never leaves the server
  prepStartedAt?: string
  answerStartedAt?: string
  submittedAt?: string
  answerText?: string       // chat track
  videoUrl?: string         // video avatar track
  autoSubmitted: boolean
  draft?: string            // last auto-saved in-progress text
}

export interface IntegrityEvent {
  type:
    | 'tab_switch'
    | 'window_blur'
    | 'paste_blocked'
    | 'copy_blocked'
    | 'fullscreen_exit'
    | string
  at: string
}

/** A single conversational turn (chatbot track). Server-held source of truth. */
export interface Turn {
  id: string
  role: 'interviewer' | 'candidate'
  content: string
  questionIndex?: number       // 0-based primary-question this belongs to
  isFollowUp?: boolean
  createdAt: string
  // Timed mode (an interviewer turn awaiting the candidate's answer):
  thinkingStartedAt?: string
  answerStartedAt?: string
  submittedAt?: string
  autoAdvanced?: boolean
  draft?: string               // candidate's in-progress answer to THIS interviewer turn
}

export interface InterviewSession {
  id: string
  templateId: string
  track: TrackType
  candidate: { name: string; email: string }
  status: SessionStatus
  questions: SessionQuestion[] // SERVER-HELD — never sent in full to the client
  currentIndex: number
  createdAt: string
  startedAt?: string
  completedAt?: string
  integrityEvents: IntegrityEvent[]
  tabSwitchCount: number
  resumeText?: string          // SERVER-ONLY
  // Chatbot track (conversational) — server-held; only revealed turns go out.
  mode?: InterviewMode
  transcript?: Turn[]
  plannedQuestionCount?: number
  followUpsThisQuestion?: number
}

/* ─── Scoring / results ─────────────────────────────────────────────────── */

export type Recommendation = 'strong_yes' | 'yes' | 'maybe' | 'no'

export interface PerQuestionResult {
  questionId: string
  kpiScores: Record<string, number> // keyed by KpiDefinition.id, 0–100
  feedback: string
}
export interface ResultReport {
  sessionId: string
  perQuestion: PerQuestionResult[]
  kpiAverages: Record<string, number>
  overallScore: number          // weighted, computed server-side (not by the model)
  summary: string
  strengths?: string[]
  improvements?: string[]
  recommendation?: Recommendation
  generatedAt: string
  degraded?: boolean            // true when scoring fell back (no/failed Gemini)
}

/* ─── Client-safe DTOs (what the candidate browser is allowed to receive) ── */

export interface PublicTimingView {
  prepSeconds: number
  answerSeconds: number
  allowSkipPrep: boolean
  allowEarlySubmit: boolean
  warningThresholdSeconds: number
}

/**
 * The ONLY session view the candidate client ever receives. Note: no future
 * questions, no idealAnswerNotes, no categories — just the current question.
 */
export interface CandidateSessionState {
  sessionId: string
  status: SessionStatus
  track: TrackType
  phase: InterviewPhase | null     // null outside an active question
  remainingSeconds: number         // server-computed
  totalPhaseSeconds: number        // prep or answer total, for ring math
  question: { id: string; text: string } | null // CURRENT only
  progress: { current: number; total: number }   // e.g. 3 of 8
  draft: string
  timing: PublicTimingView
  branding: BrandingConfig
  integrity: IntegrityConfig
  tabSwitchWarnings: number
  awaitingResume: boolean          // adaptive track needs a résumé before starting
}

/* ─── API request bodies ────────────────────────────────────────────────── */

export interface CreateSessionRequest {
  templateId: string
  candidate: { name: string; email: string }
  track?: TrackType
}
export interface SubmitAnswerRequest {
  questionId: string   // must equal the current question (anti-tamper)
  answerText?: string
  videoUrl?: string
}
export interface SaveDraftRequest {
  questionId: string
  draft: string
}
export interface IntegrityEventRequest {
  type: IntegrityEvent['type']
}

/* ─── Recruiter views ───────────────────────────────────────────────────── */

export interface SessionListItem {
  id: string
  candidate: { name: string; email: string }
  templateId: string
  templateName: string
  track: TrackType
  status: SessionStatus
  createdAt: string
  startedAt?: string
  completedAt?: string
  overallScore?: number
}

export interface SessionReportQuestion {
  id: string
  text: string
  category?: string
  answerText?: string
  videoUrl?: string
  timeUsedSeconds?: number
  autoSubmitted: boolean
}
export interface SessionReportView {
  session: {
    id: string
    candidate: { name: string; email: string }
    templateName: string
    track: TrackType
    status: SessionStatus
    createdAt: string
    startedAt?: string
    completedAt?: string
    questions: SessionReportQuestion[]
    integrityEvents: IntegrityEvent[]
    tabSwitchCount: number
  }
  rubric: KpiRubric
  report: ResultReport | null
}

export interface ApiError {
  error: string
}

/* ─── Resume → Question Set generation (Gemini) ─────────────────────────── */

export type QuestionStyle = 'technical' | 'non_technical' | 'mix'
export type QuestionDifficulty = 'easy' | 'medium' | 'hard'
export type DifficultyChoice = QuestionDifficulty | 'mixed'
export type GeminiModel = 'gemini-2.5-flash' | 'gemini-2.5-pro'

export interface GeneratedInterviewQuestion {
  text: string
  type: 'technical' | 'non_technical'
  category: string
  difficulty: QuestionDifficulty
  skillTag: string
  rationale: string
}

export interface GenerateQuestionSetResult {
  questions: GeneratedInterviewQuestion[]
  suggestedName: string
}

/** Server settings status — the key value is NEVER returned, only a masked hint. */
export interface AppSettingsStatus {
  geminiKeySet: boolean
  geminiKeyMasked?: string
  source: 'saved' | 'env' | 'none'
  model: string
}

/* ─── Chatbot track — client-safe DTOs & requests ───────────────────────── */

export interface ChatbotPublicTiming {
  mode: InterviewMode
  thinkingSeconds: number
  perQuestionSeconds: number
  allowSkipThinking: boolean
  allowEarlySubmit: boolean
  warningThresholdSeconds: number
}

/** A revealed turn the candidate is allowed to see (no server-only fields). */
export interface ChatbotTurnView {
  id: string
  role: 'interviewer' | 'candidate'
  content: string
  questionIndex?: number
  isFollowUp?: boolean
}

/**
 * The ONLY conversational view the candidate receives. Contains the transcript
 * already revealed turn-by-turn — never the plan or any upcoming question.
 */
export interface ChatbotSessionState {
  sessionId: string
  status: SessionStatus
  track: TrackType   // 'chatbot' or 'video_avatar' — both use the conversational engine
  transcript: ChatbotTurnView[]
  awaitingInterviewer: boolean       // server is generating the next turn
  finished: boolean
  phase: 'thinking' | 'answer' | null // timed mode only; null in conversational
  remainingSeconds: number
  totalPhaseSeconds: number
  currentTurnId: string | null        // interviewer turn being answered (anti-tamper)
  progress: { current: number; total: number }
  draft: string
  timing: ChatbotPublicTiming
  branding: BrandingConfig
  integrity: IntegrityConfig
  tabSwitchWarnings: number
  awaitingResume: boolean
}

export interface SubmitChatAnswerRequest {
  turnId: string        // must equal currentTurnId (anti-tamper / stale guard)
  answerText: string
}
export interface SaveChatDraftRequest {
  turnId: string
  draft: string
}
