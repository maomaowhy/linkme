import { defineConfig } from 'tsup';

export default defineConfig({
  entry: {
    main: 'electron/main.ts',
    preload: 'electron/preload.ts',
  },
  format: 'cjs',
  platform: 'node',
  outDir: 'dist-electron',
  outExtension: () => ({ js: '.cjs' }),
  external: ['electron', 'ws', 'express', 'qrcode'],
  clean: true,
});
