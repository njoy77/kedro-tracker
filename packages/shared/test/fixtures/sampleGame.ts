// The design spec §17 sample game (COLD DECK) as wire operations, built the same way as
// apps/ios/Kedro/Core/Sample/PreviewData.swift (same fixed IDs, same timestamps).

import { parseOperation, seatIdOf, type Operation, type Round, type Seat, type WireOperation } from '../../src/index.ts'

/** `000000kk-0000-4000-8000-0000000000nn`, PreviewData.fixedUUID(kind:_:). */
export function fixedUUID(kind: number, number: number): string {
  const hex = (value: number) => value.toString(16).padStart(2, '0')
  return `000000${hex(kind)}-0000-4000-8000-0000000000${hex(number)}`
}

export const ids = {
  noah: fixedUUID(1, 1),
  ana: fixedUUID(1, 2),
  ben: fixedUUID(1, 3),
  cleo: fixedUUID(1, 4),
  sam: fixedUUID(2, 1),
  noahPhone: fixedUUID(3, 1),
  anaPhone: fixedUUID(3, 2),
  game: fixedUUID(4, 1),
}

export const seats = {
  noah: seatIdOf({ kind: 'player', id: ids.noah }),
  ana: seatIdOf({ kind: 'player', id: ids.ana }),
  ben: seatIdOf({ kind: 'player', id: ids.ben }),
  cleo: seatIdOf({ kind: 'player', id: ids.cleo }),
  sam: seatIdOf({ kind: 'guest', id: ids.sam }),
}

export const SAMPLE_START_MS = 1_792_875_600_000

export const sampleSeats: Seat[] = [
  { player: { kind: 'player', id: ids.noah }, displayName: 'Noah', order: 0, handle: 'noah', deviceId: ids.noahPhone, languageLevel: 'unhinged' },
  { player: { kind: 'player', id: ids.ana }, displayName: 'Ana', order: 1, handle: 'ana.k', deviceId: ids.anaPhone, languageLevel: 'unhinged' },
  { player: { kind: 'player', id: ids.ben }, displayName: 'Ben', order: 2, handle: 'ben', languageLevel: 'unhinged' },
  { player: { kind: 'player', id: ids.cleo }, displayName: 'Cleo', order: 3, handle: 'cleo', languageLevel: 'unhinged' },
  { player: { kind: 'guest', id: ids.sam }, displayName: 'Sam', order: 4, gamesPlayed: 2 },
]

const order = [seats.noah, seats.ana, seats.ben, seats.cleo, seats.sam]

/** (knocker, hands for Noah, Ana, Ben, Cleo, Sam), exactly as design §17. */
const table: [string, number[]][] = [
  [seats.ana, [9, 3, 12, 7, 15]],
  [seats.ben, [6, 11, 5, 5, 20]],
  [seats.noah, [8, 3, 14, 10, 9]],
  [seats.cleo, [3, 16, 7, 2, -1]],
  [seats.noah, [2, 9, 6, 11, 4]],
  [seats.sam, [7, 2, 9, 8, 1]],
  [seats.ana, [5, 2, 2, 6, 12]],
  [seats.noah, [0, 1, 12, 6, 21]],
]

export const sampleRounds: Round[] = table.map(([knocker, hands], index) => ({
  number: index + 1,
  hands: Object.fromEntries(order.map((seat, i) => [seat, hands[i]])),
  knocker,
}))

/** Builds operations with increasing HLCs, like Swift's OperationBuilder. */
export class OperationBuilder {
  wallMs: number
  counter = 0
  sequence = 0
  operations: WireOperation[] = []

  constructor(readonly gameId: string, readonly device: string, readonly actor: string | null, startMs: number) {
    this.wallMs = startMs
  }

  advance(minutes: number) {
    this.wallMs += minutes * 60_000
    this.counter = 0
  }

  add(type: WireOperation['type'], payload: unknown, options: { device?: string; actor?: string | null } = {}) {
    this.wallMs += 1000
    this.sequence += 1
    const deviceId = options.device ?? this.device
    this.operations.push({
      opId: opId(this.gameId, this.sequence),
      gameId: this.gameId,
      deviceId,
      hlc: { wallMs: this.wallMs, counter: this.counter, node: deviceId },
      actorPlayerId: options.actor === undefined ? this.actor : options.actor,
      type,
      payload,
    })
    return this.operations[this.operations.length - 1]
  }
}

/** The game's UUID with the sequence in bytes 8–11 (PreviewData's deterministic op IDs). */
function opId(gameId: string, sequence: number): string {
  const hex = gameId.replace(/-/g, '').split('')
  const bytes = [
    0xa0 | ((sequence >>> 24) & 0x0f),
    (sequence >>> 16) & 0xff,
    (sequence >>> 8) & 0xff,
    sequence & 0xff,
  ].map((value) => value.toString(16).padStart(2, '0')).join('')
  hex.splice(16, 8, ...bytes.split(''))
  const flat = hex.join('')
  return `${flat.slice(0, 8)}-${flat.slice(8, 12)}-${flat.slice(12, 16)}-${flat.slice(16, 20)}-${flat.slice(20)}`
}

export type SampleOptions = { throughRound?: number; finished?: boolean; liveKnock?: boolean }

/** The sample game's wire operations (PreviewData.sampleOperations). */
export function sampleWireOperations({ throughRound = 8, finished = true, liveKnock = false }: SampleOptions = {}): WireOperation[] {
  const builder = new OperationBuilder(ids.game, ids.noahPhone, ids.noah, SAMPLE_START_MS)
  builder.add('GameCreated', {
    config: { plannedRounds: 6, scoringMode: 'scorekeeper', tableWord: 'Cold Deck', firstDealerSeat: seats.noah, scorekeeperSeat: seats.noah },
    host: seats.noah,
  })
  for (const seat of sampleSeats) builder.add('PlayerSeated', { seat })
  builder.add('GameStarted', { seatOrder: order, firstDealer: seats.noah })
  const rounds = sampleRounds.slice(0, Math.max(0, Math.min(throughRound, 8)))
  for (const round of rounds) {
    builder.advance(4)
    builder.add('RoundRecorded', { round })
    if (round.number === 5) {
      builder.add('ReactionAdded', { roundNumber: 5, seatId: seats.ana, reaction: 'fire' }, { device: ids.anaPhone, actor: ids.ana })
      builder.add('ReactionAdded', { roundNumber: 5, seatId: seats.noah, reaction: 'skull' })
    }
    if (round.number === 6) builder.add('RoundsChanged', { plannedRounds: 8 })
  }
  if (liveKnock && rounds.length < 8) {
    builder.advance(2)
    builder.add('KnockMarked', { roundNumber: rounds.length + 1, knocker: seats.sam }, { device: ids.anaPhone, actor: ids.ana })
    builder.add('TauntSent', {
      tauntId: fixedUUID(5, 1), roundNumber: rounds.length + 1, from: seats.ana, fromName: 'Ana',
      target: { kind: 'seat', seatId: seats.sam }, content: { kind: 'canned', id: 'TT-01' },
    }, { device: ids.anaPhone, actor: ids.ana })
  }
  if (finished && rounds.length === 8) {
    builder.advance(1)
    builder.add('GameFinished', { reason: 'completed', finalRounds: rounds })
  }
  return builder.operations
}

export function parsed(wire: WireOperation[]): Operation[] {
  return wire.map((op) => {
    const result = parseOperation(op)
    if (!result.ok) throw new Error(`Fixture op failed to parse: ${result.error}`)
    return result.value.operation
  })
}

export function sampleOperations(options?: SampleOptions): Operation[] {
  return parsed(sampleWireOperations(options))
}
