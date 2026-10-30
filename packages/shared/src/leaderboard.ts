// Leaderboard ranking (PRD §5.3, design §12.4).
//
// - A player needs 10 finished, non-abandoned games to hold a placement ("Not Yet Ranked" below):
//   ratings over fewer games swing too much on one result to rank people by.
// - Sorts: rating (default), win rate, wins, avg score (lower is better), knock success.
// - Per-sort minimums on top of that: win rate needs 10 games (the same as ranking), knock success
//   needs 15 knocks.
//   Below a sort's minimum a player is listed after the ranked rows without a number.
// - The rank shown is the rank for that sort (competition ranking: ties share a number).

import { displayRating, RATING_START, type Rating } from './ratings.ts'
import type { PlayerStats, Subject } from './stats.ts'

export const LEADERBOARD_SORTS = ['rating', 'winRate', 'wins', 'avgScore', 'knockSuccess'] as const
export type LeaderboardSort = (typeof LEADERBOARD_SORTS)[number]
export const LEADERBOARD_SCOPES = ['global', 'playedWith'] as const
export type LeaderboardScope = (typeof LEADERBOARD_SCOPES)[number]

export const LEADERBOARD_MINIMUMS = {
  /** Games to hold any placement (and to reveal a rating). */
  rankGames: 10,
  winRateGames: 10,
  knockSuccessKnocks: 15,
} as const

export type LeaderboardEntry = {
  subject: Subject
  /** Rank for this sort, or null when below the sort's minimum. */
  rank: number | null
  /** The sorted-on value (rating rounded), or null when below the minimum. */
  value: number | null
  rating: number
  stats: PlayerStats
  /** What a below-minimum player still needs for this sort. */
  needs?: { games?: number; knocks?: number }
}

export type NotYetRankedEntry = { subject: Subject; gamesPlayed: number; gamesToRank: number }

export type BuiltLeaderboard = {
  /** Ranked rows, then below-minimum rows (rank null), in display order. */
  rows: LeaderboardEntry[]
  notYetRanked: NotYetRankedEntry[]
}

export type LeaderboardInput = {
  /** Stats for every subject in scope (players only; unclaimed guests never appear). */
  stats: Iterable<PlayerStats>
  ratings: ReadonlyMap<Subject, Rating>
  sort: LeaderboardSort
}

export function buildLeaderboard({ stats, ratings, sort }: LeaderboardInput): BuiltLeaderboard {
  const eligible: PlayerStats[] = []
  const notYetRanked: NotYetRankedEntry[] = []
  for (const entry of stats) {
    if (entry.gamesPlayed >= LEADERBOARD_MINIMUMS.rankGames) eligible.push(entry)
    else notYetRanked.push({
      subject: entry.subject,
      gamesPlayed: entry.gamesPlayed,
      gamesToRank: LEADERBOARD_MINIMUMS.rankGames - entry.gamesPlayed,
    })
  }

  const ratingOf = (subject: Subject) => displayRating(ratings.get(subject)?.rating ?? RATING_START)
  const qualifying: LeaderboardEntry[] = []
  const below: LeaderboardEntry[] = []
  for (const entry of eligible) {
    const needs = sortNeeds(entry, sort)
    const row: LeaderboardEntry = { subject: entry.subject, rank: null, value: null, rating: ratingOf(entry.subject), stats: entry }
    if (needs) below.push({ ...row, needs })
    else qualifying.push({ ...row, value: sortValue(entry, row.rating, sort) })
  }

  const ascending = sort === 'avgScore'
  qualifying.sort((a, b) => {
    const left = a.value ?? 0
    const right = b.value ?? 0
    if (left !== right) return ascending ? left - right : right - left
    return tieBreak(a, b)
  })
  qualifying.forEach((row, index) => {
    const previous = qualifying[index - 1]
    row.rank = previous && previous.value === row.value ? previous.rank : index + 1
  })
  below.sort((a, b) => b.stats.gamesPlayed - a.stats.gamesPlayed || b.stats.knocks - a.stats.knocks || tieBreak(a, b))
  notYetRanked.sort((a, b) => b.gamesPlayed - a.gamesPlayed || compare(a.subject, b.subject))

  return { rows: [...qualifying, ...below], notYetRanked }
}

function sortNeeds(stats: PlayerStats, sort: LeaderboardSort): LeaderboardEntry['needs'] | undefined {
  if (sort === 'winRate' && stats.gamesPlayed < LEADERBOARD_MINIMUMS.winRateGames) {
    return { games: LEADERBOARD_MINIMUMS.winRateGames - stats.gamesPlayed }
  }
  if (sort === 'knockSuccess' && stats.knocks < LEADERBOARD_MINIMUMS.knockSuccessKnocks) {
    return { knocks: LEADERBOARD_MINIMUMS.knockSuccessKnocks - stats.knocks }
  }
  return undefined
}

function sortValue(stats: PlayerStats, rating: number, sort: LeaderboardSort): number {
  switch (sort) {
    case 'rating':
      return rating
    case 'winRate':
      return round(stats.winRate, 4)
    case 'wins':
      return stats.wins
    case 'avgScore':
      return round(stats.avgScore, 2)
    case 'knockSuccess':
      return round(stats.knockSuccess ?? 0, 4)
  }
}

function tieBreak(a: LeaderboardEntry, b: LeaderboardEntry): number {
  return b.stats.gamesPlayed - a.stats.gamesPlayed || compare(a.subject, b.subject)
}

function round(value: number, places: number): number {
  const factor = 10 ** places
  return Math.round(value * factor) / factor
}

function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}
