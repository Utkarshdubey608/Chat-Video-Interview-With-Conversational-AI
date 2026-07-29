import { geminiClient, modelName, geminiEnabled } from './gemini'
import { isAuthError } from './autopilotAgent'
import {
  buildMimicGuidePrompt,
  OUT_OF_SCOPE_REFUSAL,
  type GuideRole,
} from './mimicGuidePrompt'

/**
 * Mimic Guide — free-form (markdown) help assistant for the TalbotIQ AI
 * Interview Platform. Ported from Xeno Guide: it has no tools, answers from the
 * system prompt's curated knowledge of TalbotIQ, and returns plain markdown.
 * Full conversation history is passed for multi-turn context, and the caller's
 * role tailors the navigation links. Reuses the platform's existing Gemini
 * client (key stays server-side) instead of adding a second AI stack.
 */

export type GuideMessage = { role: 'user' | 'assistant'; content: string }

/**
 * Canned knowledge base used when the live model is unavailable (no key /
 * provider outage / depleted quota). Each topic has a couple of phrasings so
 * repeated questions don't return identical text. Matched by keyword against the
 * latest user message; falls back to a general overview. Mirrors Xeno Guide's
 * degraded-mode behaviour so the assistant stays useful instead of erroring.
 */
const GUIDE_FAQ: Array<{ match: RegExp; answers: string[] }> = [
  {
    match: /session|invite|assign|link/,
    answers: [
      '**Creating an interview session:**\n\n1. Go to **Sessions** (your recruiter home).\n2. Create a session from an existing **Template**.\n3. Share the generated **invite link** with your candidate.\n4. When they finish, open the session\'s **report** to see the score and recommendation.\n\n[Go to Sessions](/sessions)',
      'Interviews are run as **sessions**. From **Sessions**, create one from a template, send the candidate their invite link, then review the report once they\'re done.\n\n[Go to Sessions](/sessions)',
    ],
  },
  {
    match: /template/,
    answers: [
      '**Templates** define how an interview runs — the **track**, the question source (adaptive AI or a fixed **question set**), the rubric KPIs, timing, and voice. Create or duplicate one, then use it when you create a session.\n\n[Manage Templates](/templates)',
    ],
  },
  {
    match: /question set|question-set|questions|rubric|resume|résumé/,
    answers: [
      '**Question Sets** are reusable fixed question lists. Build one, drag to reorder, or **generate questions from a résumé**. A template can use a question set or use adaptive AI questions instead.\n\n[Manage Question Sets](/question-sets)',
    ],
  },
  {
    match: /track|chat|chatbot|voice|avatar|timed|type of interview|interview type/,
    answers: [
      'TalbotIQ supports four interview **tracks**:\n\n- **Timed Q&A** — typed answers with a per-question countdown.\n- **Chatbot / Conversational** — a typed conversation with adaptive follow-ups.\n- **Voice** — a real-time spoken interview.\n- **Video Avatar** — an AI avatar speaks each question on screen.\n\nPick the track in a **Template**.\n\n[Manage Templates](/templates)',
    ],
  },
  {
    match: /avatar screening|screening|tavus|replica|persona|setup|deepgram|hume|rekognition/,
    answers: [
      '**AI Avatar Screening** runs a live AI-avatar video interview and then analyses it. Configure it in **Setup** (pick a replica + persona), run it in the **Interview** room, and review speech, emotion, and facial analytics in **Results**.\n\n[Set up Avatar Screening](/setup)',
    ],
  },
  {
    match: /result|report|score|analytics|recommendation/,
    answers: [
      '**Results:** open a session\'s **report** from the Sessions list for the recommendation, a KPI/rubric radar, per-question feedback, and PDF export. For trends across all interviews, use **Analytics**.\n\n[View Analytics](/analytics)',
    ],
  },
  {
    match: /face|framing|camera|system check|system-check|mic|microphone/,
    answers: [
      'Before a video or avatar interview, the **system check** verifies your microphone and camera. For video/avatar it includes a **face-fit** framing aid that runs in your browser and asks you to centre your face and hold still — it only helps you frame yourself and is not used for scoring.',
    ],
  },
  {
    match: /login|sign in|role|recruiter|candidate|access|permission|iam/,
    answers: [
      '**Roles:** sign in at the login page. Your role is set on the server from your verified email — allowed domains/addresses become **recruiters**; everyone else is a **candidate**. Recruiters see the full app; candidates see only their assigned interviews.',
    ],
  },
  {
    match: /key|api key|gemini|setting/,
    answers: [
      '**Settings** is where a recruiter enters the **Tavus** key and manages the **Gemini** key (kept server-side), and sees whether Deepgram, Hume, and Rekognition are configured.\n\n[Open Settings](/settings)',
    ],
  },
]

function cannedAnswer(question: string): string {
  const q = question.toLowerCase()
  // Vary selection per call so repeated questions aren't identical.
  const pick = <T,>(arr: T[]): T => arr[Math.floor(Math.random() * arr.length)]!
  for (const topic of GUIDE_FAQ) {
    if (topic.match.test(q)) return pick(topic.answers)
  }
  return pick([
    'I can help you navigate TalbotIQ. Ask me how to **create a session**, build a **template** or **question set**, run **AI Avatar Screening**, or read your **results**.',
    'Happy to help! Try: *"How do I create an interview session?"*, *"What interview tracks are there?"*, or *"Where do I see a candidate\'s score?"*',
    'TalbotIQ is an AI Interview Platform. I can walk you through templates, question sets, sessions, the interview tracks, AI Avatar Screening, and results & analytics — what would you like to do?',
  ])
}

export async function runMimicGuide(
  messages: GuideMessage[],
  role: GuideRole,
): Promise<string> {
  const lastUser =
    [...messages].reverse().find((m) => m.role === 'user')?.content ?? ''

  // No key configured anywhere → degrade to the canned knowledge base.
  if (!geminiEnabled()) return cannedAnswer(lastUser)

  try {
    const contents = messages.map((m) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }],
    }))
    // History is trimmed to the last 20 turns client-side, which can leave a
    // model turn first — Gemini expects the conversation to open with a user
    // turn, so drop any leading model messages.
    while (contents.length > 0 && contents[0].role === 'model') contents.shift()
    const res = await geminiClient().models.generateContent({
      model: modelName(),
      contents,
      config: { systemInstruction: buildMimicGuidePrompt(role) },
    })
    const text = (res.text ?? '').trim()
    return text || OUT_OF_SCOPE_REFUSAL
  } catch (error) {
    console.error(
      '[mimic-guide] degraded:',
      error instanceof Error ? error.message : error,
    )
    // Auth/credential failure is NOT a transient outage — say so plainly instead
    // of silently serving canned answers (which masks a broken key as "working"
    // and quietly degrades scoring/question-generation too).
    if (isAuthError(error)) {
      return (
        "I can't reach the AI model right now — the Gemini API key looks invalid, expired, or missing. " +
        'Add a valid Gemini API key in **Settings → Gemini** (or set `GEMINI_API_KEY` on the server), then ask me again. ' +
        "Until then I'll answer from my built-in notes only."
      )
    }
    // Model unavailable (outage / depleted quota) — answer from the canned
    // knowledge base so the assistant stays useful instead of erroring.
    return cannedAnswer(lastUser)
  }
}
