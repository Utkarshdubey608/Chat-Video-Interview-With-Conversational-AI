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
