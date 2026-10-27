// Types and constants shared between the web app and the API.

export const API_VERSION = '0.1.0'

/** Supabase table backing the key-value store used by the web app. */
export const KV_TABLE = 'kedro_kv'

export type HealthResponse = {
  status: 'ok'
  version: string
}
