// Profiles, search and the player directory.

import {
  isoSeconds,
  normalizeHandle,
  type GuestSuggestion,
  type PlayedWithRow,
  type Player,
  type PlayerSummary,
  type UUID,
} from '@kedro/shared'
import { HttpError, notFound } from '../http.ts'
import { HandleTakenError, type PlayerRow, type PlayerUpdate, type Store } from '../store/types.ts'

export const SEARCH_LIMIT = 20
export const DIRECTORY_PAGE = 50

export class PlayersService {
  constructor(private readonly store: Store) {}

  async me(caller: UUID): Promise<Player> {
    return toPlayer(await this.requireProfile(caller))
  }

  /** The caller's profile row, or 404 `profileRequired` (sign-up isn't finished yet). */
  async requireProfile(caller: UUID): Promise<PlayerRow> {
    const row = await this.store.getPlayer(caller)
    if (!row) throw new HttpError(404, 'profileRequired', 'Finish setting up your profile first')
    return row
  }

  async updateMe(caller: UUID, update: PlayerUpdate): Promise<Player> {
    try {
      return toPlayer(await this.store.upsertPlayer(caller, update))
    } catch (error) {
      if (error instanceof HandleTakenError) throw new HttpError(409, 'handleTaken', 'That handle is taken')
      throw error
    }
  }

  async handleAvailable(caller: UUID, input: string): Promise<{ handle: string; available: boolean }> {
    const handle = normalizeHandle(input)
    if (!handle) throw new HttpError(400, 'invalidRequest', 'Handles are 3–20 characters: a–z, 0–9, "." and "_"')
    return { handle, available: await this.store.isHandleAvailable(handle, caller) }
  }

  /** Display name contains the query, or handle starts with it; "@" searches handles only. Blocked players (either way) are excluded. */
  async search(caller: UUID, rawQuery: string, limit = SEARCH_LIMIT): Promise<PlayerSummary[]> {
    let query = rawQuery.trim().toLowerCase()
    const handleOnly = query.startsWith('@')
    if (handleOnly) query = query.slice(1)
    if (!query) return []
    const hidden = await this.hiddenFrom(caller)
    const rows = await this.store.searchPlayers(query.slice(0, 40), {
      limit: Math.min(Math.max(1, limit), 50),
      excludeIds: [caller, ...hidden],
      handleOnly,
    })
    return this.summaries(rows)
  }

  /** One page of every player A–Z (`PlayerDirectoryResponse`). The cursor is the next row offset. */
  async directory(caller: UUID, cursor: string | undefined, limit = DIRECTORY_PAGE): Promise<{ players: PlayerSummary[]; next: string | null }> {
    const offset = cursor === undefined || cursor === '' ? 0 : Number(cursor)
    if (!Number.isInteger(offset) || offset < 0) throw new HttpError(400, 'invalidRequest', 'cursor is not valid')
    const size = Math.min(Math.max(1, limit), 100)
    const rows = await this.store.listPlayers({ offset, limit: size })
    const hidden = await this.hiddenFrom(caller)
    const visible = rows.filter((row) => row.id !== caller && !hidden.has(row.id))
    return { players: await this.summaries(visible), next: rows.length === size ? String(offset + size) : null }
  }

  async player(caller: UUID, playerId: UUID): Promise<PlayerSummary> {
    const hidden = await this.hiddenFrom(caller)
    const row = hidden.has(playerId) ? null : await this.store.getPlayer(playerId)
    if (!row) throw notFound('No such player')
    const [summary] = await this.summaries([row])
    return summary
  }

  async playedWith(caller: UUID): Promise<PlayedWithRow[]> {
    const rows = await this.store.playedWith(caller)
    const hidden = await this.hiddenFrom(caller)
    const visible = rows.filter((row) => !hidden.has(row.playerId))
    const summaries = new Map((await this.summaries(await this.store.getPlayers(visible.map((row) => row.playerId)))).map((s) => [s.id, s]))
    return visible.flatMap((row) => {
      const player = summaries.get(row.playerId)
      return player ? [{ player, gamesTogether: row.gamesTogether, lastPlayedAt: isoSeconds(row.lastPlayedMs) }] : []
    })
  }

  async guestSuggestions(caller: UUID, name: string): Promise<GuestSuggestion[]> {
    return (await this.store.guestSuggestions(caller, name.slice(0, 40))).slice(0, SEARCH_LIMIT)
  }

  /** Players the caller blocked or who blocked the caller. */
  async hiddenFrom(caller: UUID): Promise<Set<UUID>> {
    const { blocked, blockedBy } = await this.store.blockRelations(caller)
    return new Set([...blocked, ...blockedBy])
  }

  /** Summaries with lifetime games played. */
  async summaries(rows: readonly PlayerRow[]): Promise<PlayerSummary[]> {
    if (rows.length === 0) return []
    const stats = new Map((await this.store.playerStats(rows.map((row) => row.id))).map((entry) => [entry.subject, entry]))
    return rows.map((row) => toSummary(row, stats.get(`p:${row.id}`)?.gamesPlayed ?? 0))
  }
}

export function toPlayer(row: PlayerRow): Player {
  const player: Player = { id: row.id, displayName: row.displayName, handle: row.handle, avatar: row.avatar, createdAt: isoSeconds(row.createdAt) }
  if (row.titleId) player.titleId = row.titleId
  return player
}

export function toSummary(row: PlayerRow, gamesPlayed?: number): PlayerSummary {
  const summary: PlayerSummary = { id: row.id, displayName: row.displayName, handle: row.handle, avatar: row.avatar }
  if (row.titleId) summary.titleId = row.titleId
  if (gamesPlayed !== undefined) summary.gamesPlayed = gamesPlayed
  return summary
}
