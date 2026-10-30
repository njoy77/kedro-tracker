// Ratings are never updated incrementally: every change to the set of finished games (a finish,
// an abandon or restore of a finished game, a guest claim) replays every finished, non-abandoned
// game with packages/shared's replayRatings and replaces the stored ratings in one go.

import { replayRatings, subjectOf, type RatedGame } from '@kedro/shared'
import type { FinishedSeatRow, Store } from '../store/types.ts'

export class RatingsService {
  private running: Promise<void> | null = null
  private pending = false

  constructor(private readonly store: Store) {}

  /**
   * Replays now. Concurrent calls coalesce: while a replay runs, further requests schedule one
   * more replay after it (so the last change is always included).
   */
  async replay(): Promise<void> {
    if (this.running) {
      this.pending = true
      return this.running
    }
    this.running = (async () => {
      try {
        do {
          this.pending = false
          await this.replayOnce()
        } while (this.pending)
      } finally {
        this.running = null
      }
    })()
    return this.running
  }

  private async replayOnce(): Promise<void> {
    const rows = await this.store.finishedSeatRows()
    const { ratings, changes } = replayRatings(ratedGames(rows))
    await this.store.replaceRatings([...ratings.values()], changes)
  }
}

/** Groups finished seat rows into games, one placement per subject (a claimed guest seated beside their own account counts once). */
export function ratedGames(rows: readonly FinishedSeatRow[]): RatedGame[] {
  const games = new Map<string, RatedGame>()
  // Own seats before claimed guest seats, so the player's own result is the one that counts.
  const sorted = [...rows].sort((a, b) => Number(a.guestId !== null) - Number(b.guestId !== null))
  for (const row of sorted) {
    const game = games.get(row.gameId) ?? { gameId: row.gameId, finishedAtMs: row.finishedAtMs, placements: [] }
    const subject = subjectOf(row)
    if (!game.placements.some((placement) => placement.subject === subject)) game.placements.push({ subject, total: row.total })
    games.set(row.gameId, game)
  }
  return [...games.values()]
}
