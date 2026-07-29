/**
 * Deepgram pre-recorded transcription for the Video Interview track. The key
 * stays server-side (same key as the live relay in deepgramRelay.ts). We fetch
 * the uploaded clip by its Firebase Storage download URL and POST the bytes to
 * Deepgram's pre-recorded /v1/listen endpoint.
 */
const DG_URL = 'https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&punctuate=true&language=en-US'

/** Pure extractor — the first channel's first alternative transcript, or ''. */
export function parseDeepgramTranscript(json: unknown): string {
  const j = json as { results?: { channels?: Array<{ alternatives?: Array<{ transcript?: string }> }> } }
  const t = j?.results?.channels?.[0]?.alternatives?.[0]?.transcript
  return typeof t === 'string' ? t.trim() : ''
}

/** Transcribe a clip at `url`. Returns '' on any failure or when no key is set. */
export async function transcribeVideoUrl(url: string): Promise<string> {
  const key = (process.env.DEEPGRAM_API_KEY ?? '').trim()
  if (!key) {
    if (url) console.warn('[transcribe] DEEPGRAM_API_KEY not set — video answer will have no transcript')
    return ''
  }
  if (!url) return ''
  // A hung fetch/Deepgram round-trip must never block scoring forever — scoring
  // waits on these transcriptions (see maybeScore), so bound them hard.
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), 30_000)
  try {
    const media = await fetch(url, { signal: ctrl.signal })
    if (!media.ok) throw new Error(`could not fetch clip (${media.status})`)
    const bytes = Buffer.from(await media.arrayBuffer())
    const res = await fetch(DG_URL, {
      method: 'POST',
      headers: { Authorization: `Token ${key}`, 'Content-Type': media.headers.get('content-type') || 'video/webm' },
      body: bytes,
      signal: ctrl.signal,
    })
    if (!res.ok) throw new Error(`deepgram ${res.status}`)
    return parseDeepgramTranscript(await res.json())
  } finally {
    clearTimeout(timer)
  }
}
