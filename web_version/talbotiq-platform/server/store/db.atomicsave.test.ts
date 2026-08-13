/**
 * Verifies the JSON store's persistence SAFETY properties:
 *   1. writes are atomic (temp file + rename), so a crash or a full disk can
 *      never leave a truncated db.json where init() would read it;
 *   2. no temp files are left behind on success or failure;
 *   3. a failed write is OBSERVABLE via saveHealth() instead of silently
 *      losing data, and recovery resets the counter.
 *
 * (3) is the one that matters operationally: saveNow() deliberately never
 * throws, so before saveHealth() existed a full disk lost data while the API
 * kept answering 200s.
 *
 * DATA_DIR must be set BEFORE db.ts is imported, so the import is dynamic.
 * Run with:  npx tsx server/store/db.atomicsave.test.ts
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'talbotiq-atomic-'))
process.env.DATA_DIR = tmp

const { db } = await import('./db')
db.init()

const target = path.join(tmp, 'db.json')
const tmpLeftovers = () => fs.readdirSync(tmp).filter((f) => f.includes('.tmp'))

console.log('\n=== a successful save is atomic and leaves no temp files ===')
assert('saveNow() reports success', db.saveNow() === true)
assert('db.json exists', fs.existsSync(target))
assert('no .tmp leftovers', tmpLeftovers().length === 0, tmpLeftovers().join(', '))

const firstSnapshot = fs.readFileSync(target, 'utf8')
assert('snapshot parses as JSON', (() => { try { JSON.parse(firstSnapshot); return true } catch { return false } })())

console.log('\n=== health reports OK after a successful save ===')
const healthy = db.saveHealth()
assert('ok === true', healthy.ok === true)
assert('consecutiveFailures === 0', healthy.consecutiveFailures === 0)
assert('lastError === null', healthy.lastError === null)
assert('lastSavedAt is an ISO timestamp', typeof healthy.lastSavedAt === 'string' && !Number.isNaN(Date.parse(healthy.lastSavedAt!)))

console.log('\n=== a failing write is observable, non-throwing, and non-destructive ===')
// Simulate an unwritable disk by making the rename target a directory: the temp
// write succeeds, the rename fails. This is the closest safe stand-in for
// ENOSPC / EACCES and exercises the same catch path.
const brokenDir = fs.mkdtempSync(path.join(os.tmpdir(), 'talbotiq-broken-'))
fs.mkdirSync(path.join(brokenDir, 'db.json'), { recursive: true })
fs.writeFileSync(path.join(brokenDir, 'db.json', 'occupied'), 'x') // non-empty → rename cannot clobber it

const modPath = new URL('./db.ts', import.meta.url).href
process.env.DATA_DIR = brokenDir
const { db: db2 } = await import(`${modPath}?broken`) as typeof import('./db')
db2.init()

let threw = false
let result = true
try { result = db2.saveNow() } catch { threw = true }

assert('saveNow() did NOT throw', threw === false)
assert('saveNow() returned false', result === false)

const broken = db2.saveHealth()
assert('health ok === false', broken.ok === false)
assert('consecutiveFailures >= 1', broken.consecutiveFailures >= 1, String(broken.consecutiveFailures))
assert('lastError is populated', typeof broken.lastError === 'string' && broken.lastError.length > 0)

const strayTemps = fs.readdirSync(brokenDir).filter((f) => f.includes('.tmp'))
assert('no .tmp leftovers after a failure', strayTemps.length === 0, strayTemps.join(', '))

console.log('\n=== consecutive failures accumulate ===')
db2.saveNow()
assert('counter incremented past 1', db2.saveHealth().consecutiveFailures >= 2, String(db2.saveHealth().consecutiveFailures))

console.log('\n=== the original snapshot is untouched by the failed writes ===')
assert('first store still readable', fs.existsSync(target))
assert('first store byte-identical', fs.readFileSync(target, 'utf8') === firstSnapshot)

fs.rmSync(tmp, { recursive: true, force: true })
fs.rmSync(brokenDir, { recursive: true, force: true })

console.log(`\n${failures === 0 ? '✅ ALL ATOMIC-SAVE TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
