import type {
  TimingConfig,
  IntegrityConfig,
  BrandingConfig,
  KpiRubric,
  ConversationTimingConfig,
  ChatbotTimerConfig,
  AdaptiveConfig,
  VoiceOption,
  InterviewPersona,
  VoiceConfig,
} from '../../shared/types'

export const DEFAULT_TIMING: TimingConfig = {
  prepSeconds: 30,
  answerSeconds: 120,
  allowSkipPrep: true,
  allowEarlySubmit: true,
  warningThresholdSeconds: 15,
}

/** Chatbot track — TIMED mode defaults. */
export const DEFAULT_CONVERSATION_TIMING: ConversationTimingConfig = {
  thinkingSeconds: 30,
  perQuestionSeconds: 120,
  allowSkipThinking: true,
  allowEarlySubmit: true,
  warningThresholdSeconds: 15,
}

/** Conversational track — per-question timer overlay. ON by default (product
 *  decision 2026-07): every new chatbot template shows the countdown; recruiters
 *  can disable it per template for a pure conversational flow. */
export const DEFAULT_CHATBOT_TIMER: ChatbotTimerConfig = {
  enabled: true,
  perQuestionSeconds: 120,
  timeFollowUps: true,
  followUpSeconds: 90,
  includeThinkingPhase: false,
  thinkingSeconds: 20,
  warningThresholdSeconds: 15,
  allowEarlySubmit: true,
  autoSubmitOnExpiry: true,
}

/** Chatbot track — adaptive conversation defaults. */
export function defaultAdaptive(role = 'Software Engineer'): AdaptiveConfig {
  return {
    role,
    difficulty: 'mixed',
    style: 'mix',
    numberOfQuestions: 5,
    technicalCount: 3,
    nonTechnicalCount: 2,
    focusTopics: [],
    allowFollowUps: false,   // default OFF — numberOfQuestions is the real total; opt in to follow-ups
    maxFollowUpsPerQuestion: 1,
    interviewerTone: 'friendly and professional',
    language: 'English',
  }
}

/* ─── Voice track — engine, voice catalog, personas ─────────────────────── */

/** Default Gemini Live model. Benchmarked 2026-07: gemini-3.1-flash-live-preview
 *  reaches first audio in ~740ms vs ~2.8s for the 2.5 native-audio preview
 *  (which also "thinks" before speaking) — ~4× snappier turn-taking. */
export const DEFAULT_LIVE_MODEL =
  process.env.GEMINI_LIVE_MODEL || 'gemini-3.1-flash-live-preview'

/**
 * Browsable catalog of Gemini Live native-audio prebuilt voices. Names are the
 * `prebuiltVoiceConfig.voiceName` values; all are multilingual timbres. The
 * gender/description tags follow Google's published voice characteristics.
 */
export const VOICE_CATALOG: VoiceOption[] = [
  { id: 'Aoede',      label: 'Aoede',      gender: 'female', language: 'English (multilingual)', engine: 'gemini_live', description: 'Breezy, natural' },
  { id: 'Kore',       label: 'Kore',       gender: 'female', language: 'English (multilingual)', engine: 'gemini_live', description: 'Firm, composed' },
  { id: 'Leda',       label: 'Leda',       gender: 'female', language: 'English (multilingual)', engine: 'gemini_live', description: 'Youthful, warm' },
  { id: 'Zephyr',     label: 'Zephyr',     gender: 'female', language: 'English (multilingual)', engine: 'gemini_live', description: 'Bright, upbeat' },
  { id: 'Callirrhoe', label: 'Callirrhoe', gender: 'female', language: 'English (multilingual)', engine: 'gemini_live', description: 'Easy-going' },
  { id: 'Erinome',    label: 'Erinome',    gender: 'female', language: 'English (multilingual)', engine: 'gemini_live', description: 'Clear, measured' },
  { id: 'Despina',    label: 'Despina',    gender: 'female', language: 'English (multilingual)', engine: 'gemini_live', description: 'Smooth, calm' },
  { id: 'Laomedeia',  label: 'Laomedeia',  gender: 'female', language: 'English (multilingual)', engine: 'gemini_live', description: 'Upbeat, lively' },
  { id: 'Charon',     label: 'Charon',     gender: 'male',   language: 'English (multilingual)', engine: 'gemini_live', description: 'Informative, steady' },
  { id: 'Orus',       label: 'Orus',       gender: 'male',   language: 'English (multilingual)', engine: 'gemini_live', description: 'Firm, authoritative' },
  { id: 'Puck',       label: 'Puck',       gender: 'male',   language: 'English (multilingual)', engine: 'gemini_live', description: 'Upbeat, friendly' },
  { id: 'Fenrir',     label: 'Fenrir',     gender: 'male',   language: 'English (multilingual)', engine: 'gemini_live', description: 'Excitable, energetic' },
  { id: 'Iapetus',    label: 'Iapetus',    gender: 'male',   language: 'English (multilingual)', engine: 'gemini_live', description: 'Clear, articulate' },
  { id: 'Umbriel',    label: 'Umbriel',    gender: 'male',   language: 'English (multilingual)', engine: 'gemini_live', description: 'Easy-going' },
  { id: 'Enceladus',  label: 'Enceladus',  gender: 'male',   language: 'English (multilingual)', engine: 'gemini_live', description: 'Breathy, soft' },
  { id: 'Algieba',    label: 'Algieba',    gender: 'male',   language: 'English (multilingual)', engine: 'gemini_live', description: 'Smooth, warm' },
]

/** Selectable interviewer personas: character + default voice. Fully editable. */
export const PERSONA_PRESETS: InterviewPersona[] = [
  {
    id: 'friendly_hr',
    name: 'Friendly HR Screener',
    description: 'Warm, encouraging first-round screener who puts candidates at ease.',
    stylePrompt:
      'You are a warm, personable HR screener. You sound friendly and encouraging, keep the candidate at ease, and speak in a relaxed conversational tone.',
    defaultVoiceId: 'Aoede',
  },
  {
    id: 'rigorous_tech',
    name: 'Rigorous Technical Interviewer',
    description: 'Sharp, focused engineer probing depth and problem-solving.',
    stylePrompt:
      'You are a sharp, focused senior engineer running a technical interview. You are professional and respectful, but you probe for depth and precision. Stay crisp and direct.',
    defaultVoiceId: 'Charon',
  },
  {
    id: 'warm_behavioral',
    name: 'Warm Behavioral Interviewer',
    description: 'Empathetic interviewer exploring experience and collaboration.',
    stylePrompt:
      'You are an empathetic behavioral interviewer. You listen closely, sound genuinely interested, and gently draw out stories about the candidate’s experience and how they work with others.',
    defaultVoiceId: 'Leda',
  },
  {
    id: 'exec_panel',
    name: 'Executive Panel Lead',
    description: 'Composed, senior leader assessing strategic thinking and presence.',
    stylePrompt:
      'You are a composed, senior executive leading a final-round conversation. You are gracious but discerning, assessing judgment, strategic thinking, and presence. Speak with calm authority.',
    defaultVoiceId: 'Orus',
  },
]

export const DEFAULT_VOICE_CONFIG: VoiceConfig = {
  engine: 'gemini_live',
  personaId: 'friendly_hr',
  voiceId: 'Aoede',
  allowBargeIn: true,
  language: 'en-US',
  model: DEFAULT_LIVE_MODEL,
}

export const DEFAULT_INTEGRITY: IntegrityConfig = {
  enforceFullscreen: false,
  detectTabSwitch: true,
  disablePasteInAnswers: true,
  disableCopy: false,
  maxTabSwitchWarnings: 3,
  logEvents: true,
}

export const DEFAULT_BRANDING: BrandingConfig = {
  companyName: 'TalbotIQ',
  accentColor: '#0d5c3a',
  welcomeMessage:
    'Welcome to your interview. Find a quiet spot, take a breath, and answer naturally — there are no trick questions.',
}

/**
 * Default KPI rubric. IDs are stable slugs (not random) so scores key
 * consistently and custom KPIs added later never collide with these.
 */
export function defaultRubric(): KpiRubric {
  return {
    scoreScale: 100,
    kpis: [
      { id: 'communication',  label: 'Communication Clarity',     description: 'Clear, articulate, easy to follow.',                         weight: 1, enabled: true },
      { id: 'relevance',      label: 'Relevance to Question',      description: 'Directly answers what was asked.',                           weight: 1, enabled: true },
      { id: 'depth',          label: 'Technical / Domain Depth',   description: 'Demonstrates real expertise and substance.',                 weight: 1, enabled: true },
      { id: 'structure',      label: 'Structure & Conciseness',    description: 'Well-organized (e.g. STAR); concise, no rambling.',          weight: 1, enabled: true },
      { id: 'problem_solving',label: 'Problem-Solving',            description: 'Logical reasoning and a sound approach to problems.',        weight: 1, enabled: true },
      { id: 'professionalism',label: 'Professionalism / Confidence',description: 'Composed, confident, professional tone.',                    weight: 1, enabled: true },
    ],
  }
}
