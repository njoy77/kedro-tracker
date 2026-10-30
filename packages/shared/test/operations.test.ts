import { describe, expect, test } from 'bun:test'
import { OPERATION_TYPES, isStateChanging, parseOperation, type OperationType } from '../src/index.ts'
import { fixedUUID, ids, sampleRounds, sampleSeats, seats } from './fixtures/sampleGame.ts'

/** One valid payload for every operation type, in the JSON shapes of ARCHITECTURE.md §4.2. */
const examples: Record<OperationType, unknown> = {
  GameCreated: { config: { plannedRounds: 6, scoringMode: 'scorekeeper', tableWord: 'Cold Deck' }, host: seats.noah },
  GameStarted: { seatOrder: [seats.noah, seats.ana], firstDealer: seats.noah },
  GameConfigured: { tableWord: 'Last Call', scoringMode: 'selfReport', houseVoiceCap: 'clean' },
  PlayerSeated: { seat: { ...sampleSeats[0], avatar: { kind: 'emoji', emoji: '🦊', colorIndex: 3 }, titleId: 'TI-12' } },
  SeatRemoved: { seatId: seats.sam },
  ScorekeeperChanged: { seatId: seats.ana },
  RoundRecorded: { round: sampleRounds[0] },
  RoundEdited: { round: sampleRounds[0] },
  RoundUndone: { roundNumber: 6 },
  KnockMarked: { roundNumber: 6, knocker: seats.sam },
  KnockerProposed: { roundNumber: 6, knocker: seats.noah },
  KnockerResolved: { roundNumber: 6, knocker: seats.noah },
  HandReported: { roundNumber: 6, seatId: seats.noah, hand: 7, knocked: false },
  RoundsChanged: { plannedRounds: 8 },
  DealerChanged: { roundNumber: 6, dealer: seats.noah },
  TauntSent: {
    tauntId: fixedUUID(5, 1), roundNumber: 6, from: seats.ana, fromName: 'Ana',
    target: { kind: 'seat', seatId: seats.sam }, content: { kind: 'canned', id: 'TT-01' },
  },
  TauntRetracted: { tauntId: fixedUUID(5, 1), reason: 'filter' },
  ReactionAdded: { roundNumber: 5, seatId: seats.ana, reaction: 'fire' },
  ReceiptSent: { fromSeat: seats.noah, toSeat: seats.ana, receiptKey: 'RC-02' },
  TableSpeakerClaimed: { deviceId: ids.noahPhone },
  GameFinished: { reason: 'completed', finalRounds: sampleRounds },
  GameAbandoned: {},
  GameRestored: {},
}

const envelope = (type: OperationType, payload: unknown) => ({
  opId: fixedUUID(6, OPERATION_TYPES.indexOf(type)),
  gameId: ids.game,
  deviceId: ids.noahPhone,
  hlc: { wallMs: 1_761_700_000_000, counter: 0, node: ids.noahPhone },
  actorPlayerId: ids.noah,
  type,
  payload,
})

describe('operation wire contract', () => {
  test('accepts all 23 types', () => {
    expect(OPERATION_TYPES).toHaveLength(23)
    for (const type of OPERATION_TYPES) {
      const result = parseOperation(envelope(type, examples[type]))
      if (!result.ok) throw new Error(`${type}: ${result.error}`)
      expect(result.value.operation.type).toBe(type)
    }
  })

  test('KnockMarked with the knocker omitted (cleared) and a watcher taunt with no from', () => {
    expect(parseOperation(envelope('KnockMarked', { roundNumber: 6 })).ok).toBe(true)
    const watcher = { ...(examples.TauntSent as object), from: undefined, content: { kind: 'custom', text: 'hi' } }
    expect(parseOperation(envelope('TauntSent', watcher)).ok).toBe(true)
  })

  test('keeps the raw payload (unknown keys survive storage)', () => {
    const payload = { roundNumber: 6, futureField: true }
    const result = parseOperation(envelope('RoundUndone', payload))
    expect(result.ok && result.value.rawPayload).toEqual(payload)
    expect(result.ok && result.value.operation.payload).toEqual({ roundNumber: 6 })
  })

  test('rejects malformed seat IDs, hands and avatars', () => {
    expect(parseOperation(envelope('SeatRemoved', { seatId: 'x:1' })).ok).toBe(false)
    expect(parseOperation(envelope('RoundRecorded', { round: { ...sampleRounds[0], hands: { [seats.noah]: -3 } } })).ok).toBe(false)
    const badAvatar = { seat: { ...sampleSeats[0], avatar: { kind: 'emoji', emoji: '🦊', colorIndex: 12 } } }
    expect(parseOperation(envelope('PlayerSeated', badAvatar)).ok).toBe(false)
  })

  test('state-changing classification matches Swift', () => {
    const free = OPERATION_TYPES.filter((type) => !isStateChanging(type))
    expect(free.sort()).toEqual(['ReactionAdded', 'ReceiptSent', 'TableSpeakerClaimed', 'TauntRetracted', 'TauntSent'])
  })
})
