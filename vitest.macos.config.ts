import {defineConfig} from 'vitest/config';
import react from '@vitejs/plugin-react';
export default defineConfig({plugins:[react()],test:{environment:'jsdom',setupFiles:['tests/macos/setup.ts'],include:['tests/macos/*.test.{ts,tsx}']}});
