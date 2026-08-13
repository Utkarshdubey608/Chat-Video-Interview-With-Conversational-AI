import { randomUUID } from 'node:crypto'
import { FieldValue } from 'firebase-admin/firestore'
import { db } from '../store/db'
import { adminFirestore } from './firebaseAdmin'
import { HttpError } from '../util/ah'
import {
  DEFAULT_TIMING, DEFAULT_INTEGRITY, DEFAULT_BRANDING, defaultRubric, DEFAULT_VOICE_CONFIG,
} from '../store/defaults'
import type {
  AuthContext, InterviewSession, InterviewTemplate, SessionQuestion,
  TrackType, ResultReport, AdaptiveConfig, QuestionStyle, DifficultyChoice,
} from '../../shared/types'

/**
 * Bulk-invite bridge.
 *
 * Invites created by the recruiter live in Firestore (`interviews/{id}`, shared
 * with the Flutter app). The candidate interview ENGINE, however, is the local
 * Express/JSON session store and is entirely template-driven. Rather than rebuild
 * every track (chat / chatbot / voice / video) against Firestore, we MATERIALISE
 * a local session (id === the Firestore interview id) + a synthesised template
 * from the invite the first time the assigned candidate opens their link, then
 * run the existing engine. On completion, `syncInviteResult` writes the score and
 * status back to the Firestore doc so the recruiter + Flutter app see it.
 */

const inviteTemplateId = (interviewId: string) => `invite:${interviewId}`

/** Web mode → local track (the Firestore doc stores the precise `mode`). */
function trackForInvite(data: Record<string, unknown>): TrackType {
  const mode = data.mode as string | undefined
  if (mode === 'chatbot' || mode === 'voice' || mode === 'video_avatar' || mode === 'chat' || mode === 'video' || mode === 'two_way') return mode
  return data.type === 'video' ? 'video_avatar' : 'chat' // fall back from the Flutter `type`
}

/** Test-only surface (pure helpers). */
export const __test = { trackForInvite }

/** Build a valid local template from the invite's stored screening config. */
function synthTemplate(interviewId: string, data: Record<string, unknown>, now: string): InterviewTemplate {
  const role = (data.role as string) || 'this role'
  const track = trackForInvite(data)
  const screening = (data.screening as Record<string, unknown> | undefined) ?? {}
  // Two-way Interview has no scripted question source (the recruiter conducts a
  // live call) — the invite carries no `screening.source` for it (see
  // invites.ts), which would otherwise default to 'adaptive' below and wrongly
  // gate the candidate on a résumé upload (awaitingResume) before they can reach
  // the live room. Force 'fixed' (with an empty embedded question list) instead.
  const source = track === 'two_way' ? 'fixed' : (screening.source as string) === 'set' ? 'fixed' : 'adaptive'

  const techCount = Number(screening.techCount ?? 3)
  const nonTechCount = Number(screening.nonTechCount ?? 2)
  const embedded = Array.isArray(data.questions) ? (data.questions as string[]) : []
  const count = source === 'fixed'
    ? Math.max(1, embedded.length)
    : Math.max(1, Math.min(25, techCount + nonTechCount || 5))

  const adaptive: AdaptiveConfig | undefined = source === 'adaptive'
    ? {
        role,
        difficulty: (screening.difficulty as DifficultyChoice) || 'mixed',
        style: (screening.style as QuestionStyle) || 'mix',
        numberOfQuestions: count,
        technicalCount: techCount,
        nonTechnicalCount: nonTechCount,
        focusTopics: Array.isArray(screening.domains) ? (screening.domains as string[]) : [],
        allowFollowUps: false,
        maxFollowUpsPerQuestion: 1,
        interviewerTone: 'friendly and professional',
        language: 'English',
      }
    : undefined

  return {
    id: inviteTemplateId(interviewId),
    name: `${role} — invite`,
    role,
    track,
    questionSource: source,
    timing: { ...DEFAULT_TIMING, numberOfQuestions: count },
    rubric: defaultRubric(),
    integrity: { ...DEFAULT_INTEGRITY },
    branding: { ...DEFAULT_BRANDING },
    mode: 'conversational',
    ...(adaptive ? { adaptive } : {}),
    ...(track === 'voice' ? { voice: { ...DEFAULT_VOICE_CONFIG } } : {}),
    createdAt: now,
    updatedAt: now,
  }
}

/**
 * Resolve a Firestore invite the assigned candidate is opening into a local
 * session + template (idempotent). Returns the session/template, or throws:
 *   404 if the invite doesn't exist or isn't assigned to this caller (no leak),
 *   409 if it's already completed.
 */
export async function materializeInviteSession(
  interviewId: string,
  auth: AuthContext,
): Promise<{ session: InterviewSession; template: InterviewTemplate }> {
  // Already materialised — reuse it.
  const existing = db.sessions.get(interviewId)
  if (existing) {
    const tpl = db.templates.get(existing.templateId)
    if (!tpl) throw new HttpError(404, 'Template for session not found')
    return { session: existing, template: tpl }
  }

  const snap = await adminFirestore().collection('interviews').doc(interviewId).get()
  if (!snap.exists) throw new HttpError(404, 'Interview not found')
  const data = snap.data() as Record<string, unknown>

  // Assignment check on the VERIFIED email. A mismatch names the signed-in email
  // so the candidate can self-serve ("sign in with the invited address") — the
  // doc ids are unguessable random strings delivered by email, so confirming
  // existence to a signed-in non-assignee is an acceptable trade for not dead-ending
  // every candidate who happens to be signed in with another account.
  const assigned = String(data.candidateEmailLower ?? '').trim().toLowerCase()
  if (!assigned) throw new HttpError(404, 'Interview not found')
  if (assigned !== auth.email) {
    console.warn(`[invite] claim mismatch for ${interviewId}: signed-in ${auth.email || '(no email)'} ≠ assigned candidate`)
    throw new HttpError(403,
      `This invitation was sent to a different email address. You are signed in as ${auth.email || 'an account without an email'} — sign out, then sign in (or create your candidate account) with the email address that received the invitation.`)
  }
  if (data.status === 'completed') throw new HttpError(409, 'This interview has already been completed')

  const now = new Date().toISOString()
  const template = synthTemplate(interviewId, data, now)
  db.templates.set(template.id, template)

  const embedded = Array.isArray(data.questions) ? (data.questions as string[]) : []
  const questions: SessionQuestion[] =
    template.questionSource === 'fixed'
      ? embedded.filter(Boolean).map((text) => ({ id: randomUUID(), text, autoSubmitted: false }))
      : []

  const session: InterviewSession = {
    id: interviewId,
    templateId: template.id,
    recruiterId: (data.recruiterId as string) || undefined,
    track: template.track,
    candidate: {
      name: (data.candidateName as string) || auth.email,
      email: assigned,
    },
    status: 'created',
    questions,
    currentIndex: 0,
    createdAt: now,
    integrityEvents: [],
    tabSwitchCount: 0,
    viaInvite: true,
  }
  db.sessions.set(session.id, session)
  db.scheduleSave()

  // Mark the launch on the Firestore doc (best-effort; never block the candidate).
  adminFirestore().collection('interviews').doc(interviewId)
    .update({ status: 'in_progress', attemptsUsed: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() })
    .catch((err) => console.error('[invite] failed to mark in_progress for', interviewId, err))

  return { session, template }
}

/**
 * Push a completed session's score back to its Firestore `interviews/{id}` doc
 * (unpublished — the recruiter publishes separately). No-op for non-invite
 * sessions. Best-effort; failures are logged, never thrown.
 */
export function syncInviteResult(session: InterviewSession, report: ResultReport): void {
  if (!session.viaInvite) return
  const result = {
    overallScore: report.overallScore,
    summary: report.summary,
    recommendation: report.recommendation ?? 'maybe',
    strengths: report.strengths ?? [],
    improvements: report.improvements ?? [],
    evaluatedBy: 'ai' as const,
    detail: { perQuestion: report.perQuestion, kpiAverages: report.kpiAverages, generatedAt: report.generatedAt },
  }
  adminFirestore().collection('interviews').doc(session.id)
    .update({
      status: 'completed',
      completedAt: FieldValue.serverTimestamp(),
      result,
      resultPublished: false, // recruiter publishes to the candidate separately
      updatedAt: FieldValue.serverTimestamp(),
    })
    .catch((err) => console.error('[invite] failed to sync result for', session.id, err))
}
