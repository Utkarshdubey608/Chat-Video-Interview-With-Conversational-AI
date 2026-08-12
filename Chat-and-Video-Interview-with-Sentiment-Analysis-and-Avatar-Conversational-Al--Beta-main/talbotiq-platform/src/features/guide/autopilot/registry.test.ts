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
