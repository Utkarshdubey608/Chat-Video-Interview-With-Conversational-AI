/** Run: npx tsx src/features/guide/autopilot/filterMatch.test.ts */
import { matchOption, normalizeTrack } from './filterMatch'

let failures = 0
function assert(label: string, cond: boolean) { console.log(`  ${cond ? 'PASS' : 'FAIL'}  ${label}`); if (!cond) failures++ }

const ROLES = ['Senior Backend Engineer', 'UI UX developer', 'Data Scientist']

// matchOption
assert('exact case-insensitive', matchOption('ui ux developer', ROLES) === 'UI UX developer')
assert('substring of option', matchOption('backend', ROLES) === 'Senior Backend Engineer')
assert('option is substring of input', matchOption('senior backend engineer role', ROLES) === 'Senior Backend Engineer')
assert('no match → null', matchOption('marketing', ROLES) === null)
assert('empty → null', matchOption('   ', ROLES) === null)
assert('first match wins', matchOption('e', ['Alpha', 'Beta', 'Gamma']) === 'Beta') // 'beta' includes 'e'

// normalizeTrack — clearing
assert('all → all', normalizeTrack('all') === 'all')
assert('empty → all', normalizeTrack('') === 'all')
assert('any → all', normalizeTrack('Any') === 'all')

// normalizeTrack — raw keys
assert('key voice', normalizeTrack('voice') === 'voice')
assert('key two_way', normalizeTrack('two_way') === 'two_way')

// normalizeTrack — spoken labels
assert('Voice label', normalizeTrack('Voice') === 'voice')
assert('Chatbot label', normalizeTrack('Chatbot') === 'chatbot')
assert('Timed Q&A → chat', normalizeTrack('Timed Q&A') === 'chat')
assert('timed qa → chat', normalizeTrack('timed qa') === 'chat')
assert('Video Avatar → video_avatar', normalizeTrack('Video Avatar') === 'video_avatar')
assert('avatar → video_avatar', normalizeTrack('avatar') === 'video_avatar')
assert('Video Interview → video', normalizeTrack('Video Interview') === 'video')
assert('plain video → video', normalizeTrack('video') === 'video')
assert('two-way → two_way', normalizeTrack('two-way') === 'two_way')
assert('two way interview → two_way', normalizeTrack('two way interview') === 'two_way')

// normalizeTrack — the tricky disambiguation: "video avatar" must NOT resolve to plain video
assert('video avatar not plain video', normalizeTrack('the video avatar track') === 'video_avatar')
assert('unknown → null', normalizeTrack('carrier pigeon') === null)

console.log(`\n${failures === 0 ? '✅ ALL FILTER-MATCH TESTS PASSED' : `❌ ${failures} FAILED`}`)
process.exit(failures === 0 ? 0 : 1)
