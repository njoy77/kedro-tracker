// Server entry (`bun run dev` / `bun run start`). Configuration: see config.ts.

import { createApp } from './app.ts'
import { DevTokenVerifier, SupabaseTokenVerifier, type TokenVerifier } from './auth.ts'
import { loadConfig } from './config.ts'
import { fetchLegacyRows, seedFromLegacy, type DevAccount } from './dev/seed.ts'
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

const { app, services } = createApp({ store, verifier, log, logRequests: true, clipSecret: config.clipSecret, linkSigningKey: config.linkSigningKey, publicUrl: config.publicUrl })

// Local test data (see dev/seed.ts). Only with dev auth and the in-memory store.
if (config.devSeed && config.devAuth && !config.supabase) {
  let accounts: DevAccount[] = []
  app.get('/dev/accounts', (c) => c.json({ accounts }))
  if (!config.legacySource) {
    log('KEDRO_DEV_SEED: no SUPABASE_URL / SUPABASE_ANON_KEY to read the web data from (run bun run env:pull)')
  } else {
    const seeded = await seedFromLegacy(await fetchLegacyRows(config.legacySource.url, config.legacySource.anonKey), { store, services })
    accounts = seeded.accounts
    log(`Seeded from the web app: ${seeded.imported} games imported, ${seeded.skipped} skipped, ${accounts.length} test accounts. Sign in as "dev:<id>" (GET /dev/accounts).`)
  }
}

export default {
  port: config.port,
  fetch: app.fetch,
}
