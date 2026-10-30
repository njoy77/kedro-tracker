// Derivations both stores compute the same way from finished-game seats, so the in-memory store
// used by tests behaves exactly like Supabase.

import { compareStrings, normalizeForFilter, subjectOf, type StatsRow, type UUID } from '@kedro/shared'
import type { GuestSuggestionRow, PlayedWithRow } from './types.ts'

/** One seat in a finished, non-abandoned game, with the player behind claimed guests filled in. */
export type FinishedSeatDetail = {
  gameId: UUID
  finishedAtMs: number
  seatId: string
  playerId: UUID | null
  guestId: UUID | null
  seatOrder: number
  displayName: string
  total: number
  isWinner: boolean
  roundsPlayed: number
  knocks: number
  knocksLanded: number
  knocksTied: number
  knocksFailed: number
}

/**
 * Stats rows with a player's own seat ahead of a claimed guest seat in the same game, so
 * aggregateStats (which keeps one row per game) counts the player's own result.
 */
export function orderStatsRows(seats: readonly FinishedSeatDetail[]): StatsRow[] {
  return [...seats]
    .sort((a, b) => Number(a.guestId !== null) - Number(b.guestId !== null) || compareStrings(a.gameId, b.gameId))
    .map((seat) => ({
      gameId: seat.gameId,
      finishedAtMs: seat.finishedAtMs,
      subject: subjectOf(seat),
      total: seat.total,
      isWinner: seat.isWinner,
      roundsPlayed: seat.roundsPlayed,
      knocks: seat.knocks,
      knocksLanded: seat.knocksLanded,
      knocksTied: seat.knocksTied,
      knocksFailed: seat.knocksFailed,
    }))
}

/** Everyone `playerId` shared a finished game with, most recent first. */
export function playedWithFrom(seats: readonly FinishedSeatDetail[], playerId: UUID): PlayedWithRow[] {
  const games = new Set(seats.filter((seat) => seat.playerId === playerId).map((seat) => seat.gameId))
  const together = new Map<UUID, PlayedWithRow & { games: Set<UUID> }>()
  for (const seat of seats) {
    if (!games.has(seat.gameId) || !seat.playerId || seat.playerId === playerId) continue
    const row = together.get(seat.playerId) ?? { playerId: seat.playerId, gamesTogether: 0, lastPlayedMs: 0, games: new Set<UUID>() }
    row.games.add(seat.gameId)
    row.gamesTogether = row.games.size
    row.lastPlayedMs = Math.max(row.lastPlayedMs, seat.finishedAtMs)
    together.set(seat.playerId, row)
  }
  return [...together.values()]
    .sort((a, b) => b.lastPlayedMs - a.lastPlayedMs || b.gamesTogether - a.gamesTogether || compareStrings(a.playerId, b.playerId))
    .map(({ playerId: id, gamesTogether, lastPlayedMs }) => ({ playerId: id, gamesTogether, lastPlayedMs }))
}

/** Unclaimed guests from `playerId`'s finished games whose name matches ("Sam · guest · 2 games with you"). */
export function guestSuggestionsFrom(seats: readonly FinishedSeatDetail[], playerId: UUID, name: string): GuestSuggestionRow[] {
  const wanted = normalizeForFilter(name, { lookalikes: false })
  const games = new Set(seats.filter((seat) => seat.playerId === playerId).map((seat) => seat.gameId))
  const counts = new Map<UUID, GuestSuggestionRow & { games: Set<UUID>; lastMs: number }>()
  for (const seat of seats) {
    if (!games.has(seat.gameId) || !seat.guestId || seat.playerId) continue
    if (wanted && !normalizeForFilter(seat.displayName, { lookalikes: false }).includes(wanted)) continue
    const row = counts.get(seat.guestId) ?? { guestId: seat.guestId, name: seat.displayName, gamesTogether: 0, games: new Set<UUID>(), lastMs: 0 }
    row.games.add(seat.gameId)
    row.gamesTogether = row.games.size
    if (seat.finishedAtMs >= row.lastMs) {
      row.lastMs = seat.finishedAtMs
      row.name = seat.displayName // the most recent spelling
    }
    counts.set(seat.guestId, row)
  }
  return [...counts.values()]
    .sort((a, b) => b.gamesTogether - a.gamesTogether || b.lastMs - a.lastMs)
    .map(({ guestId, name: guestName, gamesTogether }) => ({ guestId, name: guestName, gamesTogether }))
}
