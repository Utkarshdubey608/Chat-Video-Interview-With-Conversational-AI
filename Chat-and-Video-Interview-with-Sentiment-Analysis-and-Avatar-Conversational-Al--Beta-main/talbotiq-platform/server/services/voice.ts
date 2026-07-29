import type { Server } from 'node:http'
import { randomUUID } from 'node:crypto'
import { WebSocketServer, WebSocket } from 'ws'
import { Modality, StartSensitivity, EndSensitivity, type Session } from '@google/genai'
import { db } from '../store/db'
import { contextFromUpgrade, isAssignedCandidate, ownsSession } from '../middleware/auth'
import { geminiClient, geminiEnabled, generateQuestions } from './gemini'
import { scoreSession } from './scoring'
import { createVoiceFlow, type VoiceFlow, type FlowAction, type TimerTag } from './voiceFlow'
import { syncInviteResult } from './inviteBridge'
import { stripForSpeech, SPOKEN_STYLE_RULES, VARIED_THANKS_RULE } from '../../shared/speech'
import {
  PERSONA_PRESETS, VOICE_CATALOG, DEFAULT_LIVE_MODEL, DEFAULT_VOICE_CONFIG,
} from '../store/defaults'
import type {
  InterviewSession, InterviewTemplate, Turn, TimeOfDay,
  VoiceClientMessage, VoiceServerMessage,
} from '../../shared/types'

/**
 * Real-time Voice Interview Track. The candidate's mic audio streams to our
 * backend over a WebSocket; we relay to the Gemini Live native-audio API (the
 * key stays server-only) and stream the agent's audio back. The Live model runs
 * the interview naturally (greeting → "are you ready?" → questions → wrap-up)
 * from a strict, backend-authored ordered script; we capture both sides via Live
 * transcription and, on finish, rebuild a canonical transcript and reuse the
 * existing conversational scoring pipeline.
 *
 * RESILIENCE: interview state lives in a per-session runtime that OUTLIVES any
 * single WebSocket. A transient drop (client network blip, proxy reset, or a
 * Gemini Live disconnect) does NOT end + score the interview — it opens a short
 * reconnect grace window during which the candidate's socket can re-attach and
 * seamlessly continue (the Live session is kept alive when possible, or restarted
 * "continue from the next question" if Live itself dropped). Only an explicit End,
 * genuine completion, the hard duration cap, or an expired grace window finalize.
 */

const nowIso = () => new Date().toISOString()
const greetingWord = (tod?: TimeOfDay) =>
  tod === 'morning' ? 'Good morning' : tod === 'afternoon' ? 'Good afternoon' : tod === 'evening' ? 'Good evening' : 'Hello'

const FALLBACK_Q = [
  'Tell me about your background and what drew you to this role.',
  'Walk me through a project you’re proud of and your specific contribution.',
  'Describe a hard problem you solved recently and how you approached it.',
  'How do you handle disagreement with a teammate about a technical decision?',
  'Where do you want to grow over the next couple of years?',
]

/* ─── question plan (reuses the shared adaptive/fixed pipeline) ──────────── */

async function ensureQuestionPlan(session: InterviewSession, template: InterviewTemplate): Promise<void> {
  if (session.questions && session.questions.length > 0) return
  if (template.questionSource === 'fixed') {
    const set = template.fixedQuestionSetId ? db.questionSets.get(template.fixedQuestionSetId) : undefined
    session.questions = (set?.questions ?? []).map((q) => ({
      id: randomUUID(), text: q.text, category: q.category, idealAnswerNotes: q.idealAnswerNotes, autoSubmitted: false,
    }))
  } else {
    const count = template.adaptive?.numberOfQuestions ?? template.timing.numberOfQuestions ?? 5
    let gen: { text: string; category?: string; idealAnswerNotes?: string }[] = []
    try {
      if (geminiEnabled() && session.resumeText)
        gen = await generateQuestions({
          resumeText: session.resumeText, role: template.role, seniority: template.seniority, count,
          // Honor the invite wizard's tailor parameters (style/counts/difficulty/domains).
          style: template.adaptive?.style,
          technicalCount: template.adaptive?.technicalCount,
          nonTechnicalCount: template.adaptive?.nonTechnicalCount,
          difficulty: template.adaptive?.difficulty,
          focusTopics: template.adaptive?.focusTopics,
        })
    } catch (err) {
      console.error('[voice] question generation failed, using fallback:', err)
    }
    if (gen.length === 0) gen = FALLBACK_Q.slice(0, count).map((text) => ({ text, category: 'General' }))
    session.questions = gen.map((g) => ({
      id: randomUUID(), text: g.text, category: g.category, idealAnswerNotes: g.idealAnswerNotes, autoSubmitted: false,
    }))
  }
  session.currentIndex = 0
  db.scheduleSave()
}

/* ─── English-locked transcription helpers ──────────────────────────────── */

/**
 * ASR language hints for the candidate's speech. For English interviews we hint
 * EVERY major English variant so any accent (Indian, British, American,
 * Australian…) is transcribed as English — never auto-detected as another
 * language/script. Non-English templates pass their configured code through.
 */
const ENGLISH_VARIANTS = ['en-IN', 'en-US', 'en-GB', 'en-AU']

/** Old Live models baked into stored templates — always upgraded to the current
 *  default (benchmarked 2026-07: ~2.8s to first audio vs ~740ms on 3.1-live). */
const LEGACY_LIVE_MODELS = new Set(['gemini-2.5-flash-native-audio-preview-09-2025'])
export function transcriptionLanguages(lang: string): string[] {
  return lang.trim().toLowerCase().startsWith('en') ? ENGLISH_VARIANTS : [lang]
}

/**
 * Bias the Live ASR toward this interview's own vocabulary — the role plus
 * acronyms (SQL, OOP), mixed-case/dotted tech terms (PostgreSQL, Node.js, C++),
 * and proper-noun phrases from the question plan — so accented technical terms
 * resolve to the right English words instead of drifting.
 */
export function adaptationPhrases(role: string, questions: string[]): string[] {
  const out = new Set<string>()
  if (role.trim()) out.add(role.trim().slice(0, 60))
  const text = questions.join('\n')
  // Acronyms / mixed-case / digit-, +/#- or dot-bearing tokens.
  for (const m of text.matchAll(/[A-Za-z][A-Za-z0-9+#.]*[A-Za-z0-9+#]/g)) {
    const w = m[0]
    if (w.length < 2 || w.length > 40) continue
    if (/^[A-Z]{2,}[0-9+#]*$/.test(w) || /[a-z][A-Z]/.test(w) || /[0-9+#]/.test(w) || /\w\.\w/.test(w)) out.add(w)
  }
  // Consecutive-capitalized proper-noun phrases: "Employer Worker Registration System".
  for (const m of text.matchAll(/[A-Z][a-z0-9]+(?:[ -][A-Z][a-z0-9]+)+/g)) out.add(m[0].slice(0, 60))
  return [...out].slice(0, 32)
}

/* ─── system instruction: persona + strict on-interview guardrails + plan ── */

function buildSystemInstruction(
  session: InterviewSession, template: InterviewTemplate, questions: string[], tod?: TimeOfDay,
): string {
  const persona = PERSONA_PRESETS.find((p) => p.id === template.voice?.personaId) ?? PERSONA_PRESETS[0]
  const name = session.candidate?.name && session.candidate.name !== 'Candidate' ? session.candidate.name : ''
  const role = `${template.seniority ? template.seniority + ' ' : ''}${template.role || 'this'}`
  // Strip formatting from the question text — generated questions can carry
  // markdown/backticks, and "asterisk asterisk" must never be spoken.
  const list = questions.map((q, i) => `${i + 1}. ${stripForSpeech(q)}`).join('\n')
  const lang = template.voice?.language || 'en-US'
  const languageRule = lang.trim().toLowerCase().startsWith('en')
    ? `LANGUAGE: this interview is conducted ENTIRELY IN ENGLISH. Speak only English, and treat EVERYTHING the candidate says as English — candidates may have any accent (Indian, British, American, or other), but their words are English. Never switch to, mix in, or acknowledge any other language or script under any circumstances. If the candidate genuinely answers in another language, warmly ask them to continue in English.`
    : `LANGUAGE: this interview is conducted ENTIRELY in the language with code "${lang}". Speak only that language and expect the candidate's answers in it; never switch language or script mid-interview.`
  return [
    persona.stylePrompt,
    languageRule,
    `You are conducting a LIVE SPOKEN interview for a ${role} role. ${SPOKEN_STYLE_RULES} Keep every question SHORT: one or two spoken sentences.`,
    `FLOW:
1. Open with a brief "${greetingWord(tod)}" greeting, warmly welcome the candidate${name ? ` by name (${name})` : ''}, add one short line on how this will go, then ask if they're ready to begin, and stop and wait.
2. If they clearly say yes, begin. If they're unsure or not ready, reassure them in one short line and ask again; only start on a clear yes.
3. Ask the questions in the list below IN ORDER, one at a time, phrased naturally and briefly. You MUST ask every single one before finishing. ${VARIED_THANKS_RULE} Do NOT wrap up or say goodbye until you have asked and heard an answer to the FINAL question in the list.
4. Only AFTER the last question is answered, give a warm CLOSING: thank them sincerely, let them know that's everything and they're all done and free to leave the interview now, that our HR team will be in touch about the next steps, and that they're welcome to reach out to us anytime. Then stop and wait for them to respond. When they reply (e.g. "thank you"), you may say a brief goodbye.`,
    `THE QUESTIONS, IN ORDER — ask every one, do not add, skip, or reorder, and NEVER say their numbers aloud:\n${list}`,
    `STRICT RULES: Ask ONLY these questions. Do NOT introduce unrelated topics, trivia, or spontaneous tangents. No small talk beyond the opening greeting. If the candidate goes off-topic, rambles, or asks YOU questions, briefly and politely acknowledge, then steer straight back to the interview and the next planned question; do not get pulled into another conversation. Never announce question numbers. One question at a time. Cover ALL the questions, then close; never add extra questions of your own and never finish early.`,
    `If you ever receive a bracketed [DIRECTOR: ...] note, follow its instruction silently and never read it aloud.`,
  ].join('\n\n')
}

/* ─── per-session runtime (outlives any single WebSocket) ────────────────── */

const scored = new Set<string>()

/** Keep a dropped interview (Live session + progress) alive this long, waiting
 *  for the candidate to reconnect, before giving up and finalizing as interrupted. */
const RECONNECT_GRACE_MS = 60_000
/** WebSocket keepalive — ping the browser so idle proxies don't sever a long
 *  call, and detect a genuinely dead socket (missed pong) deliberately. */
const HEARTBEAT_MS = 25_000
/** Cap consecutive Gemini Live restarts (with no turn of progress between them)
 *  so a persistently-failing Live session ends the interview instead of looping. */
const MAX_LIVE_RESTARTS = 4

type Timer = ReturnType<typeof setTimeout>

interface VoiceRuntime {
  sessionId: string
  session: InterviewSession
  template: InterviewTemplate
  ws: WebSocket                    // CURRENT client socket (swapped on reconnect)
  live?: Session
  flow?: VoiceFlow
  questions: string[]
  idleMs: number
  candidateSilenceMs: number
  // startup coordination
  planReady: boolean
  pendingReady: boolean
  pendingReadyTod?: TimeOfDay
  started: boolean
  flowStarted: boolean
  starting: boolean                // a startLive() call is in flight
  finalized: boolean
  muted: boolean
  liveRestarts: number             // consecutive Live restarts without progress (loop guard)
  // live transcription buffers for the CURRENT turn
  greetingText: string
  pendingInterviewer: string
  pendingCandidate: string
  lastTranscriptAt: number
  turnAudioLogged: boolean
  // timers
  timers: Partial<Record<TimerTag, Timer>>
  graceTimer?: Timer
  heartbeat?: ReturnType<typeof setInterval>
  pongOk: boolean
}

const runtimes = new Map<string, VoiceRuntime>()

// Default watchdog windows (mirrors createVoiceFlow's defaults so the driver can
// re-arm the right timer on reconnect without reaching into the flow closure).
const IDLE_MS = 180_000
const CANDIDATE_SILENCE_MS = 15_000

function sendJson(ws: WebSocket, msg: VoiceServerMessage) {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg))
}

function clearTimer(rt: VoiceRuntime, tag: TimerTag) {
  if (rt.timers[tag]) { clearTimeout(rt.timers[tag]!); delete rt.timers[tag] }
}
function clearAllTimers(rt: VoiceRuntime) {
  (Object.keys(rt.timers) as TimerTag[]).forEach((t) => clearTimer(rt, t))
}
function stopHeartbeat(rt: VoiceRuntime) {
  if (rt.heartbeat) { clearInterval(rt.heartbeat); rt.heartbeat = undefined }
}
function clearGrace(rt: VoiceRuntime) {
  if (rt.graceTimer) { clearTimeout(rt.graceTimer); rt.graceTimer = undefined }
}

/** Bucket any in-progress (not-yet-turn-complete) candidate speech into the flow
 *  BEFORE a terminal call, so a partial final answer isn't lost on End / timeout /
 *  grace-expiry. Must run before the flow finalizes. */
function flushCandidate(rt: VoiceRuntime) {
  if (rt.pendingCandidate.trim() && rt.flow && !rt.flow.finalized) {
    const t = rt.pendingCandidate.trim()
    rt.pendingCandidate = ''
    runActions(rt, rt.flow.onCandidateTurn(t))
  }
}

// Execute the flow controller's decisions (the only place with I/O + timers).
function runActions(rt: VoiceRuntime, actions: FlowAction[]) {
  for (const a of actions) {
    if (a.kind === 'nudge') {
      try { rt.live?.sendClientContent({ turns: `[DIRECTOR: ${a.text}]`, turnComplete: true }) } catch { /* noop */ }
    } else if (a.kind === 'armTimer') {
      clearTimer(rt, a.tag)
      rt.timers[a.tag] = setTimeout(() => {
        if (rt.finalized || !rt.flow) return
        flushCandidate(rt)                     // salvage a partial answer before a timeout end
        if (!rt.finalized && rt.flow) runActions(rt, rt.flow.onTimer(a.tag))
      }, a.ms)
    } else if (a.kind === 'clearTimer') {
      clearTimer(rt, a.tag)
    } else if (a.kind === 'finalize') {
      finalize(rt, a.reason, a.graceful)
    }
  }
}

function finalize(rt: VoiceRuntime, reason: string, graceful: boolean) {
  if (rt.finalized) return
  rt.finalized = true
  clearAllTimers(rt)
  clearGrace(rt)
  stopHeartbeat(rt)
  rt.pendingCandidate = ''

  const { session, template, questions } = rt
  // Build the scored transcript from the flow's per-question answer buckets
  // (aligned even when VAD split a spoken answer across turns).
  const answers = rt.flow ? rt.flow.answers : questions.map(() => '')
  const transcript: Turn[] = []
  if (rt.greetingText.trim()) transcript.push({ id: randomUUID(), role: 'interviewer', content: rt.greetingText.trim(), turnType: 'greeting', createdAt: nowIso() })
  let answered = 0
  for (let i = 0; i < questions.length; i++) {
    transcript.push({ id: randomUUID(), role: 'interviewer', content: questions[i], turnType: 'question', questionIndex: i, createdAt: nowIso() })
    const a = (answers[i] ?? '').trim()
    if (a) answered++
    transcript.push({ id: randomUUID(), role: 'candidate', content: a, questionIndex: i, createdAt: nowIso() })
  }
  session.transcript = transcript
  session.mode = 'conversational'
  session.plannedQuestionCount = questions.length
  session.currentIndex = answered
  if (session.status === 'in_progress' || session.status === 'created' || session.status === 'system_check') {
    session.status = 'completed'
    session.completedAt = nowIso()
  }
  db.scheduleSave()

  // Reuse the existing conversational scoring pipeline (fire-and-forget).
  if (!db.reports.has(session.id) && !scored.has(session.id)) {
    scored.add(session.id)
    scoreSession(session, template)
      .then((report) => { db.reports.set(session.id, report); db.scheduleSave(); syncInviteResult(session, report) })
      .catch((err) => console.error('[voice] scoring failed for', session.id, err))
      .finally(() => scored.delete(session.id))
  }
  sendJson(rt.ws, { type: 'ended', reason, graceful })
  try { rt.live?.close() } catch { /* noop */ }
  runtimes.delete(rt.sessionId)
}

/**
 * An unexpected transport drop (client socket closed, or Gemini Live closed).
 * Do NOT finalize: pause the conversation watchdogs and open a grace window in
 * which the candidate can reconnect and continue. If nobody reconnects in time,
 * salvage the last partial answer and finalize as interrupted.
 */
function handleDrop(rt: VoiceRuntime, reason: string) {
  if (rt.finalized || rt.graceTimer) return
  clearTimer(rt, 'idle')
  clearTimer(rt, 'candidateSilence')   // maxDuration stays: it is a hard wall-clock cap
  stopHeartbeat(rt)
  console.warn(`[voice] connection dropped (${reason}) for ${rt.sessionId}; holding ${RECONNECT_GRACE_MS / 1000}s for reconnect`)
  rt.graceTimer = setTimeout(() => {
    rt.graceTimer = undefined
    if (rt.finalized) return
    flushCandidate(rt)
    if (!rt.finalized) {
      if (rt.flow) runActions(rt, rt.flow.onEnd(reason))
      else finalize(rt, reason, false)
    }
  }, RECONNECT_GRACE_MS)
}

/** Wire (or re-wire) a client socket to a runtime: message/close/error + heartbeat. */
function attachWs(rt: VoiceRuntime, ws: WebSocket) {
  rt.ws = ws

  ws.on('message', (raw, isBinary) => {
    if (rt.ws !== ws) return
    // BINARY frame = raw mic PCM16 (16 kHz). Base64-encode server-side (cheap,
    // off the client's main thread) and forward straight to Gemini Live.
    if (isBinary) {
      if (!rt.muted && rt.live) rt.live.sendRealtimeInput({ audio: { data: (raw as Buffer).toString('base64'), mimeType: 'audio/pcm;rate=16000' } })
      return
    }
    let msg: VoiceClientMessage
    try { msg = JSON.parse(raw.toString()) } catch { return }
    if (msg.type === 'ready') {
      rt.pendingReadyTod = msg.timeOfDay
      if (rt.started) return                 // resume: Live is already running (or being restarted)
      if (rt.planReady) void startLive(rt, msg.timeOfDay)
      else rt.pendingReady = true
    }
    else if (msg.type === 'mute') { rt.muted = msg.muted }
    else if (msg.type === 'end') {
      // Candidate-initiated end: finalize immediately (no grace).
      flushCandidate(rt)
      if (!rt.finalized) { if (rt.flow) runActions(rt, rt.flow.onEnd('ended')); else finalize(rt, 'ended', false) }
      try { ws.close() } catch { /* noop */ }
    }
  })

  ws.on('close', () => {
    if (rt.ws !== ws) return                  // a socket we already replaced — ignore
    if (rt.finalized) return
    if (!rt.started) {                        // dropped before the interview began — nothing to hold
      rt.finalized = true                     // tombstone: a deferred startLive() (plan still generating) must bail
      stopHeartbeat(rt); clearAllTimers(rt); clearGrace(rt)
      try { rt.live?.close() } catch { /* noop */ }
      runtimes.delete(rt.sessionId)
      return
    }
    handleDrop(rt, 'closed')                  // keep Live alive; wait for reconnect
  })
  ws.on('error', () => { /* 'close' will follow; handled there */ })

  // Heartbeat: ping the browser; a missed pong means the socket is dead.
  ws.on('pong', () => { rt.pongOk = true })
  stopHeartbeat(rt)
  rt.pongOk = true
  rt.heartbeat = setInterval(() => {
    if (rt.ws !== ws) { stopHeartbeat(rt); return }
    if (ws.readyState !== WebSocket.OPEN) return
    if (!rt.pongOk) { try { ws.terminate() } catch { /* noop */ } ; return }
    rt.pongOk = false
    try { ws.ping() } catch { /* noop */ }
  }, HEARTBEAT_MS)
}

/** Re-attach a reconnecting client to its still-alive interview. */
function resume(rt: VoiceRuntime, ws: WebSocket) {
  clearGrace(rt)
  // Drop any previous socket that is somehow still open (takeover / double tab).
  try { if (rt.ws !== ws && rt.ws.readyState === WebSocket.OPEN) rt.ws.close() } catch { /* noop */ }
  attachWs(rt, ws)
  sendJson(ws, { type: 'state', phase: 'connecting' })
  // Re-arm the conversation watchdog now that the candidate is back.
  if (rt.flow && !rt.finalized) {
    const closing = rt.flow.phase === 'closing'
    runActions(rt, [{ kind: 'armTimer', tag: closing ? 'candidateSilence' : 'idle', ms: closing ? rt.candidateSilenceMs : rt.idleMs }])
  }
  // If Live survived the drop, playback simply resumes on the new socket. If Live
  // itself died, restart it continuing from the next unanswered question.
  if (rt.started && !rt.live && !rt.starting) void startLive(rt, rt.pendingReadyTod, true)
  else sendJson(ws, { type: 'state', phase: 'listening' })
}

async function startLive(rt: VoiceRuntime, tod?: TimeOfDay, isResume = false) {
  if (rt.finalized || runtimes.get(rt.sessionId) !== rt) return // torn down (e.g. dropped while the plan was generating)
  if (rt.live || rt.starting) return
  if (rt.questions.length === 0) { sendJson(rt.ws, { type: 'error', message: 'No questions available for this interview' }); return }
  rt.starting = true
  if (!rt.started) {
    rt.started = true
    rt.session.status = 'in_progress'
    rt.session.startedAt = nowIso()
    db.scheduleSave()
  }
  if (!rt.flow) rt.flow = createVoiceFlow(rt.questions, { idleMs: rt.idleMs, candidateSilenceMs: rt.candidateSilenceMs })

  const { session, template } = rt
  const vcfg = template.voice ?? DEFAULT_VOICE_CONFIG
  const persona = PERSONA_PRESETS.find((p) => p.id === vcfg.personaId) ?? PERSONA_PRESETS[0]
  const voiceName = VOICE_CATALOG.find((v) => v.id === vcfg.voiceId)?.id ?? persona.defaultVoiceId

  try {
    const interviewLang = vcfg.language || 'en-US'
    const asrLanguages = transcriptionLanguages(interviewLang)
    const asrPhrases = adaptationPhrases(template.role, rt.questions)
    const liveModel =
      vcfg.model && !LEGACY_LIVE_MODELS.has(vcfg.model) ? vcfg.model : DEFAULT_LIVE_MODEL

    const sysBase = buildSystemInstruction(session, template, rt.questions, tod)
    const systemInstruction = isResume
      ? `${sysBase}\n\nRESUME: The call was briefly interrupted by a connection issue and has just reconnected. Do NOT greet again, do NOT restart, and do NOT repeat any question you already asked. Simply continue from where you left off and ask the next planned question you had not yet fully covered.`
      : sysBase

    const liveParams = (full: boolean) => ({
      model: liveModel,
      config: {
        responseModalities: [Modality.AUDIO],
        speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName } } },
        systemInstruction,
        inputAudioTranscription: full
          ? {
              languageHints: { languageCodes: asrLanguages },
              ...(asrPhrases.length ? { adaptationPhrases: asrPhrases } : {}),
            }
          : {},
        outputAudioTranscription: {},
        ...(full ? { thinkingConfig: { thinkingBudget: 0 } } : {}),
        realtimeInputConfig: {
          automaticActivityDetection: {
            startOfSpeechSensitivity: StartSensitivity.START_SENSITIVITY_HIGH,
            endOfSpeechSensitivity: EndSensitivity.END_SENSITIVITY_HIGH,
            prefixPaddingMs: 20,
            silenceDurationMs: 500,
          },
        },
      },
      callbacks: {
        onopen: () => {
          if (rt.flowStarted) return // never double-start the flow (fresh vs. resume)
          rt.flowStarted = true
          sendJson(rt.ws, { type: 'state', phase: 'greeting' })
          if (rt.flow) runActions(rt, rt.flow.start())
        },
        onmessage: (m: any) => {
          const sc = m?.serverContent
          // Agent audio out → relay to the client as raw BINARY PCM (24 kHz).
          let spoke = false
          for (const part of sc?.modelTurn?.parts ?? []) {
            if (part?.inlineData?.data && rt.ws.readyState === WebSocket.OPEN) {
              rt.ws.send(Buffer.from(part.inlineData.data, 'base64'))
              spoke = true
            }
          }
          if (spoke) {
            sendJson(rt.ws, { type: 'state', phase: 'speaking' })
            if (!rt.turnAudioLogged && rt.lastTranscriptAt) {
              rt.turnAudioLogged = true
              console.log(`[voice:lat] agent audio ${Date.now() - rt.lastTranscriptAt}ms after candidate's last transcribed words`)
            }
          }
          if (sc?.outputTranscription?.text) {
            rt.pendingInterviewer += sc.outputTranscription.text
            sendJson(rt.ws, { type: 'caption', role: 'interviewer', text: rt.pendingInterviewer, final: false })
          }
          if (sc?.inputTranscription?.text) {
            rt.pendingCandidate += sc.inputTranscription.text
            rt.lastTranscriptAt = Date.now()
            // Candidate is actively speaking → the call is NOT idle. Reset the watchdog
            // so a long or thoughtful answer is never cut off mid-sentence.
            if (rt.flow) runActions(rt, rt.flow.onCandidateActivity())
            sendJson(rt.ws, { type: 'state', phase: 'listening' })
            sendJson(rt.ws, { type: 'caption', role: 'candidate', text: rt.pendingCandidate, final: false })
          }
          // Barge-in: the candidate interrupted — flush client playback.
          if (sc?.interrupted) {
            rt.pendingInterviewer = ''
            rt.flow?.onInterrupted()
            if (vcfg.allowBargeIn) sendJson(rt.ws, { type: 'interrupted' })
          }
          // Turn boundary: candidate answer (if any) precedes the agent's reply.
          if (sc?.turnComplete) {
            rt.turnAudioLogged = false
            rt.liveRestarts = 0 // a completed turn = real progress; reset the restart guard
            if (rt.pendingCandidate.trim()) {
              const text = rt.pendingCandidate.trim()
              rt.pendingCandidate = ''
              sendJson(rt.ws, { type: 'caption', role: 'candidate', text, final: true })
              if (rt.flow) runActions(rt, rt.flow.onCandidateTurn(text))
            }
            if (!rt.finalized && rt.pendingInterviewer.trim()) {
              const text = rt.pendingInterviewer.trim()
              rt.pendingInterviewer = ''
              if (!rt.greetingText) rt.greetingText = text // first interviewer turn is the greeting
              sendJson(rt.ws, { type: 'caption', role: 'interviewer', text, final: true })
              if (rt.flow) runActions(rt, rt.flow.onInterviewerTurn(text))
            }
            if (!rt.finalized) sendJson(rt.ws, { type: 'state', phase: 'listening' })
          }
        },
        onerror: (e: any) => sendJson(rt.ws, { type: 'error', message: e?.message || 'Voice engine error' }),
        onclose: () => {
          rt.live = undefined
          if (rt.finalized || !rt.started) return
          if (rt.ws.readyState === WebSocket.OPEN) {
            // Client is still here but Gemini Live dropped. Restart Live in place and
            // continue from the next question — bounded so a failing session can't loop.
            if (rt.liveRestarts >= MAX_LIVE_RESTARTS) {
              flushCandidate(rt)
              if (!rt.finalized) { if (rt.flow) runActions(rt, rt.flow.onEnd('live-unstable')); else finalize(rt, 'live-unstable', false) }
              return
            }
            rt.liveRestarts++
            console.warn(`[voice] Live closed mid-interview (${rt.sessionId}); restart ${rt.liveRestarts}/${MAX_LIVE_RESTARTS}`)
            if (!rt.starting) void startLive(rt, rt.pendingReadyTod, true)
          } else {
            // Both client and Live are gone — hold for the client to reconnect.
            handleDrop(rt, 'live-closed')
          }
        },
      },
    })

    try {
      rt.live = await geminiClient().live.connect(liveParams(true))
    } catch (err) {
      // Some Live models reject language hints / thinkingConfig — retry compatible.
      console.warn('[voice] live.connect with full config failed; retrying compatible:', err)
      rt.live = await geminiClient().live.connect(liveParams(false))
    }

    // The interview may have been ended/torn down while we awaited the connect —
    // don't leave an orphaned Live session hanging off a dead runtime.
    if (rt.finalized || runtimes.get(rt.sessionId) !== rt) {
      try { rt.live?.close() } catch { /* noop */ }
      rt.live = undefined
      return
    }

    // Kick off the appropriate opening turn (native audio only speaks when prompted).
    rt.live.sendClientContent({
      turns: isResume
        ? 'We are reconnected. Continue the interview now: ask the next question you had not yet covered. Do not greet again.'
        : 'Begin the interview now: greet me and ask if I am ready to begin.',
      turnComplete: true,
    })
  } catch (err: any) {
    sendJson(rt.ws, { type: 'error', message: err?.message || 'Could not start the voice interview' })
    if (!rt.flowStarted) rt.started = false // allow a fresh retry only if we never really began
  } finally {
    rt.starting = false
  }
}

async function handleConnection(ws: WebSocket, sessionId: string) {
  // Reconnect to an interview that's still alive (dropped socket within grace,
  // or a second tab taking over) — seamlessly resume rather than start anew.
  const existing = runtimes.get(sessionId)
  if (existing && !existing.finalized) { resume(existing, ws); return }

  const session0 = db.sessions.get(sessionId)
  const template0 = session0 ? db.templates.get(session0.templateId) : undefined
  if (!session0 || !template0) { sendJson(ws, { type: 'error', message: 'Session not found' }); ws.close(); return }
  const session: InterviewSession = session0
  const template: InterviewTemplate = template0
  if (session.track !== 'voice') { sendJson(ws, { type: 'error', message: 'Not a voice session' }); ws.close(); return }
  if (!geminiEnabled()) { sendJson(ws, { type: 'error', message: 'Voice interviews require a Gemini API key on the server' }); ws.close(); return }
  if (template.questionSource === 'adaptive' && !session.resumeText) {
    sendJson(ws, { type: 'error', message: 'A résumé is required before starting' }); ws.close(); return
  }
  // A completed interview never reopens.
  if (session.status === 'completed' || session.status === 'expired') {
    sendJson(ws, { type: 'ended', reason: 'already-completed', graceful: true }); ws.close(); return
  }

  const rt: VoiceRuntime = {
    sessionId, session, template, ws,
    questions: [], idleMs: IDLE_MS, candidateSilenceMs: CANDIDATE_SILENCE_MS,
    planReady: false, pendingReady: false, started: false, flowStarted: false, starting: false,
    finalized: false, muted: false, liveRestarts: 0,
    greetingText: '', pendingInterviewer: '', pendingCandidate: '', lastTranscriptAt: 0, turnAudioLogged: false,
    timers: {}, pongOk: true,
  }
  runtimes.set(sessionId, rt)
  attachWs(rt, ws)
  sendJson(ws, { type: 'state', phase: 'connecting' })

  // Build the ordered question plan (async), then start if the client is ready.
  void (async () => {
    try {
      await ensureQuestionPlan(session, template)
      rt.questions = session.questions.map((q) => q.text)
      if (rt.questions.length === 0) { sendJson(rt.ws, { type: 'error', message: 'No questions available for this interview' }); ws.close(); return }
      rt.planReady = true
      if (rt.pendingReady) void startLive(rt, rt.pendingReadyTod)
    } catch (err) {
      console.error('[voice] failed to prepare question plan:', err)
      sendJson(rt.ws, { type: 'error', message: 'Could not prepare the interview' })
      ws.close()
    }
  })()
}

/** Mount the voice WebSocket relay on the existing HTTP server. The handshake is
 *  authenticated (token in the query string) and authorized to the assigned
 *  candidate or the owning recruiter before the socket is accepted. */
export function attachVoiceWebSocket(server: Server) {
  const wss = new WebSocketServer({ noServer: true })
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url ?? '', 'http://localhost')
    const match = url.pathname.match(/^\/api\/voice\/([^/]+)$/)
    if (!match) return // let other upgrade handlers (if any) deal with it
    const sessionId = decodeURIComponent(match[1])
    void (async () => {
      const auth = await contextFromUpgrade(req)
      const session = auth ? db.sessions.get(sessionId) : undefined
      if (!auth || !session || !(isAssignedCandidate(session, auth) || ownsSession(session, auth))) {
        try { socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n') } catch { /* noop */ }
        socket.destroy()
        return
      }
      wss.handleUpgrade(req, socket, head, (ws) => { void handleConnection(ws, sessionId) })
    })()
  })
}
