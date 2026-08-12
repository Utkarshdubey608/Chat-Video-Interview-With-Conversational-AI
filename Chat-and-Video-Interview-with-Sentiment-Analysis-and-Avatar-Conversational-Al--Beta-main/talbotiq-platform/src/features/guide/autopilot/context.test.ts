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
