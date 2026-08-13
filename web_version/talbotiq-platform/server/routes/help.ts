import { Router } from 'express'
import { z } from 'zod'
import { requireAuth } from '../middleware/auth'
import { runMimicGuide } from '../services/mimicGuide'
import { streamGuideSpeech } from '../services/mimicGuideTts'
import { runAutopilotAgent } from '../services/autopilotAgent'
import { HttpError } from '../util/ah'
import type { GuideRole } from '../services/mimicGuidePrompt'

/**
 * Mimic Guide chat endpoint. Mounted at /api/help behind `authenticate`, so both
 * recruiters and candidates can use it. Mirrors Xeno Guide's route: the body is
 * validated, the reply is always returned with a 200 (validation and model
 * errors both resolve to a friendly reply) so the chat stays usable, and raw
 * errors are never surfaced to the client.
 */
export const helpRouter = Router()

// Up to 20 turns of history for multi-turn context. The per-message cap must
// exceed the longest possible assistant reply (bilingual answers with the
// <details> English block can pass 4000 chars) — otherwise one long reply in
// the history would fail validation on every later turn.
const BodySchema = z.object({
  messages: z
    .array(
      z.object({
        role: z.enum(['user', 'assistant']),
        content: z.string().min(1).max(8000),
      }),
    )
    .min(1)
    .max(20),
})

const GENERIC_ERROR = 'Something went wrong. Please try again.'

helpRouter.post('/chat', async (req, res) => {
  try {
    const { messages } = BodySchema.parse(req.body)
    const role: GuideRole = requireAuth(req).role === 'recruiter' ? 'recruiter' : 'candidate'
    const reply = await runMimicGuide(messages, role)
    res.json({ reply })
  } catch (error) {
    console.error('[mimic-guide] chat error', error)
    res.json({ reply: GENERIC_ERROR })
  }
})

// Mimic Guide Autopilot agent turn: decides ONE next action (or asks a
// clarifying question) given the recruiter/candidate's screen context and the
// registered actions available there. Same auth as /chat; the actions
// themselves are RBAC-gated both client- and server-side when they execute.
const ParamSpecSchema = z.object({
  name: z.string(), type: z.enum(['string', 'number', 'boolean', 'enum']),
  enum: z.array(z.string()).optional(), required: z.boolean().optional(), description: z.string().optional(),
})
const AgentSchema = z.object({
  // Tolerant on purpose: long sessions overflow any hard cap, and one empty turn
  // must not brick the loop — the handler below trims to the recent non-empty tail.
  messages: z.array(z.object({ role: z.enum(['user', 'assistant']), content: z.string().max(8000) })).min(1).max(200),
  context: z.object({
    route: z.string().max(200),
    availableActions: z.array(z.object({
      name: z.string(), description: z.string(), screen: z.string(), sideEffect: z.boolean(), params: z.array(ParamSpecSchema),
    })).max(100),
    state: z.record(z.string(), z.unknown()).default({}),
  }),
})

helpRouter.post('/agent', async (req, res) => {
  try {
    const parsed = AgentSchema.parse(req.body)
    requireAuth(req) // recruiter or candidate — same as /chat; actions themselves are RBAC-gated client+server
    // Keep only the recent, non-empty tail — never hard-reject a long/imperfect
    // history (that would fail EVERY subsequent turn and brick the session).
    let msgs = parsed.messages.filter((m) => m.content.trim()).slice(-30)
    if (msgs.length === 0) msgs = [{ role: 'user' as const, content: 'Hello' }]
    const decision = await runAutopilotAgent({ ...parsed, messages: msgs })
    res.json(decision)
  } catch (error) {
    console.error('[autopilot] /agent error', error)
    res.json({ say: 'Something went wrong. Please try again.', awaitingUser: true })
  }
})

// Text-to-speech for the assistant's answers. STREAMS the audio as newline-
// delimited base64 PCM (24 kHz) so the client can start playing within ~1s
// instead of waiting for the whole clip. The full clip is cached server-side, so
// a repeat request replays instantly. Errors before any audio return a real
// status so the client can fall back gracefully.
const TtsSchema = z.object({
  text: z.string().min(1).max(2000),
  lang: z.string().min(2).max(12),
})

helpRouter.post('/tts', async (req, res) => {
  const parsed = TtsSchema.safeParse(req.body)
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid TTS request' })
    return
  }
  const { text, lang } = parsed.data
  res.setHeader('Content-Type', 'application/x-ndjson; charset=utf-8')
  res.setHeader('Cache-Control', 'no-store')
  res.setHeader('X-Accel-Buffering', 'no') // don't let a proxy buffer the stream
  let wrote = false
  try {
    await streamGuideSpeech(text, lang, (b64) => {
      wrote = true
      res.write(b64 + '\n')
      ;(res as unknown as { flush?: () => void }).flush?.()
    })
    res.end()
  } catch (error) {
    console.error('[mimic-guide] tts error', error)
    if (!wrote && !res.headersSent) {
      const status = error instanceof HttpError ? error.status : 502
      res.status(status).json({ error: error instanceof Error ? error.message : 'Voice synthesis failed' })
    } else {
      res.end() // already streaming — just close; the client keeps what it got
    }
  }
})
