import type {
  TimingConfig,
  IntegrityConfig,
  BrandingConfig,
  KpiRubric,
  ConversationTimingConfig,
  AdaptiveConfig,
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
