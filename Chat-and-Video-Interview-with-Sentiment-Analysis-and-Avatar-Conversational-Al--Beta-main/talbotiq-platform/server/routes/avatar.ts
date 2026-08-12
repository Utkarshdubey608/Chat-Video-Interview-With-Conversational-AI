import { Router } from 'express'
import { randomUUID } from 'node:crypto'
import multer from 'multer'
import { ah, HttpError } from '../util/ah'
import { db } from '../store/db'
import { geminiClient } from '../services/gemini'
import { detectFaces } from '../services/rekognition'

/**
 * AI Avatar Screening — hybrid credential proxy.
 *
 * The teammate's source app called Deepgram / Hume / Gemini directly from the
 * browser (keys in the client bundle) and AWS Rekognition via a standalone proxy.
 * Here every third-party key stays SERVER-SIDE: these routes are thin key-injecting
 * proxies, so the client keeps its exact prompt/parse/aggregation logic and only
 * the credential moves to the server.
 *
 * Server env vars (see .env.example): DEEPGRAM_API_KEY, HUME_API_KEY,
 * GEMINI_API_KEY (shared with scoring), AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY /
 * AWS_REGION. The Tavus key is entered at runtime in the Settings UI (never bundled).
 */
export const avatarRouter = Router()

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 25 * 1024 * 1024 } })

const env = (k: string) => (process.env[k] ?? '').trim()
const deepgramKey = () => env('DEEPGRAM_API_KEY')
const humeKey = () => env('HUME_API_KEY')
const geminiKey = () => (db.settings.geminiApiKey || process.env.GEMINI_API_KEY || '').trim()
const awsCreds = () => ({
  accessKeyId: env('AWS_ACCESS_KEY_ID'),
  secretAccessKey: env('AWS_SECRET_ACCESS_KEY'),
  region: env('AWS_REGION') || 'us-east-2',
})

const HUME_BASE = 'https://api.hume.ai'
const DEEPGRAM_BASE = 'https://api.deepgram.com'
const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/models'

/* ─── which services are configured (UI gating; never returns secrets) ───── */
avatarRouter.get('/status', (_req, res) => {
  const aws = awsCreds()
  res.json({
    deepgram: !!deepgramKey(),
    // Voice-emotion analysis is available when Hume is configured OR the Gemini
    // audio fallback can run (Hume discontinued its batch prosody API).
    hume: !!humeKey() || !!geminiKey(),
    gemini: !!geminiKey(),
    rekognition: !!(aws.accessKeyId && aws.secretAccessKey),
  })
})

/* ─── Deepgram: mint a short-lived token for the browser WS (key stays server) ─ */
avatarRouter.post('/deepgram/token', ah(async (_req, res) => {
  const key = deepgramKey()
  if (!key) throw new HttpError(400, 'Deepgram is not configured on the server')
  const r = await fetch(`${DEEPGRAM_BASE}/v1/auth/grant`, {
    method: 'POST',
    headers: { Authorization: `Token ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ ttl_seconds: 30 }),
  })
  const data = await r.json().catch(() => null) as { access_token?: string; expires_in?: number; err_msg?: string } | null
  if (!r.ok || !data?.access_token) throw new HttpError(502, `Deepgram token grant failed: ${data?.err_msg ?? `HTTP ${r.status}`}`)
  res.json({ access_token: data.access_token, expires_in: data.expires_in ?? 30 })
}))

/* ─── Voice-emotion analysis: Hume batch with a Gemini audio fallback ─────── */
//
// Hume discontinued its batch Expression-Measurement API ("The Expression
// Measurement API has been discontinued"), so a plain proxy can never succeed.
// Strategy: try real Hume first (works if the account/product returns), and on
// ANY submit failure fall back to Gemini's audio understanding, asking it to
// score vocal prosody per ~5s segment using Hume's exact emotion vocabulary.
// The result is wrapped in Hume's BatchPrediction wire shape, so the client's
// poll → predictions → buildSessionResult pipeline works completely unchanged.

/** Emotion names the client's categorizeEmotion() understands (hume.types.ts). */
const VOICE_EMOTIONS = [
  // positive_high
  'Excitement', 'Enthusiasm', 'Pride', 'Joy', 'Amusement',
  // positive_calm
  'Calmness', 'Contentment', 'Satisfaction', 'Interest',
  // cognitive
  'Concentration', 'Determination', 'Realization', 'Curiosity', 'Surprise (positive)',
  // social
  'Sympathy', 'Nostalgia',
  // negative
  'Anxiety', 'Confusion', 'Disappointment', 'Distress', 'Embarrassment', 'Fear', 'Sadness', 'Tiredness',
  // disengagement
  'Boredom', 'Doubt', 'Awkwardness',
]
const VOICE_EMOTIONS_ALLOWED = new Set(VOICE_EMOTIONS.map((n) => n.toLowerCase()))

interface VoiceSegment { begin: number; end: number; emotions: Array<{ name: string; score: number }> }
interface VoiceJob { status: 'IN_PROGRESS' | 'COMPLETED' | 'FAILED'; predictions?: unknown[]; error?: string; createdAt: number }
const voiceJobs = new Map<string, VoiceJob>()
const VOICE_JOB_TTL_MS = 60 * 60 * 1000

function purgeVoiceJobs() {
  const cutoff = Date.now() - VOICE_JOB_TTL_MS
  for (const [id, job] of voiceJobs) if (job.createdAt < cutoff) voiceJobs.delete(id)
}

const VOICE_PROMPT = `You are an expert vocal prosody analyst. Listen to this recording of a job-interview candidate answering questions.

Divide the recording into consecutive segments of roughly 4-6 seconds covering the ENTIRE duration. For EACH segment, score how the candidate's VOICE sounds (tone, energy, pace, steadiness, tremor) — not the meaning of the words — across 6 to 10 emotions chosen ONLY from this exact list:
${VOICE_EMOTIONS.join(', ')}

Rules:
- "begin" and "end" are seconds from the start of the audio; segments must be contiguous and cover the full duration.
- Scores are 0.0-1.0. Most real scores land between 0.05 and 0.6; only strong, unmistakable vocal signals exceed 0.6.
- For silent or non-speech segments use low-intensity Calmness/Boredom style scores rather than skipping the segment.
- Use ONLY the emotion names given, spelled exactly as written.
- Output ONLY a JSON array, no prose: [{"begin": 0, "end": 5.2, "emotions": [{"name": "Calmness", "score": 0.42}, ...]}, ...]`

function sanitizeVoiceSegments(raw: unknown): VoiceSegment[] {
  if (!Array.isArray(raw)) return []
  const out: VoiceSegment[] = []
  for (const s of raw as Array<Record<string, unknown>>) {
    const begin = Number(s?.begin)
    const end = Number(s?.end)
    if (!Number.isFinite(begin) || !Number.isFinite(end) || end <= begin || begin < 0) continue
    const emotions = (Array.isArray(s?.emotions) ? (s.emotions as Array<Record<string, unknown>>) : [])
      .map((e) => ({ name: String(e?.name ?? ''), score: Math.max(0, Math.min(1, Number(e?.score))) }))
      .filter((e) => e.name && Number.isFinite(e.score) && VOICE_EMOTIONS_ALLOWED.has(e.name.toLowerCase()))
    if (emotions.length) out.push({ begin, end, emotions })
  }
  return out.sort((a, b) => a.begin - b.begin)
}

/** Wrap Gemini segments in Hume's BatchPrediction envelope (see hume.types.ts). */
function wrapAsBatchPredictions(segments: VoiceSegment[], filename: string): unknown[] {
  return [{
    source: { type: 'file', filename },
    results: {
      predictions: [{
        file: filename,
        models: {
          prosody: {
            grouped_predictions: [{
              id: 'gemini-voice-0',
              predictions: segments.map((s) => ({ time: { begin: s.begin, end: s.end }, emotions: s.emotions })),
            }],
          },
        },
      }],
      errors: [],
    },
  }]
}

async function analyzeVoiceWithGemini(buffer: Buffer, mimeType: string): Promise<VoiceSegment[]> {
  const model = (db.settings.geminiModel || process.env.GEMINI_MODEL || 'gemini-2.5-flash').trim()
  const data = buffer.toString('base64')
  // MediaRecorder produces audio/webm (Opus). Gemini's documented audio types
  // don't include it, but it accepts webm as a VIDEO container — so retry with
  // video/webm (audio track still analyzed) if the audio mime is rejected.
  const mimes = [...new Set([mimeType.split(';')[0].trim() || 'audio/webm', 'video/webm'])]
  let lastErr: unknown
  for (const mime of mimes) {
    try {
      const res = await geminiClient().models.generateContent({
        model,
        contents: [{ role: 'user', parts: [{ inlineData: { mimeType: mime, data } }, { text: VOICE_PROMPT }] }],
        config: { responseMimeType: 'application/json', temperature: 0.2, maxOutputTokens: 60000 },
      })
      const text = (res.text ?? '').replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/```\s*$/i, '').trim()
      const segments = sanitizeVoiceSegments(JSON.parse(text))
      if (segments.length === 0) throw new Error('Gemini returned no usable prosody segments')
      return segments
    } catch (err) {
      lastErr = err
      console.warn(`[avatar] Gemini voice analysis with mime "${mime}" failed:`, (err as Error)?.message)
    }
  }
  throw lastErr instanceof Error ? lastErr : new Error(String(lastErr))
}

async function runGeminiVoiceJob(jobId: string, buffer: Buffer, mimeType: string, filename: string) {
  try {
    const segments = await analyzeVoiceWithGemini(buffer, mimeType)
    voiceJobs.set(jobId, { status: 'COMPLETED', predictions: wrapAsBatchPredictions(segments, filename), createdAt: Date.now() })
    console.log(`[avatar] voice analysis ${jobId} completed — ${segments.length} prosody segments (Gemini fallback)`)
  } catch (err) {
    voiceJobs.set(jobId, { status: 'FAILED', error: (err as Error)?.message ?? String(err), createdAt: Date.now() })
    console.error(`[avatar] voice analysis ${jobId} failed:`, (err as Error)?.message)
  }
}

avatarRouter.post('/hume/jobs', upload.single('file'), ah(async (req, res) => {
  purgeVoiceJobs()
  const file = (req as typeof req & { file?: { buffer: Buffer; mimetype: string; originalname: string } }).file
  if (!file) throw new HttpError(400, 'No audio file uploaded')

  // 1) Real Hume first, when configured — works again automatically if Hume
  //    ever restores the product (or a different account has access).
  const key = humeKey()
  if (key) {
    try {
      const form = new FormData()
      form.append('file', new Blob([new Uint8Array(file.buffer)], { type: file.mimetype || 'audio/webm' }), file.originalname || 'interview.webm')
      form.append('json', JSON.stringify({ models: { prosody: {} } }))
      const r = await fetch(`${HUME_BASE}/v0/batch/jobs`, { method: 'POST', headers: { 'X-Hume-Api-Key': key }, body: form })
      const data = await r.json().catch(() => null) as { job_id?: string; id?: string; message?: string } | null
      const jobId = data?.job_id ?? data?.id
      if (r.ok && jobId) return res.json({ job_id: jobId })
      console.warn(`[avatar] Hume submit failed (${data?.message ?? `HTTP ${r.status}`}) — using Gemini voice-analysis fallback`)
    } catch (err) {
      console.warn('[avatar] Hume submit errored — using Gemini voice-analysis fallback:', (err as Error)?.message)
    }
  }

  // 2) Gemini audio fallback (same job/poll/predictions contract as Hume).
  if (!geminiKey()) throw new HttpError(502, 'Voice analysis unavailable: Hume rejected the job and Gemini is not configured')
  const jobId = `gemvoice-${randomUUID()}`
  voiceJobs.set(jobId, { status: 'IN_PROGRESS', createdAt: Date.now() })
  void runGeminiVoiceJob(jobId, file.buffer, file.mimetype || 'audio/webm', file.originalname || 'interview.webm')
  res.json({ job_id: jobId })
}))

avatarRouter.get('/hume/jobs/:id', ah(async (req, res) => {
  purgeVoiceJobs()
  const id = req.params.id
  if (id.startsWith('gemvoice-')) {
    const job = voiceJobs.get(id)
    // Unknown id (e.g. server restarted and the in-memory job vanished): report
    // FAILED with 200 so the client fails FAST instead of retrying 404s for
    // ~10 minutes and blocking the Gemini ATS auto-run behind the spinner.
    if (!job) return res.json({ job_id: id, status: 'FAILED', error: 'Voice-analysis job no longer exists (server restarted?)' })
    return res.json({ job_id: id, status: job.status, ...(job.error ? { error: job.error } : {}) })
  }
  const key = humeKey()
  if (!key) throw new HttpError(400, 'Hume is not configured on the server')
  const r = await fetch(`${HUME_BASE}/v0/batch/jobs/${encodeURIComponent(id)}`, { headers: { 'X-Hume-Api-Key': key } })
  const text = await r.text()
  if (!r.ok) throw new HttpError(502, `Hume poll failed: HTTP ${r.status}`)
  res.type('application/json').send(text)
}))

avatarRouter.get('/hume/jobs/:id/predictions', ah(async (req, res) => {
  const id = req.params.id
  if (id.startsWith('gemvoice-')) {
    const job = voiceJobs.get(id)
    if (!job) return res.status(404).json({ error: 'Unknown voice-analysis job' })
    if (job.status !== 'COMPLETED') return res.status(409).json({ error: `Job is ${job.status}` })
    return res.json(job.predictions ?? [])
  }
  const key = humeKey()
  if (!key) throw new HttpError(400, 'Hume is not configured on the server')
  const r = await fetch(`${HUME_BASE}/v0/batch/jobs/${encodeURIComponent(id)}/predictions`, { headers: { 'X-Hume-Api-Key': key } })
  const text = await r.text()
  if (!r.ok) throw new HttpError(502, `Hume predictions fetch failed: HTTP ${r.status}`)
  res.type('application/json').send(text)
}))

/* ─── Gemini: key-injecting passthrough (client builds the prompt + parses) ─ */
avatarRouter.post('/gemini-generate', ah(async (req, res) => {
  const key = geminiKey()
  if (!key) throw new HttpError(400, 'Gemini is not configured on the server')
  const model = String(req.body?.model ?? 'gemini-2.5-flash')
  if (!/^gemini-[\w.-]+$/.test(model)) throw new HttpError(400, 'Invalid model name')
  const requestBody = req.body?.requestBody
  if (!requestBody || typeof requestBody !== 'object') throw new HttpError(400, 'Missing requestBody')
  const r = await fetch(`${GEMINI_BASE}/${model}:generateContent?key=${key}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(requestBody),
  })
  const text = await r.text()
  res.status(r.status).type('application/json').send(text)
}))

/* ─── AWS Rekognition DetectFaces (folded in from the standalone proxy) ──── */
avatarRouter.post('/analyze-face', ah(async (req, res) => {
  const { imageBase64, questionIdx, timestampMs } = req.body ?? {}
  if (!imageBase64) return res.status(400).json({ success: false, error: 'imageBase64 required' })
  // Reject tiny/blank frames without spending an API call.
  if ((imageBase64.length * 3) / 4 < 5000) return res.json({ success: false, reason: 'frame_too_small', questionIdx, timestampMs })
  try {
    const r = await detectFaces(imageBase64)
    if (!r.success) return res.status(400).json({ success: false, error: r.error })
    res.json({ success: true, faceDetails: r.faceDetails, questionIdx, timestampMs })
  } catch (err) {
    const e = err as { name?: string; message?: string }
    console.error('[avatar] Rekognition error:', e?.name, e?.message)
    res.status(500).json({ success: false, error: e?.message ?? String(err) })
  }
}))
