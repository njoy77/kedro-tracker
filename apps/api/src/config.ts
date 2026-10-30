// Environment configuration. Keys live in Vercel (the single source of truth) and reach local
// development through `bun run env:pull`, which writes apps/api/.env.local (Bun loads it).
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
//
// APNs (Live Activity broadcast pushes) is not configured yet: see push/liveActivity.ts.

export type ApiConfig = {
  port: number
  supabase: { url: string; anonKey: string; serviceRoleKey: string; jwtSecret?: string } | null
  devAuth: boolean
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
    supabase:
      url && anonKey && serviceRoleKey
        ? { url: url.replace(/\/+$/, ''), anonKey, serviceRoleKey, jwtSecret: env.SUPABASE_JWT_SECRET || undefined }
        : null,
    devAuth: env.KEDRO_DEV_AUTH === '1',
    clipSecret: env.KEDRO_CLIP_SECRET || undefined,
    linkSigningKey: env.KEDRO_LINK_SIGNING_KEY || undefined,
    publicUrl: env.KEDRO_PUBLIC_URL || undefined,
    missing,
  }
}
