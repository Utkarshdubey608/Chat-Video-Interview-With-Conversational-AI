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
