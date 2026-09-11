import { resolve } from 'node:path';

import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  resolve: {
    alias: {
      '@tursodatabase/database-wasm-common': resolve(
        import.meta.dirname,
        'wasm_common_patch.mjs',
      ),
    },
  },
  build: {
    emptyOutDir: false,
    lib: {
      entry: resolve(import.meta.dirname, 'entry.mjs'),
      fileName: () => 'turso_upstream.js',
      formats: ['es'],
      name: 'turso-dart',
    },
    outDir: resolve(import.meta.dirname, '../../web'),
  },
});
