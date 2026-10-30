// GET /v1/leaderboard (PRD §5.3, design §12.4). Ranking rules live in packages/shared
// (buildLeaderboard); this gathers the scope's stats and ratings and attaches profiles.

import {
  buildLeaderboard,
  RATING_START,
  displayRating,
  type LeaderboardEntry,
  type LeaderboardResponse,
  type LeaderboardRow,
  type LeaderboardScope,
  type LeaderboardSort,
  type NotYetRankedEntry,
  type NotYetRankedRow,
  type PlayerProfileResponse,
  type PlayerSummary,
  type UUID,
} from '@kedro/shared'
import { notFound } from '../http.ts'
import type { Store } from '../store/types.ts'
import { toSummary, type PlayersService } from './players.ts'

export const DEFAULT_LEADERBOARD_LIMIT = 100
export const MAX_LEADERBOARD_LIMIT = 500

export class LeaderboardService {
  constructor(
    private readonly store: Store,
    private readonly players: PlayersService,
  ) {}

  async leaderboard(
    caller: UUID,
    { scope, sort, limit = DEFAULT_LEADERBOARD_LIMIT }: { scope: LeaderboardScope; sort: LeaderboardSort; limit?: number },
  ): Promise<LeaderboardResponse> {
    const cap = Math.min(Math.max(1, limit), MAX_LEADERBOARD_LIMIT)
    const hidden = await this.players.hiddenFrom(caller)
    const scopeIds = scope === 'playedWith' ? [caller, ...(await this.store.playedWith(caller)).map((row) => row.playerId)] : undefined
    const stats = (await this.store.playerStats(scopeIds)).filter((entry) => !hidden.has(entry.subject.slice(2)))
    const ratings = await this.store.ratings(stats.map((entry) => entry.subject))
    const built = buildLeaderboard({ stats, ratings, sort })

    const ids = [...built.rows, ...built.notYetRanked].map((entry) => entry.subject.slice(2))
    const profiles = new Map((await this.store.getPlayers(ids)).map((row) => [row.id, row]))
    const summary = (subject: string, gamesPlayed: number): PlayerSummary | null => {
      const row = profiles.get(subject.slice(2))
      return row ? toSummary(row, gamesPlayed) : null
    }

    const me = `p:${caller}`
    const rows = built.rows.flatMap((entry) => {
      const player = summary(entry.subject, entry.stats.gamesPlayed)
      return player ? [leaderboardRow(entry, player, entry.subject === me)] : []
    })
    const notYetRanked = built.notYetRanked.flatMap((entry) => {
      const player = summary(entry.subject, entry.gamesPlayed)
      return player ? [notYetRankedRow(entry, player, entry.subject === me)] : []
    })

    const response: LeaderboardResponse = {
      scope,
      sort,
      rows: rows.slice(0, cap),
      notYetRanked: notYetRanked.slice(0, cap),
      notYetRankedCount: notYetRanked.length,
    }
    const mine = rows.find((row) => row.isMe) ?? notYetRanked.find((row) => row.isMe)
    if (mine) response.me = mine
    return response
  }

  /**
   * GET /v1/players/:playerId/profile: one player's server-side record. The rank is the global
   * rating rank over everyone (not filtered by the caller's blocks), so every phone shows the same
   * number for the same person.
   */
  async profile(caller: UUID, playerId: UUID): Promise<PlayerProfileResponse> {
    const hidden = await this.players.hiddenFrom(caller)
    const row = hidden.has(playerId) ? null : await this.store.getPlayer(playerId)
    if (!row) throw notFound('No such player')
    const subject = `p:${playerId}`
    const everyone = await this.store.playerStats()
    const ratings = await this.store.ratings(everyone.map((entry) => entry.subject))
    const mine = everyone.find((entry) => entry.subject === subject)
    const built = buildLeaderboard({ stats: everyone, ratings, sort: 'rating' })
    const ranked = built.rows.find((entry) => entry.subject === subject)
    const rating = ratings.get(subject)
    const response: PlayerProfileResponse = {
      player: toSummary(row, mine?.gamesPlayed ?? 0),
      rating: rating ? displayRating(rating.rating) : null,
      globalRank: ranked?.rank ?? null,
    }
    if (mine) {
      response.stats = {
        gamesPlayed: mine.gamesPlayed,
        wins: mine.wins,
        winRate: mine.winRate,
        avgScore: mine.avgScore,
        knocks: mine.knocks,
        knocksLanded: mine.knocksLanded,
        knockSuccess: mine.knockSuccess,
      }
    }
    return response
  }
}

function leaderboardRow(entry: LeaderboardEntry, player: PlayerSummary, isMe: boolean): LeaderboardRow {
  const { stats } = entry
  const row: LeaderboardRow = {
    rank: entry.rank,
    player,
    value: entry.value,
    rating: entry.rating ?? displayRating(RATING_START),
    gamesPlayed: stats.gamesPlayed,
    wins: stats.wins,
    winRate: stats.winRate,
    avgScore: stats.avgScore,
    knocks: stats.knocks,
    knocksLanded: stats.knocksLanded,
    knockSuccess: stats.knockSuccess,
    isMe,
  }
  if (entry.needs) row.needs = entry.needs
  return row
}

function notYetRankedRow(entry: NotYetRankedEntry, player: PlayerSummary, isMe: boolean): NotYetRankedRow {
  return { player, gamesPlayed: entry.gamesPlayed, gamesToRank: entry.gamesToRank, isMe }
}
