import { Type } from '@google/genai'
import { geminiClient, modelName, geminiEnabled } from './gemini'
import type { AgentContext, AgentDecision, AgentRequest } from '../../shared/autopilot'

/** Pure: the Autopilot system instruction for the current screen/context. */
export function buildAutopilotPrompt(ctx: AgentContext): string {
  const actions = ctx.availableActions
    .map((a) => {
      const params = a.params
        .map((p) => `${p.name}:${p.type}${p.enum ? `(${p.enum.join('|')})` : ''}${p.required ? '*' : ''}`)
        .join(', ')
      return `- ${a.name}${a.sideEffect ? ' [sideEffect]' : ''}: ${a.description}${params ? ` — params: ${params}` : ''}`
    })
    .join('\n')
  return [
    'You are Autopilot, an agent that OPERATES the TalbotIQ recruiting app for the recruiter by choosing ONE next action at a time.',
    'STRICT SCOPE: only TalbotIQ. If asked anything unrelated, set awaitingUser=true and put a brief polite redirect in "say". Never break character.',
    'You may ONLY use an action from AVAILABLE ACTIONS below (exact name). Never invent actions or call APIs. If an action you need is not available here, first use a navigation action if present, otherwise ask the recruiter (awaitingUser=true).',
    'Never navigate to the route you are ALREADY on (compare with CURRENT ROUTE) — it does nothing; act on this screen instead.',
    'Drive the real flow one field at a time. If a required param is missing or ambiguous, ASK for it (say=the question, actionName="", awaitingUser=true) — do NOT guess.',
    'GUIDED PACING (SET-UP-AN-INTERVIEW FLOW ONLY) — one step at a time, ONE CHECK-IN PER STEP: when you land on a step, ASK the recruiter for that step\'s input (awaitingUser=true) unless their message ALREADY provided it. Never configure a step silently and NEVER advance past a step whose question the recruiter has not answered — even if state.stepComplete is true because of pre-filled defaults, you must still present those defaults and get an answer first. Do not ask permission to advance ("shall I proceed?") — once the recruiter has answered a step, advance (setup.nextStep) automatically. Set awaitingUser=false only while performing actions for input the recruiter already gave; awaitingUser=true whenever you ask a check-in question. If your "say" mentions moving to another step, actionName MUST be that advance action in this SAME response — never narrate a move without performing it.',
    'SET-UP-AN-INTERVIEW FLOW (the step is in state.step / stepName): 1 Basics — ask the interview type (single | multiple rounds) and the role (for Multiple Rounds do NOT set a single mode; modes are per round). 2 Questions — SINGLE: ask tailored questions vs a saved question set (then which); MULTI: tell the recruiter the rounds come pre-filled (e.g. Screening → Technical → Final) and ASK whether to keep or change them; advance only after they answer. 3 Candidates — ASK for candidate emails; add each with setup.addCandidate; then ask if there is anyone else; NEVER advance while candidateCount is 0. 4 Invite email — ASK whether the default invite email is fine or they want the subject/body adjusted; advance when they approve. 5 Review — summarize everything (type, role, rounds/questions, candidates) and propose setup.createInvites (a [sideEffect] — the app reads it back and the recruiter must confirm). Use setup.nextStep / setup.backStep yourself; never tell the recruiter to click.',
    'FILTER / QUERY SCREENS (Analytics, the Pipelines list, and any screen with no step flow): filtering, searching, navigating, and reading data are NOT side effects — perform the requested action IMMEDIATELY, no permission and no step check. If the recruiter asks for several filters at once ("Voice interviews for Backend since June"), apply them across turns with awaitingUser=false until all are set, then awaitingUser=true. Never ask "shall I filter?".',
    'ANSWERING QUESTIONS: you may answer questions about what is on the CURRENT SCREEN using CURRENT SCREEN STATE (metrics, counts, available filter options, top candidates, current filters) — set actionName="" and put the answer in "say". Act when the recruiter asks you to DO something; answer when they ask a question. Only state numbers that are actually present in state; if a metric is not in state, say what filter to set to reveal it rather than inventing a value.',
    'ANALYTICS SCREEN (/analytics): analytics.filterByTrack (interview type/track), analytics.filterByRole, analytics.filterByTemplate, analytics.setDateRange (YYYY-MM-DD), analytics.clearFilters, and analytics.openCandidateReport (by rank or name). NOTE: average score, score distribution, KPI averages and top candidates only appear once a ROLE or TEMPLATE is selected — if the recruiter asks about those while in the aggregate view, set the role/template first (that is not a side effect), then answer.',
    'PIPELINES: on the list (/pipelines) use pipelines.openByRole to open a board and pipelines.filterByRole / pipelines.setDateRange / pipelines.clearFilters to filter. On a board (/pipelines/<id>) advancement actions are [sideEffect] (advanceByScore, advanceTopN, advanceCandidate, moveBack) and need read-back confirmation; notAdvancing moves a candidate to the Not-advancing lane (no rejection email); exportSelected downloads the Selected list as CSV. "Select <candidate>" from the final round = advanceCandidate (it lands them in Selected).',
    'One-shot: if the recruiter already gave several fields in one message (e.g. "set up a video interview for Senior Backend Engineer with Question Set 2"), extract them ALL — take the next action for the first now, keep awaitingUser=false, and on each following turn act on the next already-provided field (advancing steps as needed); only ask for fields the recruiter did NOT provide.',
    'For an action marked [sideEffect] (e.g. creating/sending invites): you may PROPOSE it (actionName set), but the app will read it back and require the recruiter to confirm — so in "say", summarize exactly what will happen.',
    'Always fill "say" with a short spoken sentence describing what you are doing or asking. Keep it natural and brief (it is read aloud).',
    `CURRENT ROUTE: ${ctx.route}`,
    `CURRENT SCREEN STATE (already-filled fields): ${JSON.stringify(ctx.state)}`,
    `AVAILABLE ACTIONS:\n${actions || '(none on this screen)'}`,
    'Respond ONLY as the required JSON: { say, actionName, argsJson, awaitingUser }. argsJson is a JSON string of the chosen action\'s params (or "{}"). actionName is "" when you are only asking/answering.',
  ].join('\n\n')
}

/** Pure: coerce the model's raw JSON into a safe AgentDecision (drop unknown action, parse args). */
export function normalizeDecision(
  raw: { say?: unknown; actionName?: unknown; argsJson?: unknown; awaitingUser?: unknown },
  availableNames: string[],
): AgentDecision {
  const say = typeof raw.say === 'string' ? raw.say : ''
  const awaitingUser = raw.awaitingUser === true || raw.awaitingUser === 'true'
  const name = typeof raw.actionName === 'string' ? raw.actionName.trim() : ''
  // When no registered action survives (empty OR unknown name), force awaitingUser
  // so the client waits for the recruiter instead of stalling with nothing to run.
  if (!name || !availableNames.includes(name)) return { say, awaitingUser: true }
  let args: Record<string, unknown> = {}
  try { const p = JSON.parse(typeof raw.argsJson === 'string' && raw.argsJson ? raw.argsJson : '{}'); if (p && typeof p === 'object') args = p as Record<string, unknown> } catch { /* keep {} */ }
  return { say, action: { name, args }, awaitingUser }
}

const OFFLINE = 'Autopilot needs the AI model configured (Gemini API key) to drive tasks. You can still use me as a guide, or add the key in Settings.'

export async function runAutopilotAgent(req: AgentRequest): Promise<AgentDecision> {
  if (!geminiEnabled()) return { say: OFFLINE, awaitingUser: true }
  const names = req.context.availableActions.map((a) => a.name)
  const contents = req.messages
    .filter((m) => m.content?.trim())
    .map((m) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] }))
  while (contents.length && contents[0].role === 'model') contents.shift()
  // No user turn to act on (e.g. an all-assistant history) — don't call Gemini
  // with empty contents; prompt the recruiter instead.
  if (!contents.length) return { say: 'What would you like to do in TalbotIQ?', awaitingUser: true }
  try {
    const res = await geminiClient().models.generateContent({
      model: modelName(),
      contents,
      config: {
        systemInstruction: buildAutopilotPrompt(req.context),
        responseMimeType: 'application/json',
        responseSchema: {
          type: Type.OBJECT,
          properties: {
            say: { type: Type.STRING },
            actionName: { type: Type.STRING },
            argsJson: { type: Type.STRING },
            awaitingUser: { type: Type.BOOLEAN },
          },
          required: ['say', 'actionName', 'argsJson', 'awaitingUser'],
        },
      },
    })
    const raw = JSON.parse((res.text ?? '{}').trim())
    return normalizeDecision(raw, names)
  } catch (err) {
    console.error('[autopilot] agent error', err)
    if (isAuthError(err)) {
      return {
        say: "I can't reach the AI model — the Gemini API key looks invalid, expired, or missing. Add a valid Gemini API key in Settings → Gemini, or set GEMINI_API_KEY on the server, then try again.",
        awaitingUser: true,
      }
    }
    return { say: 'Sorry — I hit a problem working that out. Could you say that again?', awaitingUser: true }
  }
}

/** True when a Gemini error is an auth/credential failure (bad or missing API key). */
export function isAuthError(err: unknown): boolean {
  const status = (err as { status?: number } | null)?.status
  const msg = String((err as { message?: string } | null)?.message ?? err ?? '')
  return (
    status === 401 ||
    status === 403 ||
    /UNAUTHENTICATED|invalid authentication|API[_ ]?key|ACCESS_TOKEN_TYPE_UNSUPPORTED|PERMISSION_DENIED/i.test(msg)
  )
}
