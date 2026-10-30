// Finished-game projections and lifetime stats (PRD §5.1). All stats are derived from finished,
// non-abandoned games with at least 3 rounds (early-ended games count if they reach 3), never
// from separately maintained counters, so corrections and guest claims always produce correct
// numbers.

import { COUNTED_MIN_ROUNDS, type FinishReason, type Round } from './domain.ts'
import { gameTotals, roundsPlayed, standings, type FoldedGame } from './fold.ts'
import { seatGuestId, seatIdOf, seatPlayerId, type SeatId, type UUID } from './ids.ts'
import { knockOutcome, roundScores } from './scoring.ts'

/** One seat's result in a finished game (a row of `finished_game_seats`). */
export type FinishedSeatResult = {
  seatId: SeatId
  /** The player behind the seat: the seat's own player, or the claiming player for a claimed guest. */
  playerId: UUID | null
  guestId: UUID | null
  displayName: string
  seatOrder: number
  total: number
  rank: number
  rankShared: boolean
  isWinner: boolean
  roundsPlayed: number
  knocks: number
  knocksLanded: number
  knocksTied: number
  knocksFailed: number
  lowestHand: number | null
  highestHand: number | null
}

/** A finished game, ready for stats (a row of `finished_games` plus its seats). */
export type FinishedGameProjection = {
  gameId: UUID
  finishedAtMs: number
  finishReason: FinishReason
  plannedRounds: number
  tableWord: string
  rounds: Round[]
  seats: FinishedSeatResult[]
}

/** True when a finished game counts for stats, ratings and the leaderboard (3+ rounds). */
export function countsForStats(game: Pick<FoldedGame, 'rounds'>): boolean {
  return game.rounds.length >= COUNTED_MIN_ROUNDS
}

/**
 * Projects a finished game; null unless the fold says it is finished and it has the rounds to
 * count. Seats that played fewer than `COUNTED_MIN_ROUNDS` (a late joiner) are left out.
 */
export function projectFinishedGame(game: FoldedGame): FinishedGameProjection | null {
  if (game.status !== 'finished' || game.finishedAtMs === null || game.finishReason === null) return null
  if (!countsForStats(game)) return null
  const totalsBySeat = gameTotals(game)
  const counted = standings(game).filter(({ seat }) => roundsPlayed(game, seatIdOf(seat.player)) >= COUNTED_MIN_ROUNDS)
  const seats = counted.map(({ seat, total, rank, isWinner }): FinishedSeatResult => {
    const seatId = seatIdOf(seat.player)
    let knocks = 0, landed = 0, tied = 0, failed = 0
    let lowest: number | null = null, highest: number | null = null
    for (const round of game.rounds) {
      const hand = round.hands[seatId]
      if (hand === undefined) continue
      lowest = lowest === null ? hand : Math.min(lowest, hand)
      highest = highest === null ? hand : Math.max(highest, hand)
      if (round.knocker !== seatId) continue
      knocks += 1
      const outcome = knockOutcome(round.hands, round.knocker)
      if (outcome === 'landed') landed += 1
      else if (outcome === 'tied') tied += 1
      else if (outcome === 'failed') failed += 1
    }
    return {
      seatId,
      playerId: seatPlayerId(seatId),
      guestId: seatGuestId(seatId),
      displayName: seat.displayName,
      seatOrder: seat.order,
      total: totalsBySeat[seatId] ?? total,
      rank: rank.position,
      rankShared: rank.isShared,
      isWinner,
      roundsPlayed: roundsPlayed(game, seatId),
      knocks,
      knocksLanded: landed,
      knocksTied: tied,
      knocksFailed: failed,
      lowestHand: lowest,
      highestHand: highest,
    }
  })
  return {
    gameId: game.gameId,
    finishedAtMs: game.finishedAtMs,
    finishReason: game.finishReason,
    plannedRounds: game.config.plannedRounds,
    tableWord: game.config.tableWord,
    rounds: game.rounds,
    seats,
  }
}

/** Round scores for one seat across a game (stats helpers). */
export function seatRoundScores(rounds: Round[], seatId: SeatId): number[] {
  return rounds.flatMap((round) => {
    const score = roundScores(round.hands, round.knocker)[seatId]
    return score === undefined ? [] : [score]
  })
}

// MARK: Lifetime stats

/**
 * The identity stats are grouped by: `"p:<playerId>"` for players (including claimed guests,
 * whose rows carry the claiming player's ID) or `"g:<guestId>"` for unclaimed guests.
 */
export type Subject = string

export function subjectOf(row: { playerId: UUID | null; guestId: UUID | null; seatId?: SeatId }): Subject {
  if (row.playerId) return `p:${row.playerId}`
  if (row.guestId) return `g:${row.guestId}`
  return row.seatId ?? 'unknown'
}

/** The input to stats: one seat in one finished, non-abandoned game. */
export type StatsRow = {
  gameId: UUID
  finishedAtMs: number
  subject: Subject
  total: number
  isWinner: boolean
  roundsPlayed: number
  knocks: number
  knocksLanded: number
  knocksTied: number
  knocksFailed: number
}

export type PlayerStats = {
  subject: Subject
  gamesPlayed: number
  wins: number
  /** Wins ÷ games played (0–1). */
  winRate: number
  /** Sum of final scores. */
  totalScore: number
  /** Average final score per game (lower is better). */
  avgScore: number
  roundsPlayed: number
  /** Sum of round scores ÷ rounds played. */
  avgPerRound: number
  knocks: number
  knocksLanded: number
  knocksTied: number
  knocksFailed: number
  /** Rounds knocked ÷ rounds played. */
  knockRate: number
  /** Landed knocks ÷ knocks; null with no knocks. */
  knockSuccess: number | null
  bestGame: number | null
  worstGame: number | null
  currentWinStreak: number
  longestWinStreak: number
}

export function statsRowsFromProjection(projection: FinishedGameProjection): StatsRow[] {
  return projection.seats.map((seat) => ({
    gameId: projection.gameId,
    finishedAtMs: projection.finishedAtMs,
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

/** Lifetime stats per subject. Rows from abandoned games must already be excluded. */
export function aggregateStats(rows: readonly StatsRow[]): Map<Subject, PlayerStats> {
  const bySubject = new Map<Subject, StatsRow[]>()
  for (const row of rows) {
    const list = bySubject.get(row.subject) ?? []
    list.push(row)
    bySubject.set(row.subject, list)
  }
  const result = new Map<Subject, PlayerStats>()
  for (const [subject, list] of bySubject) {
    // One row per game (a claimed guest seated beside their own account counts once).
    const games = dedupeByGame(list).sort((a, b) => a.finishedAtMs - b.finishedAtMs || compare(a.gameId, b.gameId))
    const sum = (pick: (row: StatsRow) => number) => games.reduce((total, row) => total + pick(row), 0)
    const gamesPlayed = games.length
    const wins = games.filter((row) => row.isWinner).length
    const totalScore = sum((row) => row.total)
    const roundsPlayed = sum((row) => row.roundsPlayed)
    const knocks = sum((row) => row.knocks)
    const knocksLanded = sum((row) => row.knocksLanded)
    let longest = 0, run = 0
    for (const row of games) {
      run = row.isWinner ? run + 1 : 0
      longest = Math.max(longest, run)
    }
    let current = 0
    for (let index = games.length - 1; index >= 0 && games[index].isWinner; index--) current += 1
    result.set(subject, {
      subject,
      gamesPlayed,
      wins,
      winRate: gamesPlayed === 0 ? 0 : wins / gamesPlayed,
      totalScore,
      avgScore: gamesPlayed === 0 ? 0 : totalScore / gamesPlayed,
      roundsPlayed,
      avgPerRound: roundsPlayed === 0 ? 0 : totalScore / roundsPlayed,
      knocks,
      knocksLanded,
      knocksTied: sum((row) => row.knocksTied),
      knocksFailed: sum((row) => row.knocksFailed),
      knockRate: roundsPlayed === 0 ? 0 : knocks / roundsPlayed,
      knockSuccess: knocks === 0 ? null : knocksLanded / knocks,
      bestGame: gamesPlayed === 0 ? null : Math.min(...games.map((row) => row.total)),
      worstGame: gamesPlayed === 0 ? null : Math.max(...games.map((row) => row.total)),
      currentWinStreak: current,
      longestWinStreak: longest,
    })
  }
  return result
}

function dedupeByGame(rows: StatsRow[]): StatsRow[] {
  const seen = new Set<UUID>()
  return rows.filter((row) => !seen.has(row.gameId) && seen.add(row.gameId))
}

function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}
