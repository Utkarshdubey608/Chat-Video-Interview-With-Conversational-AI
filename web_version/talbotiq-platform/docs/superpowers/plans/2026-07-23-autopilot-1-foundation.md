# Mimic Guide Autopilot — Plan 1: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the whitelisted agent foundation — shared action types + a pure arg validator, the client action registry + `useAutopilotActions` hook, the pure executor decision logic, and the server `POST /api/help/agent` endpoint (Gemini structured output) — with NO UI wiring and NO screen changes yet (Plan 2). The Mimic Guide is behaviorally unchanged.

**Architecture:** Screens will (Plan 2) register named handlers into a client registry via a hook; a server agent maps the conversation + available actions → a structured `AgentDecision { say, action?, awaitingUser }`; a client executor validates the action's args against its `ParamSpec[]`, gates side-effects behind confirmation, runs the registered handler, and loops. Plan 1 delivers those primitives + tests; nothing is wired to the panel or the wizard.

**Tech Stack:** TypeScript, Node/Express, React 18, zustand, `@google/genai` (Gemini, structured output via `responseMimeType`/`responseSchema`), the repo's `tsx` unit-test convention.

## Global Constraints

- **ADDITIVE / whitelist-only.** New files + one additive route only. The Mimic Guide (`MimicGuide.tsx`, `/api/help/chat`, `/tts`) is untouched — the guide behaves exactly as today. No screen/wizard changes in Plan 1.
- **Frozen modules untouched:** auth, invite-link/claim, sessions, Firestore field names. Keys server-side (reuse `geminiClient()`; never expose to client).
- **The LLM can only NAME a registered action.** Args are validated client-side against the action's `ParamSpec[]`; unknown action or invalid args ⇒ the executor refuses (no run) and the agent re-asks.
- **Structured output shape:** the model returns `{ say, actionName, argsJson, awaitingUser }`; the server maps it to `AgentDecision` (`action` present only when `actionName` is non-empty). This avoids dynamic-object response schemas.
- **Gemini usage** mirrors `server/services/gemini.ts`: `geminiClient().models.generateContent({ model: modelName(), contents, config: { systemInstruction, responseMimeType: 'application/json', responseSchema: { type: Type.OBJECT, … } } })`, `Type` imported from `@google/genai`. Degraded path when `!geminiEnabled()`.
- **Gates:** `npx tsx <file>.test.ts` per test; `npm run build` (src+shared); `npx tsc -p server/tsconfig.json --noEmit` (server). `npm run lint` is non-functional.

## File structure (this plan)

- `shared/autopilot.ts` — CREATE: types (`ParamSpec`, `ActionDescriptor`, `AgentContext`, `AgentRequest`, `AgentDecision`) + pure `validateArgs()`.
- `shared/autopilot.test.ts` — CREATE: `validateArgs` unit tests.
- `server/services/autopilotAgent.ts` — CREATE: `buildAutopilotPrompt()` (pure) + `runAutopilotAgent()` (Gemini) + degraded path.
- `server/services/autopilotAgent.test.ts` — CREATE: `buildAutopilotPrompt` + decision-normalization unit tests.
- `server/routes/help.ts` — MODIFY: add `POST /agent` (auth-gated, same router).
- `src/features/guide/autopilot/registry.ts` — CREATE: zustand registry + `useAutopilotActions` hook + pure selectors.
- `src/features/guide/autopilot/registry.test.ts` — CREATE: registry store unit tests.
- `src/features/guide/autopilot/executor.ts` — CREATE: pure `planExecution()` + loop-control helper.
- `src/features/guide/autopilot/executor.test.ts` — CREATE: `planExecution` unit tests.

---

## Task 1: Shared types + `validateArgs` (`shared/autopilot.ts`)

**Files:** Create `shared/autopilot.ts`, `shared/autopilot.test.ts`.

**Interfaces — Produces:**
- Types `ParamSpec`, `ActionDescriptor`, `AgentContext`, `AgentRequest`, `AgentDecision` (per the design spec's data-model block).
- `validateArgs(params: ParamSpec[], args: Record<string, unknown>): { ok: boolean; errors: string[]; value: Record<string, unknown> }` — pure; coerces number/boolean, checks enum membership + required.

- [ ] **Step 1: Write the failing test `shared/autopilot.test.ts`**

```ts
/** Run: npx tsx shared/autopilot.test.ts */
import { validateArgs, type ParamSpec } from './autopilot'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

const modeP: ParamSpec[] = [{ name: 'mode', type: 'enum', enum: ['chatbot', 'voice'], required: true }]
assert('valid enum', validateArgs(modeP, { mode: 'voice' }).ok)
assert('invalid enum rejected', !validateArgs(modeP, { mode: 'telepathy' }).ok)
assert('missing required rejected', !validateArgs(modeP, {}).ok)

const roleP: ParamSpec[] = [{ name: 'role', type: 'string', required: true }]
assert('string ok', validateArgs(roleP, { role: 'Senior Dev' }).value.role === 'Senior Dev')
assert('empty string = missing', !validateArgs(roleP, { role: '' }).ok)

const numP: ParamSpec[] = [{ name: 'n', type: 'number', required: true }]
assert('number coerced from string', validateArgs(numP, { n: '5' }).value.n === 5)
assert('NaN rejected', !validateArgs(numP, { n: 'abc' }).ok)

const boolP: ParamSpec[] = [{ name: 'b', type: 'boolean' }]
assert('boolean from "true"', validateArgs(boolP, { b: 'true' }).value.b === true)

const optP: ParamSpec[] = [{ name: 'x', type: 'string' }]
assert('optional absent ok', validateArgs(optP, {}).ok)
assert('unknown args ignored (not in params)', validateArgs(roleP, { role: 'R', bogus: 9 }).value.bogus === undefined)

console.log(`\n${failures === 0 ? '✅ ALL AUTOPILOT-SHARED TESTS PASSED' : `❌ ${failures} FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify fail** — `npx tsx shared/autopilot.test.ts` → FAIL (module missing).

- [ ] **Step 3: Implement `shared/autopilot.ts`**

```ts
/**
 * Mimic Guide Autopilot — shared contract between the client registry/executor
 * and the server agent. Pure + dependency-free (imported by both the Vite client
 * and the Express server). The LLM only ever NAMES a registered action; args are
 * validated here against the action's ParamSpec before anything runs.
 */
export type ParamType = 'string' | 'number' | 'boolean' | 'enum'

export interface ParamSpec {
  name: string
  type: ParamType
  enum?: string[]
  required?: boolean
  description?: string
}

/** Serializable action descriptor the LLM sees. Handlers live only client-side. */
export interface ActionDescriptor {
  name: string          // unique, e.g. 'setup.selectMode'
  description: string
  screen: string        // 'global' | 'setup' | …
  sideEffect: boolean   // true ⇒ read-back confirm required before running
  params: ParamSpec[]
}

export interface AgentContext {
  route: string
  availableActions: ActionDescriptor[]
  state: Record<string, unknown>
}

export interface AgentRequest {
  messages: { role: 'user' | 'assistant'; content: string }[]
  context: AgentContext
}

export interface AgentDecision {
  say: string
  action?: { name: string; args: Record<string, unknown> }
  awaitingUser: boolean
}

/** Validate + coerce args against a ParamSpec list. Pure. Unknown keys are dropped. */
export function validateArgs(
  params: ParamSpec[],
  args: Record<string, unknown> | undefined,
): { ok: boolean; errors: string[]; value: Record<string, unknown> } {
  const errors: string[] = []
  const value: Record<string, unknown> = {}
  const src = args ?? {}
  for (const p of params) {
    const raw = src[p.name]
    const missing = raw === undefined || raw === null || raw === ''
    if (missing) {
      if (p.required) errors.push(`Missing required "${p.name}"`)
      continue
    }
    switch (p.type) {
      case 'string':
        if (typeof raw !== 'string') errors.push(`"${p.name}" must be text`)
        else value[p.name] = raw
        break
      case 'number': {
        const n = Number(raw)
        if (Number.isNaN(n)) errors.push(`"${p.name}" must be a number`)
        else value[p.name] = n
        break
      }
      case 'boolean':
        value[p.name] = raw === true || raw === 'true'
        break
      case 'enum':
        if (!p.enum?.includes(String(raw))) errors.push(`"${p.name}" must be one of: ${(p.enum ?? []).join(', ')}`)
        else value[p.name] = String(raw)
        break
    }
  }
  return { ok: errors.length === 0, errors, value }
}
```

- [ ] **Step 4: Run to verify pass** — `npx tsx shared/autopilot.test.ts` → `✅ ALL AUTOPILOT-SHARED TESTS PASSED`.

- [ ] **Step 5: Commit**
```bash
git add shared/autopilot.ts shared/autopilot.test.ts
git commit -m "feat(autopilot): shared action types + arg validator"
```

---

## Task 2: Server agent endpoint (`autopilotAgent.ts` + `/agent` route)

**Files:** Create `server/services/autopilotAgent.ts`, `server/services/autopilotAgent.test.ts`; modify `server/routes/help.ts`.

**Interfaces:**
- Consumes: `geminiClient`, `modelName`, `geminiEnabled` (`server/services/gemini.ts`); `Type` from `@google/genai`; types from `shared/autopilot.ts`.
- Produces: `buildAutopilotPrompt(ctx: AgentContext): string` (pure); `normalizeDecision(raw, availableNames): AgentDecision` (pure — drops an unknown `actionName`, parses `argsJson`); `runAutopilotAgent(req: AgentRequest): Promise<AgentDecision>`; `POST /api/help/agent`.

- [ ] **Step 1: Write the failing test `server/services/autopilotAgent.test.ts`**

```ts
/** Run: npx tsx server/services/autopilotAgent.test.ts */
import { buildAutopilotPrompt, normalizeDecision } from './autopilotAgent'
import type { AgentContext } from '../../shared/autopilot'

let failures = 0
function assert(label: string, cond: boolean) { console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}`); if (!cond) failures++ }

const ctx: AgentContext = {
  route: '/sessions/new',
  availableActions: [
    { name: 'setup.selectMode', description: 'Select mode', screen: 'setup', sideEffect: false,
      params: [{ name: 'mode', type: 'enum', enum: ['chatbot', 'voice'], required: true }] },
    { name: 'setup.createInvites', description: 'Create + send invites', screen: 'setup', sideEffect: true, params: [] },
  ],
  state: { step: 1, mode: '', role: '' },
}
const prompt = buildAutopilotPrompt(ctx)
assert('prompt lists action names', prompt.includes('setup.selectMode') && prompt.includes('setup.createInvites'))
assert('prompt marks side-effect', /createInvites[\s\S]*side.?effect/i.test(prompt) || prompt.includes('sideEffect'))
assert('prompt includes current route', prompt.includes('/sessions/new'))
assert('prompt states TalbotIQ-only scope', /TalbotIQ/.test(prompt))

const names = ctx.availableActions.map((a) => a.name)
// unknown action name is dropped
const d1 = normalizeDecision({ say: 'ok', actionName: 'setup.hackTheDb', argsJson: '{}', awaitingUser: false }, names)
assert('unknown action dropped', d1.action === undefined)
// known action + args parsed
const d2 = normalizeDecision({ say: 'Selecting voice', actionName: 'setup.selectMode', argsJson: '{"mode":"voice"}', awaitingUser: false }, names)
assert('known action kept', d2.action?.name === 'setup.selectMode' && (d2.action?.args as any).mode === 'voice')
// bad argsJson → empty args, action still named
const d3 = normalizeDecision({ say: 'x', actionName: 'setup.selectMode', argsJson: 'not json', awaitingUser: false }, names)
assert('bad argsJson → empty args', d3.action?.name === 'setup.selectMode' && Object.keys(d3.action?.args ?? {}).length === 0)
// empty actionName → no action
const d4 = normalizeDecision({ say: 'What role?', actionName: '', argsJson: '', awaitingUser: true }, names)
assert('empty actionName → no action, awaiting', d4.action === undefined && d4.awaitingUser === true)

console.log(`\n${failures === 0 ? '✅ ALL AUTOPILOT-AGENT TESTS PASSED' : `❌ ${failures} FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify fail** — `npx tsx server/services/autopilotAgent.test.ts` → FAIL.

- [ ] **Step 3: Implement `server/services/autopilotAgent.ts`**

```ts
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
    'Drive the real flow one field at a time. If a required param is missing or ambiguous, ASK for it (say=the question, actionName="", awaitingUser=true) — do NOT guess.',
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
  if (!name || !availableNames.includes(name)) return { say, awaitingUser: awaitingUser || !name }
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
    return { say: 'Sorry — I hit a problem working that out. Could you say that again?', awaitingUser: true }
  }
}
```

- [ ] **Step 4: Add `POST /agent` to `server/routes/help.ts`**

Add imports:
```ts
import { runAutopilotAgent } from '../services/autopilotAgent'
```
Add a schema + route (after the chat route):
```ts
const ParamSpecSchema = z.object({
  name: z.string(), type: z.enum(['string', 'number', 'boolean', 'enum']),
  enum: z.array(z.string()).optional(), required: z.boolean().optional(), description: z.string().optional(),
})
const AgentSchema = z.object({
  messages: z.array(z.object({ role: z.enum(['user', 'assistant']), content: z.string().min(1).max(8000) })).min(1).max(30),
  context: z.object({
    route: z.string().max(200),
    availableActions: z.array(z.object({
      name: z.string(), description: z.string(), screen: z.string(), sideEffect: z.boolean(), params: z.array(ParamSpecSchema),
    })).max(100),
    state: z.record(z.string(), z.unknown()).default({}),
  }),
})

helpRouter.post('/agent', async (req, res) => {
  try {
    const parsed = AgentSchema.parse(req.body)
    requireAuth(req) // recruiter or candidate — same as /chat; actions themselves are RBAC-gated client+server
    const decision = await runAutopilotAgent(parsed)
    res.json(decision)
  } catch (error) {
    console.error('[autopilot] /agent error', error)
    res.json({ say: 'Something went wrong. Please try again.', awaitingUser: true })
  }
})
```

- [ ] **Step 5: Run to verify pass + gates** — `npx tsx server/services/autopilotAgent.test.ts` (PASS), `npx tsc -p server/tsconfig.json --noEmit` (exit 0), `npm run build` (exit 0).

- [ ] **Step 6: Commit**
```bash
git add server/services/autopilotAgent.ts server/services/autopilotAgent.test.ts server/routes/help.ts
git commit -m "feat(autopilot): server agent endpoint (Gemini structured output) + /api/help/agent"
```

---

## Task 3: Client action registry + `useAutopilotActions` hook (`registry.ts`)

**Files:** Create `src/features/guide/autopilot/registry.ts`, `src/features/guide/autopilot/registry.test.ts`.

**Interfaces:**
- Consumes: `zustand` (`create`), types from `shared/autopilot.ts`, React (`useEffect`).
- Produces:
  - `interface RegisteredAction { descriptor: ActionDescriptor; run: (args: Record<string, unknown>) => void | Promise<void> }`
  - `useAutopilotRegistry` (zustand store) with state `{ byScreen: Record<string, { actions: Record<string, RegisteredAction>; getState: () => Record<string, unknown> }> }` and actions `registerScreen(screen, actions, getState)`, `unregisterScreen(screen)`.
  - Pure selectors (exported, testable): `listDescriptors(state): ActionDescriptor[]`, `snapshotState(state): Record<string, unknown>`, `findAction(state, name): RegisteredAction | undefined`.
  - `useAutopilotActions(screen, defs, opts)` hook: registers on mount, unregisters on unmount. `defs` maps action-name → `{ description, sideEffect?, params?, run }`.

- [ ] **Step 1: Write the failing test `src/features/guide/autopilot/registry.test.ts`**

```ts
/** Run: npx tsx src/features/guide/autopilot/registry.test.ts */
import { useAutopilotRegistry, listDescriptors, snapshotState, findAction } from './registry'

let failures = 0
function assert(label: string, cond: boolean) { console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}`); if (!cond) failures++ }

const store = useAutopilotRegistry
let ran: unknown = null
store.getState().registerScreen(
  'setup',
  {
    selectMode: { description: 'Select mode', params: [{ name: 'mode', type: 'enum', enum: ['voice'], required: true }], run: (a) => { ran = a } },
    createInvites: { description: 'Create invites', sideEffect: true, run: () => { ran = 'sent' } },
  },
  () => ({ step: 1, mode: '' }),
)

const descs = listDescriptors(store.getState())
assert('descriptors listed with screen-qualified names', descs.some((d) => d.name === 'setup.selectMode'))
assert('createInvites is sideEffect', descs.find((d) => d.name === 'setup.createInvites')?.sideEffect === true)
assert('default sideEffect false', descs.find((d) => d.name === 'setup.selectMode')?.sideEffect === false)
assert('state snapshot exposed', (snapshotState(store.getState()) as any).step === 1)

const a = findAction(store.getState(), 'setup.selectMode')
assert('findAction returns handler', !!a)
a!.run({ mode: 'voice' })
assert('handler ran with args', (ran as any).mode === 'voice')

store.getState().unregisterScreen('setup')
assert('unregister clears actions', listDescriptors(store.getState()).length === 0)

console.log(`\n${failures === 0 ? '✅ ALL AUTOPILOT-REGISTRY TESTS PASSED' : `❌ ${failures} FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify fail** — FAIL (module missing).

- [ ] **Step 3: Implement `src/features/guide/autopilot/registry.ts`**

```ts
import { useEffect } from 'react'
import { create } from 'zustand'
import type { ActionDescriptor, ParamSpec } from '@shared/autopilot'

export interface RegisteredAction {
  descriptor: ActionDescriptor
  run: (args: Record<string, unknown>) => void | Promise<void>
}
/** What a screen passes per action (name is the map key; screen prefixes it). */
export interface ActionDef {
  description: string
  sideEffect?: boolean
  params?: ParamSpec[]
  run: (args: Record<string, unknown>) => void | Promise<void>
}
interface ScreenReg { actions: Record<string, RegisteredAction>; getState: () => Record<string, unknown> }
interface RegistryState {
  byScreen: Record<string, ScreenReg>
  registerScreen: (screen: string, defs: Record<string, ActionDef>, getState?: () => Record<string, unknown>) => void
  unregisterScreen: (screen: string) => void
}

export const useAutopilotRegistry = create<RegistryState>((set) => ({
  byScreen: {},
  registerScreen: (screen, defs, getState) =>
    set((s) => {
      const actions: Record<string, RegisteredAction> = {}
      for (const [key, def] of Object.entries(defs)) {
        const name = `${screen}.${key}`
        actions[name] = {
          descriptor: { name, description: def.description, screen, sideEffect: def.sideEffect ?? false, params: def.params ?? [] },
          run: def.run,
        }
      }
      return { byScreen: { ...s.byScreen, [screen]: { actions, getState: getState ?? (() => ({})) } } }
    }),
  unregisterScreen: (screen) =>
    set((s) => {
      const next = { ...s.byScreen }
      delete next[screen]
      return { byScreen: next }
    }),
}))

/* ── Pure selectors (unit-tested) ── */
export function listDescriptors(state: RegistryState): ActionDescriptor[] {
  return Object.values(state.byScreen).flatMap((sc) => Object.values(sc.actions).map((a) => a.descriptor))
}
export function snapshotState(state: RegistryState): Record<string, unknown> {
  return Object.values(state.byScreen).reduce<Record<string, unknown>>((acc, sc) => ({ ...acc, ...sc.getState() }), {})
}
export function findAction(state: RegistryState, name: string): RegisteredAction | undefined {
  for (const sc of Object.values(state.byScreen)) if (sc.actions[name]) return sc.actions[name]
  return undefined
}

/** Screens call this while mounted to expose their real handlers to Autopilot. */
export function useAutopilotActions(
  screen: string,
  defs: Record<string, ActionDef>,
  opts?: { getState?: () => Record<string, unknown> },
): void {
  const register = useAutopilotRegistry((s) => s.registerScreen)
  const unregister = useAutopilotRegistry((s) => s.unregisterScreen)
  // Re-register whenever defs identity changes; callers should memoize defs/getState.
  useEffect(() => {
    register(screen, defs, opts?.getState)
    return () => unregister(screen)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [screen, defs, opts?.getState])
}
```
Note: confirm `@shared` alias resolves under tsx (it does at build via vite/tsconfig paths; the test imports the module which imports `@shared/autopilot` — if tsx can't resolve `@shared` at test runtime, change the import in `registry.ts` to a relative `../../../../shared/autopilot`). Verify by running the test; adjust the import to relative if resolution fails.

- [ ] **Step 4: Run to verify pass + build** — `npx tsx src/features/guide/autopilot/registry.test.ts` (PASS); `npm run build` (exit 0).

- [ ] **Step 5: Commit**
```bash
git add src/features/guide/autopilot/registry.ts src/features/guide/autopilot/registry.test.ts
git commit -m "feat(autopilot): client action registry + useAutopilotActions hook"
```

---

## Task 4: Pure executor decision logic (`executor.ts`)

**Files:** Create `src/features/guide/autopilot/executor.ts`, `src/features/guide/autopilot/executor.test.ts`.

**Interfaces:**
- Consumes: `validateArgs` (`@shared/autopilot`), registry selectors + types (`./registry`).
- Produces: `planExecution(decision: AgentDecision, actions: ActionDescriptor[]): ExecPlan` where `ExecPlan = { kind: 'ask' } | { kind: 'refuse'; reason: string } | { kind: 'run'; name: string; args } | { kind: 'confirm'; name: string; args; summary: string }` — pure; drives the executor. (The impure part — actually calling `findAction(...).run` and the POST loop — lives in the panel/Plan 2; Plan 1 only ships + tests the pure planner.)

- [ ] **Step 1: Write the failing test `src/features/guide/autopilot/executor.test.ts`**

```ts
/** Run: npx tsx src/features/guide/autopilot/executor.test.ts */
import { planExecution } from './executor'
import type { ActionDescriptor, AgentDecision } from '@shared/autopilot'

let failures = 0
function assert(label: string, cond: boolean) { console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}`); if (!cond) failures++ }

const actions: ActionDescriptor[] = [
  { name: 'setup.selectMode', description: 'Select mode', screen: 'setup', sideEffect: false, params: [{ name: 'mode', type: 'enum', enum: ['voice', 'chatbot'], required: true }] },
  { name: 'setup.createInvites', description: 'Create + send invites', screen: 'setup', sideEffect: true, params: [] },
]
const dec = (d: Partial<AgentDecision>): AgentDecision => ({ say: '', awaitingUser: false, ...d })

assert('no action → ask', planExecution(dec({ say: 'What role?', awaitingUser: true }), actions).kind === 'ask')
assert('unknown action → refuse', planExecution(dec({ action: { name: 'setup.nope', args: {} } }), actions).kind === 'refuse')
assert('bad args → refuse', planExecution(dec({ action: { name: 'setup.selectMode', args: { mode: 'x' } } }), actions).kind === 'refuse')
const run = planExecution(dec({ action: { name: 'setup.selectMode', args: { mode: 'voice' } } }), actions)
assert('valid non-sideEffect → run', run.kind === 'run' && (run as any).args.mode === 'voice')
const conf = planExecution(dec({ say: 'Create invites for 3?', action: { name: 'setup.createInvites', args: {} } }), actions)
assert('sideEffect → confirm', conf.kind === 'confirm' && (conf as any).summary.includes('Create invites'))

console.log(`\n${failures === 0 ? '✅ ALL AUTOPILOT-EXECUTOR TESTS PASSED' : `❌ ${failures} FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify fail** — FAIL.

- [ ] **Step 3: Implement `src/features/guide/autopilot/executor.ts`**

```ts
import { validateArgs, type ActionDescriptor, type AgentDecision } from '@shared/autopilot'

export type ExecPlan =
  | { kind: 'ask' }
  | { kind: 'refuse'; reason: string }
  | { kind: 'run'; name: string; args: Record<string, unknown> }
  | { kind: 'confirm'; name: string; args: Record<string, unknown>; summary: string }

/**
 * Pure: decide what to DO with an AgentDecision, given the actions available.
 * - no action → 'ask' (the agent is questioning/answering; caller waits or shows `say`)
 * - unknown action or invalid args → 'refuse' (caller re-asks with the reason)
 * - side-effect action with valid args → 'confirm' (caller shows read-back, waits for yes)
 * - otherwise → 'run' (caller invokes the registered handler)
 */
export function planExecution(decision: AgentDecision, actions: ActionDescriptor[]): ExecPlan {
  if (!decision.action) return { kind: 'ask' }
  const desc = actions.find((a) => a.name === decision.action!.name)
  if (!desc) return { kind: 'refuse', reason: `Unknown action "${decision.action.name}"` }
  const { ok, errors, value } = validateArgs(desc.params, decision.action.args)
  if (!ok) return { kind: 'refuse', reason: errors.join('; ') }
  if (desc.sideEffect) return { kind: 'confirm', name: desc.name, args: value, summary: decision.say || `Run ${desc.name}?` }
  return { kind: 'run', name: desc.name, args: value }
}
```

- [ ] **Step 4: Run to verify pass + build** — `npx tsx src/features/guide/autopilot/executor.test.ts` (PASS); `npm run build` (exit 0).

- [ ] **Step 5: Commit**
```bash
git add src/features/guide/autopilot/executor.ts src/features/guide/autopilot/executor.test.ts
git commit -m "feat(autopilot): pure executor decision planner"
```

---

## Self-review notes (author)

- **Spec coverage (foundation slice):** whitelist-only + arg validation → Task 1 (`validateArgs`) + Task 4 (`planExecution` refuses unknown/invalid); agent brain (Gemini structured output, degraded path, scope) → Task 2; the registry + per-screen hook that later lets screens expose handlers → Task 3; side-effect ⇒ confirm gate → Task 4 (`confirm` plan). UI wiring, wizard instrumentation, voice, and the client POST-loop are **Plan 2/3** (this plan ships only tested primitives).
- **Additive:** new files + one additive `/agent` route; `MimicGuide.tsx` and the existing `/chat`+`/tts` are untouched, so the guide is behaviorally identical. No screen/wizard changes.
- **Testability:** every non-trivial pure unit is tsx-tested (`validateArgs`, `buildAutopilotPrompt`, `normalizeDecision`, registry selectors, `planExecution`). The Gemini call + React hook effect are covered by build/tsc (no HTTP/browser harness, per repo convention).
- **Type consistency:** `AgentDecision`/`ActionDescriptor`/`ParamSpec` defined once in `shared/autopilot.ts`, imported by server (`autopilotAgent.ts`) and client (`registry.ts`, `executor.ts`). The model's raw `{say,actionName,argsJson,awaitingUser}` is normalized to `AgentDecision` in one place (`normalizeDecision`).
- **`@shared` alias caveat** flagged in Task 3/4 — if tsx can't resolve `@shared` at test runtime, switch those imports to relative paths (the tests will reveal it immediately).
- **Follow-ups (Plan 2/3):** the Autopilot panel UX (toggle, transcript, step tracker, confirm card, action log), the client POST→execute→loop wiring, `InviteWizard` instrumentation (`useAutopilotActions('setup', …)`), `global.navigate`, voice push-to-talk + spoken prompts, one-shot, interrupt/correct/take-over.
