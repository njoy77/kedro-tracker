// Folds a game's operation log into its state. A server-side port of
// apps/ios/Kedro/Core/Game/GameFold.swift covering everything that affects scores, seats, the
// game's status and moderation. (Audit text, feed entries and self-report progress UI are
// client-only.)
//
// Deterministic: de-duplicate by opId, sort by (hlc, deviceId, opId), apply. Conflict rules:
// - concurrent edits: the later HLC wins (it is applied last);
// - a round recorded twice: the earlier is kept, the other is a conflict;
// - after GameFinished, state-changing operations are refused (late) and the finisher's
//   finalRounds are authoritative;
// - abandon beats everything (including a finish within 15 minutes) except a restore within
//   15 minutes.

import type { FinishReason, GameConfig, Round, Seat, TauntContent, TauntTarget } from './domain.ts'
import { PLANNED_ROUNDS_LIMITS, SEAT_LIMITS } from './domain.ts'
import { compareHlc, type HLC } from './hlc.ts'
import { seatIdOf, type SeatId, type UUID } from './ids.ts'
import { compareFoldOrder, isStateChanging, type Operation, type PayloadByType } from './operations.ts'
import { HAND_MAX, HAND_MIN, ordered, ranks, roundScores, totals, winners, type Rank } from './scoring.ts'

/** How long an abandoned game can be restored, and how long after a finish a racing abandon still wins. */
export const RESTORE_WINDOW_MS = 15 * 60 * 1000

export type GameStatus = 'lobby' | 'active' | 'finished' | 'abandoned'

export type LateReason =
  | 'afterFinish'
  | 'afterAbandon'
  | 'seatsLocked'
  | 'afterDeal'
  | 'tableFull'
  | 'invalid'
  | 'unknownRound'
  | 'notLatestRound'
  | 'restoreExpired'

export type TauntRecord = {
  tauntId: UUID
  opId: UUID
  actorPlayerId: UUID | null
  roundNumber: number
  from: SeatId | null
  fromName: string
  target: TauntTarget
  content: TauntContent
  retracted: boolean
  retractReason?: string
}

export type ReceiptRecord = { opId: UUID; from: SeatId; to: SeatId; receiptKey: string; actorPlayerId: UUID | null }

export type FoldedGame = {
  gameId: UUID
  /** False until a GameCreated op is folded in. */
  created: boolean
  config: GameConfig
  hostSeat: SeatId | null
  status: GameStatus
  /** Clockwise (dealing) order. */
  seats: Seat[]
  rounds: Round[]
  dealerAnchor: { roundNumber: number; seat: SeatId } | null
  liveKnock: { roundNumber: number; knocker: SeatId } | null
  /** Self-report: the seats that have reported a hand for the round in play. */
  reportedSeats: SeatId[]
  finishReason: FinishReason | null
  createdAtMs: number | null
  startedAtMs: number | null
  finishedAtMs: number | null
  abandonedAtMs: number | null
  tableSpeakerDeviceId: UUID | null
  taunts: TauntRecord[]
  receipts: ReceiptRecord[]
  /** opIds of duplicate round records (the earlier record was kept). */
  conflicts: UUID[]
  /** Operations the fold refused. */
  late: { opId: UUID; type: Operation['type']; reason: LateReason }[]
  latestHlc: HLC | null
  /** Ops applied, after de-duplication. */
  operationCount: number
}

export const DEFAULT_CONFIG: GameConfig = { plannedRounds: 6, scoringMode: 'scorekeeper', tableWord: 'Cold Deck' }

/** Folds operations for one game (defaults to the first op's game; others are ignored). */
export function foldGame(operations: readonly Operation[], gameId?: UUID): FoldedGame {
  const id = gameId ?? operations[0]?.gameId ?? '00000000-0000-0000-0000-000000000000'
  const seen = new Set<string>()
  const sorted = operations
    .filter((op) => op.gameId === id && !seen.has(op.opId) && seen.add(op.opId))
    .sort(compareFoldOrder)
  const reducer = new Reducer(id)
  for (const op of sorted) reducer.apply(op)
  return reducer.state
}

// MARK: Derived values

export type Standing = { seat: Seat; total: number; rank: Rank; isWinner: boolean }

/** Totals for every seat (0 for seats with no rounds). */
export function gameTotals(game: FoldedGame): Record<SeatId, number> {
  const result: Record<SeatId, number> = Object.fromEntries(game.seats.map((seat) => [seatIdOf(seat.player), 0]))
  const summed = totals(game.rounds.map((round) => roundScores(round.hands, round.knocker)))
  for (const [seat, total] of Object.entries(summed)) result[seat] = total
  return result
}

/** Standings best first; equal totals keep seat order. Winners share the lowest total. */
export function standings(game: FoldedGame): Standing[] {
  const byTotal = gameTotals(game)
  const rankBySeat = ranks(byTotal)
  const best = winners(byTotal)
  const seatById = new Map(game.seats.map((seat) => [seatIdOf(seat.player), seat]))
  return ordered(byTotal, game.seats.map((seat) => seatIdOf(seat.player))).flatMap((id) => {
    const seat = seatById.get(id)
    if (!seat) return []
    return [{ seat, total: byTotal[id] ?? 0, rank: rankBySeat[id], isWinner: game.rounds.length > 0 && best.has(id) }]
  })
}

/** Who deals a round: anchored at Round 1's first dealer, one seat clockwise per round. */
export function dealerForRound(game: FoldedGame, round: number): SeatId | null {
  if (game.seats.length === 0) return null
  const ids = game.seats.map((seat) => seatIdOf(seat.player))
  const anchor = game.dealerAnchor ?? {
    roundNumber: 1,
    seat: game.config.firstDealerSeat ?? game.hostSeat ?? ids[0],
  }
  const anchorIndex = Math.max(0, ids.indexOf(anchor.seat))
  const count = ids.length
  const offset = (((round - anchor.roundNumber) % count) + count) % count
  return ids[(anchorIndex + offset) % count]
}

export function isLive(status: GameStatus): boolean {
  return status === 'lobby' || status === 'active'
}

// MARK: Reducer

type Report = PayloadByType['HandReported']

class Reducer {
  state: FoldedGame
  private statusBeforeAbandon: GameStatus = 'lobby'
  private abandonedHlc: HLC | null = null
  private finishedHlc: HLC | null = null
  private liveKnocks = new Map<number, SeatId>()
  private reports = new Map<number, Map<SeatId, Report>>()
  private reportOrder = new Map<number, SeatId[]>()
  private resolvedKnockers = new Map<number, SeatId>()
  private lastTouch = new Map<number, Operation>()

  constructor(gameId: UUID) {
    this.state = {
      gameId,
      created: false,
      config: { ...DEFAULT_CONFIG },
      hostSeat: null,
      status: 'lobby',
      seats: [],
      rounds: [],
      dealerAnchor: null,
      liveKnock: null,
      reportedSeats: [],
      finishReason: null,
      createdAtMs: null,
      startedAtMs: null,
      finishedAtMs: null,
      abandonedAtMs: null,
      tableSpeakerDeviceId: null,
      taunts: [],
      receipts: [],
      conflicts: [],
      late: [],
      latestHlc: null,
      operationCount: 0,
    }
  }

  apply(op: Operation): void {
    this.applyOperation(op)
    // The live knock is for the round in play only: saving or undoing a round moves it.
    const nextRound = this.state.rounds.length + 1
    const knocker = this.state.status === 'active' || this.state.status === 'lobby' ? this.liveKnocks.get(nextRound) : undefined
    this.state.liveKnock = knocker ? { roundNumber: nextRound, knocker } : null
    this.state.reportedSeats = [...(this.reports.get(nextRound)?.keys() ?? [])]
  }

  private applyOperation(op: Operation): void {
    const state = this.state
    state.latestHlc = op.hlc
    state.operationCount += 1

    if (state.status === 'abandoned') {
      if (op.type === 'GameAbandoned') return
      if (op.type !== 'GameRestored') {
        if (isStateChanging(op.type) || op.type === 'TauntSent') this.refuse(op, 'afterAbandon')
        return
      }
    } else if (state.status === 'finished') {
      switch (op.type) {
        case 'ReceiptSent':
        case 'ReactionAdded':
        case 'TableSpeakerClaimed':
        case 'TauntRetracted':
          break
        case 'GameFinished':
          return // a second phone also tapped Finish
        case 'GameAbandoned':
          if (!this.finishedHlc || op.hlc.wallMs - this.finishedHlc.wallMs > RESTORE_WINDOW_MS) {
            this.refuse(op, 'afterFinish')
            return
          }
          break
        default:
          this.refuse(op, 'afterFinish')
          return
      }
    }

    switch (op.type) {
      case 'GameCreated': return this.gameCreated(op)
      case 'GameStarted': return this.gameStarted(op)
      case 'GameConfigured': return this.gameConfigured(op)
      case 'PlayerSeated': return this.playerSeated(op)
      case 'SeatRemoved': return this.seatRemoved(op)
      case 'ScorekeeperChanged': return this.scorekeeperChanged(op)
      case 'RoundRecorded': return this.roundRecorded(op.payload.round, op)
      case 'RoundEdited': return this.roundEdited(op)
      case 'RoundUndone': return this.roundUndone(op)
      case 'KnockMarked': return this.knockMarked(op)
      case 'KnockerProposed': return // proposals only drive the client's "Who knocked?" UI
      case 'KnockerResolved': return this.knockerResolved(op)
      case 'HandReported': return this.handReported(op)
      case 'RoundsChanged': return this.roundsChanged(op)
      case 'DealerChanged': return this.dealerChanged(op)
      case 'TauntSent': return this.tauntSent(op)
      case 'TauntRetracted': return this.tauntRetracted(op)
      case 'ReactionAdded': return // no server-side effect
      case 'ReceiptSent': return this.receiptSent(op)
      case 'TableSpeakerClaimed':
        state.tableSpeakerDeviceId = op.payload.deviceId
        return
      case 'GameFinished': return this.gameFinished(op)
      case 'GameAbandoned': return this.gameAbandoned(op)
      case 'GameRestored': return this.gameRestored(op)
    }
  }

  // MARK: Setup and seats

  private gameCreated(op: Operation<'GameCreated'>) {
    if (this.state.created) return
    this.state.created = true
    this.state.config = { ...op.payload.config }
    this.state.hostSeat = op.payload.host
    this.state.createdAtMs = op.hlc.wallMs
  }

  private gameConfigured(op: Operation<'GameConfigured'>) {
    const state = this.state
    if (state.status !== 'lobby') return this.refuse(op, 'afterDeal')
    const tableWord = op.payload.tableWord.trim()
    if (!tableWord) return this.refuse(op, 'invalid')
    state.config.tableWord = tableWord
    state.config.scoringMode = op.payload.scoringMode
    if (op.payload.houseVoiceCap) state.config.houseVoiceCap = op.payload.houseVoiceCap
    else delete state.config.houseVoiceCap
  }

  private gameStarted(op: Operation<'GameStarted'>) {
    const state = this.state
    if (state.status !== 'lobby') return
    const { seatOrder, firstDealer } = op.payload
    const listed = new Set(seatOrder)
    const unlisted = this.sortedSeats(state.seats).filter((seat) => !listed.has(seatIdOf(seat.player)))
    for (const seat of state.seats) {
      const index = seatOrder.indexOf(seatIdOf(seat.player))
      if (index >= 0) seat.order = index
    }
    unlisted.forEach((seat, index) => {
      seat.order = seatOrder.length + index
    })
    this.sortSeats()
    const dealer = this.seat(firstDealer) ? firstDealer : (state.seats[0] ? seatIdOf(state.seats[0].player) : null)
    if (dealer) {
      state.config.firstDealerSeat = dealer
      state.dealerAnchor = { roundNumber: 1, seat: dealer }
    }
    state.status = 'active'
    state.startedAtMs = op.hlc.wallMs
  }

  private playerSeated(op: Operation<'PlayerSeated'>) {
    const state = this.state
    const incoming = { ...op.payload.seat }
    const id = seatIdOf(incoming.player)
    const index = state.seats.findIndex((seat) => seatIdOf(seat.player) === id)
    if (index >= 0) {
      if (state.rounds.length > 0 || state.status !== 'lobby') incoming.order = state.seats[index].order
      state.seats[index] = incoming
      this.sortSeats()
      return
    }
    if (state.rounds.length > 0) return this.refuse(op, 'seatsLocked')
    if (state.seats.length >= SEAT_LIMITS.max) return this.refuse(op, 'tableFull')
    state.seats.push(incoming)
    this.sortSeats()
  }

  private seatRemoved(op: Operation<'SeatRemoved'>) {
    const state = this.state
    const { seatId } = op.payload
    if (!this.seat(seatId)) return
    if (state.rounds.length > 0) return this.refuse(op, 'seatsLocked')
    state.seats = state.seats.filter((seat) => seatIdOf(seat.player) !== seatId)
    if (state.dealerAnchor?.seat === seatId) state.dealerAnchor = null
    if (state.config.firstDealerSeat === seatId) delete state.config.firstDealerSeat
    if (state.config.scorekeeperSeat === seatId) delete state.config.scorekeeperSeat
  }

  private scorekeeperChanged(op: Operation<'ScorekeeperChanged'>) {
    if (!this.seat(op.payload.seatId)) return this.refuse(op, 'invalid')
    this.state.config.scorekeeperSeat = op.payload.seatId
  }

  // MARK: Rounds

  private roundRecorded(round: Round, op: Operation) {
    const state = this.state
    if (!this.isValid(round)) return this.refuse(op, 'invalid')
    if (round.number >= 1 && round.number <= state.rounds.length) {
      const existing = state.rounds[round.number - 1]
      if (!sameRound(existing, round)) state.conflicts.push(op.opId)
      return
    }
    if (round.number !== state.rounds.length + 1) return this.refuse(op, 'unknownRound')
    if (state.status === 'lobby') this.startImplicitly(op)
    state.rounds.push(cloneRound(round))
    this.lastTouch.set(round.number, op)
  }

  private roundEdited(op: Operation<'RoundEdited'>) {
    const state = this.state
    const { round } = op.payload
    if (round.number < 1 || round.number > state.rounds.length) return this.refuse(op, 'unknownRound')
    if (!this.isValid(round)) return this.refuse(op, 'invalid')
    if (sameRound(state.rounds[round.number - 1], round)) return
    state.rounds[round.number - 1] = cloneRound(round)
    this.lastTouch.set(round.number, op)
  }

  private roundUndone(op: Operation<'RoundUndone'>) {
    const state = this.state
    const number = op.payload.roundNumber
    if (number !== state.rounds.length || number < 1) return this.refuse(op, 'notLatestRound')
    state.rounds.pop()
    this.lastTouch.delete(number)
    this.reports.delete(number)
    this.reportOrder.delete(number)
    this.resolvedKnockers.delete(number)
  }

  private knockMarked(op: Operation<'KnockMarked'>) {
    const { roundNumber, knocker } = op.payload
    if (roundNumber !== this.state.rounds.length + 1) return
    if (!knocker) {
      this.liveKnocks.delete(roundNumber)
      return
    }
    if (!this.seat(knocker)) return this.refuse(op, 'invalid')
    this.liveKnocks.set(roundNumber, knocker)
  }

  private knockerResolved(op: Operation<'KnockerResolved'>) {
    const { roundNumber, knocker } = op.payload
    if (roundNumber !== this.state.rounds.length + 1 || !this.seat(knocker)) return
    this.resolvedKnockers.set(roundNumber, knocker)
    this.completeSelfReportIfReady(roundNumber, op)
  }

  private handReported(op: Operation<'HandReported'>) {
    const report = op.payload
    if (report.roundNumber !== this.state.rounds.length + 1) return
    if (!this.seat(report.seatId) || report.hand < HAND_MIN || report.hand > HAND_MAX) return this.refuse(op, 'invalid')
    const roundReports = this.reports.get(report.roundNumber) ?? new Map<SeatId, Report>()
    if (!roundReports.has(report.seatId)) {
      this.reportOrder.set(report.roundNumber, [...(this.reportOrder.get(report.roundNumber) ?? []), report.seatId])
    }
    roundReports.set(report.seatId, report)
    this.reports.set(report.roundNumber, roundReports)
    this.completeSelfReportIfReady(report.roundNumber, op)
  }

  /** Self-report: once every seat has reported and the knocker is settled, the round is saved. */
  private completeSelfReportIfReady(number: number, op: Operation) {
    const roundReports = this.reports.get(number)
    if (!roundReports || !this.state.seats.every((seat) => roundReports.has(seatIdOf(seat.player)))) return
    const claimed = (this.reportOrder.get(number) ?? []).filter((seat) => roundReports.get(seat)?.knocked === true)
    const knocker = this.resolvedKnockers.get(number) ?? (claimed.length === 1 ? claimed[0] : undefined)
    if (!knocker) return
    const hands: Record<SeatId, number> = {}
    for (const [seat, report] of roundReports) hands[seat] = report.hand
    this.roundRecorded({ number, hands, knocker }, op)
  }

  // MARK: Game shape

  private roundsChanged(op: Operation<'RoundsChanged'>) {
    const planned = Math.min(
      Math.max(op.payload.plannedRounds, this.state.rounds.length, PLANNED_ROUNDS_LIMITS.min),
      PLANNED_ROUNDS_LIMITS.max,
    )
    this.state.config.plannedRounds = planned
  }

  private dealerChanged(op: Operation<'DealerChanged'>) {
    const { roundNumber, dealer } = op.payload
    if (!this.seat(dealer) || roundNumber < 1) return this.refuse(op, 'invalid')
    this.state.dealerAnchor = { roundNumber, seat: dealer }
  }

  private gameFinished(op: Operation<'GameFinished'>) {
    const state = this.state
    const finalRounds = op.payload.finalRounds
    if (finalRounds.length > 0) {
      const current = state.rounds
      const numbers = new Set([...current.map((round) => round.number), ...finalRounds.map((round) => round.number)])
      for (const number of [...numbers].sort((a, b) => a - b)) {
        const mine = current[number - 1]
        const theirs = finalRounds.find((round) => round.number === number)
        const touch = this.lastTouch.get(number)
        if (!sameRound(mine, theirs) && touch && touch.opId !== op.opId) this.refuse(touch, 'afterFinish')
      }
      // The finisher's view is authoritative, renumbered 1…n.
      state.rounds = [...finalRounds]
        .sort((a, b) => a.number - b.number)
        .map((round, index) => ({ ...cloneRound(round), number: index + 1 }))
    }
    state.status = 'finished'
    state.finishReason = op.payload.reason
    state.finishedAtMs = op.hlc.wallMs
    this.finishedHlc = op.hlc
  }

  private gameAbandoned(op: Operation<'GameAbandoned'>) {
    this.statusBeforeAbandon = this.state.status
    this.state.status = 'abandoned'
    this.state.abandonedAtMs = op.hlc.wallMs
    this.abandonedHlc = op.hlc
  }

  private gameRestored(op: Operation<'GameRestored'>) {
    if (this.state.status !== 'abandoned' || !this.abandonedHlc) return
    if (op.hlc.wallMs - this.abandonedHlc.wallMs > RESTORE_WINDOW_MS) return this.refuse(op, 'restoreExpired')
    this.state.status = this.statusBeforeAbandon
    this.state.abandonedAtMs = null
    this.abandonedHlc = null
  }

  // MARK: Trash talk

  private tauntSent(op: Operation<'TauntSent'>) {
    const p = op.payload
    if (this.state.taunts.some((taunt) => taunt.tauntId === p.tauntId)) return
    this.state.taunts.push({
      tauntId: p.tauntId,
      opId: op.opId,
      actorPlayerId: op.actorPlayerId,
      roundNumber: p.roundNumber,
      from: p.from ?? null,
      fromName: p.fromName,
      target: p.target,
      content: p.content,
      retracted: false,
    })
  }

  private tauntRetracted(op: Operation<'TauntRetracted'>) {
    const taunt = this.state.taunts.find((candidate) => candidate.tauntId === op.payload.tauntId)
    if (!taunt) return
    taunt.retracted = true
    if (op.payload.reason) taunt.retractReason = op.payload.reason
  }

  private receiptSent(op: Operation<'ReceiptSent'>) {
    const { fromSeat, toSeat, receiptKey } = op.payload
    if (fromSeat === toSeat || !this.seat(fromSeat) || !this.seat(toSeat)) return
    if (this.state.receipts.some((receipt) => receipt.from === fromSeat && receipt.to === toSeat)) return
    this.state.receipts.push({ opId: op.opId, from: fromSeat, to: toSeat, receiptKey, actorPlayerId: op.actorPlayerId })
  }

  // MARK: Helpers

  private startImplicitly(op: Operation) {
    const state = this.state
    state.status = 'active'
    state.startedAtMs = op.hlc.wallMs
    const first = state.config.firstDealerSeat ?? state.hostSeat ?? (state.seats[0] ? seatIdOf(state.seats[0].player) : null)
    if (!state.dealerAnchor && first) state.dealerAnchor = { roundNumber: 1, seat: first }
  }

  private isValid(round: Round): boolean {
    const seatIds = new Set(this.state.seats.map((seat) => seatIdOf(seat.player)))
    if (seatIds.size === 0) return false
    const handKeys = Object.keys(round.hands)
    if (round.hands[round.knocker] === undefined || !seatIds.has(round.knocker)) return false
    if (handKeys.length !== seatIds.size || !handKeys.every((key) => seatIds.has(key))) return false
    return Object.values(round.hands).every((hand) => hand >= HAND_MIN && hand <= HAND_MAX)
  }

  private seat(id: SeatId): Seat | undefined {
    return this.state.seats.find((seat) => seatIdOf(seat.player) === id)
  }

  private refuse(op: Operation, reason: LateReason) {
    if (this.state.late.some((late) => late.opId === op.opId)) return
    this.state.late.push({ opId: op.opId, type: op.type, reason })
  }

  private sortedSeats(seats: Seat[]): Seat[] {
    return [...seats].sort(seatSort)
  }

  private sortSeats() {
    this.state.seats.sort(seatSort)
  }
}

function seatSort(a: Seat, b: Seat): number {
  if (a.order !== b.order) return a.order - b.order
  const left = seatIdOf(a.player)
  const right = seatIdOf(b.player)
  return left < right ? -1 : left > right ? 1 : 0
}

function cloneRound(round: Round): Round {
  return { number: round.number, hands: { ...round.hands }, knocker: round.knocker }
}

/** Value equality of two rounds (hands compared as maps). */
export function sameRound(a: Round | undefined, b: Round | undefined): boolean {
  if (!a || !b) return a === b
  if (a.number !== b.number || a.knocker !== b.knocker) return false
  const left = Object.keys(a.hands)
  if (left.length !== Object.keys(b.hands).length) return false
  return left.every((key) => a.hands[key] === b.hands[key])
}

/** True when `a` sorts strictly after `b` in HLC order. */
export function isAfter(a: HLC, b: HLC): boolean {
  return compareHlc(a, b) > 0
}
