/**
 * Static checks on the deployment build config. Docker itself is not run here —
 * these assert the properties that silently break a Render deploy.
 * Run with:  npx tsx server/docker.config.test.ts
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.join(here, '..')

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8')) as {
  dependencies?: Record<string, string>
  devDependencies?: Record<string, string>
  engines?: { node?: string }
}

console.log('\n=== package.json ===')
assert('tsx is a runtime dependency', Boolean(pkg.dependencies?.tsx), 'it runs the server in prod')
assert('tsx is NOT also a devDependency', !pkg.devDependencies?.tsx, 'duplicate entries drift')
assert('engines.node pinned to 20.x', pkg.engines?.node === '20.x', String(pkg.engines?.node))

console.log('\n=== .dockerignore placement ===')
assert('.dockerignore at build-context root', fs.existsSync(path.join(ROOT, '.dockerignore')))
assert('no stale server/.dockerignore', !fs.existsSync(path.join(ROOT, 'server', '.dockerignore')), 'Docker never reads it there')

const ignore = fs.readFileSync(path.join(ROOT, '.dockerignore'), 'utf8')
for (const entry of ['node_modules', 'dist', '.env', 'server/data']) {
  assert(`.dockerignore excludes ${entry}`, new RegExp(`^${entry.replace('.', '\\.')}\\s*$`, 'm').test(ignore))
}

console.log('\n=== Dockerfile ===')
const df = fs.readFileSync(path.join(ROOT, 'server', 'Dockerfile'), 'utf8')
assert('pins node:20', /^FROM node:20/m.test(df))
assert('no `|| npm install` lockfile-drift fallback', !/\|\|\s*npm install/.test(df))
assert('uses npm ci', /npm ci/.test(df))
assert('no stray `npm install tsx` layer', !/npm install tsx/.test(df))
assert('copies shared/', /COPY shared/.test(df))
assert('copies server/', /COPY server/.test(df))
assert('copies tsconfig.json', /COPY tsconfig\.json/.test(df))
assert('presets DATA_DIR', /ENV DATA_DIR=/.test(df))
assert('runs as non-root', /^USER node$/m.test(df))
assert('entrypoint runs the server', /CMD \[.*tsx.*server\/index\.ts.*\]/.test(df))

console.log(`\n${failures === 0 ? '✅ ALL DOCKER-CONFIG TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
