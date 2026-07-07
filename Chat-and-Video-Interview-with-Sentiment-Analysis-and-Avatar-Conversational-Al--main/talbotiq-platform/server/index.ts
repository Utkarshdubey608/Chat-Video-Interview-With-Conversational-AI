import 'dotenv/config'
import express, { type ErrorRequestHandler } from 'express'
import cors from 'cors'
import { db } from './store/db'
import { templatesRouter } from './routes/templates'
import { questionSetsRouter } from './routes/questionSets'
import { sessionsRouter } from './routes/sessions'
import { settingsRouter } from './routes/settings'
import { HttpError } from './util/ah'

db.init()

const app = express()
app.use(cors())
app.use(express.json({ limit: '4mb' }))

app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    ts: new Date().toISOString(),
    gemini: Boolean(process.env.GEMINI_API_KEY),
  })
})

app.use('/api/templates', templatesRouter)
app.use('/api/question-sets', questionSetsRouter)
app.use('/api/sessions', sessionsRouter)
app.use('/api/settings', settingsRouter)

const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => {
  if (err instanceof HttpError) {
    res.status(err.status).json({ error: err.message })
    return
  }
  console.error('[server] unhandled error:', err)
  res.status(500).json({ error: err?.message ?? 'Internal server error' })
}
app.use(errorHandler)

const PORT = Number(process.env.PORT ?? 8787)
app.listen(PORT, () => {
  console.log(`[server] TalbotIQ API listening on http://localhost:${PORT}`)
  if (!process.env.GEMINI_API_KEY)
    console.warn('[server] GEMINI_API_KEY not set — adaptive questions & scoring use heuristic fallback.')
})
