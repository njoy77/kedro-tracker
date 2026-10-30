// Writes converted legacy games into a Store and rebuilds their projections (games, seats,
// finished games, ratings), exactly as if the ops had been uploaded. Idempotent: op IDs are
// stable, and a guest's first claim token hash stays.

import { randomBytes } from 'node:crypto'
import { hlcString } from '@kedro/shared'
import type { Services } from '../app.ts'
import { claimTokenHash } from '../services/social.ts'
import type { Store } from '../store/types.ts'
import { convertLegacy, type LegacyExport, type LegacyGuest, type SkippedGame } from './convert.ts'

export type ImportReport = {
  imported: number
  alreadyImported: number
  skipped: SkippedGame[]
  /** Every legacy username with its claim code (new codes only for people the server hasn't seen). */
  codes: { legacyId: string; displayName: string; guestId: string; claimCode: string }[]
}

/**
 * @param existingCodes Claim codes from an earlier run (legacy player ID → code), reused so codes
 *   already handed out stay valid.
 * @param apply false for a dry run: convert and report, write nothing.
 */
export async function importLegacy(
  data: LegacyExport,
  { store, services, existingCodes = {}, apply }: { store: Store; services: Services; existingCodes?: Record<string, string>; apply: boolean },
): Promise<ImportReport> {
  const codes = new Map<string, string>(Object.entries(existingCodes))
  const codeFor = (legacyId: string) => {
    let code = codes.get(legacyId)
    if (!code) {
      // Letters, digits and dashes only: the app's claim sheet (iOS PendingClaims.code) takes nothing else.
      code = `kedro-legacy-${randomBytes(16).toString('hex')}`
      codes.set(legacyId, code)
    }
    return code
  }
  const converted = convertLegacy(data, (legacyId) => claimTokenHash(codeFor(legacyId)))
  const report: ImportReport = { imported: 0, alreadyImported: 0, skipped: converted.skipped, codes: [] }
  const used = new Set(converted.guests.map((guest: LegacyGuest) => guest.legacyId))
  for (const guest of converted.guests) {
    if (!used.has(guest.legacyId)) continue
    report.codes.push({ legacyId: guest.legacyId, displayName: guest.displayName, guestId: guest.guestId, claimCode: codeFor(guest.legacyId) })
  }
  if (!apply) {
    report.imported = converted.games.length
    return report
  }
  for (const game of converted.games) {
    const existing = await store.getGame(game.gameId)
    await store.ensureGame(game.gameId, null)
    const inserted = await store.insertOps(game.operations.map((operation) => ({ operation, hlc: hlcString(operation.hlc), receivedBy: null })))
    if (inserted.length === 0 && existing) {
      report.alreadyImported += 1
      continue
    }
    await services.ops.reproject(game.gameId, { previousStatus: existing?.status ?? null, changedShape: true, uploader: null })
    report.imported += 1
  }
  return report
}
