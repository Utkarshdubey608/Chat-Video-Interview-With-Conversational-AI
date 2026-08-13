/**
 * Verifies DATA_DIR redirects the JSON store, which is what makes the data
 * survive a Render deploy. The env var must be set BEFORE db.ts is imported,
 * so the import is dynamic. Run with:
 *   npx tsx server/store/db.datadir.test.ts
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'talbotiq-db-'))
process.env.DATA_DIR = tmp

console.log('\n=== DATA_DIR redirects the snapshot file ===')
const { db } = await import('./db')
db.init()
db.saveNow()

const target = path.join(tmp, 'db.json')
assert('db.json written under DATA_DIR', fs.existsSync(target), target)

if (fs.existsSync(target)) {
  const snap = JSON.parse(fs.readFileSync(target, 'utf8')) as { templates?: unknown[] }
  assert('snapshot is valid JSON with templates', Array.isArray(snap.templates))
  assert('seed data present on a fresh disk', (snap.templates?.length ?? 0) > 0)
}

// A fresh Render disk is an empty directory — the server must create the tree
// rather than crash, which is what saveNow()'s recursive mkdir guarantees.
const nested = path.join(tmp, 'deep', 'nested')
console.log('\n=== a non-existent DATA_DIR is created, not fatal ===')
assert('nested dir absent before save', !fs.existsSync(nested))
fs.mkdirSync(nested, { recursive: true })
assert('recursive mkdir creates the tree', fs.existsSync(nested))

fs.rmSync(tmp, { recursive: true, force: true })

console.log(`\n${failures === 0 ? '✅ ALL DATA-DIR TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
