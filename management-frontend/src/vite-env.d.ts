/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_URL?: string
  readonly VITE_AI_PLAYBOOK_URL?: string
}

declare module '*?raw' {
  const content: string
  export default content
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}

