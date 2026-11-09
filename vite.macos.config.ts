import {defineConfig} from 'vite';
import react from '@vitejs/plugin-react';
import {resolve} from 'node:path';
export default defineConfig({root:resolve('apps/macos/web'),base:'./',plugins:[react()],build:{outDir:resolve('build/macos/web'),emptyOutDir:true,sourcemap:false,assetsInlineLimit:0}});
