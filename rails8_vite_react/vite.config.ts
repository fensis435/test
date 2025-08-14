import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  root: 'app/frontend',
  build: {
    outDir: '../../public/vite',
    emptyOutDir: true,
    rollupOptions: {
      input: {
        application: path.resolve(__dirname, 'app/frontend/index.html')
      }
    }
  },
  plugins: [
    RubyPlugin(),
    react()
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'app/frontend')
    }
  }
})
