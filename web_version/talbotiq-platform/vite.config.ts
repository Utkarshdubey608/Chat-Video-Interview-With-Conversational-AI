import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      output: {
        /**
         * Split the big third-party dependencies into their own chunks.
         *
         * This is a bundling change only — no application code moves. The point
         * is cacheability and visibility: React and Firebase change far less
         * often than product code, so isolating them means a normal deploy no
         * longer invalidates them in every visitor's cache, and the build output
         * shows what each dependency actually costs.
         *
         * Note this does NOT remove Firebase from the marketing page's critical
         * path — AuthProvider still imports it eagerly, so it is still fetched.
         * Doing that requires changing where AuthProvider mounts, which is auth
         * code and needs sign-off.
         */
        manualChunks: {
          'vendor-react': ['react', 'react-dom', 'react-router-dom'],
          'vendor-firebase': ['firebase/app', 'firebase/auth', 'firebase/firestore'],
          'vendor-query': ['@tanstack/react-query'],
        },
      },
    },
  },
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
