// Types, rules and contracts shared between the API, the web app and (by mirroring) the iOS app.

export const API_VERSION = '0.2.0'

/** Supabase table backing the key-value store used by the legacy web app. */
export const KV_TABLE = 'kedro_kv'

export * from './api.ts'
export * from './domain.ts'
export * from './fold.ts'
export * from './hlc.ts'
export * from './ids.ts'
export * from './leaderboard.ts'
export * from './operations.ts'
export * from './ratings.ts'
export * from './scoring.ts'
export * from './stats.ts'
export * from './taunts.ts'
