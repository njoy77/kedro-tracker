// Imports the legacy web app's history (`kedro_kv`) into the v3 schema (PRD §3.2, §9, decision 7).
//
//   bun scripts/import-legacy.ts --file export.json --codes ~/kedro-legacy-codes.json           # dry run
//   bun scripts/import-legacy.ts --file export.json --codes ~/kedro-legacy-codes.json --apply   # write
//   bun scripts/import-legacy.ts --from-kv --codes ~/kedro-legacy-codes.json [--apply]           # read kedro_kv directly
//
// Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (from `bun run env:pull`, apps/api/.env.local)
// for --apply and --from-kv. Without --apply nothing is written anywhere except the codes file.
//
// The codes file holds every legacy username's claim code (`{legacyPlayerId: code}`). It is a
// secret: keep it outside the repo, and hand each person their own code (they redeem it in the
// app under "Got a claim code?"). Re-runs reuse it, so codes already handed out stay valid.

import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { createServices } from '../apps/api/src/app.ts'
import { loadConfig } from '../apps/api/src/config.ts'
import { importLegacy } from '../apps/api/src/legacy/importer.ts'
import { readLegacyExport } from '../apps/api/src/legacy/convert.ts'
import { MemoryStore } from '../apps/api/src/store/memory.ts'
import { SupabaseStore } from '../apps/api/src/store/supabase.ts'
import type { Store } from '../apps/api/src/store/types.ts'

const args = process.argv.slice(2)
const flag = (name: string) => args.includes(name)
const value = (name: string) => {
  const index = args.indexOf(name)
  return index >= 0 ? args[index + 1] : undefined
}

const apply = flag('--apply')
const codesPath = value('--codes')
if (!codesPath) throw new Error('Pass --codes <path outside the repo> for the claim codes file')
if (resolve(codesPath).startsWith(resolve(import.meta.dir, '..'))) throw new Error('Keep the claim codes file outside the repo')

const config = loadConfig()
const needsSupabase = apply || flag('--from-kv')
if (needsSupabase && !config.supabase) throw new Error(`Supabase is not configured (missing ${config.missing.join(', ')})`)
const supabase = needsSupabase && config.supabase ? new SupabaseStore(config.supabase) : null

let raw: unknown
const file = value('--file')
if (file) {
  raw = JSON.parse(readFileSync(file, 'utf8'))
} else if (flag('--from-kv') && config.supabase) {
  const response = await fetch(`${config.supabase.url}/rest/v1/kedro_kv?select=key,value&key=in.(kedro_players,kedro_games)`, {
    headers: { apikey: config.supabase.serviceRoleKey, authorization: `Bearer ${config.supabase.serviceRoleKey}` },
  })
  if (!response.ok) throw new Error(`Reading kedro_kv failed: ${response.status}`)
  raw = await response.json()
} else {
  throw new Error('Pass --file <export.json> or --from-kv')
}

const existingCodes = existsSync(codesPath) ? (JSON.parse(readFileSync(codesPath, 'utf8')) as Record<string, string>) : {}
const store: Store = apply && supabase ? supabase : new MemoryStore()
const services = createServices({ store, clipSecret: config.clipSecret })
const report = await importLegacy(readLegacyExport(raw), { store, services, existingCodes, apply })

writeFileSync(codesPath, `${JSON.stringify(Object.fromEntries(report.codes.map((row) => [row.legacyId, row.claimCode])), null, 2)}\n`, { mode: 0o600 })
const reasons = report.skipped.reduce<Record<string, number>>((counts, row) => ({ ...counts, [row.reason]: (counts[row.reason] ?? 0) + 1 }), {})
console.log(`${apply ? 'Imported' : 'Would import'} ${report.imported} game(s); ${report.alreadyImported} already imported.`)
console.log(`Skipped ${report.skipped.length}: ${JSON.stringify(reasons)}`)
console.log(`${report.codes.length} legacy username(s) are claimable; codes written to ${codesPath}`)
for (const row of report.codes) console.log(`  ${row.displayName}  guest ${row.guestId}`)
