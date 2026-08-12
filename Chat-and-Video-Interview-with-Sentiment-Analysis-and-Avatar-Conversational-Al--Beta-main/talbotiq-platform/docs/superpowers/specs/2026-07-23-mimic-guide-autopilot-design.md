# Mimic Guide "Autopilot" — Design Spec

**Date:** 2026-07-23
**Branch:** `feat/avatar-screening-migration`
**Status:** Draft — awaiting user review

## Problem / goal

Today the **Mimic Guide** (`src/features/guide/MimicGuide.tsx`, mounted globally in `App.tsx`)
is a read-only assistant: it answers "how do I…" questions (Gemini `gemini-2.5-flash`, no
tools), speaks answers (`speakSmart`), takes dictation (browser Web Speech), and renders
navigation as markdown links the user clicks. It cannot *do* anything.

This feature upgrades it into **Autopilot** — a JARVIS-style agent that OPERATES TalbotIQ by
talking with the recruiter (voice or typed). The recruiter says "set up an interview";
Autopilot drives the real flow step by step — asking one field at a time ("which mode?",
"what role?"), acting on the answer (selecting the mode card, filling the role, advancing the
wizard step), and confirming before anything that sends. It acts ONLY through a whitelisted
action registry wired to the same handlers the UI buttons already call. Scope: TalbotIQ only.
Additive; frozen modules untouched; keys server-side.

## Scope & principles

- **Whitelist-only.** Autopilot invokes ONLY registered actions. The LLM maps conversation →
  (action name + args); a deterministic executor validates and runs the registered handler.
  It can never invent UI, call raw APIs freely, or exceed the user's own permissions.
- **Additive.** No rewrite of `InviteWizard` or any frozen module (auth, invite-link/claim,
  sessions, Firestore field names). Screens become drivable by *exposing* named commands via
  a hook; their local `useState` stays local. Autopilot OFF ⇒ the guide behaves exactly as today.
- **Reuse.** Gemini client + keys (server-side), the multilingual voice stack
  (`startSpeechRecognition`, `speakSmart`, `src/lib/languages.ts`, `shared/speech.ts`), the
  existing `/api/help/*` router + auth, and the guide's scoping/persona.
- **Confirm every side-effect.** Create-invites / send / advance / delete / bulk require an
  explicit read-back confirmation (voice "yes" or click). Nothing sends silently.
- **RBAC inherent.** Actions call the screen's own handlers, which exist only for the
  authorized user on the authorized route; server endpoints stay auth-gated. Autopilot can do
  nothing the logged-in user couldn't do manually. It cannot bypass auth/invite-link logic.
- **TalbotIQ-scoped.** Out-of-scope requests → polite redirect (reuse the guide's scope rule).

## Verified context (facts this design relies on)

- **Guide client:** `src/features/guide/MimicGuide.tsx` — a single global instance (App.tsx,
  sibling of `<Routes>`, survives navigation, recruiter-only render). Local `useState` +
  localStorage. Sends `POST /api/help/chat` → `{ reply }` markdown. Mic = `toggleMic()` →
  `startSpeechRecognition(locale, onResult…)` (`src/lib/speechRecognition.ts`, browser Web
  Speech, single-utterance, appends to `draft`, never auto-sends). TTS = `toggleSpeak` /
  auto-speak → `speakSmart(text, voiceLang)` (`src/lib/guideSpeech.ts`). Voice-language
  selector = `VoiceLangSelect` over `LANGUAGES` (`src/lib/languages.ts`, 55 langs) → `voiceLang`.
- **Guide server:** `runMimicGuide(messages, role)` (`server/services/mimicGuide.ts`) →
  `geminiClient().models.generateContent({ model: modelName(), contents, config:{
  systemInstruction: buildMimicGuidePrompt(role) }})`. **No `tools`/`functionDeclarations`.**
  Falls back to canned FAQ if no Gemini key. Prompt in `mimicGuidePrompt.ts` (strict TalbotIQ
  scope, multilingual, navigation-as-markdown).
- **Routes:** `server/routes/help.ts`, mounted `app.use('/api/help', authenticate, helpRouter)`
  (`server/index.ts`). `POST /chat` ({messages}) → {reply}; `POST /tts` ({text,lang}) → ndjson
  PCM. Both require a Firebase bearer token (global fetch interceptor attaches it).
- **Voice reuse:** `startSpeechRecognition(lang, onResult, onError, onEnd): ()=>void` +
  `isSpeechRecognitionSupported()`; `speakSmart(text, voiceLang, onEnd?, onUnavailable?):
  ()=>void`; `SPEECH_LOCALES`/`detectSpeechLocale` (`shared/speech.ts`); `LANGUAGES`
  (`src/lib/languages.ts`). All decoupled, take `(text|lang)` args — reusable as-is.
- **State crux:** the ONLY zustand store is `src/store/useAppStore.ts` (legacy interview
  runtime — NOT wizard/filters). `InviteWizard` state (`setupType, mode, role, source, cfg,
  selectedSetId, step, candidates, rounds, emailDraft`) is all local `useState`, not externally
  reachable. Navigation is hook-only (`useNavigate()` inside components); no singleton history.
  No generic command bus. **Precedent:** `IntroFaceSync.tsx` exposes handlers via a `window`
  event / `window.mimicSyncFaces()` while mounted — proves the "component registers handlers
  while mounted" pattern is idiomatic here.

## Resolved decisions

| Fork | Decision |
|---|---|
| v1 scope | Build the full architecture; wire ONLY the guided **Set-up-an-interview → Create invites** flow end to end. Widen the registry (templates, question sets, results, pipelines, CSV, nav) post-v1. |
| Drive-the-UI architecture | **Action registry + per-screen `useAutopilotActions` hook** (components expose their real setters as named actions while mounted). NOT lifting wizard state into a store (too invasive to the just-built wizard). |
| Agent brain / loop | **Server `POST /api/help/agent`** → Gemini **structured JSON** `{ say, action?, awaitingUser }` (constrained via `responseSchema`). NOT native function-calling threading (structured output gives `say`+`action`+`awaitingUser` together — a cleaner control signal for a one-action-at-a-time loop). |
| Voice input (v1) | Reuse the browser Web Speech mic, **push-to-talk per step**; typed input is an equal path. Server STT + continuous listening deferred. |
| Param typing | Each action carries a serializable **`ParamSpec[]`** (name/type/enum/required/description) used both to prompt Gemini and to validate args client-side (self-contained; no zod-to-json-schema dep). |

## Architecture

### Data model (new shared types — `shared/autopilot.ts`)

```ts
export type ParamType = 'string' | 'number' | 'boolean' | 'enum'
export interface ParamSpec {
  name: string
  type: ParamType
  enum?: string[]
  required?: boolean
  description?: string
}
/** Serializable descriptor the LLM sees. Handlers live only client-side. */
export interface ActionDescriptor {
  name: string                 // unique, e.g. 'setup.selectMode'
  description: string
  screen: string               // 'global' | 'setup' | …
  sideEffect: boolean          // true ⇒ read-back confirm required
  params: ParamSpec[]
}
export interface AgentContext {
  route: string                // current pathname
  availableActions: ActionDescriptor[]
  state: Record<string, unknown>   // getState() snapshot of the active screen
}
export interface AgentRequest {
  messages: { role: 'user' | 'assistant'; content: string }[]
  context: AgentContext
}
export interface AgentDecision {
  say: string                  // spoken/shown to the recruiter
  action?: { name: string; args: Record<string, unknown> }
  awaitingUser: boolean        // true ⇒ stop looping and wait for the recruiter
}
```

### Client registry + `useAutopilotActions` hook

A small global registry (a new zustand store `src/features/guide/autopilot/registry.ts` — the
one place other than `useAppStore` we add a store; scoped to Autopilot only). A screen registers
its actions while mounted:

```ts
useAutopilotActions('setup', {
  selectMode: { description: 'Select the interview mode', sideEffect: false,
    params: [{ name: 'mode', type: 'enum', enum: MODE_VALUES, required: true }],
    run: ({ mode }) => setMode(mode) },
  setRole: { description: 'Set the candidate role', sideEffect: false,
    params: [{ name: 'role', type: 'string', required: true }], run: ({ role }) => setRole(role) },
  nextStep: { description: 'Advance to the next wizard step', sideEffect: false, params: [],
    run: () => guardedNext() },
  createInvites: { description: 'Create + send the invites', sideEffect: true, params: [],
    run: () => submit() },
  // …
}, { getState: () => ({ step, setupType, mode, role, source, selectedSetId, candidates }) })
```

The hook: on mount, registers each `{ descriptor, run }` under `screen.name`; on unmount,
unregisters; publishes `getState`. `run` receives validated args. Local `useState` is untouched.

The Autopilot panel lives inside `<BrowserRouter>` (like `MimicGuide` today), so it holds its
own `useNavigate`/`useLocation` — it registers `global.navigate`
(`{ params:[{name:'path',type:'string'}], run: ({path}) => navigate(path) }`) and reports the
current `route` itself. So Autopilot can `navigate('/sessions/new')`, which mounts the wizard,
which registers the setup actions. No separate top-level registrant component is needed.

### Server agent endpoint — `POST /api/help/agent`

`server/routes/help.ts` gains `/agent` (same `authenticate` mount). Body = `AgentRequest`. It
calls `runAutopilotAgent(req)` in a new `server/services/autopilotAgent.ts`:
- Builds a system prompt (Autopilot persona: operate TalbotIQ only; drive one field at a time;
  ask for a missing required param rather than guess; propose the side-effect action but the
  CLIENT confirms; refuse out-of-scope) + the `availableActions` (name/description/params) +
  the current `route` and `state`.
- Calls Gemini `generateContent` with `config.responseMimeType='application/json'` +
  `responseSchema` for `AgentDecision` (so `action.name` must be one of the available names).
- Returns `AgentDecision`. If no Gemini key → returns `{ say: <canned>, awaitingUser: true }`
  (degraded: Autopilot explains it needs the model; the plain guide still works).

Server never runs handlers; it only maps conversation → decision. The registry (descriptors +
handlers) is client-authoritative; the client passes descriptors per turn (availability depends
on the mounted screen).

### Client executor loop

On each recruiter utterance (voice transcript or typed), and after each executed non-terminal
action:
1. POST `AgentRequest` (messages + current `route`/`availableActions`/`state`).
2. Receive `AgentDecision`. Speak/show `say` (`speakSmart` honoring the language selector).
3. If `action`: look it up in the registry; **validate `args` against its `ParamSpec[]`** (type/
   enum/required). Invalid → don't run; append a corrective note and re-ask (one more turn).
4. If the action is `sideEffect`: render a **read-back confirm card** ("I'll create + send
   invites to 12 candidates for Video Interview, Senior Backend Engineer — confirm?"), speak
   it, and **wait for explicit yes** (voice/click) before `run`. Else `run` immediately.
5. After a successful non-side-effect `run`, if `!awaitingUser` → loop (re-POST with the new
   `getState()`), up to a **cap of 8 steps/utterance**. Stop when `awaitingUser`, a confirm is
   pending, the cap is hit, or the user interrupts.

This yields: guided "asks one field, fills it, advances"; one-shot ("set up a video interview
for Senior Backend Engineer with Question Set 2") → the model emits `selectMode` → next turn
`setRole` → `selectQuestionSet` → `nextStep`…, asking only for missing params.

### Voice / typed I/O (reuse)

- **Input:** push-to-talk mic → `startSpeechRecognition(locale, …)` → transcript shown live
  (correctable) → on confirm/enter, fed to the executor as the utterance. Typed textarea feeds
  the same executor. (Autopilot's mic AUTO-SUBMITS the transcript as the current answer, unlike
  the guide's dictate-into-draft; the live transcript + a brief editable window prevent
  acting on a mis-hear.)
- **Output:** `speakSmart(say, voiceLang)` speaks each prompt/confirmation; honors the language
  selector + content-script detection (Hindi/Telugu, etc.).

## v1 action registry (setup flow)

- **global:** `navigate(path)`.
- **setup (InviteWizard):** `setInterviewType(single|multi)`, `selectMode(mode)`, `setRole(role)`,
  `setQuestionSource(tailor|set)`, `selectQuestionSet(id)`, `setDifficulty/setCounts/setDomains`
  (tailor), `nextStep`/`backStep`/`goToStep(n)`, `addCandidate({email, role})`, `createInvites`
  **(sideEffect)**. `getState()` returns the wizard's current step + field values so the agent
  knows what's filled and what to ask next.
- **read/answer:** `answerQuestion(q)` → delegates to the existing guide Q&A for "how do I…".

Registry is extensible: a new action = register `{ descriptor, run }` under a screen; Autopilot
picks it up automatically when that screen is mounted.

## UX (in the existing Mimic Guide panel)

Add an **Autopilot** toggle. When ON: a **step tracker** (current task + step), the **field it's
asking for**, a **live mic transcript** (editable before acting), the existing mic + language
selector, spoken prompts, a **read-back confirm card** (Confirm/Cancel) before any side-effect,
and an **on-screen action log** (action + args + time). The recruiter can interrupt, correct
("no, make it Voice"), go back a step, or take over manually anytime. As Autopilot acts, the
REAL app UI updates (navigates, selects the mode card, fills role, advances steps) — the
recruiter watches it happen. Autopilot OFF ⇒ the panel is exactly today's guide.

## Safety / scope / RBAC / audit

- LLM output constrained to registered action names (responseSchema); unknown/invalid → the
  executor refuses and the agent re-asks. No raw API calls, no invented actions.
- Every `sideEffect` action requires an explicit read-back confirmation; no silent send.
- RBAC inherent (handlers = the screen's own setters; server endpoints stay auth-gated). No
  role escalation, no auth/invite-link bypass.
- Every executed action is shown on-screen + appended to a session audit log (action, args,
  time, confirmed-by).
- Strict TalbotIQ scope; out-of-scope → polite redirect (guide scope rule reused).
- Ambiguous intent or missing required param → the agent ASKS, never guesses.

## New / changed files (additive)

- `shared/autopilot.ts` — CREATE (types above).
- `server/services/autopilotAgent.ts` — CREATE (`runAutopilotAgent`, Gemini structured output).
- `server/routes/help.ts` — MODIFY: add `POST /agent` (auth-gated, same router).
- `src/features/guide/autopilot/registry.ts` — CREATE (zustand registry + `useAutopilotActions`).
- `src/features/guide/autopilot/executor.ts` — CREATE (validate → confirm → run → loop).
- `src/features/guide/autopilot/AutopilotPanel.tsx` (or extend `MimicGuide.tsx`) — CREATE/MODIFY
  (toggle, step tracker, transcript, confirm card, action log; reuse mic + speakSmart).
- `src/features/recruiter/InviteWizard.tsx` — MODIFY (additive `useAutopilotActions('setup', …)`
  + a `getState`; expose `guardedNext`/`addManual`/`submit` to the hook — no state change).
- `global.navigate` + route reporting are provided by the Autopilot panel itself (it's inside
  `<BrowserRouter>`), so no separate registrant component is needed.

## Build phasing (multi-plan)

1. **Plan 1 — Registry + executor + agent endpoint (foundation).** `shared/autopilot.ts`;
   `registry.ts` + `useAutopilotActions`; `global.navigate` + route context; `autopilotAgent.ts`
   + `POST /api/help/agent` (structured output); executor (validate/confirm/run/loop) with 2-3
   nav actions. Unit-testable pure pieces: param validation, decision parsing, loop control.
2. **Plan 2 — Guided setup → create-invites.** Instrument `InviteWizard` with the setup actions
   + `getState`; the read-back confirm for `createInvites`; the Autopilot panel UX (toggle, step
   tracker, action log). End-to-end guided run (typed).
3. **Plan 3 — Voice + one-shot + controls.** Push-to-talk transcript wiring + spoken prompts
   (reuse); one-shot multi-param extraction; interrupt / correct / go-back / take-over; audit
   polish. Verify per acceptance criteria (voice + typed, full setup-to-invite).

(Registry widening to Templates/Question-Sets/Results/Pipelines/CSV = post-v1, additive.)

## Testing

- Unit (tsx): `ParamSpec` validation (type/enum/required, reject unknown action), the executor's
  decision handling (side-effect ⇒ confirm-gate; loop stops on `awaitingUser`/cap), and the
  agent prompt builder (available-action list, out-of-scope refusal string).
- Server: `/api/help/agent` returns a well-formed `AgentDecision`; degraded (no key) path.
- Manual (no browser harness): a full guided run — "set up an interview" → mode → role →
  question set → add candidate → **confirm** → create invites — by typing, then by voice; plus
  a one-shot instruction; plus an out-of-scope request (polite redirect); plus Autopilot-off
  still works as the plain guide.

## Guardrails restated

Additive; the guide still works with Autopilot off. Whitelist-only execution; every side-effect
confirmed; RBAC inherent; keys server-side; TalbotIQ-scoped. Frozen modules (auth,
invite-link/claim, sessions, Firestore field names) untouched — Autopilot drives the wizard by
calling its existing handlers, and `createInvites` goes through the unchanged invite path. If any
step requires bypassing RBAC/auth/invite-link or rewriting a frozen module, PAUSE and ASK.

## Open items (defaulted; flag to change)

- Voice input = browser Web Speech (Chrome/Edge; multilingual via locales). Server STT deferred.
- Listening = push-to-talk per step. Continuous hands-free deferred.
- Agent loop = structured JSON single-next-action (cap 8/utterance). Native function-calling deferred.
- Audit log = in-session + on-screen for v1 (server-persisted audit deferred).

## Acceptance criteria

- [ ] Recruiter completes a real task (set up + create invites) end to end by VOICE, by TYPING,
      or mixing — Autopilot asks each field, fills it, and advances, mirroring the real flow.
- [ ] One-shot instructions extract all available params and ask only for the missing ones.
- [ ] Autopilot acts ONLY through the whitelisted registry (never invents actions / raw APIs);
      args are schema-validated; missing params asked one at a time.
- [ ] The REAL app UI updates as it acts (navigates, selects cards, fills fields, advances) and
      it speaks each step; voice honors the language selector (multilingual).
- [ ] EVERY side-effect (create invites/send/advance/delete/bulk) requires an explicit read-back
      confirmation; nothing sends silently.
- [ ] RBAC respected (no exceeding the user's permissions, no auth/invite-link bypass); actions
      are audit-logged + on-screen; ambiguous intent → it asks.
- [ ] Strictly TalbotIQ-scoped; out-of-scope → polite redirect. Additive; frozen modules
      untouched; keys server-side; still works as a plain guide with Autopilot off.
