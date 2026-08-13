import { db } from '../store/db'
import { HttpError } from '../util/ah'
import { avatarInterviewContext, avatarGreetingText } from '../../shared/speech'
import type { AvatarInterviewSettings, AvatarSettingsStatus, TimeOfDay } from '../../shared/types'

/**
 * Server-side Tavus client for CANDIDATE video-avatar interviews.
 *
 * The recruiter configures the avatar once on the Setup page and clicks
 * "Apply to Candidate Interviews" — that stores the config + Tavus key here
 * (db.settings.avatar). When a candidate starts a video_avatar session, the
 * server creates the Tavus conversation from that config, so:
 *   • the candidate's browser never needs (or sees) a Tavus key, and
 *   • every candidate in the batch/role gets the SAME configured avatar.
 *
 * The payload mirrors the recruiter-run Setup flow EXACTLY — persona context +
 * a STRICT question script + a personalised greeting — and deliberately never
 * sends `properties.pipeline_mode`, which the Tavus API rejects
 * ("Unknown field", the 400 that broke the old client-side path).
 */

const TAVUS_BASE = 'https://tavusapi.com/v2'

export function avatarSettings(): (AvatarInterviewSettings & { tavusKey?: string; updatedAt?: string }) | undefined {
  return db.settings.avatar
}

/** The Tavus key candidates' conversations are created with.
 *  Precedence: GLOBAL key (Settings page — single source of truth) → the key
 *  stored with the applied avatar config (legacy) → server env fallback.
 *  Global-first means changing the key in Settings applies everywhere at once,
 *  even if an older key is still baked into a previously-applied config. */
export function tavusKey(): string {
  return (
    (db.settings.tavusApiKey ?? '').trim() ||
    (db.settings.avatar?.tavusKey ?? '').trim() ||
    (process.env.TAVUS_API_KEY ?? '').trim()
  )
}

/** Ready to run candidate avatar interviews? Needs a replica AND a key. */
export function avatarConfigured(): boolean {
  return Boolean(db.settings.avatar?.replicaId && tavusKey())
}

/** Masked status for the recruiter UI — never returns the key. */
export function avatarStatus(): AvatarSettingsStatus {
  const a = db.settings.avatar
  return {
    configured: avatarConfigured(),
    hasKey: Boolean(tavusKey()),
    replicaId: a?.replicaId || undefined,
    personaId: a?.personaId || undefined,
    language: a?.language || undefined,
    updatedAt: a?.updatedAt,
  }
}

export interface CandidateConversation {
  conversation_id: string
  conversation_url: string
}

/**
 * Build the conversation payload for one candidate — same shape as the Setup
 * page's recruiter-run payload (proven to work on this account), with the
 * spoken parts produced by the SHARED voice/persona standard (shared/speech.ts):
 * warm time-appropriate greeting, ready-check, varied thank-you after every
 * answer, warm wrap-up — and questions stripped of any formatting so nothing
 * markdown-ish is ever read aloud.
 */
function buildPayload(
  cfg: AvatarInterviewSettings,
  candidateName: string,
  questions: string[],
  timeOfDay?: TimeOfDay,
  resumeText?: string,
): Record<string, unknown> {
  const ctx = avatarInterviewContext({
    personaText: cfg.conversationalContext,
    candidateName: candidateName.trim() || undefined,
    aiName: cfg.aiName,
    questions,
    timeOfDay,
    resumeText, // the candidate's résumé — background the avatar speaks from
  })
  const greeting = avatarGreetingText({
    custom: cfg.customGreeting,
    candidateName: candidateName.trim() || undefined,
    aiName: cfg.aiName,
    timeOfDay,
  })

  const properties: Record<string, unknown> = {
    max_call_duration: cfg.maxCallDuration && cfg.maxCallDuration >= 60 ? cfg.maxCallDuration : 1800,
    participant_left_timeout: 60,
    enable_transcription: true, // candidate speech → live captions → answers for scoring
  }
  // Language: full name, only when not the default (mirrors the Setup page).
  if (cfg.language && cfg.language !== 'English') properties.language = cfg.language
  if (cfg.enableRecording) properties.enable_recording = true
  // NOTE: properties.pipeline_mode intentionally NOT sent — Tavus rejects it.

  // Recruiter's conversation name (Setup) is the base; candidate name appended.
  const base = cfg.conversationName?.trim() || 'TalbotIQ'
  const body: Record<string, unknown> = {
    replica_id: cfg.replicaId,
    conversation_name: `${base} — ${candidateName.trim() || 'Candidate'}`,
    conversational_context: ctx,
    custom_greeting: greeting,
    properties,
  }
  if (cfg.personaId) body.persona_id = cfg.personaId
  if (cfg.callbackUrl?.trim()) body.callback_url = cfg.callbackUrl.trim()
  return body
}

/** Create the candidate's Tavus conversation. Throws HttpError with the Tavus message on failure. */
export async function createCandidateConversation(
  candidateName: string,
  questions: string[],
  timeOfDay?: TimeOfDay,
  resumeText?: string,
): Promise<CandidateConversation> {
  const cfg = db.settings.avatar
  const key = tavusKey()
  if (!cfg?.replicaId || !key)
    throw new HttpError(503, 'The video avatar is not configured yet — the recruiter must apply avatar settings on the Setup page.')

  const res = await fetch(`${TAVUS_BASE}/conversations`, {
    method: 'POST',
    headers: { 'x-api-key': key, 'Content-Type': 'application/json' },
    body: JSON.stringify(buildPayload(cfg, candidateName, questions, timeOfDay, resumeText)),
  })
  if (!res.ok) {
    const err = await res.json().catch(() => null) as { message?: string; error?: string } | null
    const msg = err?.message ?? err?.error ?? `Tavus error (HTTP ${res.status})`
    console.error('[avatar] Tavus conversation create failed:', msg)
    throw new HttpError(502, typeof msg === 'string' ? msg : JSON.stringify(msg))
  }
  const conv = await res.json() as CandidateConversation
  if (!conv.conversation_url) throw new HttpError(502, 'Tavus returned no conversation URL')
  return conv
}

/**
 * Pull the finished conversation's transcript from Tavus (server → Tavus, so it
 * works even where webhooks can't reach us, e.g. local dev). Tavus attaches the
 * transcript to the conversation shortly after it ends (`?verbose=true`
 * includes the transcription events). Returns null when it isn't ready yet or
 * the shape is unrecognized — callers retry.
 */
export async function fetchConversationTranscript(
  conversationId: string,
): Promise<Array<{ role: 'interviewer' | 'candidate'; text: string }> | null> {
  const key = tavusKey()
  if (!key || !conversationId) return null
  try {
    const res = await fetch(`${TAVUS_BASE}/conversations/${conversationId}?verbose=true`, {
      headers: { 'x-api-key': key },
    })
    if (!res.ok) return null
    const data = (await res.json()) as Record<string, unknown>

    // The transcript may sit directly on the conversation, or inside a
    // transcription event — accept both shapes defensively.
    const direct = data.transcript
    const events = Array.isArray(data.events) ? (data.events as Array<Record<string, unknown>>) : []
    const eventTranscript = events
      .map((e) => (e.properties as Record<string, unknown> | undefined)?.transcript ?? e.transcript)
      .find((t) => Array.isArray(t) && t.length > 0)
    const raw = Array.isArray(direct) && direct.length > 0 ? direct : eventTranscript
    if (!Array.isArray(raw)) return null

    const turns: Array<{ role: 'interviewer' | 'candidate'; text: string }> = []
    for (const item of raw as Array<Record<string, unknown>>) {
      const role = String(item.role ?? '')
      const text = typeof item.content === 'string' ? item.content : typeof item.text === 'string' ? item.text : ''
      if (!text.trim()) continue
      if (role === 'system') continue
      turns.push({ role: role === 'user' ? 'candidate' : 'interviewer', text: text.trim() })
    }
    return turns.length > 0 ? turns : null
  } catch (err) {
    console.error('[avatar] transcript pull failed for', conversationId, err)
    return null
  }
}

/** End a Tavus conversation (frees the concurrency slot). Best-effort. */
export async function endCandidateConversation(conversationId: string): Promise<void> {
  const key = tavusKey()
  if (!key || !conversationId) return
  try {
    await fetch(`${TAVUS_BASE}/conversations/${conversationId}/end`, {
      method: 'POST',
      headers: { 'x-api-key': key },
    })
  } catch (err) {
    console.error('[avatar] failed to end Tavus conversation', conversationId, err)
  }
}
