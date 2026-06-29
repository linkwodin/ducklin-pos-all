import path from 'node:path'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

// Declare process for TypeScript (available in Node.js environment)
declare const process: {
  env: {
    DEPLOY_TARGET?: string
    VITE_DEPLOY_TARGET?: string
  }
}

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, __dirname, '')
  if (mode === 'uat') {
    const api = (env.VITE_API_URL ?? '').trim()
    if (!api.startsWith('http://') && !api.startsWith('https://')) {
      throw new Error(
        'UAT build needs VITE_API_URL as an absolute URL in .env.uat (see env.uat example). Relative /api/v1 breaks Firebase Hosting.',
      )
    }
  }

  // Use '/' for Firebase Hosting (absolute paths work fine)
  // Firebase Hosting supports absolute paths and handles routing properly
  // Use './' for Cloud Storage deployments (relative paths required)
  // Check if building for Firebase by checking mode or environment variable
  const deployTarget = process.env.DEPLOY_TARGET
  const viteDeployTarget = process.env.VITE_DEPLOY_TARGET
  const isFirebase = mode === 'firebase' || viteDeployTarget === 'firebase' || deployTarget === 'firebase'
  const base = isFirebase ? '/' : './'
  const pkg = JSON.parse(readFileSync(path.join(__dirname, 'package.json'), 'utf8')) as { version?: string }
  
  return {
    plugins: [react()],
    base: base,
    define: {
      'import.meta.env.VITE_APP_VERSION': JSON.stringify(pkg.version ?? '0.0.0'),
    },
    resolve: {
      alias: {
        '@repoDocs': path.resolve(__dirname, '../docs'),
      },
    },
    server: {
      port: 3000,
      proxy: {
        '/api': {
          target: 'http://localhost:8868',
          changeOrigin: true,
        },
        '/uploads': {
          target: 'http://localhost:8868',
          changeOrigin: true,
        },
      },
    },
  }
})

