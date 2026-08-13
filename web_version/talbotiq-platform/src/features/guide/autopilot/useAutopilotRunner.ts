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
    if (name === 'global.navigate' && typeof args.path === 'string') {
      // Already on that route → treat as success (prevents navigate loops).
      if (window.location.pathname !== args.path) navRef.current(args.path)
      return
    }
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
      // Send only the recent, non-empty tail — the full session history grows
      // unbounded and the server caps messages; a long chat used to 400 EVERY
      // turn from then on, permanently bricking Autopilot.
      const recent = messages.filter((m) => m.content.trim()).slice(-24)
      try { decision = await helpApi.agent({ messages: recent, context: ctx }) }
      catch { return { say: 'Sorry — I could not reach Autopilot. Please try again.', awaiting: true } }
      lastSay = decision.say || lastSay
      const plan: ExecPlan = planExecution(decision, ctx.availableActions)
      pushLog(logLine(plan))
      messages.push({ role: 'assistant', content: decision.say || 'Done.' }) // never an EMPTY turn (would fail validation later)

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
