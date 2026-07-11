import { Router } from 'express'
import { db } from '../store/db'
import { ah } from '../util/ah'
import { keyStatus } from '../services/gemini'

export const settingsRouter = Router()

// Status only — the raw key is never returned to the client.
settingsRouter.get('/', (_req, res) => {
  res.json(keyStatus())
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
