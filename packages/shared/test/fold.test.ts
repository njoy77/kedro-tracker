import { describe, expect, test } from 'bun:test'
import {
  RESTORE_WINDOW_MS,
  dealerForRound,
  foldGame,
  gameTotals,
  hlcString,
  liveActivityContentState,
  parseHlc,
  parseOperation,
  projectFinishedGame,
  standings,
  type Operation,
  type WireOperation,
} from '../src/index.ts'
import { OperationBuilder, fixedUUID, ids, parsed, sampleOperations, sampleRounds, sampleWireOperations, seats } from './fixtures/sampleGame.ts'

function withExtra(base: WireOperation[], build: (builder: OperationBuilder) => void): Operation[] {
  const last = base[base.length - 1]
  const builder = new OperationBuilder(ids.game, ids.noahPhone, ids.noah, last.hlc.wallMs)
  builder.sequence = 1000
  build(builder)
  return parsed([...base, ...builder.operations])
}

describe('foldGame: the §17 sample game', () => {
  test('finishes with Noah 28, Ana 34, Cleo 65, Ben 67, Sam 70', () => {
    const game = foldGame(sampleOperations())
    expect(game.status).toBe('finished')
    expect(game.finishReason).toBe('completed')
    expect(game.rounds).toHaveLength(8)
    expect(game.config.plannedRounds).toBe(8)
    const table = standings(game).map((row) => [row.seat.displayName, row.total, row.rank.position, row.isWinner])
    expect(table).toEqual([
      ['Noah', 28, 1, true],
      ['Ana', 34, 2, false],
      ['Cleo', 65, 3, false],
      ['Ben', 67, 4, false],
      ['Sam', 70, 5, false],
    ])
  })

  test('after Round 5 the standings are Noah 26, Ana 29, Ben 44, Cleo 45, Sam 47', () => {
    const game = foldGame(sampleOperations({ throughRound: 5, finished: false }))
    expect(game.status).toBe('active')
    expect(standings(game).map((row) => row.total)).toEqual([26, 29, 44, 45, 47])
  })

  test('dealers for R1–R8 are Noah, Ana, Ben, Cleo, Sam, Noah, Ana, Ben', () => {
    const game = foldGame(sampleOperations({ throughRound: 0, finished: false }))
    const names = [1, 2, 3, 4, 5, 6, 7, 8].map((round) => game.seats.find((seat) => `${seat.player.kind[0]}:${seat.player.id}` === dealerForRound(game, round))?.displayName)
    expect(names).toEqual(['Noah', 'Ana', 'Ben', 'Cleo', 'Sam', 'Noah', 'Ana', 'Ben'])
  })

  test('arrival order does not matter', () => {
    const ops = sampleOperations()
    const shuffled = [...ops].reverse()
    const doubled = [...ops, ...ops]
    expect(gameTotals(foldGame(shuffled))).toEqual(gameTotals(foldGame(ops)))
    expect(foldGame(doubled).operationCount).toBe(ops.length)
  })

  test('projects the finished game for stats', () => {
    const projection = projectFinishedGame(foldGame(sampleOperations()))
    expect(projection).not.toBeNull()
    const noah = projection?.seats.find((seat) => seat.seatId === seats.noah)
    expect(noah).toMatchObject({ total: 28, rank: 1, isWinner: true, knocks: 3, knocksLanded: 2, knocksFailed: 1, roundsPlayed: 8, lowestHand: 0 })
    const sam = projection?.seats.find((seat) => seat.seatId === seats.sam)
    expect(sam).toMatchObject({ guestId: ids.sam, playerId: null, total: 70, knocks: 1, knocksLanded: 1, lowestHand: -1 })
    const knocks = projection?.seats.reduce((sum, seat) => sum + seat.knocks, 0)
    const landed = projection?.seats.reduce((sum, seat) => sum + seat.knocksLanded, 0)
    const tied = projection?.seats.reduce((sum, seat) => sum + seat.knocksTied, 0)
    expect([knocks, landed, tied]).toEqual([8, 4, 2])
    expect(projectFinishedGame(foldGame(sampleOperations({ finished: false })))).toBeNull()
  })
})

describe('foldGame: conflict rules', () => {
  test('a second, different record of a round keeps the earlier one', () => {
    const ops = withExtra(sampleWireOperations({ throughRound: 2, finished: false }), (b) => {
      b.add('RoundRecorded', { round: { ...sampleRounds[1], hands: { ...sampleRounds[1].hands, [seats.sam]: 0 } } })
    })
    const game = foldGame(ops)
    expect(game.rounds[1]).toEqual(sampleRounds[1])
    expect(game.conflicts).toHaveLength(1)
  })

  test('edits re-score; the later HLC wins', () => {
    const ops = withExtra(sampleWireOperations({ throughRound: 2, finished: false }), (b) => {
      b.add('RoundEdited', { round: { ...sampleRounds[0], hands: { ...sampleRounds[0].hands, [seats.ana]: 9 } } })
      b.add('RoundEdited', { round: { ...sampleRounds[0], hands: { ...sampleRounds[0].hands, [seats.ana]: 7 } } })
    })
    const game = foldGame(ops)
    // Ana 7 vs Cleo 7: tied, so Ana scores her hand.
    expect(gameTotals(game)[seats.ana]).toBe(7 + 11)
  })

  test('only the latest round can be undone', () => {
    const ops = withExtra(sampleWireOperations({ throughRound: 3, finished: false }), (b) => {
      b.add('RoundUndone', { roundNumber: 2 })
      b.add('RoundUndone', { roundNumber: 3 })
    })
    const game = foldGame(ops)
    expect(game.rounds).toHaveLength(2)
    expect(game.late.map((late) => late.reason)).toEqual(['notLatestRound'])
  })

  test('state-changing ops after the finish are refused; reactions and receipts are not', () => {
    const ops = withExtra(sampleWireOperations(), (b) => {
      b.add('RoundEdited', { round: { ...sampleRounds[0], hands: { ...sampleRounds[0].hands, [seats.noah]: 0 } } })
      b.add('ReceiptSent', { fromSeat: seats.noah, toSeat: seats.ana, receiptKey: 'RC-02' })
      b.add('ReactionAdded', { roundNumber: 8, seatId: seats.ben, reaction: 'clown' })
    })
    const game = foldGame(ops)
    expect(gameTotals(game)[seats.noah]).toBe(28)
    expect(game.late.map((late) => [late.type, late.reason])).toEqual([['RoundEdited', 'afterFinish']])
    expect(game.receipts).toHaveLength(1)
  })

  test("the finisher's finalRounds are authoritative", () => {
    const wire = sampleWireOperations()
    const finished = wire[wire.length - 1]
    const changed = { ...sampleRounds[7], hands: { ...sampleRounds[7].hands, [seats.noah]: 3 } } // Noah 3 vs Ana 1: failed
    const edited: WireOperation = { ...finished, payload: { reason: 'completed', finalRounds: [...sampleRounds.slice(0, 7), changed] } }
    const game = foldGame(parsed([...wire.slice(0, -1), edited]))
    expect(gameTotals(game)[seats.noah]).toBe(28 + 10 + 13)
    expect(game.late.map((late) => late.type)).toEqual(['RoundRecorded'])
  })

  test('abandon beats a finish within 15 minutes; later it is refused', () => {
    const early = withExtra(sampleWireOperations(), (b) => b.add('GameAbandoned', {}))
    expect(foldGame(early).status).toBe('abandoned')
    const late = withExtra(sampleWireOperations(), (b) => {
      b.advance(16)
      b.add('GameAbandoned', {})
    })
    expect(foldGame(late).status).toBe('finished')
  })

  test('a restore within the window brings the game back', () => {
    const ops = withExtra(sampleWireOperations({ throughRound: 4, finished: false }), (b) => {
      b.add('GameAbandoned', {})
      b.add('RoundRecorded', { round: sampleRounds[4] })
      b.advance(RESTORE_WINDOW_MS / 60_000 - 1)
      b.add('GameRestored', {})
    })
    const game = foldGame(ops)
    expect(game.status).toBe('active')
    expect(game.rounds).toHaveLength(4)
    expect(game.late.map((late) => late.reason)).toEqual(['afterAbandon'])
  })

  test('an expired restore is refused', () => {
    const ops = withExtra(sampleWireOperations({ throughRound: 4, finished: false }), (b) => {
      b.add('GameAbandoned', {})
      b.advance(16)
      b.add('GameRestored', {})
    })
    expect(foldGame(ops).status).toBe('abandoned')
  })

  test('seats lock after Round 1 and the table holds 8', () => {
    const newSeat = (n: number) => ({ seat: { player: { kind: 'guest', id: fixedUUID(9, n) }, displayName: `G${n}`, order: 10 + n } })
    const locked = withExtra(sampleWireOperations({ throughRound: 1, finished: false }), (b) => b.add('PlayerSeated', newSeat(1)))
    expect(foldGame(locked).seats).toHaveLength(5)
    expect(foldGame(locked).late[0].reason).toBe('seatsLocked')
    const full = withExtra(sampleWireOperations({ throughRound: 0, finished: false }), (b) => {
      for (let n = 1; n <= 4; n++) b.add('PlayerSeated', newSeat(n))
    })
    expect(foldGame(full).seats).toHaveLength(8)
    expect(foldGame(full).late[0].reason).toBe('tableFull')
  })

  test('self-report completes a round once everyone reported and one knock was claimed', () => {
    const ops = withExtra(sampleWireOperations({ throughRound: 0, finished: false }), (b) => {
      const hands: [string, number][] = [[seats.noah, 9], [seats.ana, 3], [seats.ben, 12], [seats.cleo, 7], [seats.sam, 15]]
      for (const [seatId, hand] of hands) b.add('HandReported', { roundNumber: 1, seatId, hand, knocked: seatId === seats.ana })
    })
    const game = foldGame(ops)
    expect(game.rounds).toEqual([sampleRounds[0]])
  })

  test('self-report waits for a resolved knocker when several claimed it', () => {
    const ops = withExtra(sampleWireOperations({ throughRound: 0, finished: false }), (b) => {
      const hands: [string, number][] = [[seats.noah, 9], [seats.ana, 3], [seats.ben, 12], [seats.cleo, 7], [seats.sam, 15]]
      for (const [seatId, hand] of hands) b.add('HandReported', { roundNumber: 1, seatId, hand, knocked: seatId !== seats.sam })
    })
    expect(foldGame(ops).rounds).toHaveLength(0)
    const resolved = withExtra(sampleWireOperations({ throughRound: 0, finished: false }), (b) => {
      const hands: [string, number][] = [[seats.noah, 9], [seats.ana, 3], [seats.ben, 12], [seats.cleo, 7], [seats.sam, 15]]
      for (const [seatId, hand] of hands) b.add('HandReported', { roundNumber: 1, seatId, hand, knocked: seatId !== seats.sam })
      b.add('KnockerResolved', { roundNumber: 1, knocker: seats.ana })
    })
    expect(foldGame(resolved).rounds).toEqual([sampleRounds[0]])
  })

  test('custom taunts can be retracted', () => {
    const tauntId = fixedUUID(5, 2)
    const ops = withExtra(sampleWireOperations({ throughRound: 1, finished: false }), (b) => {
      b.add('TauntSent', { tauntId, roundNumber: 2, from: seats.ana, fromName: 'Ana', target: { kind: 'table' }, content: { kind: 'custom', text: 'hello' } })
      b.add('TauntRetracted', { tauntId, reason: 'filter' })
    })
    const game = foldGame(ops)
    expect(game.taunts).toHaveLength(1)
    expect(game.taunts[0]).toMatchObject({ retracted: true, retractReason: 'filter' })
  })
})

describe('operations', () => {
  test('rejects an unknown type and a bad payload', () => {
    const op = sampleWireOperations()[0]
    expect(parseOperation({ ...op, type: 'Nope' }).ok).toBe(false)
    const bad = parseOperation({ ...op, payload: { config: { plannedRounds: 0 } } })
    expect(bad.ok).toBe(false)
    if (!bad.ok) expect(bad.opId).toBe(op.opId)
  })

  test('actorPlayerId defaults to null and IDs are lowercased', () => {
    const op = sampleWireOperations()[0]
    const { actorPlayerId: _, ...rest } = op
    const result = parseOperation({ ...rest, opId: op.opId.toUpperCase() })
    expect(result.ok && result.value.operation.actorPlayerId).toBeNull()
    expect(result.ok && result.value.operation.opId).toBe(op.opId)
  })

  test('HLC strings sort like HLCs', () => {
    const a = { wallMs: 1_761_700_000_000, counter: 2, node: 'b' }
    const b = { wallMs: 1_761_700_000_000, counter: 10, node: 'a' }
    const c = { wallMs: 999, counter: 0, node: 'z' }
    expect(hlcString(a)).toBe('001761700000000-00002-b')
    expect([hlcString(b), hlcString(a), hlcString(c)].sort()).toEqual([hlcString(c), hlcString(a), hlcString(b)])
    expect(parseHlc(hlcString(a))).toEqual(a)
    expect(parseHlc('001761700000000-00002-8f14e45f-ceea-467f')).toEqual({ wallMs: 1_761_700_000_000, counter: 2, node: '8f14e45f-ceea-467f' })
    expect(parseHlc('nope')).toBeNull()
  })
})

describe('live knock and the Live Activity content state', () => {
  test('a marked knock is live until the round is saved', () => {
    const marked = foldGame(sampleOperations({ throughRound: 5, finished: false, liveKnock: true }))
    expect(marked.liveKnock).toEqual({ roundNumber: 6, knocker: seats.sam })
    const saved = foldGame(sampleOperations({ throughRound: 6, finished: false }))
    expect(saved.liveKnock).toBeNull()
  })

  test('the content state carries standings, the next dealer and the last outcome', () => {
    const state = liveActivityContentState(foldGame(sampleOperations({ throughRound: 5, finished: false, liveKnock: true })))
    expect(state.tableWord).toBe('Cold Deck')
    expect(state.roundsPlayed).toBe(5)
    expect(state.plannedRounds).toBe(6)
    expect(state.dealerSeat).toBe(seats.noah)
    expect(state.liveKnocker).toBe(seats.sam)
    // R5: Noah knocked with 2 against Sam's 4 and landed (−10).
    expect(state.lastRound).toEqual({ number: 5, knocker: seats.noah, outcome: 'landed' })
    expect(state.standings.map((row) => [row.displayName, row.total, row.lastScore])).toEqual([
      ['Noah', 26, -10],
      ['Ana', 29, 9],
      ['Ben', 44, 6],
      ['Cleo', 45, 11],
      ['Sam', 47, 4],
    ])
    expect(JSON.stringify(state).length).toBeLessThan(4096)
  })

  test('a finished game has no dealer and no live knock', () => {
    const state = liveActivityContentState(foldGame(sampleOperations()))
    expect(state.status).toBe('finished')
    expect(state.dealerSeat).toBeUndefined()
    expect(state.standings.map((row) => row.total)).toEqual([28, 34, 65, 67, 70])
  })
})
