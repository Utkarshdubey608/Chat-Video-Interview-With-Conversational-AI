import { GoogleGenAI, Type } from '@google/genai'
import type {
  InterviewSession,
  InterviewTemplate,
  GeneratedInterviewQuestion,
  QuestionStyle,
  DifficultyChoice,
} from '../../shared/types'
import { db } from '../store/db'

/**
 * Resolve the active Gemini key at call time, in priority order:
 *   1. a per-request override (entered in the modal)
 *   2. a key saved in Settings (server store)
 *   3. the GEMINI_API_KEY environment variable
 */
function resolveKey(override?: string): string | undefined {
  const o = override?.trim()
  return o || db.settings.geminiApiKey || process.env.GEMINI_API_KEY || undefined
}

const clients = new Map<string, GoogleGenAI>()
function ai(override?: string): GoogleGenAI {
  const key = resolveKey(override)
  if (!key) throw new Error('No Gemini API key configured')
  let c = clients.get(key)
  if (!c) {
    c = new GoogleGenAI({ apiKey: key })
    clients.set(key, c)
  }
  return c
}

export function modelName(override?: string): string {
  return override || db.settings.geminiModel || process.env.GEMINI_MODEL || 'gemini-2.5-flash'
}

/** Shared client accessor for other services (e.g. the conversation engine). */
export function geminiClient(override?: string): GoogleGenAI {
  return ai(override)
}

export const geminiEnabled = (override?: string) => Boolean(resolveKey(override))

/** Masked hint + source for the Settings UI (never returns the full key). */
export function keyStatus() {
  const saved = db.settings.geminiApiKey?.trim()
  const env = process.env.GEMINI_API_KEY?.trim()
  const active = saved || env
  return {
    geminiKeySet: Boolean(active),
    geminiKeyMasked: active
      ? `${active.slice(0, 4)}…${active.slice(-4)}`
      : undefined,
    source: (saved ? 'saved' : env ? 'env' : 'none') as 'saved' | 'env' | 'none',
    model: modelName(),
  }
}

async function withRetry<T>(fn: () => Promise<T>, tries = 3): Promise<T> {
  let lastErr: unknown
  for (let i = 0; i < tries; i++) {
    try {
      return await fn()
    } catch (e) {
      lastErr = e
      await new Promise((r) => setTimeout(r, 400 * (i + 1)))
    }
  }
  throw lastErr
}

/* ─── Adaptive question generation ──────────────────────────────────────── */

export interface GeneratedQuestion {
  text: string
  category: string
  idealAnswerNotes: string
}

export async function generateQuestions(opts: {
  resumeText: string
  role: string
  seniority?: string
  count: number
}): Promise<GeneratedQuestion[]> {
  const { resumeText, role, seniority, count } = opts
  const prompt = `You are an expert interviewer. Based on the candidate's résumé below, write exactly ${count} interview questions tailored to a ${seniority ?? ''} ${role} role.
Mix behavioral and role-specific/technical questions, grounded in the candidate's actual experience. For each question include a short category and concise ideal-answer notes a human scorer can use.

RÉSUMÉ:
"""
${resumeText.slice(0, 16000)}
"""`

  const res = await withRetry(() =>
    ai().models.generateContent({
      model: modelName(),
      contents: prompt,
      config: {
        responseMimeType: 'application/json',
        responseSchema: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              text: { type: Type.STRING },
              category: { type: Type.STRING },
              idealAnswerNotes: { type: Type.STRING },
            },
            required: ['text', 'category', 'idealAnswerNotes'],
          },
        },
      },
    }),
  )
  const parsed = JSON.parse(res.text ?? '[]') as GeneratedQuestion[]
  return parsed.slice(0, count)
}

/* ─── Resume PDF → Question Set generation ──────────────────────────────── */

export interface GenerateFromPdfOpts {
  pdfBase64: string
  style: QuestionStyle
  technicalCount: number
  nonTechnicalCount: number
  difficulty: DifficultyChoice
  role?: string
  model?: string
  apiKeyOverride?: string
}

export async function generateQuestionsFromPdf(
  opts: GenerateFromPdfOpts,
): Promise<GeneratedInterviewQuestion[]> {
  const { pdfBase64, style, technicalCount, nonTechnicalCount, difficulty, role, model, apiKeyOverride } = opts
  const total = style === 'mix' ? technicalCount + nonTechnicalCount : style === 'technical' ? technicalCount : nonTechnicalCount

  const styleLine =
    style === 'technical'
      ? 'Every question must be TECHNICAL — grounded in the specific technologies, tools, projects, and seniority shown in the resume.'
      : style === 'non_technical'
        ? 'Every question must be NON-TECHNICAL (behavioral, situational, culture-fit) — grounded in the candidate’s actual roles and experience.'
        : `Produce EXACTLY ${technicalCount} technical and ${nonTechnicalCount} non-technical questions.`
  const difficultyLine =
    difficulty === 'mixed'
      ? 'Use a balanced mix of easy, medium, and hard difficulty.'
      : `All questions should be ${difficulty} difficulty.`

  const systemInstruction =
    'You are an expert technical interviewer. You read a candidate résumé and produce sharp, specific interview questions tailored to that exact person. You never produce generic, copy-paste questions, and you never repeat yourself.'

  const prompt = `Read the attached candidate résumé and generate exactly ${total} interview questions${role ? ` for a ${role} role` : ''}.
${styleLine}
${difficultyLine}
Each question MUST be specific to THIS résumé — reference real technologies, projects, or experiences from it. Avoid duplicates and generic filler.
For each question provide: the question text, its type ("technical" or "non_technical"), a category (e.g. coding, system_design, behavioral, situational, culture_fit), a difficulty (easy|medium|hard), a skillTag (the résumé skill/topic it targets, e.g. React, Kafka, leadership), and a one-sentence rationale for why it fits this candidate.
Return ONLY JSON matching the provided schema.`

  const res = await withRetry(() =>
    ai(apiKeyOverride).models.generateContent({
      model: modelName(model),
      contents: [
        {
          role: 'user',
          parts: [
            { inlineData: { mimeType: 'application/pdf', data: pdfBase64 } },
            { text: prompt },
          ],
        },
      ],
      config: {
        systemInstruction,
        responseMimeType: 'application/json',
        responseSchema: {
          type: Type.OBJECT,
          properties: {
            questions: {
              type: Type.ARRAY,
              items: {
                type: Type.OBJECT,
                properties: {
                  text: { type: Type.STRING },
                  type: { type: Type.STRING, enum: ['technical', 'non_technical'] },
                  category: { type: Type.STRING },
                  difficulty: { type: Type.STRING, enum: ['easy', 'medium', 'hard'] },
                  skillTag: { type: Type.STRING },
                  rationale: { type: Type.STRING },
                },
                required: ['text', 'type', 'category', 'difficulty', 'skillTag', 'rationale'],
              },
            },
          },
          required: ['questions'],
        },
      },
    }),
  )

  const parsed = JSON.parse(res.text ?? '{"questions":[]}') as { questions: GeneratedInterviewQuestion[] }
  const all = Array.isArray(parsed.questions) ? parsed.questions : []
  if (style !== 'mix') return all.slice(0, total)

  // Enforce the exact technical / non-technical split for "mix".
  const tech = all.filter((q) => q.type === 'technical').slice(0, technicalCount)
  const nonTech = all.filter((q) => q.type === 'non_technical').slice(0, nonTechnicalCount)
  return [...tech, ...nonTech]
}

/* ─── Scoring ───────────────────────────────────────────────────────────── */

export interface RawScore {
  perQuestion: { questionId: string; scores: { kpiId: string; score: number }[]; feedback: string }[]
  summary: string
  recommendation: string
}

export async function scoreWithGemini(
  session: InterviewSession,
  template: InterviewTemplate,
): Promise<RawScore> {
  const kpis = template.rubric.kpis.filter((k) => k.enabled)
  const rubricText = kpis.map((k) => `- ${k.id} (${k.label}): ${k.description}`).join('\n')
  const transcript = session.questions
    .map((q, i) =>
      `Q${i + 1} [id:${q.id}] (${q.category ?? 'general'}): ${q.text}\n` +
      `Ideal-answer notes: ${q.idealAnswerNotes ?? '—'}\n` +
      `Candidate answer: ${q.answerText?.trim() || '(no answer given)'}\n`,
    )
    .join('\n')

  const prompt = `You are a fair but rigorous interview scorer. Score each answer against the rubric KPIs on a 0–100 scale, judging only what the candidate actually said.
Use ONLY these KPI ids: ${kpis.map((k) => k.id).join(', ')}.

RUBRIC:
${rubricText}

TRANSCRIPT:
${transcript}

For each question return its exact questionId, a score (0–100) for every KPI id listed above, and one or two sentences of specific feedback. Then provide an overall summary covering strengths and improvement areas, and a recommendation that is exactly one of: strong_yes, yes, maybe, no.`

  const res = await withRetry(() =>
    ai().models.generateContent({
      model: modelName(),
      contents: prompt,
      config: {
        responseMimeType: 'application/json',
        responseSchema: {
          type: Type.OBJECT,
          properties: {
            perQuestion: {
              type: Type.ARRAY,
              items: {
                type: Type.OBJECT,
                properties: {
                  questionId: { type: Type.STRING },
                  scores: {
                    type: Type.ARRAY,
                    items: {
                      type: Type.OBJECT,
                      properties: {
                        kpiId: { type: Type.STRING },
                        score: { type: Type.NUMBER },
                      },
                      required: ['kpiId', 'score'],
                    },
                  },
                  feedback: { type: Type.STRING },
                },
                required: ['questionId', 'scores', 'feedback'],
              },
            },
            summary: { type: Type.STRING },
            recommendation: { type: Type.STRING },
          },
          required: ['perQuestion', 'summary', 'recommendation'],
        },
      },
    }),
  )
  return JSON.parse(res.text ?? '{}') as RawScore
}

/* ─── Conversational (chatbot) transcript scoring ───────────────────────── */

export interface RawConversationScore {
  perQuestion: { questionIndex: number; scores: { kpiId: string; score: number }[]; feedback: string }[]
  summary: string
  strengths: string[]
  improvements: string[]
  recommendation: string
}

export async function scoreConversationWithGemini(
  session: InterviewSession,
  template: InterviewTemplate,
): Promise<RawConversationScore> {
  const kpis = template.rubric.kpis.filter((k) => k.enabled)
  const rubricText = kpis.map((k) => `- ${k.id} (${k.label}): ${k.description}`).join('\n')
  const transcript = (session.transcript ?? [])
    .map((t) =>
      `${t.role === 'interviewer' ? 'INTERVIEWER' : 'CANDIDATE'}` +
      `${typeof t.questionIndex === 'number' ? ` [q${t.questionIndex}${t.isFollowUp ? ' · follow-up' : ''}]` : ''}: ${t.content}`,
    )
    .join('\n')

  const prompt = `You are a fair but rigorous interview scorer. Below is a conversational interview transcript. Score each PRIMARY question (identified by its q-index) on a 0–100 scale against the rubric KPIs, judging only what the candidate actually said (fold any follow-ups into that question's score).
Use ONLY these KPI ids: ${kpis.map((k) => k.id).join(', ')}.

RUBRIC:
${rubricText}

TRANSCRIPT:
${transcript}

For each primary question return its questionIndex, a score (0–100) for every KPI id, and one or two sentences of specific feedback. Then give an overall summary, 2–4 concise strengths, 2–4 concise improvement areas, and a recommendation that is exactly one of: strong_yes, yes, maybe, no.`

  const res = await withRetry(() =>
    ai().models.generateContent({
      model: modelName(),
      contents: prompt,
      config: {
        responseMimeType: 'application/json',
        responseSchema: {
          type: Type.OBJECT,
          properties: {
            perQuestion: {
              type: Type.ARRAY,
              items: {
                type: Type.OBJECT,
                properties: {
                  questionIndex: { type: Type.NUMBER },
                  scores: {
                    type: Type.ARRAY,
                    items: {
                      type: Type.OBJECT,
                      properties: { kpiId: { type: Type.STRING }, score: { type: Type.NUMBER } },
                      required: ['kpiId', 'score'],
                    },
                  },
                  feedback: { type: Type.STRING },
                },
                required: ['questionIndex', 'scores', 'feedback'],
              },
            },
            summary: { type: Type.STRING },
            strengths: { type: Type.ARRAY, items: { type: Type.STRING } },
            improvements: { type: Type.ARRAY, items: { type: Type.STRING } },
            recommendation: { type: Type.STRING },
          },
          required: ['perQuestion', 'summary', 'strengths', 'improvements', 'recommendation'],
        },
      },
    }),
  )
  return JSON.parse(res.text ?? '{}') as RawConversationScore
}
