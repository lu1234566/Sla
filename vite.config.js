import { defineConfig } from 'vite';

// base relativa: o build funciona em qualquer subcaminho (GitHub Pages, artifact, itch.io).
export default defineConfig({
  base: './',
  build: {
    target: 'es2020',
    chunkSizeWarningLimit: 1200,
    assetsInlineLimit: 0,
  },
  server: { host: '127.0.0.1', port: 5173 },
});
