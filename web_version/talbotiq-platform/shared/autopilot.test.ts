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
