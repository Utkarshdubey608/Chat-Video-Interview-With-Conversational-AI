import type { Server } from 'node:http'
import { WebSocketServer, WebSocket } from 'ws'
import { contextFromUpgrade } from '../middleware/auth'

/**
 * Deepgram Nova-3 live-transcription relay (hybrid, key stays server-side).
 *
 * The browser can't set WS auth headers, and this project's Deepgram key can't
 * mint short-lived tokens ("Insufficient permissions" on /v1/auth/grant). So the
 * browser opens a WS to us at /api/avatar/deepgram, streams its MediaRecorder
 * (WebM/Opus) chunks, and we relay them to Deepgram with the API key in the
 * Authorization header (server-side), passing Deepgram's JSON results straight
 * back. The key never reaches the client.
 */
const DG_PARAMS = new URLSearchParams({
  model: 'nova-3',
  language: 'en-US',
  punctuate: 'true',
  smart_format: 'true',
  interim_results: 'true',
  utterance_end_ms: '1000',
  vad_events: 'true',
  filler_words: 'true',
})

export function handle(client: WebSocket) {
  const key = (process.env.DEEPGRAM_API_KEY ?? '').trim()
  if (!key) { try { client.close(1011, 'Deepgram not configured') } catch { /* noop */ } return }

  const upstream = new WebSocket(`wss://api.deepgram.com/v1/listen?${DG_PARAMS.toString()}`, {
    headers: { Authorization: `Token ${key}` },
  })

  const queue: Array<{ data: Buffer; binary: boolean }> = []
  let upstreamOpen = false

  upstream.on('open', () => {
    upstreamOpen = true
    for (const { data, binary } of queue) upstream.send(data, { binary })
    queue.length = 0
  })
  // Deepgram → browser (Results / metadata JSON). CRITICAL: preserve the frame
  // type. The ws library hands every message over as a Buffer, and send(Buffer)
  // defaults to a BINARY frame — which silently turned Deepgram's JSON text
  // frames into ArrayBuffers the client's JSON.parse choked on (= no transcript
  // ever committed). Forward text as text, binary as binary.
  upstream.on('message', (data, isBinary) => {
    if (client.readyState === WebSocket.OPEN) client.send(data as Buffer, { binary: isBinary })
  })
  upstream.on('close', (code, reason) => { try { client.close(code >= 1000 && code <= 4999 ? code : 1011, reason?.toString().slice(0, 120)) } catch { /* noop */ } })
  upstream.on('error', () => { try { client.close(1011, 'deepgram upstream error') } catch { /* noop */ } })

  // Browser → Deepgram (binary audio chunks; text for control msgs like CloseStream).
  client.on('message', (data, isBinary) => {
    if (upstreamOpen && upstream.readyState === WebSocket.OPEN) upstream.send(data as Buffer, { binary: isBinary })
    else queue.push({ data: data as Buffer, binary: isBinary })
  })
  client.on('close', () => { try { upstream.close() } catch { /* noop */ } })
  client.on('error', () => { try { upstream.close() } catch { /* noop */ } })
}

/** Mount the Deepgram relay on the existing HTTP server (own WSS, path-gated).
 *  The AI-Avatar-Screening transcription is a recruiter tool, so the upgrade is
 *  authenticated (token in the query string) and restricted to recruiters. */
export function attachDeepgramRelay(server: Server) {
  const wss = new WebSocketServer({ noServer: true })
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url ?? '', 'http://localhost')
    if (url.pathname !== '/api/avatar/deepgram') return // let other upgrade handlers deal with it
    void (async () => {
      const auth = await contextFromUpgrade(req)
      if (!auth || auth.role !== 'recruiter') {
        try { socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n') } catch { /* noop */ }
        socket.destroy()
        return
      }
      wss.handleUpgrade(req, socket, head, (ws) => handle(ws))
    })()
  })
}

/** Candidate-reachable Deepgram relay for the Video Interview (live transcription).
 *  Same relay as /api/avatar/deepgram but authorized for ANY authenticated user
 *  (the /api/avatar path is recruiter-only). Key stays server-side. */
export function attachCandidateDeepgramRelay(server: Server) {
  const wss = new WebSocketServer({ noServer: true })
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url ?? '', 'http://localhost')
    if (url.pathname !== '/api/interview/deepgram') return
    void (async () => {
      const auth = await contextFromUpgrade(req)
      if (!auth) {
        try { socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n') } catch { /* noop */ }
        socket.destroy()
        return
      }
      wss.handleUpgrade(req, socket, head, (ws) => handle(ws))
    })()
  })
}
