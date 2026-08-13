/**
 * Runs every *.test.ts in the repo through tsx, then the deployment gates.
 * Usage:  npm test
 */
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'

const ROOT = path.resolve(import.meta.dirname, '..')
// Invoke tsx's CLI with this same node binary rather than going through `npx`
// in a shell — no shell means no arg-escaping issues on paths with spaces, and
// no DEP0190 deprecation warning.
const TSX_CLI = path.join(ROOT, 'node_modules', 'tsx', 'dist', 'cli.mjs')

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name === 'dist' || e.name.startsWith('.')) continue
    const full = path.join(dir, e.name)
    if (e.isDirectory()) walk(full, out)
    else if (e.name.endsWith('.test.ts')) out.push(full)
  }
  return out
}

const tests = walk(ROOT).sort()
console.log(`Running ${tests.length} test file(s)\n`)

const failed = []
for (const t of tests) {
  const rel = path.relative(ROOT, t).replace(/\\/g, '/')
  try {
    execFileSync(process.execPath, [TSX_CLI, rel], { cwd: ROOT, stdio: 'pipe' })
    console.log(`  ✅ ${rel}`)
  } catch (err) {
    console.log(`  ❌ ${rel}`)
    console.log(String(err.stdout ?? '').split('\n').filter((l) => l.includes('FAIL')).join('\n'))
    failed.push(rel)
  }
}

if (failed.length) {
  console.log(`\n❌ ${failed.length} test file(s) failed:\n${failed.map((f) => `   ${f}`).join('\n')}`)
  process.exit(1)
}
console.log('\n✅ All test files passed')
