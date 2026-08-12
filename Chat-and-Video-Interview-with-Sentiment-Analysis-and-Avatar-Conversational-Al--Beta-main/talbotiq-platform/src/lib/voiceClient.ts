import type {
  VoiceServerMessage, VoiceClientMessage, VoicePhase, TimeOfDay,
} from '@shared/types'
import { getIdTokenOrNull } from '@/lib/firebase'

/**
 * Low-latency browser transport for the Voice Track.
 *
 * Mic audio is downsampled to 16 kHz PCM16 and PCM-encoded INSIDE the audio
 * worklet (off the main thread), batched into ~20 ms chunks, and sent as raw
 * BINARY WebSocket frames — no base64, no JSON in the hot path. The agent's
 * 24 kHz PCM comes back as binary frames too and is played gaplessly. Control
 * messages (ready/mute/end ↔ state/caption/interrupted/ended/error) are JSON
 * text frames, so the two are trivially distinguished by frame type.
 *
 * The LLM credential never touches the client — audio is relayed by our backend,
 * which holds the key server-side.
 */

const AGENT_RATE = 24000
const MIC_RATE = 16000
const CHUNK_MS = 20

// AudioWorklet: resample→PCM16→batch on the worklet thread, transfer buffers out.
const CAPTURE_WORKLET = `
class CaptureProcessor extends AudioWorkletProcessor {
  constructor() {
    super()
    this.target = ${MIC_RATE}
    this.ratio = sampleRate / this.target      // sampleRate = context rate (ideally 16000)
    this.chunk = Math.round(this.target * ${CHUNK_MS} / 1000)
    this.buf = new Int16Array(this.chunk)
    this.n = 0
    this.readPos = 0
  }
  push(f) {
    const s = f < -1 ? -1 : f > 1 ? 1 : f
    this.buf[this.n++] = s < 0 ? s * 0x8000 : s * 0x7fff
    if (this.n >= this.chunk) {
      const out = this.buf
      this.port.postMessage(out.buffer, [out.buffer])   // zero-copy transfer
      this.buf = new Int16Array(this.chunk)
      this.n = 0
    }
  }
  process(inputs) {
    const ch = inputs[0] && inputs[0][0]
    if (!ch) return true
    if (this.ratio === 1) {
      for (let i = 0; i < ch.length; i++) this.push(ch[i])
    } else {
      for (; this.readPos < ch.length; this.readPos += this.ratio) this.push(ch[Math.floor(this.readPos)])
      this.readPos -= ch.length
    }
    return true
  }
}
registerProcessor('capture-processor', CaptureProcessor)
`

/** base64 PCM16 → Float32 (used only by the one-shot voice preview). */
function base64ToFloat32(b64: string): Float32Array {
  const bin = atob(b64)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return int16BytesToFloat32(bytes.buffer)
}
function int16BytesToFloat32(buf: ArrayBuffer): Float32Array {
  const view = new DataView(buf)
  const out = new Float32Array(Math.floor(buf.byteLength / 2))
  for (let i = 0; i < out.length; i++) out[i] = view.getInt16(i * 2, true) / 0x8000
  return out
}

export async function voiceWsUrl(sessionId: string): Promise<string> {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws'
  // The WS handshake can't carry an Authorization header, so the ID token rides
  // in the query string; the server verifies it and checks session assignment.
  const token = await getIdTokenOrNull()
  const q = token ? `?token=${encodeURIComponent(token)}` : ''
  return `${proto}://${location.host}/api/voice/${encodeURIComponent(sessionId)}${q}`
}

export interface VoiceClientCallbacks {
  onPhase?: (phase: VoicePhase) => void
  onCaption?: (role: 'interviewer' | 'candidate', text: string, final: boolean) => void
  /** Agent audio became audible / drained. Server phases lead local playback by
   *  the buffered duration, so the UI should trust THIS for "speaking". */
  onAudioPlaying?: (playing: boolean) => void
  /** The socket dropped and we're transparently reconnecting (mic stays open).
   *  active=false once reconnected or after we give up. */
  onReconnecting?: (active: boolean) => void
  onEnded?: (reason?: string, graceful?: boolean) => void
  onError?: (message: string) => void
}

// Backoff between reconnect attempts (ms), capped at the last value and repeated.
const RECONNECT_DELAYS = [500, 1000, 2000, 3000, 5000, 8000]
// Keep retrying for roughly this long — must stay under the SERVER's reconnect
// grace window (60s) so we don't give up while the interview is still being held.
const RECONNECT_WINDOW_MS = 55_000

export class VoiceClient {
  private ws?: WebSocket
  private stream?: MediaStream
  private captureCtx?: AudioContext
  private worklet?: AudioWorkletNode
  private source?: MediaStreamAudioSourceNode
  private playbackCtx?: AudioContext
  private nextStartAt = 0
  private sources: AudioBufferSourceNode[] = []
  private drainTimer?: ReturnType<typeof setTimeout>
  private playing = false
  private muted = false
  private closed = false
  private serverEnded = false                 // server sent 'ended' → do not reconnect
  private timeOfDay?: TimeOfDay
  private reconnectAttempts = 0
  private reconnectStartedAt = 0
  private reconnectTimer?: ReturnType<typeof setTimeout>

  constructor(private sessionId: string, private cbs: VoiceClientCallbacks) {}

  private sendControl(msg: VoiceClientMessage) {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(msg))
  }

  async start(timeOfDay?: TimeOfDay): Promise<void> {
    this.cbs.onPhase?.('connecting')
    // 1) Mic capture at 16 kHz (the worklet resamples if the browser ignores the hint).
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 },
    })
    this.captureCtx = new AudioContext({ sampleRate: MIC_RATE })
    await this.captureCtx.audioWorklet.addModule(URL.createObjectURL(new Blob([CAPTURE_WORKLET], { type: 'application/javascript' })))
    this.source = this.captureCtx.createMediaStreamSource(this.stream)
    this.worklet = new AudioWorkletNode(this.captureCtx, 'capture-processor')
    this.worklet.port.onmessage = (e: MessageEvent<ArrayBuffer>) => {
      if (this.muted || this.ws?.readyState !== WebSocket.OPEN) return
      this.ws.send(e.data)               // raw PCM16 16 kHz — binary frame, no base64/JSON
    }
    this.source.connect(this.worklet)
    const sink = this.captureCtx.createGain()
    sink.gain.value = 0
    this.worklet.connect(sink).connect(this.captureCtx.destination)

    // 2) Playback context (agent audio is 24 kHz).
    this.playbackCtx = new AudioContext()

    // 3) WebSocket to our backend relay. The mic + playback contexts above stay
    //    alive across reconnects — only this socket is recreated on a drop.
    this.timeOfDay = timeOfDay
    await this.openWs()
  }

  /** Open (or re-open) the relay socket. Reused for the initial connect and every
   *  transparent reconnect; the server resumes the same interview seamlessly. */
  private async openWs(): Promise<void> {
    if (this.closed || this.serverEnded) return
    let url: string
    try { url = await voiceWsUrl(this.sessionId) } catch { this.scheduleReconnect(); return }
    if (this.closed || this.serverEnded) return
    const ws = new WebSocket(url)
    this.ws = ws
    ws.binaryType = 'arraybuffer'
    ws.onopen = () => {
      this.reconnectAttempts = 0
      this.reconnectStartedAt = 0
      this.cbs.onReconnecting?.(false)
      this.sendControl({ type: 'ready', timeOfDay: this.timeOfDay })
      if (this.muted) this.sendControl({ type: 'mute', muted: true }) // preserve mute across reconnect
    }
    ws.onmessage = (ev) => {
      if (typeof ev.data === 'string') this.onControl(JSON.parse(ev.data) as VoiceServerMessage)
      else this.enqueuePcm(ev.data as ArrayBuffer) // binary = agent audio (24 kHz PCM16)
    }
    ws.onerror = () => { /* a 'close' event always follows; reconnect is handled there */ }
    ws.onclose = () => {
      if (this.ws !== ws) return                 // superseded by a newer socket
      if (this.closed || this.serverEnded) return // intentional teardown / real finish
      this.scheduleReconnect()
    }
  }

  /** Retry the socket with backoff for up to RECONNECT_WINDOW_MS (matched to the
   *  server's grace window); only surface "interrupted" once that window elapses. */
  private scheduleReconnect(): void {
    if (this.closed || this.serverEnded) return
    this.flushPlayback() // drop stale audio buffered from the turn that was cut off
    const now = Date.now()
    if (this.reconnectStartedAt === 0) this.reconnectStartedAt = now
    if (now - this.reconnectStartedAt >= RECONNECT_WINDOW_MS) {
      this.cbs.onReconnecting?.(false)
      this.cbs.onEnded?.('disconnected', false)
      this.dispose() // release the mic + audio contexts; we've given up reconnecting
      return
    }
    const delay = RECONNECT_DELAYS[Math.min(this.reconnectAttempts, RECONNECT_DELAYS.length - 1)]
    this.reconnectAttempts++
    this.cbs.onReconnecting?.(true)
    this.cbs.onPhase?.('connecting')
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer)
    this.reconnectTimer = setTimeout(() => { void this.openWs() }, delay)
  }

  private onControl(msg: VoiceServerMessage) {
    switch (msg.type) {
      case 'state': this.cbs.onPhase?.(msg.phase); break
      case 'caption': this.cbs.onCaption?.(msg.role, msg.text, msg.final); break
      case 'interrupted': this.flushPlayback(); break
      case 'ended': this.serverEnded = true; this.cbs.onEnded?.(msg.reason, msg.graceful !== false); this.dispose(); break
      case 'error': this.cbs.onError?.(msg.message); break
      // 'audio' as JSON is legacy; audio now arrives as binary frames.
    }
  }

  private enqueuePcm(buf: ArrayBuffer) {
    const ctx = this.playbackCtx
    if (!ctx || buf.byteLength < 2) return
    if (ctx.state === 'suspended') void ctx.resume()
    const samples = int16BytesToFloat32(buf)
    const buffer = ctx.createBuffer(1, samples.length, AGENT_RATE)
    buffer.getChannelData(0).set(samples)
    const src = ctx.createBufferSource()
    src.buffer = buffer
    src.connect(ctx.destination)
    const startAt = Math.max(ctx.currentTime, this.nextStartAt)
    src.start(startAt)
    this.nextStartAt = startAt + buffer.duration
    this.sources.push(src)
    src.onended = () => { this.sources = this.sources.filter((s) => s !== src) }
    this.setPlaying(true)
    this.armDrainCheck()
  }

  private setPlaying(p: boolean) {
    if (this.playing === p) return
    this.playing = p
    this.cbs.onAudioPlaying?.(p)
  }

  /** Fire onAudioPlaying(false) the moment the scheduled queue actually drains. */
  private armDrainCheck() {
    if (this.drainTimer) clearTimeout(this.drainTimer)
    const ctx = this.playbackCtx
    if (!ctx) return
    const remaining = this.nextStartAt - ctx.currentTime
    if (remaining <= 0.05) { this.setPlaying(false); return }
    this.drainTimer = setTimeout(() => this.armDrainCheck(), remaining * 1000 + 60)
  }

  /** Barge-in: stop and drop everything queued for playback. */
  private flushPlayback() {
    for (const s of this.sources) { try { s.stop() } catch { /* noop */ } }
    this.sources = []
    this.nextStartAt = 0
    if (this.drainTimer) clearTimeout(this.drainTimer)
    this.setPlaying(false)
  }

  setMuted(muted: boolean) {
    this.muted = muted
    this.sendControl({ type: 'mute', muted })
  }

  /** Candidate-initiated end: tell the server to finalize, then tear down. */
  end() {
    this.sendControl({ type: 'end' })
    this.dispose()
  }

  /** Tear down mic + sockets WITHOUT finalizing (safe on unmount / remount). */
  dispose() {
    if (this.closed) return
    this.closed = true
    if (this.reconnectTimer) { clearTimeout(this.reconnectTimer); this.reconnectTimer = undefined }
    this.flushPlayback()
    try { this.worklet?.disconnect() } catch { /* noop */ }
    try { this.source?.disconnect() } catch { /* noop */ }
    this.stream?.getTracks().forEach((t) => t.stop())
    void this.captureCtx?.close()
    void this.playbackCtx?.close()
    try { this.ws?.close() } catch { /* noop */ }
  }
}

/** Play a one-shot PCM16 (24 kHz) base64 sample — used by the voice preview button. */
export async function playPcmSample(b64: string, rate = AGENT_RATE): Promise<void> {
  const ctx = new AudioContext()
  const samples = base64ToFloat32(b64)
  const buffer = ctx.createBuffer(1, samples.length, rate)
  buffer.getChannelData(0).set(samples)
  const src = ctx.createBufferSource()
  src.buffer = buffer
  src.connect(ctx.destination)
  await new Promise<void>((resolve) => { src.onended = () => resolve(); src.start() })
  void ctx.close()
}
