# Vercel + Render Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the repository deployable as-is — the Vite SPA on Vercel, the Express API on Render — so a deployment team can ship without reading source.

**Architecture:** The SPA is static on Vercel and calls the Render API directly over HTTPS and WSS, addressed by a single `VITE_API_BASE` env var. Nothing proxies through Vercel. On Render, the existing JSON store is redirected onto a mounted Persistent Disk via a new `DATA_DIR` env var. Blank env vars reproduce today's behaviour exactly, so local `npm run dev` is untouched.

**Tech Stack:** Vite 5 + React 18 + TypeScript, Express 4 on Node 20 run through `tsx`, `ws` for WebSockets, Docker, Render Blueprint (`render.yaml`), Vercel static hosting.

## Global Constraints

- All work happens inside `talbotiq-platform/` unless a path says otherwise. `render.yaml` and `vercel.json` go at the **repository root** (one level above `talbotiq-platform/`).
- **Never hard-code a hostname.** Every origin comes from an env var.
- **Blank env var == today's behaviour.** `VITE_API_BASE` blank → same-origin. `DATA_DIR` unset → `server/data`. `CORS_ORIGINS` blank → allow all. This is what protects the dev loop.
- Only `VITE_`-prefixed vars may reach the client bundle; they are public. No other secret may appear in `dist/`.
- **Test convention (this repo has no test framework):** tests are standalone `tsx` scripts using a local `assert` helper, ending with `process.exit(failures === 0 ? 0 : 1)`. Run one with `npx tsx <path>`. Follow this exactly — do **not** add vitest or jest.
- Run every command from `talbotiq-platform/` unless stated otherwise.
- **Shell:** commands are written for **Git Bash** (available on this Windows machine), because several use `grep`, `||`, and `VAR=value cmd` prefixes that PowerShell parses differently. Where a step needs PowerShell it says so inline.
- Node 20 is the target runtime. The local machine runs Node 24; that is fine for building, but `engines` must say `20.x`.

---

### Task 1: `apiOrigin` — the single source of truth for the backend URL

Everything else depends on this. It is pure and fully testable, so it goes first.

**Files:**
- Create: `talbotiq-platform/src/lib/apiOrigin.ts`
- Test: `talbotiq-platform/src/lib/apiOrigin.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces (Tasks 2 relies on these exact names):
  - `resolveHttpBase(apiBase: string | undefined): string`
  - `resolveWsUrl(apiBase: string | undefined, pageProtocol: string, pageHost: string, path: string): string`
  - `httpBase(): string`
  - `wsUrl(path: string): string`

- [ ] **Step 1: Write the failing test**

Create `talbotiq-platform/src/lib/apiOrigin.test.ts`:

```ts
/**
 * Pure-resolver tests for the API origin helper. No DOM, no import.meta.env —
 * only the pure functions are exercised. Run with:
 *   npx tsx src/lib/apiOrigin.test.ts
 */
import { resolveHttpBase, resolveWsUrl } from './apiOrigin'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}
function eq(label: string, actual: string, expected: string) {
  assert(label, actual === expected, actual === expected ? '' : `got "${actual}", want "${expected}"`)
}

console.log('\n=== resolveHttpBase ===')
eq('blank → same-origin /api', resolveHttpBase(''), '/api')
eq('undefined → same-origin /api', resolveHttpBase(undefined), '/api')
eq('whitespace → same-origin /api', resolveHttpBase('   '), '/api')
eq('absolute https base', resolveHttpBase('https://api.example.com'), 'https://api.example.com/api')
eq('trailing slash trimmed', resolveHttpBase('https://api.example.com/'), 'https://api.example.com/api')
eq('many trailing slashes trimmed', resolveHttpBase('https://api.example.com///'), 'https://api.example.com/api')
eq('scheme-less base assumes https', resolveHttpBase('api.example.com'), 'https://api.example.com/api')
eq('http base preserved', resolveHttpBase('http://localhost:8787'), 'http://localhost:8787/api')

console.log('\n=== resolveWsUrl (blank base → same-origin, page protocol decides) ===')
eq('https page → wss', resolveWsUrl('', 'https:', 'app.example.com', '/api/voice/s1'), 'wss://app.example.com/api/voice/s1')
eq('http page → ws', resolveWsUrl('', 'http:', 'localhost:3001', '/api/voice/s1'), 'ws://localhost:3001/api/voice/s1')

console.log('\n=== resolveWsUrl (explicit base → TARGET protocol decides) ===')
eq('https base → wss', resolveWsUrl('https://api.example.com', 'https:', 'app.example.com', '/api/voice/s1'), 'wss://api.example.com/api/voice/s1')
eq('http base → ws', resolveWsUrl('http://localhost:8787', 'http:', 'localhost:3001', '/api/voice/s1'), 'ws://localhost:8787/api/voice/s1')
// The page being http must NOT downgrade an https API base to ws:// — that
// would silently break the Voice Track behind any TLS-terminating proxy.
eq('http page never downgrades https base', resolveWsUrl('https://api.example.com', 'http:', 'x', '/api/voice/s1'), 'wss://api.example.com/api/voice/s1')
eq('scheme-less base assumes wss', resolveWsUrl('api.example.com', 'http:', 'x', '/api/voice/s1'), 'wss://api.example.com/api/voice/s1')
eq('trailing slash on base trimmed', resolveWsUrl('https://api.example.com/', 'https:', 'x', '/api/voice/s1'), 'wss://api.example.com/api/voice/s1')
eq('path without leading slash', resolveWsUrl('https://api.example.com', 'https:', 'x', 'api/voice/s1'), 'wss://api.example.com/api/voice/s1')
eq('query string preserved', resolveWsUrl('https://api.example.com', 'https:', 'x', '/api/avatar/deepgram?token=ab%20c'), 'wss://api.example.com/api/avatar/deepgram?token=ab%20c')

console.log(`\n${failures === 0 ? '✅ ALL API-ORIGIN TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx src/lib/apiOrigin.test.ts`
Expected: FAIL — `Cannot find module './apiOrigin'`.

- [ ] **Step 3: Write minimal implementation**

Create `talbotiq-platform/src/lib/apiOrigin.ts`:

```ts
/**
 * Single source of truth for where the backend lives.
 *
 * Web/dev — VITE_API_BASE is blank, so every URL stays same-origin and the Vite
 * proxy in vite.config.ts keeps serving /api (HTTP and WS) exactly as before.
 * Vercel/Capacitor — VITE_API_BASE points at the Render service
 * (e.g. https://talbotiq-api.onrender.com), producing absolute HTTPS/WSS URLs.
 *
 * VITE_API_BASE is a PUBLIC value (it is inlined into the bundle). It is a URL,
 * never a secret.
 */

/** Trim trailing slashes and default a scheme-less host to https, so a value
 *  like "talbotiq-api.onrender.com" still yields a usable absolute URL.
 *  Returns '' for blank input, which callers read as "use same-origin". */
function normalizeBase(apiBase: string | undefined): string {
  const raw = (apiBase ?? '').trim().replace(/\/+$/, '')
  if (!raw) return ''
  return /^https?:\/\//i.test(raw) ? raw : `https://${raw}`
}

/** Pure core of httpBase(). Exported for tests. */
export function resolveHttpBase(apiBase: string | undefined): string {
  const base = normalizeBase(apiBase)
  return base ? `${base}/api` : '/api'
}

/**
 * Pure core of wsUrl(). Exported for tests.
 *
 * When a base is configured the ws scheme follows the TARGET's protocol, not
 * the page's: an https API base must yield wss, or the browser blocks the
 * connection as mixed content. Only when the base is blank (same-origin) does
 * the page protocol decide.
 */
export function resolveWsUrl(
  apiBase: string | undefined,
  pageProtocol: string,
  pageHost: string,
  path: string,
): string {
  const base = normalizeBase(apiBase)
  const p = path.startsWith('/') ? path : `/${path}`
  if (!base) {
    const proto = pageProtocol === 'https:' ? 'wss' : 'ws'
    return `${proto}://${pageHost}${p}`
  }
  return `${base.replace(/^http:/i, 'ws:').replace(/^https:/i, 'wss:')}${p}`
}

/** Read VITE_API_BASE defensively: import.meta.env is undefined when this
 *  module is imported by a plain-Node (tsx) test, which is how tests run here. */
function envApiBase(): string | undefined {
  return (import.meta as { env?: Record<string, string | undefined> }).env?.VITE_API_BASE
}

/** Base for HTTP calls, e.g. httpBase() + '/sessions'. */
export function httpBase(): string {
  return resolveHttpBase(envApiBase())
}

/** Absolute WebSocket URL for an /api path, e.g. wsUrl('/api/voice/abc'). */
export function wsUrl(path: string): string {
  return resolveWsUrl(envApiBase(), location.protocol, location.host, path)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx tsx src/lib/apiOrigin.test.ts`
Expected: PASS — `✅ ALL API-ORIGIN TESTS PASSED`, exit 0.

- [ ] **Step 5: Verify the typecheck still passes**

Run: `npx tsc --noEmit`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add talbotiq-platform/src/lib/apiOrigin.ts talbotiq-platform/src/lib/apiOrigin.test.ts
git commit -m "feat(deploy): add apiOrigin helper resolving API host from VITE_API_BASE"
```

---

### Task 2: Repoint every client call site at the configured origin

**Files:**
- Modify: `talbotiq-platform/src/lib/api.ts:46`
- Modify: `talbotiq-platform/src/lib/faceCache.ts:10`
- Modify: `talbotiq-platform/src/lib/voiceClient.ts:75-82`
- Modify: `talbotiq-platform/src/hooks/useAudioAnalysis.ts:74-76`
- Modify: `talbotiq-platform/src/hooks/useDeepgramTranscript.ts:37-39`
- Modify: `talbotiq-platform/src/features/interview/useAnswerRecorder.ts:50-53`
- Test: `talbotiq-platform/src/lib/apiOrigin.callsites.test.ts`

**Interfaces:**
- Consumes: `httpBase()` and `wsUrl(path)` from Task 1.
- Produces: no new exports. After this task no file under `src/` builds an API URL from `location.host`.

- [ ] **Step 1: Write the failing test**

This test greps the source, because the alternative — importing React hooks and a live WebSocket — needs a DOM the repo has no harness for. It asserts the *absence* of the same-origin pattern, which is exactly the regression that would silently break production.

Create `talbotiq-platform/src/lib/apiOrigin.callsites.test.ts`:

```ts
/**
 * Guards against a client file addressing the API same-origin again. On a
 * Vercel + Render split those URLs resolve to Vercel, where no API exists.
 * Run with:  npx tsx src/lib/apiOrigin.callsites.test.ts
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const SRC = path.join(here, '..')

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

/** Every .ts/.tsx file under src/, minus this test and the helper it guards. */
function walk(dir: string, out: string[] = []): string[] {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name)
    if (e.isDirectory()) walk(full, out)
    else if (/\.tsx?$/.test(e.name) && !e.name.includes('.test.')) out.push(full)
  }
  return out
}

const files = walk(SRC).filter((f) => path.basename(f) !== 'apiOrigin.ts')

console.log('\n=== no same-origin API URLs remain in src/ ===')
for (const f of files) {
  const body = fs.readFileSync(f, 'utf8')
  const rel = path.relative(SRC, f).replace(/\\/g, '/')
  // A WebSocket URL built from the page host.
  assert(`${rel}: no location.host WS URL`, !/location\.host/.test(body))
  // A literal '/api' base. Individual '/api/...' path fragments passed INTO
  // httpBase()/wsUrl() are fine; a bare base assignment is not.
  assert(`${rel}: no bare '/api' base const`, !/^\s*const\s+BASE\s*=\s*['"]\/api/m.test(body))
}

console.log('\n=== the four WS call sites use wsUrl() ===')
for (const rel of [
  'lib/voiceClient.ts',
  'hooks/useAudioAnalysis.ts',
  'hooks/useDeepgramTranscript.ts',
  'features/interview/useAnswerRecorder.ts',
]) {
  const body = fs.readFileSync(path.join(SRC, rel), 'utf8')
  assert(`${rel} imports wsUrl`, /wsUrl/.test(body))
}

console.log('\n=== the two HTTP base sites use httpBase() ===')
for (const rel of ['lib/api.ts', 'lib/faceCache.ts']) {
  const body = fs.readFileSync(path.join(SRC, rel), 'utf8')
  assert(`${rel} imports httpBase`, /httpBase/.test(body))
}

console.log(`\n${failures === 0 ? '✅ ALL CALL-SITE TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx src/lib/apiOrigin.callsites.test.ts`
Expected: FAIL — several `location.host` and `no bare '/api' base const` assertions fail.

- [ ] **Step 3: Update `src/lib/api.ts`**

Replace line 46 (`const BASE = '/api'`) with a call through the helper. Add the import next to the other `import` lines at the top of the file:

```ts
import { httpBase } from './apiOrigin'
```

Then replace:

```ts
const BASE = '/api'
```

with:

```ts
// Resolved per call, not once at module load: VITE_API_BASE is inlined at build
// time, but reading it lazily keeps this testable and avoids import-order traps.
const BASE = httpBase()
```

- [ ] **Step 4: Update `src/lib/faceCache.ts`**

Add the import at the top of the file:

```ts
import { httpBase } from './apiOrigin'
```

Replace:

```ts
const BASE = '/api/avatar/face-cache'
```

with:

```ts
const BASE = `${httpBase()}/avatar/face-cache`
```

- [ ] **Step 5: Update `src/lib/voiceClient.ts`**

Add the import at the top of the file:

```ts
import { wsUrl } from './apiOrigin'
```

Replace the body of `voiceWsUrl` (lines 75-82) with:

```ts
export async function voiceWsUrl(sessionId: string): Promise<string> {
  // The WS handshake can't carry an Authorization header, so the ID token rides
  // in the query string; the server verifies it and checks session assignment.
  const token = await getIdTokenOrNull()
  const q = token ? `?token=${encodeURIComponent(token)}` : ''
  return wsUrl(`/api/voice/${encodeURIComponent(sessionId)}${q}`)
}
```

Note the now-unused `const proto = ...` line is removed.

- [ ] **Step 6: Update `src/hooks/useAudioAnalysis.ts`**

Add the import alongside the file's other imports:

```ts
import { wsUrl } from '@/lib/apiOrigin'
```

Delete the `const proto = location.protocol === 'https:' ? 'wss' : 'ws'` line (line 74) and replace the `new WebSocket(...)` call on line 76 with:

```ts
        const dgWs = new WebSocket(wsUrl(`/api/avatar/deepgram${dgToken ? `?token=${encodeURIComponent(dgToken)}` : ''}`))
```

- [ ] **Step 7: Update `src/hooks/useDeepgramTranscript.ts`**

Add the import alongside the file's other imports:

```ts
import { wsUrl } from '@/lib/apiOrigin'
```

Delete the `const proto = ...` line (line 37) and replace the `new WebSocket(...)` call on line 39 with:

```ts
        const ws = new WebSocket(wsUrl(`/api/avatar/deepgram${token ? `?token=${encodeURIComponent(token)}` : ''}`))
```

- [ ] **Step 8: Update `src/features/interview/useAnswerRecorder.ts`**

Add the import alongside the file's other imports:

```ts
import { wsUrl } from '@/lib/apiOrigin'
```

Delete the `const proto = ...` line (line 50) and replace the `new WebSocket(...)` call on line 53 with:

```ts
      const ws = new WebSocket(wsUrl(`/api/interview/deepgram${token ? `?token=${encodeURIComponent(token)}` : ''}`))
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `npx tsx src/lib/apiOrigin.callsites.test.ts`
Expected: PASS — `✅ ALL CALL-SITE TESTS PASSED`, exit 0.

- [ ] **Step 10: Verify the typecheck and build still pass**

Run: `npm run build`
Expected: `tsc` emits nothing and `vite build` prints `✓ built in …`. Exit 0.

If `tsc` reports `'proto' is declared but its value is never read`, a `const proto` line was missed — delete it.

- [ ] **Step 11: Commit**

```bash
git add talbotiq-platform/src
git commit -m "feat(deploy): route client HTTP + WebSocket calls through apiOrigin"
```

---

### Task 3: `DATA_DIR` override so the store lands on Render's disk

**Files:**
- Modify: `talbotiq-platform/server/store/db.ts:17-19`
- Test: `talbotiq-platform/server/store/db.datadir.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the `DATA_DIR` env contract that `render.yaml` (Task 6) sets to `/var/data`.

- [ ] **Step 1: Write the failing test**

Create `talbotiq-platform/server/store/db.datadir.test.ts`:

```ts
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
process.env.DATA_DIR = nested
console.log('\n=== a non-existent DATA_DIR is created, not fatal ===')
assert('nested dir absent before save', !fs.existsSync(nested))

fs.rmSync(tmp, { recursive: true, force: true })

console.log(`\n${failures === 0 ? '✅ ALL DATA-DIR TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx server/store/db.datadir.test.ts`
Expected: FAIL — `db.json written under DATA_DIR` fails, because the store still writes to `server/data`.

- [ ] **Step 3: Write minimal implementation**

In `talbotiq-platform/server/store/db.ts`, replace lines 17-19:

```ts
const here = path.dirname(fileURLToPath(import.meta.url))
const DATA_DIR = path.join(here, '..', 'data')
const DATA_FILE = path.join(DATA_DIR, 'db.json')
```

with:

```ts
const here = path.dirname(fileURLToPath(import.meta.url))
// DATA_DIR lets the deployment point the store at durable storage — on Render
// it is the mounted Persistent Disk (/var/data). Unset, this is the original
// server/data path, so local dev is unchanged. Container filesystems are
// ephemeral: without this the snapshot is lost on every deploy and restart.
const DATA_DIR = process.env.DATA_DIR
  ? path.resolve(process.env.DATA_DIR)
  : path.join(here, '..', 'data')
const DATA_FILE = path.join(DATA_DIR, 'db.json')
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx tsx server/store/db.datadir.test.ts`
Expected: PASS — `✅ ALL DATA-DIR TESTS PASSED`, exit 0.

- [ ] **Step 5: Verify local dev still uses the original path**

With `DATA_DIR` unset the store must still resolve to `server/data`, or this
change would have broken every developer's local data.

```bash
rm -f server/data/db.json
npm run server
```

Wait for `[server] TalbotIQ API listening on http://localhost:8787`, then stop it
(Ctrl-C) and check the file came back at the original location:

```bash
ls -l server/data/db.json
```

Expected: the file exists. (Do not use an inline `npx tsx -e` one-liner here —
this module is ESM, so `require` is unavailable inside it.)

- [ ] **Step 6: Commit**

```bash
git add talbotiq-platform/server/store/db.ts talbotiq-platform/server/store/db.datadir.test.ts
git commit -m "feat(deploy): DATA_DIR env override so the store can live on a mounted disk"
```

---

### Task 4: `CORS_ORIGINS` allowlist

**Files:**
- Create: `talbotiq-platform/server/util/cors.ts`
- Modify: `talbotiq-platform/server/index.ts:29`
- Test: `talbotiq-platform/server/util/cors.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `parseAllowedOrigins(raw: string | undefined): string[] | null`
  - `isOriginAllowed(allowed: string[] | null, origin: string | undefined): boolean`

- [ ] **Step 1: Write the failing test**

Create `talbotiq-platform/server/util/cors.test.ts`:

```ts
/**
 * Pure tests for the CORS_ORIGINS allowlist. Run with:
 *   npx tsx server/util/cors.test.ts
 */
import { parseAllowedOrigins, isOriginAllowed } from './cors'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

console.log('\n=== parseAllowedOrigins ===')
assert('unset → null (allow all)', parseAllowedOrigins(undefined) === null)
assert('blank → null (allow all)', parseAllowedOrigins('') === null)
assert('whitespace → null (allow all)', parseAllowedOrigins('   ') === null)
assert('commas only → null', parseAllowedOrigins(' , , ') === null)

const one = parseAllowedOrigins('https://app.vercel.app')
assert('single origin parsed', one?.length === 1 && one[0] === 'https://app.vercel.app')

const many = parseAllowedOrigins(' https://a.vercel.app , https://b.com/ ,https://c.dev ')
assert('multiple parsed, trimmed', many?.length === 3, JSON.stringify(many))
assert('whitespace stripped', many?.[0] === 'https://a.vercel.app')
assert('trailing slash stripped', many?.[1] === 'https://b.com')
assert('no-space entry kept', many?.[2] === 'https://c.dev')

console.log('\n=== isOriginAllowed ===')
assert('null allowlist allows anything', isOriginAllowed(null, 'https://evil.example'))
// A missing Origin header means a non-browser caller: curl, server-to-server,
// health checks, and the Brevo delivery webhook. Blocking those would break
// the webhook, so they are always allowed.
assert('missing origin allowed (webhook/health)', isOriginAllowed(['https://a.com'], undefined))
assert('listed origin allowed', isOriginAllowed(['https://a.com', 'https://b.com'], 'https://b.com'))
assert('unlisted origin rejected', !isOriginAllowed(['https://a.com'], 'https://evil.example'))
assert('trailing slash on request tolerated', isOriginAllowed(['https://a.com'], 'https://a.com/'))
assert('different scheme rejected', !isOriginAllowed(['https://a.com'], 'http://a.com'))
assert('subdomain not implicitly allowed', !isOriginAllowed(['https://a.com'], 'https://sub.a.com'))

console.log(`\n${failures === 0 ? '✅ ALL CORS TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx server/util/cors.test.ts`
Expected: FAIL — `Cannot find module './cors'`.

- [ ] **Step 3: Write minimal implementation**

Create `talbotiq-platform/server/util/cors.ts`:

```ts
/**
 * CORS_ORIGINS allowlist. The frontend is on a different origin (Vercel) from
 * this API (Render), so cross-origin requests are the normal case here.
 *
 * Blank/unset deliberately means "allow every origin" — the behaviour this
 * server had before — so a deployment that forgets the var still works rather
 * than failing in a way that looks like an app bug.
 */

const stripTrailingSlash = (v: string) => v.trim().replace(/\/+$/, '')

/** Parse a comma-separated origin list. Returns null for blank input, meaning
 *  "no restriction". */
export function parseAllowedOrigins(raw: string | undefined): string[] | null {
  const list = (raw ?? '').split(',').map(stripTrailingSlash).filter(Boolean)
  return list.length ? list : null
}

/** True when the request's Origin is permitted.
 *  A missing Origin (curl, server-to-server, Render health checks, the Brevo
 *  webhook) is always allowed — CORS only governs browser-initiated calls. */
export function isOriginAllowed(allowed: string[] | null, origin: string | undefined): boolean {
  if (!allowed) return true
  if (!origin) return true
  return allowed.includes(stripTrailingSlash(origin))
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx tsx server/util/cors.test.ts`
Expected: PASS — `✅ ALL CORS TESTS PASSED`, exit 0.

- [ ] **Step 5: Wire it into the server**

In `talbotiq-platform/server/index.ts`, add to the import block (near the other `./util` import):

```ts
import { parseAllowedOrigins, isOriginAllowed } from './util/cors'
```

Replace line 29 (`app.use(cors())`) with:

```ts
// Cross-origin is the normal case: the SPA is on Vercel, this API on Render.
// CORS_ORIGINS blank → allow all (previous behaviour); set → strict allowlist.
const allowedOrigins = parseAllowedOrigins(process.env.CORS_ORIGINS)
app.use(cors({ origin: (origin, cb) => cb(null, isOriginAllowed(allowedOrigins, origin)) }))
if (allowedOrigins) console.log(`[server] CORS restricted to: ${allowedOrigins.join(', ')}`)
else console.log('[server] CORS: all origins allowed (set CORS_ORIGINS to restrict)')
```

- [ ] **Step 6: Verify the server boots and health responds**

Run in one terminal: `npm run server`
Expected: logs `[server] CORS: all origins allowed …` and `[server] TalbotIQ API listening on http://localhost:8787`.

In a second terminal: `curl -s http://localhost:8787/api/health`
Expected: JSON containing `"ok":true`. Stop the server afterwards.

- [ ] **Step 7: Verify the restricted path logs correctly**

Run: `CORS_ORIGINS=https://example.vercel.app npm run server` (PowerShell: `$env:CORS_ORIGINS='https://example.vercel.app'; npm run server`)
Expected: logs `[server] CORS restricted to: https://example.vercel.app`. Stop the server and clear the variable.

- [ ] **Step 8: Commit**

```bash
git add talbotiq-platform/server/util/cors.ts talbotiq-platform/server/util/cors.test.ts talbotiq-platform/server/index.ts
git commit -m "feat(deploy): CORS_ORIGINS allowlist, defaulting to allow-all"
```

---

### Task 5: Container build — Dockerfile, .dockerignore, engines, tsx

**Files:**
- Modify: `talbotiq-platform/server/Dockerfile`
- Create: `talbotiq-platform/.dockerignore`
- Delete: `talbotiq-platform/server/.dockerignore`
- Modify: `talbotiq-platform/package.json`
- Test: `talbotiq-platform/server/docker.config.test.ts`

**Interfaces:**
- Consumes: the `DATA_DIR` contract from Task 3.
- Produces: an image whose entrypoint is `npx tsx server/index.ts`, honouring `PORT`, with `DATA_DIR=/var/data` preset.

**Context you need:** `tsx` is currently a `devDependency`, and the Dockerfile installs it as a separate `npm install tsx` layer after `--omit=dev`. That is fragile — it resolves an unpinned version at build time, outside the lockfile. Since `tsx` is what *runs* the server in production, it belongs in `dependencies`.

Also, `.dockerignore` is only read from the **build context root**. The build context is `talbotiq-platform/`, so the current `server/.dockerignore` is silently ignored and the whole `node_modules` tree uploads on every build.

- [ ] **Step 1: Write the failing test**

Create `talbotiq-platform/server/docker.config.test.ts`:

```ts
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx server/docker.config.test.ts`
Expected: FAIL — `tsx is a runtime dependency`, `engines.node pinned`, `.dockerignore at build-context root`, and several Dockerfile assertions fail.

- [ ] **Step 3: Move `tsx` to dependencies and pin engines**

In `talbotiq-platform/package.json`, delete `"tsx": "^4.22.4",` from `devDependencies`, add it to `dependencies` in alphabetical position (after `"three"`, before `"ws"`):

```json
    "tsx": "^4.22.4",
```

And add an `engines` block immediately after the `"version"` line:

```json
  "engines": {
    "node": "20.x"
  },
```

- [ ] **Step 4: Refresh the lockfile**

Run: `npm install --package-lock-only`
Expected: `package-lock.json` updates. This must be committed — `npm ci` in the Docker build fails if the lockfile disagrees with `package.json`.

- [ ] **Step 5: Move the `.dockerignore` to the build-context root**

Create `talbotiq-platform/.dockerignore`:

```
node_modules
dist
.vite
server/data
*.log
.env
.env.local
.git
docs
src
public
android
ios
```

Then delete the stale one:

```bash
git rm talbotiq-platform/server/.dockerignore
```

Note `src`, `public`, and `docs` are excluded: the API image never serves the SPA, so shipping them only slows the build.

- [ ] **Step 6: Rewrite the Dockerfile**

Replace the entire contents of `talbotiq-platform/server/Dockerfile`:

```dockerfile
# TalbotIQ API — container image for Render.
# Build context is the talbotiq-platform/ directory:
#   docker build -f server/Dockerfile -t talbotiq-api .
FROM node:20-slim

WORKDIR /app
ENV NODE_ENV=production

# Dependencies first, so this layer caches across source-only edits.
# `npm ci` is strict on purpose: if package-lock.json has drifted, fail loudly
# here rather than silently resolving different versions in production.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Source: the server, the shared contract it imports, and the tsconfig.
# The SPA (src/, public/) is NOT part of this image — Vercel serves it.
COPY tsconfig.json ./
COPY shared ./shared
COPY server ./server

# Render mounts its Persistent Disk here (see render.yaml). Without DATA_DIR the
# JSON store would sit on the container's ephemeral filesystem and be discarded
# on every deploy and restart.
ENV DATA_DIR=/var/data
RUN mkdir -p /var/data && chown -R node:node /var/data

USER node

# Render injects PORT and expects the process to bind it. 8787 is the local
# default that server/index.ts falls back to.
ENV PORT=8787
EXPOSE 8787

CMD ["npx", "tsx", "server/index.ts"]
```

- [ ] **Step 7: Run test to verify it passes**

Run: `npx tsx server/docker.config.test.ts`
Expected: PASS — `✅ ALL DOCKER-CONFIG TESTS PASSED`, exit 0.

- [ ] **Step 8: Verify the server still starts with tsx from dependencies**

Run: `npm run server`
Expected: `[server] TalbotIQ API listening on http://localhost:8787`. Stop it.

- [ ] **Step 9: Commit**

```bash
git add talbotiq-platform/package.json talbotiq-platform/package-lock.json \
        talbotiq-platform/.dockerignore talbotiq-platform/server/Dockerfile \
        talbotiq-platform/server/docker.config.test.ts
git commit -m "build(deploy): Render-ready Dockerfile, context-root dockerignore, pin Node 20"
```

---

### Task 6: `render.yaml` and `vercel.json`

**Files:**
- Create: `render.yaml` (repository root)
- Create: `vercel.json` (repository root)
- Test: `talbotiq-platform/server/deploy.manifests.test.ts`

**Interfaces:**
- Consumes: `DATA_DIR` (Task 3), `CORS_ORIGINS` (Task 4), the Dockerfile path (Task 5).
- Produces: the deployment manifests the runbook (Task 7) refers to.

**Context you need:** these files live at the **repository root**, not inside `talbotiq-platform/`, because Render Blueprints and Vercel both look there by default. Each then points at `talbotiq-platform/` as the project root.

- [ ] **Step 1: Write the failing test**

Create `talbotiq-platform/server/deploy.manifests.test.ts`:

```ts
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx server/deploy.manifests.test.ts`
Expected: FAIL — both manifests are missing.

- [ ] **Step 3: Create `render.yaml` at the repository root**

```yaml
# Render Blueprint — import this repo in Render ("New → Blueprint") and it
# provisions the API service below. Values marked `sync: false` are NOT stored
# in git; Render prompts for them at deploy time.
#
# Requires a paid instance type: the free tier has no Persistent Disks and idles
# out after 15 minutes, producing ~50s cold starts mid-interview.
services:
  - type: web
    name: talbotiq-api
    runtime: docker
    plan: starter
    region: oregon
    rootDir: talbotiq-platform
    dockerfilePath: ./server/Dockerfile
    dockerContext: .
    healthCheckPath: /api/health
    autoDeploy: false

    # The JSON store lives here so it survives deploys and restarts.
    # NOTE: a disk pins this service to a single instance — do not scale it out.
    disk:
      name: talbotiq-data
      mountPath: /var/data
      sizeGB: 1

    envVars:
      # ─── Deployment wiring ───────────────────────────────────────────────
      - key: NODE_ENV
        value: production
      - key: DATA_DIR
        value: /var/data
      # Comma-separated list of allowed browser origins — set this to the
      # Vercel URL once it exists. Blank means "allow every origin".
      - key: CORS_ORIGINS
        sync: false

      # ─── Firebase Admin: verifies ID tokens + reads users/{uid}.role ──────
      # Without these, every auth-guarded endpoint returns 503.
      # FIREBASE_PRIVATE_KEY must be ONE line with newlines escaped as \n.
      - key: FIREBASE_PROJECT_ID
        sync: false
      - key: FIREBASE_CLIENT_EMAIL
        sync: false
      - key: FIREBASE_PRIVATE_KEY
        sync: false
      - key: ADMIN_EMAILS
        sync: false

      # ─── Gemini: question generation, scoring, Mimic Guide ────────────────
      # Blank falls back to heuristics (no AI), which still boots.
      - key: GEMINI_API_KEY
        sync: false
      - key: GEMINI_MODEL
        value: gemini-2.5-flash
      - key: GEMINI_LIVE_MODEL
        value: gemini-3.1-flash-live-preview

      # ─── Live speech + avatar interviews ──────────────────────────────────
      - key: DEEPGRAM_API_KEY
        sync: false
      - key: HUME_API_KEY
        sync: false
      - key: TAVUS_API_KEY
        sync: false

      # ─── Two-way interview (Daily) — 503 when blank ───────────────────────
      - key: DAILY_API_KEY
        sync: false
      - key: DAILY_SUBDOMAIN
        sync: false

      # ─── AWS Rekognition (facial analysis) ────────────────────────────────
      - key: AWS_ACCESS_KEY_ID
        sync: false
      - key: AWS_SECRET_ACCESS_KEY
        sync: false
      - key: AWS_REGION
        value: us-east-2

      # ─── Invite email (Brevo SMTP) — dry-runs when incomplete ─────────────
      - key: SMTP_HOST
        value: smtp-relay.brevo.com
      - key: SMTP_PORT
        value: "587"
      - key: SMTP_USER
        sync: false
      - key: SMTP_PASS
        sync: false
      - key: MAIL_FROM
        sync: false
      - key: BREVO_API_KEY
        sync: false
      - key: BREVO_WEBHOOK_SECRET
        sync: false
```

- [ ] **Step 4: Create `vercel.json` at the repository root**

```json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "buildCommand": "cd talbotiq-platform && npm run build",
  "installCommand": "cd talbotiq-platform && npm ci",
  "outputDirectory": "talbotiq-platform/dist",
  "framework": null,
  "rewrites": [
    { "source": "/((?!assets/|mediapipe/|fonts/|favicon|.*\\.[a-zA-Z0-9]+$).*)", "destination": "/index.html" }
  ],
  "headers": [
    {
      "source": "/assets/(.*)",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
      ]
    },
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" },
        { "key": "X-Frame-Options", "value": "SAMEORIGIN" }
      ]
    }
  ]
}
```

There is deliberately **no `/api` rewrite**. The SPA calls Render directly, because Vercel rewrites cannot carry WebSocket upgrades and cap request bodies at 4.5 MB, while `server/routes/avatar.ts` accepts uploads up to 25 MB.

- [ ] **Step 5: Run test to verify it passes**

Run: `npx tsx server/deploy.manifests.test.ts`
Expected: PASS — `✅ ALL MANIFEST TESTS PASSED`, exit 0.

- [ ] **Step 6: Verify the SPA fallback regex does not swallow assets**

Run:

```bash
node -e "const r=/^\/((?!assets\/|mediapipe\/|fonts\/|favicon|.*\.[a-zA-Z0-9]+$).*)$/; for (const p of ['/login','/interview/abc','/assets/index-abc.js','/mediapipe/face_landmarker.task','/talbotiq-logo.png','/']) console.log(p.padEnd(34), r.test(p)?'→ index.html':'→ static file')"
```

Expected: `/login` and `/interview/abc` rewrite to index.html; `/assets/...`, `/mediapipe/...`, and `/talbotiq-logo.png` are served as static files.

- [ ] **Step 7: Commit**

```bash
git add render.yaml vercel.json talbotiq-platform/server/deploy.manifests.test.ts
git commit -m "build(deploy): add Render blueprint and Vercel static config"
```

---

### Task 7: Deployment runbook and `.env.example` updates

**Files:**
- Create: `talbotiq-platform/docs/DEPLOY-VERCEL-RENDER.md`
- Modify: `talbotiq-platform/.env.example`
- Modify: `talbotiq-platform/docs/DEPLOYMENT.md` (add a pointer at the top)
- Test: `talbotiq-platform/server/deploy.docs.test.ts`

**Interfaces:**
- Consumes: every env var name introduced in Tasks 3, 4, and 6.
- Produces: the document the deployment team actually follows.

- [ ] **Step 1: Write the failing test**

Create `talbotiq-platform/server/deploy.docs.test.ts`:

```ts
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx server/deploy.docs.test.ts`
Expected: FAIL — `runbook exists` fails.

- [ ] **Step 3: Write the runbook**

Create `talbotiq-platform/docs/DEPLOY-VERCEL-RENDER.md`:

````markdown
# Deploying TalbotIQ — Vercel (frontend) + Render (backend)

The SPA is static on Vercel. The Express API, including its WebSockets, runs on
Render. The SPA reaches the API directly via `VITE_API_BASE` — nothing proxies
through Vercel.

**Deploy Render first.** The frontend build needs the API's URL.

## Prerequisites

- A Render account on a **paid instance type**. The free tier has no Persistent
  Disks and idles out after 15 minutes (~50s cold start), which is unacceptable
  mid-interview.
- A Vercel account.
- A Firebase service-account JSON for project `talbotiq-9cc4e`
  (Firebase console → Project settings → Service accounts → Generate new private key).

## Step 1 — Deploy the API to Render

1. **New → Blueprint**, select this repository. Render reads `render.yaml` and
   proposes the `talbotiq-api` service with a 1 GB disk at `/var/data`.
2. Fill in the prompted env vars (see the table below). At minimum set the three
   `FIREBASE_*` values, or every auth-guarded endpoint returns 503.
   - `FIREBASE_PRIVATE_KEY` must be **one line** with newlines escaped as `\n`.
     Copy it from the service-account JSON exactly as it appears there.
3. Deploy, then confirm: `curl https://<your-service>.onrender.com/api/health`
   → `{"ok":true,...}`. The `auth` field is `true` once Firebase Admin is configured.
4. Copy the service URL — Step 2 needs it.

The Blueprint sets `autoDeploy: false`. Turn it on in the dashboard once you are
happy with manual deploys.

## Step 2 — Deploy the SPA to Vercel

1. **Add New → Project**, import this repository. `vercel.json` at the root sets
   the build command, install command, and output directory; leave the
   framework preset as **Other**.
2. Set the environment variables from the *Vercel* table below.
   `VITE_API_BASE` is the Render URL from Step 1, **with scheme, no trailing
   slash**: `https://talbotiq-api.onrender.com`.
3. Deploy, then open the site and confirm the browser devtools Network tab shows
   `/api/...` requests going to the Render host.

## Step 3 — Close the loop

1. **Restrict CORS.** In Render, set `CORS_ORIGINS` to the Vercel URL
   (e.g. `https://talbotiq.vercel.app`) and redeploy. Multiple origins are
   comma-separated. Leaving it blank allows every origin.
2. **Authorize the domain in Firebase.** Firebase console → Authentication →
   Settings → **Authorized domains** → add the Vercel domain. **Skip this and
   every login fails with `auth/unauthorized-domain`**, even though both
   deployments look healthy.
3. **Brevo webhook (only if you want delivery tracking).** Point it at
   `https://<render-url>/api/invites/brevo-webhook?token=<BREVO_WEBHOOK_SECRET>`.

## Environment variables

### Render (the API) — secrets live here

**Required for a working app**

| Var | Notes |
|---|---|
| `FIREBASE_PROJECT_ID` | `talbotiq-9cc4e` |
| `FIREBASE_CLIENT_EMAIL` | From the service-account JSON |
| `FIREBASE_PRIVATE_KEY` | One line, newlines as `\n`. Without these, auth-guarded endpoints return 503 |

**Set by the Blueprint — do not change**

| Var | Value |
|---|---|
| `NODE_ENV` | `production` |
| `DATA_DIR` | `/var/data` — the mounted disk. Changing it loses your data |
| `PORT` | Injected by Render |

**Per feature — absent, only that feature degrades**

| Var | Without it |
|---|---|
| `CORS_ORIGINS` | All origins allowed |
| `GEMINI_API_KEY` | AI question generation and scoring fall back to heuristics |
| `GEMINI_MODEL`, `GEMINI_LIVE_MODEL` | Defaults applied by the Blueprint |
| `DEEPGRAM_API_KEY` | No live speech-to-text |
| `HUME_API_KEY` | No voice prosody analysis |
| `TAVUS_API_KEY` | Deployment-wide fallback only; normally set in the Settings UI |
| `DAILY_API_KEY` | Two-way interview returns 503 |
| `DAILY_SUBDOMAIN` | Optional display convenience |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` | No Rekognition facial analysis |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `MAIL_FROM` | Invite email dry-runs (logs instead of sending) |
| `BREVO_API_KEY` | Recruiters type the sender manually instead of picking |
| `BREVO_WEBHOOK_SECRET` | No delivery tracking |
| `ADMIN_EMAILS` | No admin overlay for legacy sessions |

### Vercel (the SPA) — public values only

Everything here is compiled into the bundle and is readable by anyone. **Never
put a secret in a `VITE_` variable.**

| Var | Value |
|---|---|
| `VITE_API_BASE` | The Render URL, e.g. `https://talbotiq-api.onrender.com` (no trailing slash) |
| `VITE_FIREBASE_API_KEY` | From `.env.example` — public by design |
| `VITE_FIREBASE_AUTH_DOMAIN` | `talbotiq-9cc4e.firebaseapp.com` |
| `VITE_FIREBASE_PROJECT_ID` | `talbotiq-9cc4e` |
| `VITE_FIREBASE_STORAGE_BUCKET` | `talbotiq-9cc4e.firebasestorage.app` |
| `VITE_FIREBASE_MESSAGING_SENDER_ID` | `473028554722` |
| `VITE_FIREBASE_APP_ID` | `1:473028554722:web:152baa837fe77c7fb713bb` |

## Verifying a deployment

```bash
# API is up
curl https://<render-url>/api/health

# CORS allows the Vercel origin (expect access-control-allow-origin in the response)
curl -si -H "Origin: https://<vercel-domain>" https://<render-url>/api/health | grep -i access-control

# No secret leaked into the bundle — expect no output
npm run build && grep -r "GEMINI_API_KEY\|DEEPGRAM_API_KEY\|FIREBASE_PRIVATE_KEY" dist/
```

In the app itself: sign in (proves Firebase Auth + authorized domains), open a
Voice Track interview (proves the WebSocket reached Render), and create a
template then redeploy the Render service (proves the disk persisted it).

## Operational notes

- **The disk pins the service to one instance.** `server/store/db.ts` is a JSON
  file, not a database — two instances would overwrite each other. Do not enable
  horizontal scaling. Deploys briefly interrupt service.
- **Back up the data** by downloading `/var/data/db.json` from the Render shell
  before risky changes.
- **WebSocket origin is not filtered.** `CORS_ORIGINS` governs HTTP only; the
  `ws` upgrade path authenticates by Firebase ID token in the query string
  instead.
- To scale beyond one instance, migrate `server/store/db.ts` to Firestore —
  `firebase-admin` is already a dependency. See `docs/DEPLOYMENT.md`.
````

- [ ] **Step 4: Update `.env.example`**

Append to `talbotiq-platform/.env.example`:

```
# ─── Deployment (Vercel + Render) — see docs/DEPLOY-VERCEL-RENDER.md ───────
# Where the JSON store is written. Unset → server/data (local dev). On Render
# this is the mounted Persistent Disk, without which data is lost every deploy.
# DATA_DIR=/var/data

# Comma-separated browser origins allowed to call this API, e.g.
# "https://talbotiq.vercel.app". Blank → every origin is allowed.
# CORS_ORIGINS=
```

- [ ] **Step 5: Cross-link the old deployment doc**

Add directly under the `# Deployment — Google Cloud + Play Store` heading in
`talbotiq-platform/docs/DEPLOYMENT.md`:

```markdown
> **Deploying to Vercel + Render instead?** See
> [DEPLOY-VERCEL-RENDER.md](./DEPLOY-VERCEL-RENDER.md) — that is the supported,
> currently-configured path. This document covers the Google Cloud
> alternative and the Play Store build.
```

- [ ] **Step 6: Run test to verify it passes**

Run: `npx tsx server/deploy.docs.test.ts`
Expected: PASS — `✅ ALL DEPLOY-DOC TESTS PASSED`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add talbotiq-platform/docs/DEPLOY-VERCEL-RENDER.md talbotiq-platform/docs/DEPLOYMENT.md \
        talbotiq-platform/.env.example talbotiq-platform/server/deploy.docs.test.ts
git commit -m "docs(deploy): Vercel + Render runbook with full env var reference"
```

---

### Task 8: Full verification sweep

Proves the whole thing holds together before handoff.

**Files:**
- Create: `talbotiq-platform/scripts/verify-deploy.mjs`
- Modify: `talbotiq-platform/package.json` (add `test` and `verify:deploy` scripts)

**Interfaces:**
- Consumes: every test file from Tasks 1-7.
- Produces: `npm test` — one command the deployment team can run.

**Context you need:** the repo has no `test` script today, so the test files added in earlier tasks are invisible unless run by hand. This task wires them up.

- [ ] **Step 1: Write the runner**

Create `talbotiq-platform/scripts/verify-deploy.mjs`:

```js
/**
 * Runs every *.test.ts in the repo through tsx, then the deployment gates.
 * Usage:  npm test
 */
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'

const ROOT = path.resolve(import.meta.dirname, '..')

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

let failed = []
for (const t of tests) {
  const rel = path.relative(ROOT, t).replace(/\\/g, '/')
  try {
    execFileSync('npx', ['tsx', t], { cwd: ROOT, stdio: 'pipe', shell: process.platform === 'win32' })
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
```

- [ ] **Step 2: Add the scripts**

In `talbotiq-platform/package.json`, add to `scripts`:

```json
    "test": "node scripts/verify-deploy.mjs",
    "verify:deploy": "npm run build && node scripts/verify-deploy.mjs",
```

- [ ] **Step 3: Run the full suite**

Run: `npm test`
Expected: every test file listed with ✅, ending `✅ All test files passed`, exit 0.

Some pre-existing `.test.ts` files may fail for reasons unrelated to this work.
If one does, **do not fix it here** — record the filename and its failure in the
handoff notes, and confirm the seven files added by this plan all pass.

- [ ] **Step 4: Verify the production build**

Run: `npm run build`
Expected: `tsc` silent, `vite build` prints `✓ built in …`, exit 0.

- [ ] **Step 5: Verify no secret reached the bundle**

Run:

```bash
grep -rE "GEMINI_API_KEY|DEEPGRAM_API_KEY|HUME_API_KEY|FIREBASE_PRIVATE_KEY|AWS_SECRET|SMTP_PASS|xsmtpsib-" dist/ || echo "CLEAN: no server secrets in bundle"
```

Expected: `CLEAN: no server secrets in bundle`.

Note: `VITE_FIREBASE_API_KEY` (an `AIza…` string) **will** appear in the bundle.
That is correct and safe — Firebase web API keys are public identifiers.

- [ ] **Step 6: Verify same-origin parity (the dev loop is intact)**

Run: `npm run dev`

Expected: Vite on `http://localhost:3001`, Express on `:8787`. Open the app,
sign in, and confirm the Network tab shows `/api/...` on port 3001 (proxied) —
**not** absolute URLs. This proves a blank `VITE_API_BASE` preserved the old
behaviour. Stop both.

- [ ] **Step 7: Verify the production URL wiring**

Run: `VITE_API_BASE=https://example.onrender.com npm run build`
(PowerShell: `$env:VITE_API_BASE='https://example.onrender.com'; npm run build`)

Then: `grep -o "https://example.onrender.com" dist/assets/*.js | head -1`
Expected: at least one match — the base was inlined.

Afterwards clear the variable and rebuild so `dist/` is not left pointing at a
placeholder host: `npm run build`.

- [ ] **Step 8: Commit**

```bash
git add talbotiq-platform/scripts/verify-deploy.mjs talbotiq-platform/package.json
git commit -m "test(deploy): add npm test runner covering the deployment gates"
```

---

## Handoff checklist

Confirm before telling the team it is ready:

- [ ] `npm test` passes (or known-unrelated failures are documented).
- [ ] `npm run build` passes.
- [ ] `grep` shows no server secret in `dist/`.
- [ ] `npm run dev` still works with no env vars set.
- [ ] `render.yaml` and `vercel.json` exist at the repository root.
- [ ] The runbook documents every env var in `render.yaml`.
- [ ] **The Docker image has never been built locally** — Docker was unavailable.
      Its first real build happens on Render. Say so in the handoff rather than
      implying it is proven.
