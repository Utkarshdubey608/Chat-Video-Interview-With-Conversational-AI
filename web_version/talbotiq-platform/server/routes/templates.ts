import { Router } from 'express'
import { randomUUID } from 'node:crypto'
import { db } from '../store/db'
import { ah, HttpError } from '../util/ah'
import {
  DEFAULT_TIMING,
  DEFAULT_INTEGRITY,
  DEFAULT_BRANDING,
  DEFAULT_CONVERSATION_TIMING,
  DEFAULT_CHATBOT_TIMER,
  DEFAULT_VOICE_CONFIG,
  defaultRubric,
  defaultAdaptive,
} from '../store/defaults'
import type { InterviewTemplate } from '../../shared/types'

export const templatesRouter = Router()

templatesRouter.get('/', (_req, res) => {
  res.json([...db.templates.values()].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)))
})

templatesRouter.get('/:id', (req, res) => {
  const t = db.templates.get(req.params.id)
  if (!t) throw new HttpError(404, 'Template not found')
  res.json(t)
})

templatesRouter.post('/', ah((req, res) => {
  const now = new Date().toISOString()
  const b = req.body ?? {}
  const track = b.track ?? 'chat'
  const questionSource = b.questionSource ?? 'fixed'
  const t: InterviewTemplate = {
    id: randomUUID(),
    name: b.name ?? 'Untitled template',
    role: b.role ?? '',
    seniority: b.seniority,
    track,
    questionSource,
    fixedQuestionSetId: b.fixedQuestionSetId,
    timing: { ...DEFAULT_TIMING, ...(b.timing ?? {}) },
    rubric: b.rubric ?? defaultRubric(),
    integrity: { ...DEFAULT_INTEGRITY, ...(b.integrity ?? {}) },
    branding: { ...DEFAULT_BRANDING, ...(b.branding ?? {}) },
    // Chatbot (conversational) / voice track config
    mode: b.mode ?? (track === 'chatbot' || track === 'voice' ? 'conversational' : undefined),
    adaptive:
      b.adaptive ??
      ((track === 'chatbot' || track === 'voice') && questionSource === 'adaptive' ? defaultAdaptive(b.role || 'Software Engineer') : undefined),
    fixedAllowFollowUps: b.fixedAllowFollowUps,
    conversationTiming:
      b.conversationTiming ?? (track === 'chatbot' ? { ...DEFAULT_CONVERSATION_TIMING } : undefined),
    chatbotTimer:
      b.chatbotTimer ?? (track === 'chatbot' || track === 'video_avatar' ? { ...DEFAULT_CHATBOT_TIMER } : undefined),
    voice: b.voice ?? (track === 'voice' ? { ...DEFAULT_VOICE_CONFIG } : undefined),
    createdAt: now,
    updatedAt: now,
  }
  db.templates.set(t.id, t)
  db.scheduleSave()
  res.status(201).json(t)
}))

templatesRouter.put('/:id', ah((req, res) => {
  const existing = db.templates.get(req.params.id)
  if (!existing) throw new HttpError(404, 'Template not found')
  const updated: InterviewTemplate = {
    ...existing,
    ...req.body,
    id: existing.id,
    createdAt: existing.createdAt,
    updatedAt: new Date().toISOString(),
  }
  db.templates.set(updated.id, updated)
  db.scheduleSave()
  res.json(updated)
}))

templatesRouter.delete('/:id', (req, res) => {
  db.templates.delete(req.params.id)
  db.scheduleSave()
  res.status(204).end()
})
