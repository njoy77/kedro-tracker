// Server entry (`bun run dev` / `bun run start`). Configuration: see config.ts.

import { createApp } from './app.ts'
import { DevTokenVerifier, SupabaseTokenVerifier, type TokenVerifier } from './auth.ts'
import { loadConfig } from './config.ts'
import { MemoryStore } from './store/memory.ts'
import { SupabaseStore } from './store/supabase.ts'
import type { Store } from './store/types.ts'

const config = loadConfig()
const log = (message: string) => console.error(`[kedro-api] ${message}`)

let store: Store
let verifier: TokenVerifier
if (config.supabase) {
  if (config.devAuth) throw new Error('KEDRO_DEV_AUTH cannot be used with Supabase credentials')
  store = new SupabaseStore(config.supabase)
  verifier = new SupabaseTokenVerifier(config.supabase)
} else {
  store = new MemoryStore()
  verifier = config.devAuth ? new DevTokenVerifier() : { verify: async () => null }
  log(
    `Supabase is not configured (missing ${config.missing.join(', ')}): using an in-memory store. ` +
      (config.devAuth ? 'KEDRO_DEV_AUTH=1: tokens are "dev:<uuid>".' : 'Every /v1 request will be unauthorized; set KEDRO_DEV_AUTH=1 to try it locally.'),
  )
}

const { app } = createApp({ store, verifier, log, logRequests: true })

export default {
  port: config.port,
  fetch: app.fetch,
}
