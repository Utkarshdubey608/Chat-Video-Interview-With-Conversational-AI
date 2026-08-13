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
