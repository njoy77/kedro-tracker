// Finished games normalized for progression: people instead of seats, claims applied, running
// totals precomputed. A port of the iOS app's `Core/Stats/StatsGame.swift`; keep the two in step.

import { COUNTED_MIN_ROUNDS, type FinishReason, type Seat, type TauntContent } from '../domain.ts'
import { joinedRound, type FoldedGame } from '../fold.ts'
import { seatIdOf, type SeatId, type UUID } from '../ids.ts'
import { outcomeOf, ranks, scoresOf, winners, type KnockOutcome, type Rank } from '../scoring.ts'

/** A person, as stats know them: `"p:<playerId>"` or `"g:<guestId>"` (the seat ID format). */
export type Ref = SeatId

export function isGuestRef(ref: Ref): boolean {
  return ref.startsWith('g:')
}

/** Options that shape how history is read. Inputs, never stored counters. */
export type ProgressionOptions = {
  /** Claimed guest identities → the account that claimed them. */
  aliases?: ReadonlyMap<Ref, Ref>
  /** People the viewer blocked (or who blocked them): hidden from the Hall of Shame, Wrapped and rivals. */
  excluded?: ReadonlySet<Ref>
  /** People who finished Learn and the drill (Did the Reading). */
  didTheReading?: ReadonlySet<Ref>
  /** Rounds a game needs to count, and a seat needs to have played to count in it. */
  minimumRounds?: number
  /** IANA time zone for calendar years (Wrapped and the yearly titles). */
  timeZone?: string
}

export type ResolvedOptions = {
  aliases: ReadonlyMap<Ref, Ref>
  excluded: ReadonlySet<Ref>
  didTheReading: ReadonlySet<Ref>
  minimumRounds: number
  timeZone: string
}

export const DEFAULT_TIME_ZONE = 'America/New_York'

export function resolveOptions(options: ProgressionOptions = {}): ResolvedOptions {
  return {
    aliases: options.aliases ?? new Map(),
    excluded: options.excluded ?? new Set(),
    didTheReading: options.didTheReading ?? new Set(),
    minimumRounds: options.minimumRounds ?? COUNTED_MIN_ROUNDS,
    timeZone: options.timeZone ?? DEFAULT_TIME_ZONE,
  }
}

export function canonical(options: ResolvedOptions, ref: Ref): Ref {
  return options.aliases.get(ref) ?? ref
}

/** One person at one finished game. */
export type Participant = {
  /** The identity stats are credited to (a claimed guest maps to the account). */
  ref: Ref
  /** The identity in the seat at the time (a guest before a claim). */
  seatedAs: Ref
  name: string
  titleId: string | null
}

/** One round keyed by person, with the scores the game itself gave. */
export type StatsRound = {
  number: number
  hands: Map<Ref, number>
  knocker: Ref | null
  inherent: Ref | null
  scores: Map<Ref, number>
  outcome: KnockOutcome | null
}

export function isInherentKnockRound(round: StatsRound): boolean {
  return round.knocker !== null && round.inherent === round.knocker
}

/** The knocker of a regular knock (not inherent, not unknown). */
export function regularKnocker(round: StatsRound): Ref | null {
  return isInherentKnockRound(round) ? null : round.knocker
}

export function knockerHand(round: StatsRound): number | null {
  return round.knocker === null ? null : (round.hands.get(round.knocker) ?? null)
}

export function lowestOtherHand(round: StatsRound): number | null {
  let lowest: number | null = null
  for (const [ref, hand] of round.hands) {
    if (ref === round.knocker) continue
    lowest = lowest === null ? hand : Math.min(lowest, hand)
  }
  return lowest
}

export type StatsTaunt = { from: Ref; target: Ref | null; content: TauntContent }

export type StatsGame = {
  id: UUID
  /** Position in the chronological replay (0 = oldest). */
  index: number
  tableWord: string
  startedAtMs: number | null
  finishedAtMs: number
  finishReason: FinishReason | null
  /** Seat order. */
  participants: Participant[]
  rounds: StatsRound[]
  /** Running totals after each round (`cumulative[r]` is after round r + 1). */
  cumulative: Map<Ref, number>[]
  totals: Map<Ref, number>
  ranks: Map<Ref, Rank>
  winners: Set<Ref>
  taunts: StatsTaunt[]
  neighs: Map<Ref, number>
}

export function refsOf(game: StatsGame): Ref[] {
  return game.participants.map((participant) => participant.ref)
}

export function participantOf(game: StatsGame, ref: Ref): Participant | undefined {
  return game.participants.find((participant) => participant.ref === ref)
}

export function containsRef(game: StatsGame, ref: Ref): boolean {
  return game.participants.some((participant) => participant.ref === ref)
}

export function durationMs(game: StatsGame): number {
  return game.startedAtMs === null ? 0 : Math.max(0, game.finishedAtMs - game.startedAtMs)
}

/** Leaders (lowest running total, ties share) after a round (1-based). */
export function leadersAfter(game: StatsGame, round: number): Set<Ref> {
  if (round < 1 || round > game.cumulative.length) return new Set()
  return winners(Object.fromEntries(game.cumulative[round - 1]))
}

function gameFinishedAt(state: FoldedGame): number {
  return state.finishedAtMs ?? state.latestHlc?.wallMs ?? state.createdAtMs ?? 0
}

function counts(state: FoldedGame, options: ResolvedOptions): boolean {
  return state.status === 'finished' && state.rounds.length >= options.minimumRounds
}

/** The seats that count, in seat order: one per person, preferring the person's own seat over a claimed guest's. */
export function countedSeats(seats: readonly Seat[], options: ResolvedOptions): Seat[] {
  const chosen = new Map<Ref, Seat>()
  for (const seat of seats) {
    const own = seatIdOf(seat.player)
    const ref = canonical(options, own)
    const existing = chosen.get(ref)
    if (!existing) {
      chosen.set(ref, seat)
      continue
    }
    if (seatIdOf(existing.player) !== ref && own === ref) chosen.set(ref, seat)
  }
  const keep = new Set([...chosen.values()])
  return seats.filter((seat) => keep.has(seat))
}

/** The stats view of a folded game; null unless it counts. */
export function statsGame(state: FoldedGame, index: number, options: ResolvedOptions): StatsGame | null {
  if (!counts(state, options)) return null
  const played = new Map<SeatId, number>()
  for (const round of state.rounds) for (const seat of Object.keys(round.hands)) played.set(seat, (played.get(seat) ?? 0) + 1)
  const ordered = [...state.seats].sort((a, b) => a.order - b.order)
  const counted = countedSeats(ordered, options).filter((seat) => (played.get(seatIdOf(seat.player)) ?? 0) >= options.minimumRounds)
  const participants: Participant[] = counted.map((seat) => ({
    ref: canonical(options, seatIdOf(seat.player)),
    seatedAs: seatIdOf(seat.player),
    name: seat.displayName,
    titleId: seat.titleId ?? null,
  }))
  const countedIds = new Set(counted.map((seat) => seatIdOf(seat.player)))
  const person = (seat: SeatId): Ref => canonical(options, seat)

  const rounds: StatsRound[] = state.rounds.map((round) => {
    const hands = new Map<Ref, number>()
    for (const [seat, hand] of Object.entries(round.hands)) if (countedIds.has(seat) && !hands.has(person(seat))) hands.set(person(seat), hand)
    const scores = new Map<Ref, number>()
    for (const [seat, score] of Object.entries(scoresOf(round))) if (countedIds.has(seat) && !scores.has(person(seat))) scores.set(person(seat), score)
    return {
      number: round.number,
      hands,
      knocker: round.knocker ? person(round.knocker) : null,
      inherent: round.inherent ? person(round.inherent) : null,
      scores,
      outcome: outcomeOf(round),
    }
  })

  // Late joiners enter the running totals at their starting score on their first round.
  const lateStarts = counted.filter((seat) => joinedRound(seat) > 1)
  const lateRefs = new Set(lateStarts.map((seat) => person(seatIdOf(seat.player))))
  const running = new Map<Ref, number>()
  for (const participant of participants) if (!lateRefs.has(participant.ref) && !running.has(participant.ref)) running.set(participant.ref, 0)
  const cumulative: Map<Ref, number>[] = []
  for (const round of rounds) {
    for (const seat of lateStarts) if (joinedRound(seat) === round.number) running.set(person(seatIdOf(seat.player)), seat.startingScore ?? 0)
    for (const [ref, score] of round.scores) running.set(ref, (running.get(ref) ?? 0) + score)
    cumulative.push(new Map(running))
  }
  const totalsRecord = Object.fromEntries(running)
  const rankRecord = ranks(totalsRecord)

  const taunts: StatsTaunt[] = state.taunts.flatMap((taunt) => {
    if (taunt.retracted || !taunt.from) return []
    const target = taunt.target.kind === 'seat' ? person(taunt.target.seatId) : null
    return [{ from: person(taunt.from), target, content: taunt.content }]
  })
  const neighs = new Map<Ref, number>()
  for (const [seat, count] of Object.entries(state.neighs)) {
    if (!countedIds.has(seat)) continue
    neighs.set(person(seat), (neighs.get(person(seat)) ?? 0) + count)
  }

  return {
    id: state.gameId,
    index,
    tableWord: state.config.tableWord,
    startedAtMs: state.startedAtMs ?? state.createdAtMs,
    finishedAtMs: gameFinishedAt(state),
    finishReason: state.finishReason,
    participants,
    rounds,
    cumulative,
    totals: running,
    ranks: new Map(Object.entries(rankRecord)),
    winners: winners(totalsRecord),
    taunts,
    neighs,
  }
}

/** Normalizes and orders finished games (oldest first, ties by game ID). */
export function normalizeGames(states: readonly FoldedGame[], options: ResolvedOptions): StatsGame[] {
  const finished = states
    .filter((state) => counts(state, options))
    .sort((a, b) => gameFinishedAt(a) - gameFinishedAt(b) || (a.gameId < b.gameId ? -1 : a.gameId > b.gameId ? 1 : 0))
  const seen = new Set<UUID>()
  const games: StatsGame[] = []
  for (const state of finished) {
    if (seen.has(state.gameId)) continue
    seen.add(state.gameId)
    const game = statsGame(state, games.length, options)
    if (game) games.push(game)
  }
  return games
}

/** Lower bounds read from a hand value: −2 can only be both red Kings, −1 needs one. */
export function redKingsInHand(hand: number): number {
  if (hand <= -2) return 2
  if (hand === -1) return 1
  return 0
}
