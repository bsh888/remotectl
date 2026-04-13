import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/ws': { target: 'wss://localhost:8443', ws: true, secure: false },
      '/api': { target: 'https://localhost:8443', secure: false },
    },
  },
  build: {
    outDir: '../deploy/static',
    emptyOutDir: true,
  },
})
