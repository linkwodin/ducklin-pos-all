import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Declare process for TypeScript (available in Node.js environment)
declare const process: {
  env: {
    DEPLOY_TARGET?: string
    VITE_DEPLOY_TARGET?: string
  }
}

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
  // Use '/' for Firebase Hosting (absolute paths work fine)
  // Firebase Hosting supports absolute paths and handles routing properly
  // Use './' for Cloud Storage deployments (relative paths required)
  // Check if building for Firebase by checking mode or environment variable
  const deployTarget = process.env.DEPLOY_TARGET
  const viteDeployTarget = process.env.VITE_DEPLOY_TARGET
  const isFirebase = mode === 'firebase' || viteDeployTarget === 'firebase' || deployTarget === 'firebase'
  const base = isFirebase ? '/' : './'
  
  return {
    plugins: [react()],
    base: base,
    server: {
      port: 3000,
      proxy: {
        '/api': {
          target: 'http://localhost:8868',
          changeOrigin: true,
        },
      },
    },
  }
})

