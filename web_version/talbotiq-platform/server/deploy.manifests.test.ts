/**
 * Structural checks on render.yaml and vercel.json. Catches the mistakes that
 * only surface as a failed cloud deploy. Run with:
 *   npx tsx server/deploy.manifests.test.ts
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const REPO = path.join(here, '..', '..')

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

console.log('\n=== render.yaml ===')
const renderPath = path.join(REPO, 'render.yaml')
assert('render.yaml exists at repo root', fs.existsSync(renderPath), renderPath)
const yaml = fs.existsSync(renderPath) ? fs.readFileSync(renderPath, 'utf8') : ''
assert('declares a web service', /type:\s*web/.test(yaml))
assert('uses the docker runtime', /runtime:\s*docker/.test(yaml))
assert('root dir is talbotiq-platform', /rootDir:\s*talbotiq-platform/.test(yaml))
assert('points at server/Dockerfile', /dockerfilePath:\s*\.\/server\/Dockerfile/.test(yaml))
assert('health check path set', /healthCheckPath:\s*\/api\/health/.test(yaml))
assert('mounts a disk at /var/data', /mountPath:\s*\/var\/data/.test(yaml))
assert('presets DATA_DIR', /key:\s*DATA_DIR/.test(yaml))
assert('declares CORS_ORIGINS', /key:\s*CORS_ORIGINS/.test(yaml))
// Secrets must be prompted for, never committed.
for (const key of ['GEMINI_API_KEY', 'FIREBASE_PRIVATE_KEY', 'DEEPGRAM_API_KEY', 'DAILY_API_KEY', 'SMTP_PASS']) {
  assert(`${key} declared`, new RegExp(`key:\\s*${key}`).test(yaml))
}
assert('no literal API-key value committed', !/AIza[0-9A-Za-z_-]{10,}/.test(yaml))
const syncFalseCount = (yaml.match(/sync:\s*false/g) ?? []).length
assert('secrets use sync:false (prompted, not stored)', syncFalseCount >= 10, `found ${syncFalseCount}`)

console.log('\n=== vercel.json ===')
const vercelPath = path.join(REPO, 'vercel.json')
assert('vercel.json exists at repo root', fs.existsSync(vercelPath), vercelPath)
let vercel: Record<string, unknown> = {}
try {
  vercel = JSON.parse(fs.readFileSync(vercelPath, 'utf8')) as Record<string, unknown>
  assert('vercel.json is valid JSON', true)
} catch (err) {
  assert('vercel.json is valid JSON', false, String(err))
}
assert('outputDirectory points into talbotiq-platform', vercel.outputDirectory === 'talbotiq-platform/dist')
assert('buildCommand builds the SPA', typeof vercel.buildCommand === 'string' && /npm run build/.test(vercel.buildCommand as string))
const rewrites = (vercel.rewrites ?? []) as Array<{ source: string; destination: string }>
assert('has an SPA fallback rewrite', rewrites.some((r) => r.destination === '/index.html'))
// A rewrite of /api would defeat the whole design: WebSockets cannot traverse
// it and uploads would hit Vercel's 4.5 MB body cap (multer allows 25 MB).
assert('does NOT proxy /api through Vercel', !rewrites.some((r) => r.source.startsWith('/api')))

console.log(`\n${failures === 0 ? '✅ ALL MANIFEST TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
