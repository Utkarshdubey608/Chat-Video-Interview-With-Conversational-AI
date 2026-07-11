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
    // Express server, which holds GEMINI_API_KEY server-side only.
    proxy: {
      '/api': 'http://localhost:8787',
    },
  },
})
