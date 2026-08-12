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
