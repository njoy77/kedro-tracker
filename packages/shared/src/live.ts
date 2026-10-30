// The Live Activity content state the server broadcasts to a game's APNs broadcast channel
// (design §13.2: "Online updates go server → APNs broadcast channel per game").
//
// A broadcast reaches every phone at the table, so the state is the same for everyone: numbers,
// seat IDs and names only. Each phone renders it in its own language level and finds its own row
// (truncation, "your rank") locally. Keep it small: APNs payloads are limited to 4 KB.
//
// PROPOSAL: the platform agent owns the Swift `ActivityAttributes.ContentState`; its JSON must
// decode this shape (camelCase, optional keys omitted).

import { dealerForRound, standings, type FoldedGame, type GameStatus } from './fold.ts'
import { seatIdOf, type SeatId, type UUID } from './ids.ts'
import { knockOutcome, roundScores, type KnockOutcome } from './scoring.ts'

export type LiveActivityStanding = {
  seatId: SeatId
  displayName: string
  total: number
  rank: number
  rankShared: boolean
  /** The seat's score in the last saved round (the "last delta" column). */
  lastScore?: number
}

export type LiveActivityContentState = {
  gameId: UUID
  status: GameStatus
  tableWord: string
  roundsPlayed: number
  plannedRounds: number
  /** Who deals the next round ("NOAH DEALS"). */
  dealerSeat?: SeatId
  /** Set while a knock is marked for the round in play ("Noah knocked · last turns"). */
  liveKnocker?: SeatId
  /** The last saved round's knocker and outcome (the fact line). */
  lastRound?: { number: number; knocker: SeatId; outcome: KnockOutcome }
  /** Best first, every seat (phones truncate to five). */
  standings: LiveActivityStanding[]
  /** HLC wall time of the newest operation folded in. */
  updatedAtMs: number
}

/** The broadcast content state for a folded game. */
export function liveActivityContentState(game: FoldedGame): LiveActivityContentState {
  const last = game.rounds[game.rounds.length - 1]
  const lastScores = last ? roundScores(last.hands, last.knocker) : undefined
  const nextRound = game.rounds.length + 1
  const dealer = dealerForRound(game, nextRound)
  const outcome = last ? knockOutcome(last.hands, last.knocker) : null
  const state: LiveActivityContentState = {
    gameId: game.gameId,
    status: game.status,
    tableWord: game.config.tableWord,
    roundsPlayed: game.rounds.length,
    plannedRounds: game.config.plannedRounds,
    standings: standings(game).map(({ seat, total, rank }) => {
      const seatId = seatIdOf(seat.player)
      const row: LiveActivityStanding = { seatId, displayName: seat.displayName, total, rank: rank.position, rankShared: rank.isShared }
      const score = lastScores?.[seatId]
      if (score !== undefined) row.lastScore = score
      return row
    }),
    updatedAtMs: game.latestHlc?.wallMs ?? 0,
  }
  if (dealer && game.status === 'active') state.dealerSeat = dealer
  if (game.liveKnock && game.liveKnock.roundNumber === nextRound) state.liveKnocker = game.liveKnock.knocker
  if (last && outcome) state.lastRound = { number: last.number, knocker: last.knocker, outcome }
  return state
}
