// Local test data from the web app (`KEDRO_DEV_SEED=legacy`, with `KEDRO_DEV_AUTH=1` and no
// service-role key, so the store is in memory). At startup it reads the web app's `kedro_kv` rows
// read-only with the anon key, imports the games exactly as the legacy importer would, and turns
// every legacy username into a signed-up test account that has claimed its history. Sign in on
// the Simulator as any of them (`GET /dev/accounts`, then `Bearer dev:<id>`). Nothing is written
// to Supabase, and a restart re-reads the latest web data.

import { CURATED_AVATAR_IDS, EMOJI_COLOR_COUNT, normalizeHandle, type Avatar, type UUID } from '@kedro/shared'
import type { Services } from '../app.ts'
import { readLegacyExport, stableUUID } from '../legacy/convert.ts'
import { importLegacy } from '../legacy/importer.ts'
import type { Store } from '../store/types.ts'

export type DevAccount = { id: UUID; displayName: string; handle: string; gamesClaimed: number }

export type SeedReport = { accounts: DevAccount[]; imported: number; skipped: number }

/** Reads `kedro_players` and `kedro_games` from the web app's Supabase table (read-only). */
export async function fetchLegacyRows(url: string, anonKey: string): Promise<unknown> {
  const endpoint = `${url.replace(/\/+$/, '')}/rest/v1/kedro_kv?select=key,value&key=in.(kedro_players,kedro_games)`
  const response = await fetch(endpoint, { headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}` } })
  if (!response.ok) throw new Error(`kedro_kv read failed: ${response.status}`)
  return response.json()
}

/** Imports the web data and makes a claimed test account for every legacy player. */
export async function seedFromLegacy(rows: unknown, { store, services }: { store: Store; services: Services }): Promise<SeedReport> {
  const data = readLegacyExport(rows)
  const report = await importLegacy(data, { store, services, apply: true })
  const codes = new Map(report.codes.map((row) => [row.legacyId, row.claimCode]))
  const handles = new Set<string>()
  const accounts: DevAccount[] = []
  for (const [index, legacy] of data.players.entries()) {
    if (legacy.deleted) continue
    const displayName = legacy.username.trim().slice(0, 40) || `Player ${index + 1}`
    const id = stableUUID('dev-account', legacy.id)
    const handle = uniqueHandle(displayName, handles)
    await store.upsertPlayer(id, { displayName, handle, avatar: avatarFor(legacy.emoji, id) })
    const code = codes.get(legacy.id)
    const gamesClaimed = code ? (await services.social.claim(id, code)).gamesClaimed : 0
    accounts.push({ id, displayName, handle, gamesClaimed })
  }
  accounts.sort((a, b) => b.gamesClaimed - a.gamesClaimed || a.displayName.localeCompare(b.displayName))
  return { accounts, imported: report.imported, skipped: report.skipped.length }
}

function uniqueHandle(name: string, taken: Set<string>): string {
  let base = name.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 16)
  if (base.length < 3) base = `${base}player`.slice(0, 16)
  for (let n = 1; ; n++) {
    const handle = normalizeHandle(n === 1 ? base : `${base}${n}`)
    if (handle && !taken.has(handle)) {
      taken.add(handle)
      return handle
    }
  }
}

function avatarFor(emoji: string | undefined, id: UUID): Avatar {
  const seed = parseInt(id.slice(0, 2), 16)
  if (emoji) return { kind: 'emoji', emoji, colorIndex: seed % EMOJI_COLOR_COUNT }
  return { kind: 'curated', id: CURATED_AVATAR_IDS[seed % CURATED_AVATAR_IDS.length] }
}
