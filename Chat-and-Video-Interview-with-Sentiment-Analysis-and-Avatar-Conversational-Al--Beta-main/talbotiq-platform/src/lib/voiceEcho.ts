/**
 * Pure echo-detection for hands-free Voice mode. The speech recognizer can pick
 * up the tail of the assistant's OWN spoken reply (its "read-back") a beat after
 * playback ends — which, left unchecked, gets submitted as a spurious command or
 * (worse) matches a "yes"/"okay" confirm. The old guard went DEAF for 1.5s after
 * every reply to avoid this, which also dropped the user's real next command.
 *
 * Instead we suppress echo by CONTENT: a heard chunk is treated as echo only
 * when it is a multi-word phrase that substantially overlaps what the assistant
 * just said. A genuine user command (different words) or a short confirmation
 * ("yes", "no", "go ahead") is NEVER suppressed — so the mic stays responsive.
 * No DOM / React imports so this is unit-testable in isolation.
 */

function words(s: string): string[] {
  return s
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ') // drop punctuation, keep letters/numbers (any script)
    .split(/\s+/)
    .filter(Boolean)
}

/**
 * True when `heard` is very likely the assistant's own speech echoing back
 * (so it should be ignored), given the text the assistant just spoke.
 *
 * Rules, tuned to never eat real user input:
 *  - fewer than 3 words → NOT echo (a user "yes" / "go ahead" must always pass).
 *  - otherwise → echo only if ≥ 60% of the heard words also appear in the
 *    spoken text (the read-back reappears almost verbatim; a real command that
 *    merely shares a word or two stays below the bar).
 */
export function isLikelyEcho(heard: string, spoken: string): boolean {
  const hw = words(heard)
  if (hw.length < 3) return false
  const sw = new Set(words(spoken))
  if (sw.size === 0) return false
  const overlap = hw.filter((w) => sw.has(w)).length / hw.length
  return overlap >= 0.6
}
