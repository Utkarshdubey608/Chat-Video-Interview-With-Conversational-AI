/**
 * Keeps the runbook honest: every env var render.yaml declares must be
 * documented, and the manual console steps must be present.
 * Run with:  npx tsx server/deploy.docs.test.ts
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.join(here, '..')
const REPO = path.join(ROOT, '..')

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

const docPath = path.join(ROOT, 'docs', 'DEPLOY-VERCEL-RENDER.md')
assert('runbook exists', fs.existsSync(docPath), docPath)
const doc = fs.existsSync(docPath) ? fs.readFileSync(docPath, 'utf8') : ''

console.log('\n=== every render.yaml env var is documented ===')
const yaml = fs.readFileSync(path.join(REPO, 'render.yaml'), 'utf8')
const keys = [...yaml.matchAll(/key:\s*([A-Z0-9_]+)/g)].map((m) => m[1])
assert('render.yaml declares env vars', keys.length > 15, `found ${keys.length}`)
for (const k of keys) assert(`documented: ${k}`, doc.includes(k))

console.log('\n=== client-side vars documented ===')
for (const k of ['VITE_API_BASE', 'VITE_FIREBASE_API_KEY', 'VITE_FIREBASE_PROJECT_ID']) {
  assert(`documented: ${k}`, doc.includes(k))
}

console.log('\n=== .env.example covers the new deployment vars ===')
const envExample = fs.readFileSync(path.join(ROOT, '.env.example'), 'utf8')
for (const k of ['DATA_DIR', 'CORS_ORIGINS']) {
  assert(`.env.example mentions ${k}`, envExample.includes(k))
}

console.log('\n=== manual console steps are called out ===')
assert('Firebase authorized-domains step', /[Aa]uthorized domains/.test(doc))
assert('warns the free tier has no disk', /free tier/i.test(doc))
assert('documents the health check', doc.includes('/api/health'))
assert('states the deploy order (Render before Vercel)', /Render first|Deploy Render|Step 1/.test(doc))

console.log(`\n${failures === 0 ? '✅ ALL DEPLOY-DOC TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
