import type { TrackType } from '@shared/types'

/**
 * Pure fuzzy-match helpers used by the Autopilot filter actions on the Analytics
 * and Pipelines screens. Kept dependency-free so they can be unit-tested and so
 * the same matching logic is shared across screens (spoken role/template names,
 * interview-type/track names). No React, no DOM.
 */

/** Match a spoken/typed name against a list of valid options.
 *  Exact (case-insensitive) first, then substring in either direction so
 *  "backend" matches "Senior Backend Engineer" and vice-versa. Null if none. */
export function matchOption(input: string, options: string[]): string | null {
  const s = input.trim().toLowerCase()
  if (!s) return null
  const exact = options.find((o) => o.toLowerCase() === s)
  if (exact) return exact
  return options.find((o) => {
    const l = o.toLowerCase()
    return l.includes(s) || s.includes(l)
  }) ?? null
}

const TRACK_KEYS: TrackType[] = ['chat', 'chatbot', 'voice', 'video_avatar', 'video', 'two_way']

/** Aliases people actually say for each track. Order matters: more specific
 *  tracks (video_avatar) are listed before looser ones (video) so a substring
 *  scan resolves "video avatar" to the avatar track, not the plain video one. */
const TRACK_ALIASES: Array<[TrackType, string[]]> = [
  ['chat', ['timed q&a', 'timed qa', 'timed q and a', 'timed', 'q&a', 'q and a', 'qa', 'hirevue']],
  ['video_avatar', ['video avatar', 'avatar', 'tavus']],
  ['two_way', ['two-way interview', 'two way interview', 'two-way', 'two way', 'twoway']],
  ['video', ['video interview', 'video', 'webcam']],
  ['voice', ['voice', 'spoken', 'gemini live']],
  ['chatbot', ['chatbot', 'chat bot', 'bot', 'typed']],
]

/** Resolve a spoken interview-type/track name to its TrackType key, 'all' to
 *  clear the filter, or null when nothing matches. Accepts the raw key too. */
export function normalizeTrack(input: string): TrackType | 'all' | null {
  const s = input.trim().toLowerCase()
  if (!s || s === 'all' || s === 'all tracks' || s === 'any' || s === 'every') return 'all'
  const key = TRACK_KEYS.find((k) => k === s)
  if (key) return key
  // exact alias first, then substring (longest-specific tracks are listed first)
  for (const [t, aliases] of TRACK_ALIASES) if (aliases.includes(s)) return t
  for (const [t, aliases] of TRACK_ALIASES) if (aliases.some((a) => s.includes(a))) return t
  return null
}
