// The legacy web app's history (`kedro_kv`: `kedro_players`, `kedro_games`): reading it, turning
// its rounds into v3 rounds, and ranking it exactly like the server ranks the imported games.
// The API's importer (apps/api/src/legacy) builds operation logs from `legacyRounds`; the web app
// builds its leaderboard with `legacyLeaderboard`, so both read the same history the same way.
//
// The legacy app stored round *scores*, with the knock result marked by the scorekeeper, and let
// a round be saved with no knocker. Imported rounds keep those saved scores exactly, with hands
// filled in from them (`legacyHands`). A round with no knocker recorded credits no knock to anyone;
// the web app's inherent knock ("IK") is kept. Rounds where everyone scored 0 were the web app
// being tested and are dropped. A game that was abandoned, has fewer than 3 or more than 8
// players, or has no rounds left is skipped.

import { COUNTED_MIN_ROUNDS, SEAT_LIMITS, type Round } from './domain.ts'
import { seatIdOf, type SeatId } from './ids.ts'
import { buildLeaderboard, type BuiltLeaderboard, type LeaderboardSort } from './leaderboard.ts'
import { replayRatings, type RatedGame } from './ratings.ts'
import { FAILED_PENALTY, HAND_MAX, HAND_MIN, LANDED_SCORE, isInherentKnock, outcomeOf, scoresOf } from './scoring.ts'
import { aggregateStats, type StatsRow } from './stats.ts'

export type LegacyPlayer = { id: string; username: string; emoji?: string; deleted?: boolean }
export type LegacyRound = {
  id?: string
  timestamp?: number
  scores: { playerId: string; score: number }[]
  knockedBy?: string | null
  /** 'correct' | 'tied' | 'incorrect', marked by the scorekeeper (absent before tied knocks existed). */
  knockResult?: string | null
  /** Who went out with an inherent knock (all four cards played), if anyone. */
  inherentKnock?: string | null
}
export type LegacyGame = {
  id: string
  startedAt?: number
  endedAt?: number
  status?: string
  players: { id: string; username: string; emoji?: string; total?: number }[]
  rounds: LegacyRound[]
}

export type LegacyExport = { players: LegacyPlayer[]; games: LegacyGame[] }

export type LegacySkipReason = 'abandoned' | 'tooFewPlayers' | 'tooManyPlayers' | 'noRounds' | 'unknownPlayer'

/** Reads a `kedro_kv` export: either `[{key, value}]` rows or `{kedro_players, kedro_games}`. */
export function readLegacyExport(json: unknown): LegacyExport {
  const lookup = (key: string): unknown => {
    if (Array.isArray(json)) return (json as { key?: string; value?: unknown }[]).find((row) => row.key === key)?.value
    if (json && typeof json === 'object') return (json as Record<string, unknown>)[key]
    return undefined
  }
  const players = Array.isArray(lookup('kedro_players')) ? (lookup('kedro_players') as LegacyPlayer[]) : []
  const games = Array.isArray(lookup('kedro_games')) ? (lookup('kedro_games') as LegacyGame[]) : []
  return { players, games }
}

/**
 * A legacy game's rounds as v3 rounds (seats named by `seatOf`, in the game's player order), or
 * why it can't be imported. `timestamps` are the rounds' saved times, for the operation log.
 */
export function legacyRounds(
  game: LegacyGame,
  seatOf: (legacyPlayerId: string) => SeatId,
): { order: SeatId[]; rounds: Round[]; timestamps: (number | undefined)[] } | { skipped: LegacySkipReason } {
  if (game.status !== 'complete') return { skipped: 'abandoned' }
  if (game.players.length < SEAT_LIMITS.min) return { skipped: 'tooFewPlayers' }
  if (game.players.length > SEAT_LIMITS.max) return { skipped: 'tooManyPlayers' }
  if (game.rounds.length === 0) return { skipped: 'noRounds' }

  const seatIdByLegacy = new Map(game.players.map((player) => [player.id, seatOf(player.id)]))
  const order = game.players.map((player) => seatIdByLegacy.get(player.id) ?? '')
  const seatFor = (legacyId: string | null | undefined) => (legacyId ? seatIdByLegacy.get(legacyId) ?? null : null)
  const rounds: Round[] = []
  const timestamps: (number | undefined)[] = []
  for (const legacyRound of game.rounds) {
    const scores: Record<string, number> = {}
    for (const { playerId, score } of legacyRound.scores) {
      const seat = seatIdByLegacy.get(playerId)
      if (!seat) return { skipped: 'unknownPlayer' }
      scores[seat] = score
    }
    if (!order.every((seat) => scores[seat] !== undefined)) return { skipped: 'unknownPlayer' }
    // Rounds where everyone scored 0 were the web app being tested, not play.
    if (order.every((seat) => scores[seat] === 0)) continue
    const knocker = seatFor(legacyRound.knockedBy) ?? seatFor(legacyRound.inherentKnock)
    const inherent = seatFor(legacyRound.inherentKnock)
    if ((legacyRound.knockedBy && !seatFor(legacyRound.knockedBy)) || (legacyRound.inherentKnock && !inherent)) return { skipped: 'unknownPlayer' }
    const round: Round = { number: rounds.length + 1, hands: legacyHands(scores, order, knocker, inherent, legacyRound.knockResult), scores }
    if (knocker) round.knocker = knocker
    if (inherent) round.inherent = inherent
    rounds.push(round)
    timestamps.push(legacyRound.timestamp)
  }
  if (rounds.length === 0) return { skipped: 'noRounds' }
  return { order, rounds, timestamps }
}

/**
 * Hand values for an imported round, whose saved scores are kept as they were. The web app saved
 * scores, not hands: everyone else's score is their hand; an inherent knocker's hand is 0; a
 * beaten knocker's is their score − 10; a tied knocker's is their score. A landed knocker's hand
 * wasn't saved, so it's the lowest hand that still landed (one under the next lowest).
 */
function legacyHands(scores: Record<string, number>, order: readonly string[], knocker: string | null, inherent: string | null, result: string | null | undefined): Record<string, number> {
  const clamp = (hand: number) => Math.min(Math.max(hand, HAND_MIN), HAND_MAX)
  const hands: Record<string, number> = {}
  for (const seat of order) hands[seat] = clamp(scores[seat])
  if (inherent) hands[inherent] = 0
  if (knocker && knocker !== inherent) {
    const score = scores[knocker]
    const others = order.filter((seat) => seat !== knocker).map((seat) => hands[seat])
    if (score === LANDED_SCORE) hands[knocker] = clamp(Math.min(...others) - 1)
    else if (result === 'incorrect' || (result == null && score - FAILED_PENALTY >= HAND_MIN && score - FAILED_PENALTY > Math.min(...others))) hands[knocker] = clamp(score - FAILED_PENALTY)
  }
  return hands
}

/**
 * When an imported game finished, as its operation log records it: each operation is a
 * millisecond after the last, or at its saved time when that's later (GameCreated, a seat per
 * player, GameStarted, the rounds, then GameFinished at `endedAt`).
 */
export function legacyFinishedAtMs(game: LegacyGame, timestamps: readonly (number | undefined)[]): number {
  let wallMs = game.startedAt ?? game.rounds[0]?.timestamp ?? 0
  const tick = (atMs?: number) => (wallMs = Math.max(wallMs + 1, atMs ?? wallMs + 1))
  tick(wallMs)
  for (let seat = 0; seat < game.players.length; seat++) tick()
  tick()
  for (const timestamp of timestamps) tick(timestamp)
  return tick(game.endedAt)
}

/**
 * The legacy history's leaderboard by the server's rules (packages/shared stats, ratings and
 * leaderboard): what `GET /v1/leaderboard?scope=global` shows once every legacy player has
 * claimed their history. Subjects are `"p:<legacy player id>"`; deleted players' seats rate like
 * unclaimed guests (`"g:…"`) and are never listed.
 */
export function legacyLeaderboard(data: LegacyExport, sort: LeaderboardSort): BuiltLeaderboard {
  const active = new Set(data.players.filter((player) => !player.deleted).map((player) => player.id))
  const subjectOf = (legacyId: string) => (active.has(legacyId) ? `p:${legacyId}` : `g:${legacyId}`)
  const statsRows: StatsRow[] = []
  const rated: RatedGame[] = []
  for (const game of data.games) {
    const converted = legacyRounds(game, (id) => seatIdOf({ kind: 'guest', id }))
    if ('skipped' in converted || converted.rounds.length < COUNTED_MIN_ROUNDS) continue
    const { order, rounds } = converted
    const finishedAtMs = legacyFinishedAtMs(game, converted.timestamps)
    const totals = new Map(order.map((seat) => [seat, 0]))
    for (const round of rounds) {
      for (const [seat, score] of Object.entries(scoresOf(round))) totals.set(seat, (totals.get(seat) ?? 0) + score)
    }
    const best = Math.min(...totals.values())
    rated.push({ gameId: game.id, finishedAtMs, placements: game.players.map((player, index) => ({ subject: subjectOf(player.id), total: totals.get(order[index]) ?? 0 })) })
    game.players.forEach((player, index) => {
      if (!active.has(player.id)) return
      const seat = order[index]
      let knocks = 0, landed = 0, tied = 0, failed = 0
      for (const round of rounds) {
        // Inherent knocks are their own stat, not knocks (they can't fail).
        if (round.knocker !== seat || isInherentKnock(round)) continue
        knocks += 1
        const outcome = outcomeOf(round)
        if (outcome === 'landed') landed += 1
        else if (outcome === 'tied') tied += 1
        else if (outcome === 'failed') failed += 1
      }
      const total = totals.get(seat) ?? 0
      statsRows.push({
        gameId: game.id, finishedAtMs, subject: subjectOf(player.id), total, isWinner: total === best,
        roundsPlayed: rounds.length, knocks, knocksLanded: landed, knocksTied: tied, knocksFailed: failed,
      })
    })
  }
  return buildLeaderboard({ stats: aggregateStats(statsRows).values(), ratings: replayRatings(rated).ratings, sort })
}
