import 'dotenv/config'
import express, { type ErrorRequestHandler } from 'express'
import cors from 'cors'
import { db } from './store/db'
import { templatesRouter } from './routes/templates'
import { questionSetsRouter } from './routes/questionSets'
import { sessionsRouter } from './routes/sessions'
import { settingsRouter } from './routes/settings'
import { voicesRouter } from './routes/voices'
import { analyticsRouter } from './routes/analytics'
import { invitesRouter } from './routes/invites'
import { inviteEmailTemplatesRouter } from './routes/inviteEmailTemplates'
import { pipelinesRouter } from './routes/pipelines'
import { brevoWebhookRouter } from './routes/brevoWebhook'
import { avatarRouter } from './routes/avatar'
import { authRouter } from './routes/auth'
import { faceCacheRouter } from './routes/faceCache'
import { helpRouter } from './routes/help'
import { leadsRouter } from './routes/leads'
import { authenticate, requireRecruiter } from './middleware/auth'
import { authConfigured } from './services/firebaseAdmin'
import { attachVoiceWebSocket } from './services/voice'
import { attachDeepgramRelay, attachCandidateDeepgramRelay } from './services/deepgramRelay'
import { HttpError } from './util/ah'
import { parseAllowedOrigins, isOriginAllowed } from './util/cors'

db.init()

const app = express()
// Cross-origin is the normal case: the SPA is on Vercel, this API on Render.
// CORS_ORIGINS blank → allow all (previous behaviour); set → strict allowlist.
const allowedOrigins = parseAllowedOrigins(process.env.CORS_ORIGINS)
app.use(cors({ origin: (origin, cb) => cb(null, isOriginAllowed(allowedOrigins, origin)) }))
if (allowedOrigins) console.log(`[server] CORS restricted to: ${allowedOrigins.join(', ')}`)
else console.log('[server] CORS: all origins allowed (set CORS_ORIGINS to restrict)')
app.use(express.json({ limit: '4mb' }))

// NOTE: this path is render.yaml's healthCheckPath, so it deliberately stays
// 200 even when `persistence.ok` is false. A failing disk is a data-integrity
// problem, not a liveness one — returning 503 would make Render restart or fail
// the deploy, which cannot fix a full disk and would turn degraded-but-serving
// into a full outage. Alert on `persistence.ok === false` instead.
app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    ts: new Date().toISOString(),
    gemini: Boolean(process.env.GEMINI_API_KEY),
    auth: authConfigured(),
    authMode: authConfigured() ? 'firebase' : 'none',
    persistence: db.saveHealth(),
  })
})

// ─── Authentication + access control ──────────────────────────────────────
// Defense in depth: the backend is the real security boundary. Every ID token
// is verified server-side (Admin SDK) and authorization is enforced on every
// endpoint — client route guards are UX only.
app.use('/api/auth', authRouter)

// PUBLIC: Mimic marketing-site demo requests. Unauthenticated (visitors are
// pre-login); stored server-side only (never Firestore), so no security-rule
// change is needed. Additive — mounted alongside the other public routes.
app.use('/api/leads', leadsRouter)

// Recruiter-only surfaces: templates, question sets, settings, the voice
// catalog, aggregate analytics, and all AI-Avatar-Screening proxies. Gated
// centrally here so the routers stay focused on their domain logic.
app.use('/api/templates', authenticate, requireRecruiter, templatesRouter)
app.use('/api/question-sets', authenticate, requireRecruiter, questionSetsRouter)
app.use('/api/settings', authenticate, requireRecruiter, settingsRouter)
app.use('/api/voices', authenticate, requireRecruiter, voicesRouter)
app.use('/api/analytics', authenticate, requireRecruiter, analyticsRouter)
// Mounted BEFORE /api/invites so it wins for this path: Brevo delivery webhooks
// are PUBLIC (no bearer token) and carry their own ?token= shared-secret check.
app.use('/api/invites/brevo-webhook', brevoWebhookRouter)
app.use('/api/invites', authenticate, requireRecruiter, invitesRouter)
app.use('/api/invite-email-templates', authenticate, requireRecruiter, inviteEmailTemplatesRouter)
app.use('/api/pipelines', authenticate, requireRecruiter, pipelinesRouter)
// Mounted BEFORE /api/avatar so it wins for this path: it carries its own auth
// that also accepts ?token= (video tags can't send the Authorization header).
app.use('/api/avatar/face-cache', faceCacheRouter)
app.use('/api/avatar', authenticate, requireRecruiter, avatarRouter)

// Sessions mix recruiter (create/list/report) and candidate (take the interview)
// endpoints, so every request is authenticated at the router and each handler
// enforces ownership (recruiter) or verified-email assignment (candidate).
app.use('/api/sessions', authenticate, sessionsRouter)

// Mimic Guide in-app help assistant. Authenticated (recruiters + candidates);
// the caller's role tailors the answer's navigation links. Reuses the existing
// server-side Gemini client — no new key or provider. Additive: reads product
// knowledge only, never touches sessions/templates/question-set logic.
app.use('/api/help', authenticate, helpRouter)

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
const server = app.listen(PORT, () => {
  console.log(`[server] TalbotIQ API listening on http://localhost:${PORT}`)
  if (!process.env.GEMINI_API_KEY)
    console.warn('[server] GEMINI_API_KEY not set — adaptive questions & scoring use heuristic fallback.')
  if (!authConfigured())
    console.warn('[auth] Firebase Admin is NOT configured — auth-guarded /api endpoints will return 503. Set FIREBASE_PROJECT_ID/CLIENT_EMAIL/PRIVATE_KEY (see docs/AUTH.md).')
})

// Real-time Voice Track: WebSocket relay to Gemini Live at /api/voice/:sessionId.
attachVoiceWebSocket(server)

// AI Avatar Screening: Deepgram Nova-3 live-transcription relay at /api/avatar/deepgram.
attachDeepgramRelay(server)

// Video Interview: candidate-authorized Deepgram live-transcription relay at
// /api/interview/deepgram (same relay, open to any authenticated role).
attachCandidateDeepgramRelay(server)
