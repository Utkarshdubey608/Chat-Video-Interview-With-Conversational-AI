export interface TranscriptEntry {
  role: 'candidate' | 'ai'
  text: string
  timestamp: number
  questionIdx: number
}

export const FILLER_WORDS = new Set([
  'um', 'uh', 'hmm', 'er', 'erm', 'ah', 'like', 'basically', 'literally',
  'actually', 'right', 'okay', 'so', 'you know', 'i mean', 'kind of', 'sort of',
])

export function countFillers(text: string): number {
  const words = text.toLowerCase().replace(/[.,!?;:]/g, '').split(/\s+/)
  return words.filter(w => FILLER_WORDS.has(w)).length
}

export function countWords(entries: TranscriptEntry[]): number {
  return entries
    .filter(e => e.role === 'candidate')
    .reduce((acc, e) => acc + e.text.split(/\s+/).filter(Boolean).length, 0)
}

export function calcWpm(entries: TranscriptEntry[]): number {
  const candidate = entries.filter(e => e.role === 'candidate')
  if (candidate.length < 2) return 0
  const durationMs = candidate[candidate.length - 1].timestamp - candidate[0].timestamp
  if (durationMs <= 0) return 0
  const words = countWords(entries)
  return Math.round((words / durationMs) * 60_000)
}

class DeepgramService {
  private key = ''

  setKey(k: string) { this.key = k }
  getKey() { return this.key }

  buildWsUrl(): string {
    // Audio is streamed as WebM/Opus from a MediaRecorder (NOT raw PCM), so we do NOT
    // declare encoding/sample_rate — Deepgram auto-detects the Opus container. This path
    // is independent of the Web Audio AudioContext (which can start suspended after a
    // route change), so it streams reliably regardless of worklet state.
    const params = new URLSearchParams({
      model: 'nova-3',
      language: 'en-US',
      punctuate: 'true',
      smart_format: 'true',
      interim_results: 'true',  // emit words before the silence — maximum capture
      utterance_end_ms: '1000', // flush after 1s of silence
      vad_events: 'true',       // voice-activity events (breath / non-speech detection)
      filler_words: 'true',     // um, uh, like, you know — critical for an ATS
    })
    return `wss://api.deepgram.com/v1/listen?${params.toString()}`
  }

  // Returns the key trimmed — used by the WebSocket subprotocol auth
  getTrimmedKey(): string { return this.key.trim() }

  async testConnection(): Promise<{ ok: boolean; message: string }> {
    if (!this.key) return { ok: false, message: 'No API key set' }
    try {
      // Use a local server-side proxy in development to avoid CORS and keep the
      // Deepgram API key on the server. The proxy forwards the request and adds
      // the Authorization header using a server-side env var.
      const proxyBase = (import.meta as any).env?.VITE_DEEPGRAM_PROXY ?? ((import.meta as any).env?.DEV ? 'http://localhost:3002' : '/api')
      const url = `${proxyBase.replace(/\/$/, '')}/deepgram/projects`
      const res = await fetch(url, {
        // No client-side Authorization header — the proxy will add it.
        headers: {},
      })
      if (res.ok) return { ok: true, message: 'Deepgram Nova-3 connected' }
      if (res.status === 401) return { ok: false, message: 'Invalid API key (401)' }
      if (res.status === 403) return { ok: false, message: 'Key lacks streaming permission (403)' }
      const err = await res.json().catch(() => null)
      return { ok: false, message: err?.err_msg ?? `HTTP ${res.status}` }
    } catch (e: any) {
      return { ok: false, message: e.message ?? 'Connection failed' }
    }
  }
}

export const deepgramService = new DeepgramService()
