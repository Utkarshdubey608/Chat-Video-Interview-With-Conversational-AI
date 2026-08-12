import { Router } from 'express'
import { Modality } from '@google/genai'
import { ah, HttpError } from '../util/ah'
import { geminiClient, geminiEnabled } from '../services/gemini'
import { VOICE_CATALOG, PERSONA_PRESETS, DEFAULT_LIVE_MODEL } from '../store/defaults'
import type { VoiceCatalog } from '../../shared/types'

export const voicesRouter = Router()

// Browsable catalog for the recruiter picker (voices + persona presets).
voicesRouter.get('/', (_req, res) => {
  const body: VoiceCatalog = { voices: VOICE_CATALOG, personas: PERSONA_PRESETS }
  res.json(body)
})

/**
 * Generate a short spoken sample for the preview button. Runs one Live turn
 * server-side (key never leaves the server) and returns the concatenated PCM
 * (24 kHz) as base64 for the client to play. ~5s cap.
 */
voicesRouter.post('/:id/sample', ah(async (req, res) => {
  const voice = VOICE_CATALOG.find((v) => v.id === req.params.id)
  if (!voice) throw new HttpError(404, 'Unknown voice')
  if (!geminiEnabled()) throw new HttpError(400, 'A Gemini API key is required to preview voices')

  const line =
    typeof req.body?.text === 'string' && req.body.text.trim()
      ? String(req.body.text).slice(0, 200)
      : `Hi, I'm your interviewer today. Whenever you're ready, we'll get started.`

  const chunks: string[] = []
  await new Promise<void>((resolve) => {
    let done = false
    const finish = () => { if (done) return; done = true; try { session?.close?.() } catch { /* noop */ } resolve() }
    const timer = setTimeout(finish, 12000)
    let session: { close?: () => void } | undefined
    geminiClient().live.connect({
      model: DEFAULT_LIVE_MODEL,
      config: {
        responseModalities: [Modality.AUDIO],
        speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice.id } } },
        systemInstruction: 'Read the provided line once, warmly and naturally. Say nothing else.',
      },
      callbacks: {
        onmessage: (m: any) => {
          for (const part of m?.serverContent?.modelTurn?.parts ?? []) {
            if (part?.inlineData?.data) chunks.push(part.inlineData.data)
          }
          if (m?.serverContent?.turnComplete) { clearTimeout(timer); finish() }
        },
        onerror: () => { clearTimeout(timer); finish() },
        onclose: () => { clearTimeout(timer); finish() },
      },
    }).then((s) => {
      session = s as unknown as { close?: () => void }
      ;(s as any).sendClientContent({ turns: line, turnComplete: true })
    }).catch(() => { clearTimeout(timer); finish() })
  })

  if (chunks.length === 0) throw new HttpError(502, 'Voice preview failed — try again')
  // Each inlineData chunk is an independently-padded base64 string; naively
  // joining the strings yields invalid base64 that truncates at the first
  // padding char when decoded. Concatenate the BYTES, then re-encode once.
  const audio = Buffer.concat(chunks.map((c) => Buffer.from(c, 'base64'))).toString('base64')
  res.json({ voiceId: voice.id, mimeType: 'audio/pcm;rate=24000', audio })
}))
