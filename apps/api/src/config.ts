// Environment configuration. Keys live in Vercel (the single source of truth): the API's own keys
// in the kedro-api project, production only. Local development gets apps/api/.env.local from
// `bun run env:pull` (Bun loads it), which has no service-role key, so it runs on memory.
//
//   SUPABASE_URL               https://<project>.supabase.co (falls back to VITE_SUPABASE_URL)
//   SUPABASE_ANON_KEY          public anon key, used to verify tokens remotely (falls back to VITE_SUPABASE_ANON_KEY)
//   SUPABASE_SERVICE_ROLE_KEY  server-only; the API writes with it (bypasses RLS)
//   SUPABASE_JWT_SECRET        optional; verifies legacy HS256 tokens locally instead of asking Supabase Auth
//   PORT                       default 8787
//   KEDRO_CLIP_SECRET          optional; signs App Clip session tokens (random per process when unset)
//   KEDRO_LINK_SIGNING_KEY     optional; base64 PKCS#8 Ed25519 key that signs table-link identity
//                              attestations (random per process when unset; set it in production)
//   KEDRO_PUBLIC_URL           optional; the API's public origin, used in profile photo URLs
//   KEDRO_DEV_AUTH=1           local only, no Supabase: in-memory store, tokens are "dev:<uuid>"
//   KEDRO_DEV_SEED=legacy      with KEDRO_DEV_AUTH: load the web app's players and games (read-only)
//                              as signed-up test accounts (src/dev/seed.ts; `bun run dev:seed`)
//   VERCEL_ENV / NODE_ENV      set by the host: `production` turns on deploymentProblems' checks
//
// APNs (Live Activity broadcast pushes) is not configured yet: see push/liveActivity.ts.

export type ApiConfig = {
  port: number
  /** `production` on Vercel production (or NODE_ENV=production elsewhere), `preview` on other Vercel deployments. */
  environment: 'production' | 'preview' | 'local'
  supabase: { url: string; anonKey: string; serviceRoleKey: string; jwtSecret?: string } | null
  devAuth: boolean
  /** `legacy`: seed the in-memory store from the web app's data. */
  devSeed?: 'legacy'
  /** Where the web app's data is read from for `devSeed` (the anon key only reads). */
  legacySource?: { url: string; anonKey: string }
  clipSecret?: string
  linkSigningKey?: string
  publicUrl?: string
  /** Names of the Supabase keys that are missing (for the startup message). */
  missing: string[]
}

export function loadConfig(env: Record<string, string | undefined> = process.env): ApiConfig {
  const url = env.SUPABASE_URL ?? env.VITE_SUPABASE_URL
  const anonKey = env.SUPABASE_ANON_KEY ?? env.VITE_SUPABASE_ANON_KEY
  const serviceRoleKey = env.SUPABASE_SERVICE_ROLE_KEY
  const missing = [
    !url && 'SUPABASE_URL',
    !anonKey && 'SUPABASE_ANON_KEY',
    !serviceRoleKey && 'SUPABASE_SERVICE_ROLE_KEY',
  ].filter((name): name is string => Boolean(name))
  return {
    port: Number(env.PORT ?? 8787),
    environment:
      env.VERCEL_ENV === 'production' || (!env.VERCEL_ENV && env.NODE_ENV === 'production') ? 'production' : env.VERCEL_ENV ? 'preview' : 'local',
    supabase:
      url && anonKey && serviceRoleKey
        ? { url: url.replace(/\/+$/, ''), anonKey, serviceRoleKey, jwtSecret: env.SUPABASE_JWT_SECRET || undefined }
        : null,
    devAuth: env.KEDRO_DEV_AUTH === '1',
    devSeed: env.KEDRO_DEV_SEED === 'legacy' ? 'legacy' : undefined,
    legacySource: url && anonKey ? { url, anonKey } : undefined,
    clipSecret: env.KEDRO_CLIP_SECRET || undefined,
    linkSigningKey: env.KEDRO_LINK_SIGNING_KEY || undefined,
    publicUrl: env.KEDRO_PUBLIC_URL || undefined,
    missing,
  }
}

/**
 * Why this configuration must not serve, or [] when it can. A deployed API never runs with dev
 * auth or the dev seed. Production also needs Supabase (otherwise each instance would keep its
 * own in-memory store) and the signing keys and public URL (otherwise each instance signs App
 * Clip tokens and table links with its own random key, and photo URLs follow the request's host).
 */
export function deploymentProblems(config: ApiConfig): string[] {
  if (config.environment === 'local') return []
  const problems: string[] = []
  if (config.devAuth) problems.push('KEDRO_DEV_AUTH is set')
  if (config.devSeed) problems.push('KEDRO_DEV_SEED is set')
  if (config.environment === 'production') {
    if (!config.supabase) problems.push(`Supabase is not configured (missing ${config.missing.join(', ')})`)
    const unset = [
      !config.clipSecret && 'KEDRO_CLIP_SECRET',
      !config.linkSigningKey && 'KEDRO_LINK_SIGNING_KEY',
      !config.publicUrl && 'KEDRO_PUBLIC_URL',
    ].filter((name): name is string => Boolean(name))
    if (unset.length > 0) problems.push(`missing ${unset.join(', ')}`)
  }
  return problems
}
