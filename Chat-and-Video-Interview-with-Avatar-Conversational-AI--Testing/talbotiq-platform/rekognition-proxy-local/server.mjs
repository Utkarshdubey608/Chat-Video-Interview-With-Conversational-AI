// rekognition-proxy-local/server.mjs
// LOCAL DEVELOPMENT ONLY proxy for AWS Rekognition DetectFaces.
// The AWS secret lives here (server-side), never in the browser bundle.
//
// Setup:
//   1. cd rekognition-proxy-local
//   2. npm install
//   3. Set env vars (PowerShell):
//        $env:AWS_ACCESS_KEY_ID="AKIA..."; $env:AWS_SECRET_ACCESS_KEY="..."; $env:AWS_REGION="us-east-2"
//   4. node server.mjs   → listens on http://localhost:3002/analyze-face
//
// NEVER commit real credentials. NEVER deploy this file with hardcoded keys.

import dotenv from 'dotenv'
import path from 'path'
dotenv.config({ path: path.resolve(process.cwd(), '../.env') })

// Startup debug: show whether the .env was loaded and if a Deepgram key exists.
const _envPath = path.resolve(process.cwd(), '../.env')
const _cfg = dotenv.config({ path: _envPath })
const _key = process.env.DEEPGRAM_API_KEY ?? process.env.DG_API_KEY ?? process.env.VITE_DEEPGRAM_KEY
const _masked = _key ? `${String(_key).slice(0,4)}...${String(_key).slice(-4)}` : 'NOT SET'
console.log(`[proxy] dotenv loaded from ${_envPath} parsed=${!!_cfg.parsed} Deepgram=${_masked}`)

import express from 'express'
import cors from 'cors'
import { RekognitionClient, DetectFacesCommand } from '@aws-sdk/client-rekognition'

const PORT = process.env.PORT ?? 3002
const REGION = process.env.AWS_REGION ?? 'us-east-2'

if (!process.env.AWS_ACCESS_KEY_ID || !process.env.AWS_SECRET_ACCESS_KEY) {
  console.warn('[proxy] WARNING: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY not set — calls will fail with a credentials error.')
}

const client = new RekognitionClient({
  region: REGION,
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID ?? '',
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY ?? '',
  },
})

const app = express()
app.use(cors())
app.use(express.json({ limit: '10mb' }))

app.get('/health', (_req, res) => res.json({ ok: true, region: REGION }))

app.post('/analyze-face', async (req, res) => {
  const { imageBase64, questionIdx, timestampMs } = req.body ?? {}

  if (!imageBase64) {
    return res.status(400).json({ success: false, error: 'imageBase64 required' })
  }
  // Reject tiny/blank frames (< ~5KB) without spending an API call
  const byteEstimate = (imageBase64.length * 3) / 4
  if (byteEstimate < 5000) {
    return res.json({ success: false, reason: 'frame_too_small', questionIdx, timestampMs })
  }

  try {
    const command = new DetectFacesCommand({
      Image: { Bytes: Buffer.from(imageBase64, 'base64') },
      Attributes: ['ALL'], // emotions, landmarks, quality, pose, gaze
    })
    const response = await client.send(command)
    res.json({
      success: true,
      faceDetails: response.FaceDetails ?? [],
      questionIdx,
      timestampMs,
    })
  } catch (err) {
    console.error('[proxy] Rekognition error:', err?.name, err?.message)
    res.status(500).json({ success: false, error: err?.message ?? String(err) })
  }
})

// Deepgram proxy route (local development)
app.get('/deepgram/projects', async (_req, res) => {
  // Accept either a server env var or the VITE_ prefixed key from the repo .env
  const key = process.env.DEEPGRAM_API_KEY ?? process.env.DG_API_KEY ?? process.env.VITE_DEEPGRAM_KEY
  const masked = key ? `${String(key).slice(0,4)}...${String(key).slice(-4)}` : 'NOT SET'
  console.log(`[proxy] /deepgram/projects request — Deepgram key=${masked}`)
  if (!key) {
    console.log('[proxy] /deepgram/projects rejected: no key available')
    return res.status(500).json({ success: false, error: 'Deepgram API key not configured on server' })
  }
  try {
    const dgRes = await fetch('https://api.deepgram.com/v1/projects', {
      headers: { Authorization: `Token ${key.trim()}` },
    })
    const text = await dgRes.text()
    const contentType = dgRes.headers.get('content-type') ?? 'application/json'
    res.status(dgRes.status).set('content-type', contentType).send(text)
  } catch (err) {
    console.error('[proxy] Deepgram proxy error:', err)
    res.status(502).json({ success: false, error: err?.message ?? String(err) })
  }
})

app.listen(PORT, () => {
  console.log(`[proxy] Rekognition proxy on http://localhost:${PORT}/analyze-face  (region ${REGION})`)
})
