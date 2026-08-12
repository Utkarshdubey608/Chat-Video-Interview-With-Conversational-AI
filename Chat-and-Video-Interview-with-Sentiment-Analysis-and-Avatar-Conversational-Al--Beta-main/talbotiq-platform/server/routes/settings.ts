import { Router } from 'express'
import { db } from '../store/db'
import { ah, HttpError } from '../util/ah'
import { keyStatus } from '../services/gemini'
import { avatarStatus } from '../services/tavusServer'
import type { AvatarInterviewSettings } from '../../shared/types'

export const settingsRouter = Router()

// Status only — the raw key is never returned to the client.
settingsRouter.get('/', (_req, res) => {
  res.json(keyStatus())
})

/* ─── Video Avatar (Tavus) — applied candidate-interview config ────────────
 * Saved from the Setup page's "Apply to Candidate Interviews". The config +
 * Tavus key live server-side; every video_avatar candidate session creates its
 * conversation from them. Status responses are MASKED (never include the key). */

settingsRouter.get('/avatar', (_req, res) => {
  res.json(avatarStatus())
})

settingsRouter.put('/avatar', ah((req, res) => {
  const b = (req.body ?? {}) as Partial<AvatarInterviewSettings> & { tavusKey?: string }
  const replicaId = typeof b.replicaId === 'string' ? b.replicaId.trim() : ''
  if (!replicaId) throw new HttpError(400, 'A replica is required — pick one on the Setup page before applying.')

  const str = (v: unknown) => (typeof v === 'string' && v.trim() ? v.trim() : undefined)
  const prev = db.settings.avatar
  db.settings.avatar = {
    replicaId,
    personaId: str(b.personaId),
    aiName: str(b.aiName)?.slice(0, 60),
    conversationName: str(b.conversationName)?.slice(0, 120),
    conversationalContext: str(b.conversationalContext),
    customGreeting: str(b.customGreeting),
    language: str(b.language),
    maxCallDuration: typeof b.maxCallDuration === 'number' && b.maxCallDuration >= 60 ? Math.min(b.maxCallDuration, 7200) : undefined,
    enableRecording: b.enableRecording === true || undefined,
    callbackUrl: str(b.callbackUrl),
    fallbackQuestions: Array.isArray(b.fallbackQuestions)
      ? b.fallbackQuestions.filter((q): q is string => typeof q === 'string' && !!q.trim()).slice(0, 30)
      : undefined,
    // Keep the previously-saved key when the request doesn't carry one.
    tavusKey: str(b.tavusKey) ?? prev?.tavusKey,
    updatedAt: new Date().toISOString(),
  }
  db.scheduleSave()
  res.json(avatarStatus())
}))

settingsRouter.delete('/avatar', (_req, res) => {
  db.settings.avatar = undefined
  db.scheduleSave()
  res.json(avatarStatus())
})

/* ─── Tavus key — GLOBAL, single source of truth ───────────────────────────
 * Saved from the Settings page. Updating it here applies EVERYWHERE at once:
 * it becomes the highest-precedence key for candidate conversations and is
 * synced onto any previously-applied avatar config so no stale copy survives. */

settingsRouter.put('/tavus-key', ah((req, res) => {
  const apiKey = typeof req.body?.apiKey === 'string' ? req.body.apiKey.trim() : ''
  db.settings.tavusApiKey = apiKey || undefined
  // Sync the copy stored with the applied avatar config — one key, everywhere.
  if (db.settings.avatar) {
    db.settings.avatar.tavusKey = apiKey || undefined
    db.settings.avatar.updatedAt = new Date().toISOString()
  }
  db.scheduleSave()
  res.json({
    tavusKeySet: Boolean(apiKey),
    tavusKeyMasked: apiKey ? `${apiKey.slice(0, 4)}…${apiKey.slice(-4)}` : undefined,
  })
}))

settingsRouter.delete('/tavus-key', (_req, res) => {
  db.settings.tavusApiKey = undefined
  if (db.settings.avatar) db.settings.avatar.tavusKey = undefined
  db.scheduleSave()
  res.json({ tavusKeySet: false })
})

settingsRouter.put('/gemini-key', ah((req, res) => {
  const apiKey = typeof req.body?.apiKey === 'string' ? req.body.apiKey.trim() : ''
  const model = typeof req.body?.model === 'string' ? req.body.model.trim() : undefined
  db.settings.geminiApiKey = apiKey || undefined
  if (model) db.settings.geminiModel = model
  db.scheduleSave()
  res.json(keyStatus())
}))

settingsRouter.delete('/gemini-key', (_req, res) => {
  db.settings.geminiApiKey = undefined
  db.scheduleSave()
  res.json(keyStatus())
})
