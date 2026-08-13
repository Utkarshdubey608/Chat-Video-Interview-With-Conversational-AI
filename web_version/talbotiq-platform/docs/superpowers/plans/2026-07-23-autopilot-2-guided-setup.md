# Mimic Guide Autopilot — Plan 2: Guided Setup→Invites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Autopilot actually DRIVE the setup flow (typed). Wire the client agent loop, instrument `InviteWizard` so its real setters are registered actions, and add the Autopilot panel UX (toggle, step tracker, action log, read-back confirm card) — so the recruiter can type "set up an interview" and watch the wizard fill itself: type → mode → role → question source/set → add candidate → **confirm** → create invites. Voice I/O + one-shot polish are Plan 3.

**Architecture:** Builds on Plan 1's foundation (`shared/autopilot.ts`, `/api/help/agent`, `registry.ts`, `executor.ts`). The Autopilot panel (in `MimicGuide.tsx`) runs a client loop: build `AgentContext` from the current route + registered actions + `getState()`, POST `/api/help/agent`, feed the `AgentDecision` to `planExecution`, then **ask** (show/await), **refuse** (re-ask), **confirm** (read-back card → on yes run), or **run** (invoke the registered handler → real UI updates), looping (cap 8) until it needs the recruiter. `InviteWizard` exposes its setters via `useAutopilotActions('setup', …)` reading a live state ref (registers once, always current). Additive — the wizard's local `useState` is unchanged.

**Tech Stack:** TypeScript, React 18, zustand, react-router (`useNavigate`/`useLocation`), the repo's `tsx` unit-test convention.

## Global Constraints

- **ADDITIVE.** `InviteWizard`'s state/logic is unchanged — we only ADD a `useAutopilotActions` registration + tiny helpers (`addCandidateDirect`, `guardedNext`) that reuse existing setters. The Mimic Guide's existing chat path (`send` → `/api/help/chat`) stays intact; Autopilot is a MODE toggled on. Autopilot OFF ⇒ today's guide.
- **Whitelist + confirm (from Plan 1):** the loop only runs actions via `registry.findAction`; `planExecution` re-validates args and returns `confirm` for side-effects. **`createInvites` (side-effect) NEVER runs without the recruiter clicking Confirm** on the read-back card.
- **RBAC inherent:** actions are the wizard's own setters (recruiter-only screen); `createInvites` → the existing `submit()` → the auth-gated invite path. No bypass.
- **Frozen modules untouched:** auth, invite-link/claim, sessions, Firestore fields. Keys server-side.
- **Gates:** `npx tsx <file>.test.ts`; `npm run build`; `npx tsc -p server/tsconfig.json --noEmit`. UI verified by build + a documented manual walkthrough (no browser harness).

## File structure (this plan)

- `src/lib/api.ts` — MODIFY: add `helpApi.agent(body: AgentRequest): Promise<AgentDecision>`.
- `src/features/guide/autopilot/context.ts` — CREATE: pure `buildAgentContext(route, descriptors, state)` + `logLine(plan, decision)` helpers.
- `src/features/guide/autopilot/context.test.ts` — CREATE: unit tests.
- `src/features/guide/autopilot/useAutopilotRunner.ts` — CREATE: the client loop hook (`runTurn`, confirm state, action log) built on Plan 1's `planExecution` + registry.
- `src/features/recruiter/InviteWizard.tsx` — MODIFY: additive `useAutopilotActions('setup', …)` + `stateRef` + `addCandidateDirect` + `guardedNext`.
- `src/features/guide/MimicGuide.tsx` — MODIFY: Autopilot toggle; route the composer through the runner when ON; render step tracker + action log + read-back confirm card; register `global.navigate`.

---

## Task 1: Client agent API + pure context/log helpers

**Files:** MODIFY `src/lib/api.ts`; CREATE `src/features/guide/autopilot/context.ts`, `context.test.ts`.

**Interfaces:**
- Produces: `helpApi.agent(body: AgentRequest): Promise<AgentDecision>` (`http<AgentDecision>('/help/agent', POST)`); `buildAgentContext(route: string, descriptors: ActionDescriptor[], state: Record<string,unknown>): AgentContext` (pure); `logLine(entry): string` — a human string for the action log (pure).

- [ ] **Step 1: Write `src/features/guide/autopilot/context.test.ts`**

```ts
/** Run: npx tsx src/features/guide/autopilot/context.test.ts */
import { buildAgentContext, logLine } from './context'
import type { ActionDescriptor } from '@shared/autopilot'

let failures = 0
function assert(l: string, c: boolean) { console.log(`  ${c ? 'PASS' : 'FAIL'}  ${l}`); if (!c) failures++ }

const descs: ActionDescriptor[] = [
  { name: 'setup.selectMode', description: 'x', screen: 'setup', sideEffect: false, params: [] },
]
const ctx = buildAgentContext('/sessions/new', descs, { step: 1, role: '' })
assert('route carried', ctx.route === '/sessions/new')
assert('actions carried', ctx.availableActions.length === 1 && ctx.availableActions[0].name === 'setup.selectMode')
assert('state carried', (ctx.state as any).step === 1)

assert('log run line', logLine({ kind: 'run', name: 'setup.selectMode', args: { mode: 'voice' } }).includes('setup.selectMode'))
assert('log confirm line', logLine({ kind: 'confirm', name: 'setup.createInvites', args: {}, summary: 'Create 3?' }).toLowerCase().includes('confirm'))
assert('log refuse line', logLine({ kind: 'refuse', reason: 'Unknown action "x"' }).toLowerCase().includes('refus') || logLine({ kind: 'refuse', reason: 'Unknown action "x"' }).includes('Unknown'))

console.log(`\n${failures === 0 ? '✅ ALL AUTOPILOT-CONTEXT TESTS PASSED' : `❌ ${failures} FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 2: Run → FAIL** (`npx tsx src/features/guide/autopilot/context.test.ts`).

- [ ] **Step 3: Implement `src/features/guide/autopilot/context.ts`**

```ts
import type { ActionDescriptor, AgentContext } from '@shared/autopilot'
import type { ExecPlan } from './executor'

/** Pure: assemble the per-turn context sent to /api/help/agent. */
export function buildAgentContext(
  route: string,
  descriptors: ActionDescriptor[],
  state: Record<string, unknown>,
): AgentContext {
  return { route, availableActions: descriptors, state }
}

/** Pure: a short human line for the on-screen action log. */
export function logLine(plan: ExecPlan): string {
  switch (plan.kind) {
    case 'run': return `✓ ${plan.name}${argsSuffix(plan.args)}`
    case 'confirm': return `⏸ awaiting confirm: ${plan.summary}`
    case 'refuse': return `✕ refused: ${plan.reason}`
    case 'ask': return '… asked the recruiter'
  }
}
function argsSuffix(args: Record<string, unknown>): string {
  const keys = Object.keys(args)
  return keys.length ? ` (${keys.map((k) => `${k}=${String(args[k])}`).join(', ')})` : ''
}
```

- [ ] **Step 4: Add `helpApi.agent` to `src/lib/api.ts`**

Add the import to the existing `@shared/…` imports (or a new line): `import type { AgentRequest, AgentDecision } from '@shared/autopilot'`. Add near the other api objects:
```ts
export const helpApi = {
  agent: (body: AgentRequest) => http<AgentDecision>('/help/agent', { method: 'POST', body: JSON.stringify(body) }),
}
```
(If a `helpApi` already exists, add `agent` to it instead of redefining.)

- [ ] **Step 5: Run → PASS + build** — `npx tsx …/context.test.ts` (PASS); `npm run build` (exit 0).

- [ ] **Step 6: Commit**
```bash
git add src/lib/api.ts src/features/guide/autopilot/context.ts src/features/guide/autopilot/context.test.ts
git commit -m "feat(autopilot): client agent api + pure context/log helpers"
```

---

## Task 2: Client runner loop (`useAutopilotRunner.ts`)

**Files:** CREATE `src/features/guide/autopilot/useAutopilotRunner.ts`.

**Interfaces:**
- Consumes: `helpApi.agent`; `planExecution` + `ExecPlan` (`./executor`); `useAutopilotRegistry` + `listDescriptors`/`snapshotState`/`findAction` (`./registry`); `buildAgentContext`/`logLine` (`./context`); `useNavigate`/`useLocation` (react-router).
- Produces: `useAutopilotRunner()` → `{ runTurn(userText, history): Promise<TurnResult>, pendingConfirm, confirm(), cancelConfirm(), log }` where a side-effect action parks in `pendingConfirm` until `confirm()` runs it. `TurnResult = { say: string; awaiting: boolean }`.

- [ ] **Step 1: Implement `src/features/guide/autopilot/useAutopilotRunner.ts`**

```ts
import { useCallback, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { helpApi } from '@/lib/api'
import type { AgentDecision } from '@shared/autopilot'
import { planExecution, type ExecPlan } from './executor'
import { useAutopilotRegistry, listDescriptors, snapshotState, findAction } from './registry'
import { buildAgentContext, logLine } from './context'

const MAX_STEPS = 8
type Msg = { role: 'user' | 'assistant'; content: string }
export interface TurnResult { say: string; awaiting: boolean }
export interface PendingConfirm { name: string; args: Record<string, unknown>; summary: string }

export function useAutopilotRunner() {
  const navigate = useNavigate()
  const [log, setLog] = useState<string[]>([])
  const [pendingConfirm, setPendingConfirm] = useState<PendingConfirm | null>(null)
  const pushLog = (line: string) => setLog((l) => [...l, line])

  // navigation is an action too: register it here (the panel is inside the Router).
  const navRef = useRef(navigate)
  navRef.current = navigate

  const runOne = async (name: string, args: Record<string, unknown>) => {
    if (name === 'global.navigate' && typeof args.path === 'string') { navRef.current(args.path); return }
    const action = findAction(useAutopilotRegistry.getState(), name)
    if (action) await action.run(args)
  }

  const runTurn = useCallback(async (userText: string, history: Msg[]): Promise<TurnResult> => {
    const messages: Msg[] = [...history, { role: 'user', content: userText }]
    let lastSay = ''
    for (let i = 0; i < MAX_STEPS; i++) {
      const reg = useAutopilotRegistry.getState()
      const ctx = buildAgentContext(window.location.pathname, listDescriptors(reg), snapshotState(reg))
      let decision: AgentDecision
      try { decision = await helpApi.agent({ messages, context: ctx }) }
      catch { return { say: 'Sorry — I could not reach Autopilot. Please try again.', awaiting: true } }
      lastSay = decision.say || lastSay
      const plan: ExecPlan = planExecution(decision, ctx.availableActions)
      pushLog(logLine(plan))
      messages.push({ role: 'assistant', content: decision.say || '' })

      if (plan.kind === 'ask') return { say: decision.say, awaiting: true }
      if (plan.kind === 'refuse') {
        // tell the model why and let it re-ask on the NEXT user turn (avoid tight loops)
        messages.push({ role: 'user', content: `That action was refused: ${plan.reason}. Ask me for what you need.` })
        continue
      }
      if (plan.kind === 'confirm') {
        setPendingConfirm({ name: plan.name, args: plan.args, summary: plan.summary })
        return { say: decision.say, awaiting: true }
      }
      // plan.kind === 'run'
      await runOne(plan.name, plan.args)
      // let the loop re-read the new state and decide the next step; stop if the
      // model already said it's waiting for the recruiter.
      if (decision.awaitingUser) return { say: decision.say, awaiting: true }
      // give React a tick so the just-run setter is reflected in getState()
      await new Promise((r) => setTimeout(r, 0))
    }
    return { say: lastSay || 'Done for now.', awaiting: true }
  }, [])

  const confirm = useCallback(async () => {
    const pc = pendingConfirm
    if (!pc) return
    setPendingConfirm(null)
    pushLog(`✓ confirmed: ${pc.name}`)
    await runOne(pc.name, pc.args)
  }, [pendingConfirm])

  const cancelConfirm = useCallback(() => { if (pendingConfirm) { pushLog('✕ cancelled'); setPendingConfirm(null) } }, [pendingConfirm])

  return { runTurn, pendingConfirm, confirm, cancelConfirm, log, clearLog: () => setLog([]) }
}
```
Note: `runOne` calls `findAction(useAutopilotRegistry.getState(), name)` — reading the store imperatively (not via hook) so it always sees the latest registration. `global.navigate` is special-cased to the panel's `useNavigate`. Verify `react-router-dom`'s `useNavigate` import path matches the app (it does — used across `src/features/recruiter/*`). The `setTimeout(0)` gives React a tick so a just-run `setState` shows up in the next `getState()` snapshot; if the wizard's `getState` reads a ref (Task 3), this is belt-and-suspenders.

- [ ] **Step 2: Build** — `npm run build` (exit 0). (No unit test — the loop is impure/React; its pure inputs `planExecution`/`buildAgentContext`/`logLine` are already tested. Verified end-to-end in Task 4's manual walkthrough.)

- [ ] **Step 3: Commit**
```bash
git add src/features/guide/autopilot/useAutopilotRunner.ts
git commit -m "feat(autopilot): client runner loop (agent turn -> planExecution -> run/confirm/ask)"
```

---

## Task 3: Instrument `InviteWizard` (additive)

**Files:** MODIFY `src/features/recruiter/InviteWizard.tsx`.

**Interfaces:** registers `useAutopilotActions('setup', defs, { getState })` exposing the wizard's real setters. No state/logic change.

- [ ] **Step 1: Add a live state ref + two tiny helpers (near the other handlers)**

```ts
// Autopilot reads the LATEST wizard state through this ref (registered once).
const apStateRef = useRef({ step, setupType, mode, role, source, selectedSetId, candidates, cfg })
apStateRef.current = { step, setupType, mode, role, source, selectedSetId, candidates, cfg }

// Add a candidate by explicit email/role (Autopilot path; mirrors addManual's dedupe).
const addCandidateDirect = (email: string, r: string) => {
  const e = email.trim().toLowerCase()
  if (!e) return
  setCandidates((cs) => (cs.some((c) => c.email.toLowerCase() === e) ? cs : [...cs, { id: crypto.randomUUID(), email: email.trim(), role: (r || role).trim() }]))
}
// Advance only if the current step is valid (else no-op; Autopilot re-reads state and asks).
const guardedNext = () => {
  const s = apStateRef.current
  const ok = s.step === 1 ? step1Valid : s.step === 2 ? (s.setupType === 'multi' ? step2ValidMulti : step2Valid) : true
  if (ok) setStep((n) => Math.min(n + 1, STEPS.length))
}
```
(Names `step1Valid`/`step2Valid`/`step2ValidMulti`/`STEPS`/`setStep`/`setCandidates` etc. already exist — verify against the current file and adjust if a name differs.)

- [ ] **Step 2: Register the actions (once) via `useAutopilotActions`**

Import: `import { useAutopilotActions } from '@/features/guide/autopilot/registry'`. Add near the top of the component body (after the helpers), with a **memoized** defs object so it registers once:

```ts
const apActions = useMemo(() => ({
  setInterviewType: { description: 'Choose Single Interview or Multiple Rounds', params: [{ name: 'type', type: 'enum' as const, enum: ['single', 'multi'], required: true }], run: (a: any) => setSetupType(a.type) },
  selectMode: { description: 'Select the interview mode', params: [{ name: 'mode', type: 'enum' as const, enum: MODES.map((m) => m.value), required: true }], run: (a: any) => setMode(a.mode) },
  setRole: { description: 'Set the candidate role/title', params: [{ name: 'role', type: 'string' as const, required: true }], run: (a: any) => setRole(a.role) },
  setQuestionSource: { description: 'Choose question source: tailor (adaptive) or set (a saved question set)', params: [{ name: 'source', type: 'enum' as const, enum: ['tailor', 'set'], required: true }], run: (a: any) => setSource(a.source) },
  selectQuestionSet: { description: 'Pick a saved question set by id', params: [{ name: 'id', type: 'string' as const, required: true }], run: (a: any) => setSelectedSetId(a.id) },
  addCandidate: { description: 'Add a candidate by email', params: [{ name: 'email', type: 'string' as const, required: true }, { name: 'role', type: 'string' as const }], run: (a: any) => addCandidateDirect(a.email, a.role) },
  nextStep: { description: 'Advance to the next step (only if the current step is complete)', params: [], run: () => guardedNext() },
  backStep: { description: 'Go back one step', params: [], run: () => setStep((n) => Math.max(1, n - 1)) },
  createInvites: { description: 'Create and SEND the invites for the added candidates', sideEffect: true, params: [], run: () => { void submit() } },
  // eslint-disable-next-line react-hooks/exhaustive-deps
}), [])

useAutopilotActions('setup', apActions, {
  getState: () => {
    const s = apStateRef.current
    return {
      step: s.step, interviewType: s.setupType, mode: s.mode, role: s.role,
      questionSource: s.source, questionSetId: s.selectedSetId,
      candidateCount: s.candidates.length, candidates: s.candidates.map((c) => c.email),
      stepName: ['', 'Basics', 'Questions', 'Candidates', 'Invite email', 'Review'][s.step] ?? '',
    }
  },
})
```
Because every `run` uses stable setters (or reads `apStateRef`), the memoized `apActions` is created once → registers once → unregisters on unmount. Confirm `MODES` is in scope (it's the module-level array in this file). Confirm `useMemo`/`useRef` are imported.

- [ ] **Step 3: Build + type-check + commit**

`npm run build` (exit 0); `npx tsc -p server/tsconfig.json --noEmit` (exit 0, unaffected).
```bash
git add src/features/recruiter/InviteWizard.tsx
git commit -m "feat(autopilot): expose InviteWizard setup actions to Autopilot (additive)"
```

---

## Task 4: Autopilot panel UX in `MimicGuide.tsx` + `global.navigate`

**Files:** MODIFY `src/features/guide/MimicGuide.tsx`.

**Interfaces:** adds an Autopilot toggle; when ON, the composer routes through `useAutopilotRunner().runTurn`; renders step tracker (from `snapshotState`), action log, and the read-back confirm card. Registers `global.navigate`.

- [ ] **Step 1: Wire the runner + an Autopilot toggle**

Imports:
```ts
import { useAutopilotRunner } from './autopilot/useAutopilotRunner'
import { useAutopilotActions, useAutopilotRegistry, snapshotState } from './autopilot/registry'
```
State + runner (in the component body):
```ts
const [autopilot, setAutopilot] = useState(false)
const runner = useAutopilotRunner()
// Register navigation as a global action while the panel is mounted.
useAutopilotActions('global', useMemo(() => ({
  navigate: { description: 'Go to a TalbotIQ page (e.g. /sessions/new, /pipelines, /analytics)', params: [{ name: 'path', type: 'string' as const, required: true }], run: () => {} /* handled by the runner’s navigate */ },
}), []))
```
Note: navigation is executed inside the runner (it holds `useNavigate`); the registry entry exists only so the descriptor is offered to the model. The runner special-cases `global.navigate`. (Alternatively register the real `navigate` here and drop the runner special-case — pick one; the plan's runner special-cases it, so this descriptor's `run` is a no-op placeholder.)

- [ ] **Step 2: Route the composer through the runner when Autopilot is ON**

In `send(raw)` (or a wrapper the composer calls), branch:
```ts
const submitComposer = async (raw: string) => {
  const content = raw.trim(); if (!content || pending) return
  if (!autopilot) { send(content); return }               // existing guide path, unchanged
  setMessages((m) => [...m, { role: 'user', content }])
  setDraft(''); setPending(true)
  const history = messages.map((m) => ({ role: m.role, content: m.content }))
  const res = await runner.runTurn(content, history)
  setMessages((m) => [...m, { role: 'assistant', content: res.say }])
  setPending(false)
}
```
Point the textarea's submit (Enter / send button) at `submitComposer` when `autopilot`, else the existing `send`. Keep `send` and `/api/help/chat` untouched for the guide path.

- [ ] **Step 3: Render the Autopilot toggle, step tracker, action log, confirm card**

In the header controls row, add a toggle (reuse the existing pill/button style) that flips `autopilot`. When `autopilot`:
- **Step tracker:** read `snapshotState(useAutopilotRegistry())` — if `stepName`/`step` present, show `Task: Set up an interview · Step {step}/5 — {stepName}` (only when on `/sessions/new`; otherwise a generic "Ready — tell me what to do").
- **Action log:** render `runner.log` as a small scrollable list under the messages (monospace, dim).
- **Read-back confirm card:** when `runner.pendingConfirm`, render a prominent card with `pendingConfirm.summary` + **Confirm** (`runner.confirm()`) and **Cancel** (`runner.cancelConfirm()`) buttons. This is the ONLY path that runs a side-effect action.

Keep the mic + `VoiceLangSelect` visible (voice wiring is Plan 3; the mic still dictates into the draft for now). A one-line helper text when Autopilot is on: "Type what you want — e.g. 'set up a video interview for Senior Backend Engineer'."

- [ ] **Step 4: Build + manual walkthrough + commit**

`npm run build` (exit 0). Manual (dev server): open the guide → toggle **Autopilot** on → type "set up an interview". Expect: it navigates to `/sessions/new` (if not there), asks/【fills】interview type → mode → role → question source/set, advancing steps as you answer, one field at a time; add a candidate by saying/typing an email; when you ask to create invites, a **read-back confirm card** appears — nothing sends until you click Confirm; on Confirm the existing invite flow runs. Also verify Autopilot OFF = the plain guide, unchanged; and an out-of-scope ask ("what's the weather") → polite redirect.
```bash
git add src/features/guide/MimicGuide.tsx
git commit -m "feat(autopilot): panel UX — toggle, step tracker, action log, read-back confirm; guided setup end-to-end (typed)"
```

---

## Self-review notes (author)

- **Spec coverage (guided-typed slice):** the loop (build context → agent → planExecution → run/confirm/ask, cap 8) = Task 2; the wizard becomes drivable (setters as registered actions + live `getState`) = Task 3; the panel UX (toggle, step tracker, action log, read-back confirm) + composer routing = Task 4; navigation action = Task 4. Voice I/O, one-shot polish, and interrupt/correct/take-over are **Plan 3**.
- **Additive:** `InviteWizard` state/logic unchanged (only a ref + 2 helpers + a registration); the guide's `send`/`/api/help/chat` path untouched (Autopilot is a toggle). `createInvites` routes through the existing `submit()` (auth-gated invite path) and ONLY after the read-back Confirm.
- **Safety:** every executed action goes through `planExecution` (whitelist + arg-validate); side-effects park in `pendingConfirm` and require an explicit click; the action log shows everything on-screen.
- **Testability:** pure helpers (`buildAgentContext`, `logLine`, and Plan 1's `planExecution`/`validateArgs`/`normalizeDecision`) are tsx-tested; the React loop + wizard hook + panel are build-verified + the documented manual walkthrough (no browser harness, per repo convention).
- **Verify against the current files:** InviteWizard setter names (`setSetupType`/`setMode`/`setRole`/`setSource`/`setSelectedSetId`/`setStep`/`setCandidates`/`submit`), `MODES`, and the validity flags (`step1Valid`/`step2Valid`/`step2ValidMulti`) — the tasks say to confirm and adjust if any differ.
- **Follow-ups (Plan 3):** push-to-talk mic → `runTurn` + speaking each `say` via `speakSmart`; one-shot multi-param; interrupt/correct/go-back/take-over; optional server-persisted audit.
