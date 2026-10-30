import { describe, expect, test } from 'bun:test'
import { RESTORE_WINDOW_MS, hlcString, type WireOperation } from '@kedro/shared'
import { FILTER_RETRACTION_REASON, SERVER_DEVICE_ID } from '../src/services/ops.ts'
import { OperationBuilder, fixedUUID, harness, ids, sampleWireOperations, seats } from './support.ts'

async function seededHarness() {
  const h = harness()
  await h.profile(ids.noah, 'Noah', 'noah')
  await h.profile(ids.ana, 'Ana', 'ana.k')
  await h.profile(ids.ben, 'Ben', 'ben')
  await h.profile(ids.cleo, 'Cleo', 'cleo')
  return h
}

/** More ops for the sample game, after its last op. */
function after(base: WireOperation[], build: (builder: OperationBuilder) => void, options: { minutes?: number } = {}): WireOperation[] {
  const last = base[base.length - 1]
  const builder = new OperationBuilder(ids.game, ids.noahPhone, ids.noah, last.hlc.wallMs)
  builder.sequence = 5000 + base.length
  if (options.minutes) builder.advance(options.minutes)
  build(builder)
  return builder.operations
}

describe('auth', () => {
  test('health is public; /v1 needs a bearer token', async () => {
    const h = harness()
    expect((await h.get('/health', null)).body.status).toBe('ok')
    const response = await h.get('/v1/players/me', null)
    expect(response.status).toBe(401)
    expect(response.body.error).toBe('unauthorized')
    expect((await h.call('GET', '/v1/players/me', 'not-a-uuid')).status).toBe(401)
  })

  test('uploading needs a profile', async () => {
    const h = harness()
    const response = await h.upload(ids.noah, sampleWireOperations())
    expect(response.status).toBe(404)
    expect((response.body as unknown as { error: string }).error).toBe('profileRequired')
  })
})

describe('POST /v1/ops', () => {
  test('accepts the §17 sample game, then treats a re-upload as duplicates', async () => {
    const h = await seededHarness()
    const ops = sampleWireOperations()
    const first = await h.upload(ids.noah, ops)
    expect(first.status).toBe(200)
    expect(first.body.accepted).toHaveLength(ops.length)
    expect(first.body.duplicates).toEqual([])
    expect(first.body.rejected).toEqual([])

    const again = await h.upload(ids.noah, ops)
    expect(again.body.accepted).toEqual([])
    expect(again.body.duplicates.sort()).toEqual(ops.map((op) => op.opId).sort())

    const game = await h.store.getGame(ids.game)
    expect(game?.status).toBe('finished')
    expect(game?.roundsPlayed).toBe(8)
    expect(game?.tableWord).toBe('Cold Deck')
    expect(h.store.seats.get(ids.game)?.map((seat) => seat.displayName)).toEqual(['Noah', 'Ana', 'Ben', 'Cleo', 'Sam'])
  })

  test('projects the finished game: finals Noah 28, Ana 34, Cleo 65, Ben 67, Sam 70', async () => {
    const h = await seededHarness()
    await h.upload(ids.noah, sampleWireOperations())
    const finished = h.store.finished.get(ids.game)
    expect(finished?.isAbandoned).toBe(false)
    expect(finished?.seats.map((seat) => [seat.displayName, seat.total, seat.rank, seat.isWinner])).toEqual([
      ['Noah', 28, 1, true],
      ['Ana', 34, 2, false],
      ['Cleo', 65, 3, false],
      ['Ben', 67, 4, false],
      ['Sam', 70, 5, false],
    ])
    // Ratings were replayed: Noah up, Sam (a guest, so not public) down.
    expect(h.store.ratingRows.get(seats.noah)?.rating).toBeGreaterThan(1000)
    expect(h.store.ratingRows.get(seats.sam)?.rating).toBeLessThan(1000)
  })

  test('arrival in pieces and out of order gives the same game', async () => {
    const h = await seededHarness()
    const ops = sampleWireOperations({ finished: false })
    const created = ops.slice(0, 7) // GameCreated, five seats, GameStarted
    await h.upload(ids.noah, [...created].reverse())
    await h.upload(ids.noah, ops.slice(7).reverse())
    const game = await h.store.getGame(ids.game)
    expect(game?.status).toBe('active')
    expect(game?.roundsPlayed).toBe(8)
  })

  test('a new game must start with its GameCreated', async () => {
    const h = await seededHarness()
    const ops = sampleWireOperations().slice(1)
    const response = await h.upload(ids.noah, ops)
    expect(response.body.accepted).toEqual([])
    expect(new Set(response.body.rejected.map((row) => row.reason))).toEqual(new Set(['unknownGame']))
    expect(await h.store.getGame(ids.game)).toBeNull()
  })

  test('malformed ops are rejected as invalid; the rest of the batch still lands', async () => {
    const h = await seededHarness()
    const ops = sampleWireOperations({ throughRound: 1, finished: false })
    const bad = { ...ops[ops.length - 1], opId: fixedUUID(9, 1), payload: { round: { number: 2, hands: { nope: 3 }, knocker: 'x' } } }
    const response = await h.upload(ids.noah, [...ops, bad, { hello: 'world' } as unknown as WireOperation])
    expect(response.body.accepted).toHaveLength(ops.length)
    expect(response.body.rejected.map((row) => row.reason)).toEqual(['invalid', 'invalid'])
    expect(response.body.rejected[0].opId).toBe(fixedUUID(9, 1))
  })

  test('players not at the table cannot write to it', async () => {
    const h = await seededHarness()
    const stranger = fixedUUID(1, 99)
    await h.profile(stranger, 'Mallory', 'mallory')
    const ops = sampleWireOperations({ throughRound: 2, finished: false })
    await h.upload(ids.noah, ops)
    const edit = after(ops, (b) => b.add('RoundEdited', { round: { number: 1, hands: { [seats.noah]: 0, [seats.ana]: 0, [seats.ben]: 0, [seats.cleo]: 0, [seats.sam]: 0 }, knocker: seats.noah } }), {})
    const response = await h.upload(stranger, edit.map((op) => ({ ...op, actorPlayerId: stranger })))
    expect(response.body.rejected.map((row) => row.reason)).toEqual(['notSeated'])
  })

  test('after Round 1 a stranger cannot seat themselves to get write access', async () => {
    const h = await seededHarness()
    const stranger = fixedUUID(1, 99)
    await h.profile(stranger, 'Mallory', 'mallory')
    const ops = sampleWireOperations({ throughRound: 1, finished: false })
    await h.upload(ids.noah, ops)
    const sneak = after(ops, (b) => {
      b.add('PlayerSeated', { seat: { player: { kind: 'player', id: stranger }, displayName: 'Mallory', order: 9 } }, { actor: stranger })
      b.add('RoundsChanged', { plannedRounds: 50 }, { actor: stranger })
    })
    const response = await h.upload(stranger, sneak)
    expect(response.body.accepted).toEqual([])
    expect(response.body.rejected.every((row) => row.reason === 'notSeated')).toBe(true)
  })

  test('joining a lobby: a player seats themselves and can then read the log', async () => {
    const h = await seededHarness()
    const lobby = sampleWireOperations({ throughRound: 0, finished: false }).slice(0, 2) // created + Noah seated
    await h.upload(ids.noah, lobby)
    expect((await h.get(`/v1/games/${ids.game}/ops`, ids.ana)).status).toBe(403)
    const join = after(lobby, (b) => b.add('PlayerSeated', { seat: { player: { kind: 'player', id: ids.ana }, displayName: 'Ana', order: 1 } }, { device: ids.anaPhone, actor: ids.ana }))
    const response = await h.upload(ids.ana, join)
    expect(response.body.accepted).toHaveLength(1)
    const read = await h.get(`/v1/games/${ids.game}/ops`, ids.ana)
    expect(read.status).toBe(200)
    expect(read.body.ops).toHaveLength(3)
  })

  test('actorPlayerId must be the caller, null, or someone seated in the game', async () => {
    const h = await seededHarness()
    const ops = sampleWireOperations({ throughRound: 1, finished: false })
    await h.upload(ids.noah, ops)
    const forged = after(ops, (b) => {
      b.add('ReactionAdded', { roundNumber: 1, seatId: seats.ben, reaction: 'fire' }, { actor: ids.ben }) // Ben is seated: a relay
      b.add('ReactionAdded', { roundNumber: 1, seatId: seats.ana, reaction: 'clown' }, { actor: fixedUUID(1, 77) })
      b.add('ReactionAdded', { roundNumber: 1, seatId: seats.sam, reaction: 'laugh' }, { actor: null })
    })
    const response = await h.upload(ids.noah, forged)
    expect(response.body.accepted).toHaveLength(2)
    expect(response.body.rejected.map((row) => row.reason)).toEqual(['invalidActor'])
  })

  test('a finished game refuses state-changing ops but takes reactions, receipts and retractions', async () => {
    const h = await seededHarness()
    const ops = sampleWireOperations()
    await h.upload(ids.noah, ops)
    const late = after(ops, (b) => {
      b.add('RoundEdited', { round: { number: 8, hands: { [seats.noah]: 9, [seats.ana]: 1, [seats.ben]: 12, [seats.cleo]: 6, [seats.sam]: 21 }, knocker: seats.noah } })
      b.add('RoundRecorded', { round: { number: 9, hands: { [seats.noah]: 1, [seats.ana]: 1, [seats.ben]: 1, [seats.cleo]: 1, [seats.sam]: 1 }, knocker: seats.ana } })
      b.add('ReactionAdded', { roundNumber: 8, seatId: seats.ana, reaction: 'salute' }, { device: ids.anaPhone, actor: ids.ana })
      b.add('ReceiptSent', { fromSeat: seats.noah, toSeat: seats.ana, receiptKey: 'RC-01' })
      b.add('GameFinished', { reason: 'completed', finalRounds: [] }) // a second phone tapped Finish
    })
    const response = await h.upload(ids.noah, late)
    expect(response.body.rejected.map((row) => row.reason)).toEqual(['gameFinished', 'gameFinished'])
    expect(response.body.accepted).toHaveLength(3)
    // Totals unchanged.
    expect(h.store.finished.get(ids.game)?.seats.map((seat) => seat.total)).toEqual([28, 34, 65, 67, 70])
  })

  test('an abandon within 15 minutes of the finish voids the game for stats; a restore brings it back', async () => {
    const h = await seededHarness()
    const ops = sampleWireOperations()
    await h.upload(ids.noah, ops)
    expect(h.store.ratingRows.size).toBe(5)

    const abandon = after(ops, (b) => b.add('GameAbandoned', {}), { minutes: 5 })
    expect((await h.upload(ids.noah, abandon)).body.accepted).toHaveLength(1)
    expect((await h.store.getGame(ids.game))?.status).toBe('abandoned')
    expect(h.store.finished.get(ids.game)?.isAbandoned).toBe(true)
    expect(h.store.ratingRows.size).toBe(0)

    const all = [...ops, ...abandon]
    const tooLate = after(all, (b) => b.add('RoundsChanged', { plannedRounds: 10 }))
    expect((await h.upload(ids.noah, tooLate)).body.rejected.map((row) => row.reason)).toEqual(['gameAbandoned'])

    const restore = after(all, (b) => b.add('GameRestored', {}), { minutes: 3 })
    expect((await h.upload(ids.noah, restore)).body.accepted).toHaveLength(1)
    expect((await h.store.getGame(ids.game))?.status).toBe('finished')
    expect(h.store.finished.get(ids.game)?.isAbandoned).toBe(false)
    expect(h.store.ratingRows.size).toBe(5)
  })

  test('an abandon more than 15 minutes after the finish is refused', async () => {
    const h = await seededHarness()
    const ops = sampleWireOperations()
    await h.upload(ids.noah, ops)
    const abandon = after(ops, (b) => b.add('GameAbandoned', {}), { minutes: RESTORE_WINDOW_MS / 60_000 + 1 })
    expect((await h.upload(ids.noah, abandon)).body.rejected.map((row) => row.reason)).toEqual(['gameFinished'])
    expect((await h.store.getGame(ids.game))?.status).toBe('finished')
  })

  test('a restore after the window is refused', async () => {
    const h = await seededHarness()
    const ops = sampleWireOperations({ throughRound: 3, finished: false })
    const abandon = after(ops, (b) => b.add('GameAbandoned', {}))
    await h.upload(ids.noah, [...ops, ...abandon])
    const restore = after([...ops, ...abandon], (b) => b.add('GameRestored', {}), { minutes: 16 })
    expect((await h.upload(ids.noah, restore)).body.rejected.map((row) => row.reason)).toEqual(['gameAbandoned'])
  })

  test('custom taunts that fail the server filter are retracted by a server op', async () => {
    const h = await seededHarness()
    h.store.blocklist = ['zorpface']
    const ops = sampleWireOperations({ throughRound: 2, finished: false })
    const taunts = after(ops, (b) => {
      b.add('TauntSent', { tauntId: fixedUUID(5, 7), roundNumber: 3, from: seats.noah, fromName: 'Noah', target: { kind: 'table' }, content: { kind: 'custom', text: 'You absolute Z0RPFACE' } })
      b.add('TauntSent', { tauntId: fixedUUID(5, 8), roundNumber: 3, from: seats.noah, fromName: 'Noah', target: { kind: 'table' }, content: { kind: 'custom', text: 'Read it and weep' } })
    })
    await h.upload(ids.noah, [...ops, ...taunts])
    const log = (await h.get(`/v1/games/${ids.game}/ops`, ids.noah)).body.ops as WireOperation[]
    const retractions = log.filter((op) => op.type === 'TauntRetracted')
    expect(retractions).toHaveLength(1)
    expect(retractions[0].payload).toEqual({ tauntId: fixedUUID(5, 7), reason: FILTER_RETRACTION_REASON })
    expect(retractions[0].deviceId).toBe(SERVER_DEVICE_ID)
    expect(retractions[0].actorPlayerId).toBeNull()
    expect(hlcString(retractions[0].hlc) > hlcString(taunts[0].hlc)).toBe(true)
  })

  test('sends a Live Activity content state for live games (stub sender)', async () => {
    const h = await seededHarness()
    await h.upload(ids.noah, sampleWireOperations({ throughRound: 5, finished: false, liveKnock: true }))
    const message = h.broadcaster.sent.get(ids.game)
    expect(message?.event).toBe('update')
    expect(message?.contentState.roundsPlayed).toBe(5)
    expect(message?.contentState.standings.map((row) => row.total)).toEqual([26, 29, 44, 45, 47])
    expect(message?.contentState.dealerSeat).toBe(seats.noah) // R6 is Noah's deal (design §17)
    expect(message?.contentState.liveKnocker).toBe(seats.sam)
  })

  test('rejects more than 500 ops per request', async () => {
    const h = await seededHarness()
    const response = await h.post('/v1/ops', ids.noah, { ops: Array.from({ length: 501 }, () => ({})) })
    expect(response.status).toBe(413)
    expect(response.body.error).toBe('tooManyOps')
  })
})

describe('GET /v1/games/:gameId/ops', () => {
  test('returns the log in HLC order, and only ops after ?after=', async () => {
    const h = await seededHarness()
    const ops = sampleWireOperations()
    await h.upload(ids.noah, [...ops].reverse())
    const all = await h.get(`/v1/games/${ids.game}/ops`, ids.noah)
    expect(all.status).toBe(200)
    expect(all.body.ops.map((op: WireOperation) => op.opId)).toEqual(ops.map((op) => op.opId))
    expect(all.body.ops[0]).toEqual(ops[0])

    const cursor = hlcString(ops[9].hlc)
    const tail = await h.get(`/v1/games/${ids.game}/ops?after=${encodeURIComponent(cursor)}`, ids.ana)
    expect(tail.body.ops.map((op: WireOperation) => op.opId)).toEqual(ops.slice(10).map((op) => op.opId))
  })

  test('accepts the uppercase UUIDs Swift puts in paths', async () => {
    const h = await seededHarness()
    await h.upload(ids.noah, sampleWireOperations())
    const response = await h.get(`/v1/games/${ids.game.toUpperCase()}/ops`, ids.noah)
    expect(response.status).toBe(200)
  })

  test('404 for an unknown game, 403 when not seated, 400 for a bad cursor', async () => {
    const h = await seededHarness()
    await h.upload(ids.noah, sampleWireOperations())
    expect((await h.get(`/v1/games/${fixedUUID(4, 9)}/ops`, ids.noah)).status).toBe(404)
    expect((await h.get(`/v1/games/${ids.game}/ops`, fixedUUID(1, 50))).status).toBe(403)
    expect((await h.get(`/v1/games/${ids.game}/ops?after=yesterday`, ids.noah)).status).toBe(400)
    expect((await h.get('/v1/games/not-a-game/ops', ids.noah)).status).toBe(400)
  })
})
