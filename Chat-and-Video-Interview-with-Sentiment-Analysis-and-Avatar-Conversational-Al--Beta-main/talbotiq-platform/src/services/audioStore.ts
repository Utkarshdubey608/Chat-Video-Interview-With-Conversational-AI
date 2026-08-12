// Module-level singleton — survives React re-renders and hook unmounts
let _blob: Blob | null = null
let _chunks: BlobPart[] = []

export const audioStore = {
  push(chunk: BlobPart) {
    _chunks.push(chunk)
  },
  seal(mimeType = 'audio/webm;codecs=opus') {
    if (_chunks.length === 0) return
    _blob = new Blob(_chunks, { type: mimeType })
  },
  get blob(): Blob | null {
    return _blob
  },
  get hasData(): boolean {
    return _chunks.length > 0 || _blob !== null
  },
  reset() {
    _blob = null
    _chunks = []
  },
}
