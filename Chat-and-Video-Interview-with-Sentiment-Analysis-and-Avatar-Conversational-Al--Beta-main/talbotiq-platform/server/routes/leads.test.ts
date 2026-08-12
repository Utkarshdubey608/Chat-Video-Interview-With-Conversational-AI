/** Run: npx tsx server/routes/leads.test.ts */
import { buildLead } from './leads'

let failures = 0
function assert(label: string, cond: boolean) { console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}`); if (!cond) failures++ }

const now = '2026-07-28T10:00:00.000Z'
const lead = buildLead(
  { firstName: '  Dana ', lastName: 'Whitfield', email: '  Dana@Company.COM ', hiresPerYear: '500–2,000' },
  'id-1', now,
)
assert('trims first name', lead.firstName === 'Dana')
assert('keeps last name', lead.lastName === 'Whitfield')
assert('lowercases + trims email', lead.email === 'dana@company.com')
assert('keeps hiresPerYear', lead.hiresPerYear === '500–2,000')
assert('defaults source when absent', lead.source === 'mimic-site')
assert('stamps id + createdAt', lead.id === 'id-1' && lead.createdAt === now)

const withSource = buildLead(
  { firstName: 'A', lastName: 'B', email: 'a@b.co', hiresPerYear: '10', source: 'campaign-x' },
  'id-2', now,
)
assert('keeps provided source', withSource.source === 'campaign-x')

console.log(`\n${failures === 0 ? '✅ ALL LEADS TESTS PASSED' : `❌ ${failures} FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
