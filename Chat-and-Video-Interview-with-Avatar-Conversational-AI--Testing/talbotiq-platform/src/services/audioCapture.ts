// src/services/audioCapture.ts
//
// Single source of truth for microphone audio. Opens ONE getUserMedia stream and
// fans it out to three independent consumers:
//   1. AudioWorklet ('pcm-processor') → Int16 PCM chunks → onPCMChunk (Deepgram + Hume EVI)
//   2. MediaRecorder (WebM/Opus) → onRecordingChunk (Hume batch blob)
//
// These are three consumers of one source, never a chain. The AudioWorklet runs on a
// dedicated real-time audio thread so it never drops frames (unlike ScriptProcessorNode).

export interface AudioCaptureConfig {
  /** Called for EVERY Int16 PCM chunk produced by the worklet (~256ms @ 16kHz). For Hume EVI. */
  onPCMChunk: (chunk: ArrayBuffer) => void
  /** Called for each batch MediaRecorder data chunk — push to the batch audio store. */
  onRecordingChunk?: (chunk: Blob) => void
  /**
   * Called for each Deepgram MediaRecorder data chunk (WebM/Opus, low-latency).
   * This recorder works off the raw MediaStream and is INDEPENDENT of the AudioContext,
   * so it streams reliably even if the worklet's context starts suspended.
   */
  onDeepgramChunk?: (chunk: Blob) => void
  /** Target sample rate. Default 16000 (what Hume expects; worklet downsamples to it). */
  sampleRate?: number
  /** Batch MediaRecorder timeslice in ms. Default 1000. */
  recorderTimeslice?: number
  /** Deepgram MediaRecorder timeslice in ms. Default 250 (low latency). */
  deepgramTimeslice?: number
}

export interface AudioCapture {
  start: () => Promise<void>
  /** Flush + stop the MediaRecorder; resolves once the final chunk has been delivered. */
  flushRecording: () => Promise<void>
  stop: () => void
  getStream: () => MediaStream | null
  isActive: () => boolean
}

export function createAudioCapture(config: AudioCaptureConfig): AudioCapture {
  const targetRate = config.sampleRate ?? 16000
  const timeslice = config.recorderTimeslice ?? 1000
  const dgTimeslice = config.deepgramTimeslice ?? 250

  let audioContext: AudioContext | null = null
  let workletNode: AudioWorkletNode | null = null
  let sourceNode: MediaStreamAudioSourceNode | null = null
  let zeroGain: GainNode | null = null
  let mediaRecorder: MediaRecorder | null = null
  let deepgramRecorder: MediaRecorder | null = null
  let stream: MediaStream | null = null
  let active = false

  async function start(): Promise<void> {
    // Capture tuned for maximum speech + prosody fidelity.
    // echoCancellation / noiseSuppression / autoGainControl are deliberately OFF:
    //  - EC destroys prosody (pitch/energy) signals Hume relies on
    //  - NS removes breaths, hesitations, and low-volume words Deepgram should catch
    //  - AGC compresses emotional amplitude
    // NOTE: do NOT use exact sampleRate/channelCount constraints — some devices throw
    // OverconstrainedError and the whole capture dies. The worklet downsamples to 16kHz
    // and reads channel 0 regardless of the device's native rate/channels.
    stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: false,
        noiseSuppression: false,
        autoGainControl: false,
      },
      video: false,
    })
    const trackSettings = stream.getAudioTracks()[0]?.getSettings?.() ?? {}
    console.log('[CAP] mic track settings:', trackSettings)

    const mimeType = MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
      ? 'audio/webm;codecs=opus'
      : MediaRecorder.isTypeSupported('audio/webm')
      ? 'audio/webm'
      : 'audio/ogg;codecs=opus'

    active = true

    // ── PRIMARY, MOST RELIABLE PATH: MediaRecorders straight off the MediaStream ──
    // These do NOT depend on the Web Audio AudioContext, so they work even if the
    // worklet's context starts suspended after a route change.

    // (a) Deepgram low-latency recorder — WebM/Opus chunks → onDeepgramChunk
    if (config.onDeepgramChunk) {
      deepgramRecorder = new MediaRecorder(stream, { mimeType })
      deepgramRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) config.onDeepgramChunk?.(e.data)
      }
      deepgramRecorder.start(dgTimeslice)
      console.log(`[CAP] Deepgram recorder started — ${mimeType} @ ${dgTimeslice}ms`)
    }

    // (b) Batch recorder — WebM/Opus chunks → onRecordingChunk (Hume batch blob)
    mediaRecorder = new MediaRecorder(stream, { mimeType, audioBitsPerSecond: 128000 })
    mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) config.onRecordingChunk?.(e.data)
    }
    mediaRecorder.start(timeslice)

    // ── SECONDARY, BEST-EFFORT PATH: AudioWorklet for real-time PCM (Hume EVI) ──
    // Wrapped so any failure here never takes down the recorders above.
    try {
      audioContext = new AudioContext({ sampleRate: targetRate, latencyHint: 'interactive' })
      if (audioContext.state === 'suspended') {
        try { await audioContext.resume() } catch { /* best effort */ }
      }
      await audioContext.audioWorklet.addModule('/pcm-processor.js')

      sourceNode = audioContext.createMediaStreamSource(stream)
      workletNode = new AudioWorkletNode(audioContext, 'pcm-processor', {
        numberOfInputs: 1,
        numberOfOutputs: 1,
        outputChannelCount: [1],
        processorOptions: {},
      })

      let chunkCount = 0
      workletNode.port.onmessage = (event) => {
        if (event.data?.type === 'pcm' && active) {
          chunkCount++
          if (chunkCount === 1 || chunkCount % 40 === 0) {
            console.log(`[CAP] PCM chunk #${chunkCount}, bytes=${(event.data.buffer as ArrayBuffer).byteLength}`)
          }
          config.onPCMChunk(event.data.buffer as ArrayBuffer)
        }
      }

      // mic → worklet → (silent) gain → destination. The zero-gain hop keeps the worklet
      // reachable from the destination so the render graph drives process() (no audible echo).
      zeroGain = audioContext.createGain()
      zeroGain.gain.value = 0
      sourceNode.connect(workletNode)
      workletNode.connect(zeroGain)
      zeroGain.connect(audioContext.destination)

      console.log(`[CAP] worklet started — ctx rate=${audioContext.sampleRate}Hz, state=${audioContext.state}`)
    } catch (workletErr) {
      console.warn('[CAP] AudioWorklet path failed (recorders still active):', workletErr)
    }

    console.log(`[CAP] capture started — recorder=${mimeType}`)
  }

  function flushRecording(): Promise<void> {
    return new Promise((resolve) => {
      const rec = mediaRecorder
      if (!rec || rec.state === 'inactive') { resolve(); return }
      rec.addEventListener('stop', () => resolve(), { once: true })
      try {
        rec.requestData() // emit a final dataavailable for buffered audio
        rec.stop()
      } catch {
        resolve()
      }
    })
  }

  function stop(): void {
    active = false
    try { workletNode?.port.close() } catch { /* noop */ }
    workletNode?.disconnect()
    zeroGain?.disconnect()
    sourceNode?.disconnect()
    if (deepgramRecorder && deepgramRecorder.state !== 'inactive') {
      try { deepgramRecorder.stop() } catch { /* noop */ }
    }
    if (mediaRecorder && mediaRecorder.state !== 'inactive') {
      try { mediaRecorder.stop() } catch { /* noop */ }
    }
    stream?.getTracks().forEach((t) => t.stop())
    audioContext?.close().catch(() => {})
    workletNode = null
    zeroGain = null
    sourceNode = null
    mediaRecorder = null
    deepgramRecorder = null
    stream = null
    audioContext = null
  }

  return {
    start,
    flushRecording,
    stop,
    getStream: () => stream,
    isActive: () => active,
  }
}
