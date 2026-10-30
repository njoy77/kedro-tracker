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
  type PlayerSummary,
  type UUID,
} from '@kedro/shared'
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
