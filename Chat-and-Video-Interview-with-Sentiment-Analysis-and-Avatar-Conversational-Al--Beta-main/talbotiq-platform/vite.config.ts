import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      '@shared': path.resolve(__dirname, './shared'),
    },
  },
  server: {
    port: 3001,
    strictPort: true,
    // The API key never reaches the client — all /api calls are proxied to the
    // Express server, which holds GEMINI_API_KEY server-side only. The Voice
    // Track's realtime audio uses a WebSocket, proxied with ws:true.
    proxy: {
      // WS paths (must precede the generic /api http proxy).
      '/api/voice': { target: 'ws://localhost:8787', ws: true },
      '/api/avatar/deepgram': { target: 'ws://localhost:8787', ws: true },
      '/api/interview/deepgram': { target: 'ws://localhost:8787', ws: true }, // Video Interview live transcription
      '/api': 'http://localhost:8787',
    },
  },
})
