// Skill rating (design §12.4): multiplayer pairwise Elo from finishing order.
//
// - Every pair at a table is a match: finishing ahead (lower total) is a win, equal is a draw.
// - Everyone starts at 1,000.
// - K is scaled by 1/(n−1) for an n-player table, and doubled for a player's first 10 games.
//   Each pair uses the larger of its two players' K, so every game is zero-sum.
// - All of a game's changes are computed from the ratings before that game, then applied together.
// - Ratings are never stored as running counters: they are rebuilt by replaying every finished,
//   non-abandoned game in (finishedAt, gameId) order, so edits, claims and migrated history
//   always come out the same. The iOS app (Core/Stats) uses the same constants and order.

import type { UUID } from './ids.ts'
import type { Subject } from './stats.ts'

export const RATING_START = 1000
export const RATING_K = 32
export const RATING_PROVISIONAL_GAMES = 10
export const RATING_PROVISIONAL_MULTIPLIER = 2
/** Ratings are computed from game 1 but shown from game 10 (the leaderboard eligibility). */
export const RATING_REVEAL_GAMES = 10

export type RatedPlacement = { subject: Subject; total: number }
export type RatedGame = { gameId: UUID; finishedAtMs: number; placements: RatedPlacement[] }

export type Rating = { subject: Subject; rating: number; games: number; lastGameId: UUID | null }
export type RatingChange = { gameId: UUID; subject: Subject; before: number; after: number; delta: number; gameNumber: number }

export type RatingReplay = { ratings: Map<Subject, Rating>; changes: RatingChange[] }

/** Probability that a player rated `a` finishes ahead of one rated `b`. */
export function expectedScore(a: number, b: number): number {
  return 1 / (1 + 10 ** ((b - a) / 400))
}

/** The K-factor for a player with `gamesBefore` rated games at an `n`-player table. */
export function kFactor(gamesBefore: number, tableSize: number): number {
  const base = gamesBefore < RATING_PROVISIONAL_GAMES ? RATING_K * RATING_PROVISIONAL_MULTIPLIER : RATING_K
  return base / Math.max(1, tableSize - 1)
}

/** Replays games deterministically. Games with fewer than two distinct players are skipped. */
export function replayRatings(games: readonly RatedGame[]): RatingReplay {
  const ratings = new Map<Subject, Rating>()
  const changes: RatingChange[] = []
  const orderedGames = [...games].sort(
    (a, b) => a.finishedAtMs - b.finishedAtMs || (a.gameId < b.gameId ? -1 : a.gameId > b.gameId ? 1 : 0),
  )
  for (const game of orderedGames) {
    const placements = dedupe(game.placements)
    if (placements.length < 2) continue
    const before = placements.map(({ subject }) => ratings.get(subject) ?? { subject, rating: RATING_START, games: 0, lastGameId: null })
    // Pairs in seat order, each with the larger of the two players' K, so every game is
    // zero-sum and the sums match the iOS app's float for float (Core/Stats/Ratings.swift).
    const deltas = placements.map(() => 0)
    for (let i = 0; i < placements.length; i++) {
      for (let j = i + 1; j < placements.length; j++) {
        const a = placements[i].total
        const b = placements[j].total
        const actual = a < b ? 1 : a === b ? 0.5 : 0
        const k = Math.max(kFactor(before[i].games, placements.length), kFactor(before[j].games, placements.length))
        const change = k * (actual - expectedScore(before[i].rating, before[j].rating))
        deltas[i] += change
        deltas[j] -= change
      }
    }
    placements.forEach(({ subject }, i) => {
      const previous = before[i]
      const after = previous.rating + deltas[i]
      ratings.set(subject, { subject, rating: after, games: previous.games + 1, lastGameId: game.gameId })
      changes.push({ gameId: game.gameId, subject, before: previous.rating, after, delta: deltas[i], gameNumber: previous.games + 1 })
    })
  }
  return { ratings, changes }
}

/** Ratings are shown as whole numbers ("1,086"). */
export function displayRating(rating: number): number {
  return Math.round(rating)
}

function dedupe(placements: RatedPlacement[]): RatedPlacement[] {
  const seen = new Set<Subject>()
  return placements.filter((placement) => !seen.has(placement.subject) && seen.add(placement.subject))
}
