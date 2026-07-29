/** Run: npx tsx src/lib/voiceEcho.test.ts */
import { isLikelyEcho } from './voiceEcho'

let failures = 0
function assert(label: string, cond: boolean) { console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}`); if (!cond) failures++ }

// ── Echo of the assistant's read-back → suppressed ──
assert('verbatim read-back is echo',
  isLikelyEcho("okay I'll send the invitation to John now", "Okay, I'll send the invitation to John now.") === true)
assert('slightly-misheard read-back still echo',
  isLikelyEcho('filtering analytics to senior backend engineer', 'Filtering analytics to Senior Backend Engineer.') === true)
assert('confirm read-back starting with Okay is echo',
  isLikelyEcho('okay ready to send invitations to three candidates', 'Okay, ready to send invitations to three candidates — say yes to confirm.') === true)

// ── Genuine user speech → NOT suppressed (the whole point of the fix) ──
assert('different command is not echo',
  isLikelyEcho('show me the voice interviews', 'Okay, I sent the invitation to John.') === false)
assert('new command sharing one word is not echo',
  isLikelyEcho('open the pipelines page', 'Filtering analytics to Senior Backend Engineer.') === false)

// ── Short confirmations must ALWAYS pass (< 3 words) ──
assert('bare yes passes', isLikelyEcho('yes', 'Say yes to confirm.') === false)
assert('bare no passes', isLikelyEcho('no', 'Say yes or no.') === false)
assert('two-word ok passes', isLikelyEcho('go ahead', 'Ready — say yes to confirm and proceed.') === false)
assert('yes please go ahead passes (low overlap)',
  isLikelyEcho('yes please go ahead', 'Ready to send to three candidates, say yes to confirm.') === false)

// ── Degenerate inputs ──
assert('empty spoken → not echo', isLikelyEcho('show me analytics', '') === false)
assert('empty heard → not echo', isLikelyEcho('', 'anything') === false)

console.log(`\n${failures === 0 ? '✅ ALL VOICE-ECHO TESTS PASSED' : `❌ ${failures} FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
