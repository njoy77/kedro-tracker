// Records boards (design §12.4): the top holders of each record among a scope's players.
//
// - Best game: lowest final score in a single game (lower is better).
// - Longest streak: longest run of consecutive wins.
// - Most landed knocks: knocks with the strictly lowest hand (−10). Inherent knocks don't count.
// - Most games: finished games, including ended-early ones.
//
// Ties share a rank (competition ranking) and are listed by whoever got there first. Players with
// nothing toward a record (no wins, no landed knocks) aren't listed for it.

import type { UUID } from './ids.ts'
import type { PlayerStats, Subject } from './stats.ts'

export const RECORD_KINDS = ['bestGame', 'longestStreak', 'mostLandedKnocks', 'mostGames'] as const
export type RecordKind = (typeof RECORD_KINDS)[number]

export const DEFAULT_RECORDS_LIMIT = 25

export type RecordEntry = {
  subject: Subject
  rank: number
  value: number
  /** The game the record was set in (best game only). */
  gameId?: UUID
  /** When the record was set: the best game's finish, or when the streak was reached. */
  atMs?: number
}

/** The top `limit` holders of a record, best first. */
export function buildRecords(stats: Iterable<PlayerStats>, kind: RecordKind, limit: number = DEFAULT_RECORDS_LIMIT): RecordEntry[] {
  const candidates: (RecordEntry & { reachedMs: number })[] = []
  for (const entry of stats) {
    if (entry.gamesPlayed === 0) continue
    const lastMs = entry.lastPlayedMs ?? 0
    switch (kind) {
      case 'bestGame':
        if (entry.bestGame !== null) {
          const atMs = entry.bestGameAtMs ?? lastMs
          candidates.push({ subject: entry.subject, rank: 0, value: entry.bestGame, gameId: entry.bestGameId ?? undefined, atMs, reachedMs: atMs })
        }
        break
      case 'longestStreak':
        if (entry.longestWinStreak > 0) {
          const atMs = entry.longestWinStreakAtMs ?? lastMs
          candidates.push({ subject: entry.subject, rank: 0, value: entry.longestWinStreak, atMs, reachedMs: atMs })
        }
        break
      case 'mostLandedKnocks':
        if (entry.knocksLanded > 0) candidates.push({ subject: entry.subject, rank: 0, value: entry.knocksLanded, reachedMs: lastMs })
        break
      case 'mostGames':
        candidates.push({ subject: entry.subject, rank: 0, value: entry.gamesPlayed, reachedMs: lastMs })
        break
    }
  }
  const ascending = kind === 'bestGame'
  candidates.sort((a, b) => (ascending ? a.value - b.value : b.value - a.value) || a.reachedMs - b.reachedMs || compare(a.subject, b.subject))
  const entries: RecordEntry[] = []
  for (const [index, { reachedMs: _, gameId, atMs, ...entry }] of candidates.slice(0, Math.max(0, limit)).entries()) {
    const previous = entries[index - 1]
    const ranked: RecordEntry = { ...entry, rank: previous && previous.value === entry.value ? previous.rank : index + 1 }
    if (gameId !== undefined) ranked.gameId = gameId
    if (atMs !== undefined) ranked.atMs = atMs
    entries.push(ranked)
  }
  return entries
}

function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}
