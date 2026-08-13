/**
 * Deterministic unit tests for the voice track's English-locked ASR helpers.
 * Run with:  npx tsx server/services/voiceLanguage.test.ts
 * No Gemini / network needed — pure functions only.
 */
import { transcriptionLanguages, adaptationPhrases } from './voice'

let failures = 0
function assert(label: string, cond: boolean, extra = '') {
  console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}${extra ? ' — ' + extra : ''}`)
  if (!cond) failures++
}

/* ── 1. English templates hint every major English variant ──────────────── */
{
  console.log('\n=== 1. transcriptionLanguages ===')
  const us = transcriptionLanguages('en-US')
  assert('en-US expands to all English variants', us.length >= 4 && ['en-IN', 'en-US', 'en-GB', 'en-AU'].every((v) => us.includes(v)), JSON.stringify(us))
  assert('en-IN expands the same way', transcriptionLanguages('en-IN').includes('en-US'))
  assert('bare "en" counts as English', transcriptionLanguages('en').includes('en-IN'))
  assert('free-text "English" counts as English', transcriptionLanguages('English').includes('en-IN'))
  assert('case/whitespace tolerated', transcriptionLanguages('  EN-us ').includes('en-GB'))
  assert('non-English passes through untouched', JSON.stringify(transcriptionLanguages('fr-FR')) === '["fr-FR"]')
}

/* ── 2. Adaptation phrases pick the interview's real vocabulary ─────────── */
{
  console.log('\n=== 2. adaptationPhrases ===')
  const qs = [
    'How did you optimize the SQL queries in the Employer Worker Registration System?',
    'Explain how you applied OOP principles in Java and PostgreSQL, or C++ where needed.',
    'Tell me about deploying Node.js services with k8s.',
    'Describe a difficult problem you solved recently and how you approached it.',
  ]
  const p = adaptationPhrases('Software Engineer', qs)
  assert('includes the role', p.includes('Software Engineer'))
  assert('picks acronyms (SQL, OOP)', p.includes('SQL') && p.includes('OOP'))
  assert('picks mixed-case terms (PostgreSQL)', p.includes('PostgreSQL'))
  assert('picks symbol terms (C++)', p.includes('C++'), JSON.stringify(p))
  assert('picks dotted terms (Node.js)', p.includes('Node.js'))
  assert('picks digit terms (k8s)', p.includes('k8s'))
  assert('picks proper-noun phrases', p.some((x) => x.includes('Employer Worker Registration System')))
  assert('skips plain prose words', !p.some((x) => /^(difficult|problem|recently|approached|queries)$/i.test(x)))
  assert('caps at 32 entries', p.length <= 32, `n=${p.length}`)
  assert('empty inputs → empty list', adaptationPhrases('', []).length === 0)
}

console.log(`\n${failures === 0 ? '✅ ALL VOICE-LANGUAGE TESTS PASSED' : `❌ ${failures} ASSERTION(S) FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
