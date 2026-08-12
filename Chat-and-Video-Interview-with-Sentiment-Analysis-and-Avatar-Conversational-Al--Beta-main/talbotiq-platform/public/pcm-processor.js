// public/pcm-processor.js
// AudioWorkletProcessor — runs on a dedicated real-time audio thread, never blocks.
// Outputs Int16 PCM frames (downsampled to 16kHz mono) to the main thread via postMessage.
//
// Why AudioWorklet and not ScriptProcessorNode:
//  - ScriptProcessorNode runs on the main thread and is interrupted by React re-renders,
//    causing dropped audio frames (missed words, missed emotion frames).
//  - AudioWorklet runs on a dedicated audio thread and never drops frames.
//  - Buffer transfer is zero-copy via postMessage with a Transferable.

class PCMProcessor extends AudioWorkletProcessor {
  constructor() {
    super()
    this._targetSampleRate = 16000
    this._inputSampleRate = 0
    this._chunkSize = 4096 // ~256ms at 16kHz — optimal for both Deepgram and Hume
    this._accumulated = []
    this._accumulatedLength = 0
  }

  process(inputs) {
    const input = inputs[0]
    if (!input || !input[0]) return true

    const channelData = input[0] // mono: channel 0 only
    if (!this._inputSampleRate) {
      this._inputSampleRate = sampleRate // AudioWorklet global
    }

    // Downsample to 16kHz if the AudioContext is running at 44100/48000
    const downsampled = this._downsample(channelData, this._inputSampleRate, this._targetSampleRate)

    // Accumulate samples until we have a full chunk
    this._accumulated.push(downsampled)
    this._accumulatedLength += downsampled.length

    while (this._accumulatedLength >= this._chunkSize) {
      // Flatten accumulated buffer
      const flat = new Float32Array(this._accumulatedLength)
      let offset = 0
      for (const chunk of this._accumulated) {
        flat.set(chunk, offset)
        offset += chunk.length
      }

      // Take one chunk; keep the remainder
      const chunk = flat.slice(0, this._chunkSize)
      const remainder = flat.slice(this._chunkSize)
      this._accumulated = [remainder]
      this._accumulatedLength = remainder.length

      // Convert Float32 [-1, 1] → Int16 [-32768, 32767]
      const int16 = new Int16Array(chunk.length)
      for (let i = 0; i < chunk.length; i++) {
        const s = Math.max(-1, Math.min(1, chunk[i]))
        int16[i] = s < 0 ? s * 32768 : s * 32767
      }

      // Zero-copy transfer to the main thread
      this.port.postMessage({ type: 'pcm', buffer: int16.buffer }, [int16.buffer])
    }

    return true // keep the processor alive
  }

  _downsample(buffer, fromRate, toRate) {
    if (fromRate === toRate) return buffer
    const ratio = fromRate / toRate
    const newLength = Math.round(buffer.length / ratio)
    const result = new Float32Array(newLength)
    let offsetResult = 0
    let offsetBuffer = 0
    while (offsetResult < newLength) {
      const nextOffsetBuffer = Math.round((offsetResult + 1) * ratio)
      let accum = 0
      let count = 0
      for (let i = offsetBuffer; i < nextOffsetBuffer && i < buffer.length; i++) {
        accum += buffer[i]
        count++
      }
      result[offsetResult] = count > 0 ? accum / count : 0
      offsetResult++
      offsetBuffer = nextOffsetBuffer
    }
    return result
  }
}

registerProcessor('pcm-processor', PCMProcessor)
