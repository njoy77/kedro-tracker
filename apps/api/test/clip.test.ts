import { describe, expect, test } from 'bun:test'
import type { WireOperation } from '@kedro/shared'
import { StubNotifier } from '../src/push/notifications.ts'
import { OperationBuilder, harness, ids, sampleSeats, sampleWireOperations, seats } from './support.ts'

const clipPhone = '000000c1-0000-4000-8000-000000000001'

async function seeded(throughRound = 2) {
  const h = harness()
  await h.profile(ids.noah, 'Noah', 'noah')
  await h.profile(ids.ana, 'Ana', 'ana.k')
  const ops = sampleWireOperations({ throughRound, finished: false })
  const upload = await h.upload(ids.noah, ops)
  expect(upload.body.rejected).toEqual([])
  return { h, last: ops[ops.length - 1] }
}

async function startClip(h: ReturnType<typeof harness>) {
  const session = await h.post<{ accessToken: string; expiresAt: string }>('/v1/clip/sessions', null, {
    gameId: ids.game.toUpperCase(),
    tableToken: 'QR-CODE-123',
    deviceId: clipPhone,
  })
  expect(session.status).toBe(200)
  return session.body.accessToken
}

/** Calls with a raw bearer token (the clip's). */
async function callWith<T = any>(h: ReturnType<typeof harness>, method: string, path: string, token: string, body?: unknown) {
  const response = await h.app.request(path, {
    method,
    headers: { authorization: `Bearer ${token}`, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  const text = await response.text()
  return { status: response.status, body: (text ? JSON.parse(text) : null) as T }
}

function clipOps(last: WireOperation, build: (builder: OperationBuilder) => void): WireOperation[] {
  const builder = new OperationBuilder(ids.game, clipPhone, null, last.hlc.wallMs + 1000)
  builder.sequence = 9000
  build(builder)
  return builder.operations
}

const samWithPhone = { ...sampleSeats[4], deviceId: clipPhone, languageLevel: 'clean' }

describe('App Clip', () => {
  test('a session reads its own table and nothing else', async () => {
    const { h } = await seeded()
    const token = await startClip(h)
    const read = await callWith<{ ops: WireOperation[] }>(h, 'GET', `/v1/games/${ids.game}/ops`, token)
    expect(read.status).toBe(200)
    expect(read.body.ops.length).toBeGreaterThan(5)
    expect((await callWith(h, 'GET', `/v1/games/${ids.noah}/ops`, token)).status).toBe(403)
    expect((await callWith(h, 'GET', '/v1/players/me', token)).status).toBe(403)
    expect((await callWith(h, 'GET', `/v1/games/${ids.game}/ops`, `${token}x`)).status).toBe(401)
    expect((await h.post('/v1/clip/sessions', null, { gameId: ids.noah, tableToken: 'QR-CODE-123', deviceId: clipPhone })).status).toBe(404)
  })

  test('sits in a guest seat, reports for it, and gets a claim token once', async () => {
    const { h, last } = await seeded(2)
    const token = await startClip(h)
    const ops = clipOps(last, (b) => {
      b.add('PlayerSeated', { seat: samWithPhone })
      b.add('HandReported', { roundNumber: 3, seatId: seats.sam, hand: 4, knocked: false })
      b.add('TauntSent', { tauntId: '000000c2-0000-4000-8000-000000000001', roundNumber: 3, from: seats.sam, fromName: 'Sam', target: { kind: 'table' }, content: { kind: 'canned', id: 'TT-01' } })
    })
    const upload = await callWith<{ accepted: string[]; rejected: { reason: string }[] }>(h, 'POST', '/v1/ops', token, { ops })
    expect(upload.body.rejected).toEqual([])
    expect(upload.body.accepted).toHaveLength(3)

    const claim = await callWith<{ claimToken: string }>(h, 'POST', '/v1/clip/claims', token, { gameId: ids.game, seatId: seats.sam })
    expect(claim.status).toBe(200)
    expect(claim.body.claimToken.length).toBeGreaterThanOrEqual(16)
    expect((await callWith(h, 'POST', '/v1/clip/claims', token, { gameId: ids.game, seatId: seats.sam })).status).toBe(409)

    // The full app redeems it after signing in.
    await h.profile(ids.cleo, 'Cleo', 'cleo')
    const redeemed = await h.post<{ guestId: string }>('/v1/claims', ids.cleo, { claimToken: claim.body.claimToken })
    expect(redeemed.status).toBe(200)
    expect(redeemed.body.guestId).toBe(ids.sam)
  })

  test('refuses anything beyond its own guest seat', async () => {
    const { h, last } = await seeded(2)
    const token = await startClip(h)
    const ops = clipOps(last, (b) => {
      b.add('PlayerSeated', { seat: { ...sampleSeats[1], deviceId: clipPhone } }) // Ana's seat (a player)
      b.add('PlayerSeated', { seat: { ...samWithPhone, displayName: 'Samantha' } }) // renames
      b.add('HandReported', { roundNumber: 3, seatId: seats.ana, hand: 4, knocked: false }) // not linked
      b.add('RoundsChanged', { plannedRounds: 9 })
    })
    const upload = await callWith<{ accepted: string[]; rejected: { reason: string }[] }>(h, 'POST', '/v1/ops', token, { ops })
    expect(upload.body.accepted).toEqual([])
    expect(upload.body.rejected.map((row) => row.reason)).toEqual(['notAllowed', 'notAllowed', 'notAllowed', 'notAllowed'])
    expect((await callWith(h, 'POST', '/v1/clip/claims', token, { gameId: ids.game, seatId: seats.sam })).status).toBe(403)
    // Account tokens can't use the clip claim route.
    expect((await h.post('/v1/clip/claims', ids.noah, { gameId: ids.game, seatId: seats.sam })).status).toBe(403)
  })
})

describe('saved-seat push (N-01)', () => {
  test('a player added in the lobby without a phone gets N-01 from the host', async () => {
    const h = harness()
    await h.profile(ids.noah, 'Noah', 'noah')
    await h.profile(ids.ben, 'Ben', 'ben')
    const lobby = sampleWireOperations({ throughRound: 0, finished: false }).filter((op) => op.type !== 'GameStarted')
    await h.upload(ids.noah, lobby)
    const notifier = h.services.notifier as StubNotifier
    const sent = notifier.sent.map((row) => [row.playerId, row.payload.aps.alert.body, row.payload.kedro.kind])
    expect(sent).toContainEqual([ids.ben, 'Noah saved you a seat at Cold Deck.', 'seat'])
    // Ana has a phone linked (she sat down herself), and Noah is the uploader.
    expect(sent.map(([player]) => player)).not.toContain(ids.ana)
    expect(sent.map(([player]) => player)).not.toContain(ids.noah)
  })
})

describe('Live Activity channel', () => {
  test('seated players read the channel ID (null until APNs exists)', async () => {
    const { h } = await seeded(1)
    const read = await h.get<{ channelId: string | null }>(`/v1/games/${ids.game}/live-activity`, ids.ana)
    expect(read.status).toBe(200)
    expect(read.body.channelId).toBeNull()
    await h.profile(ids.cleo, 'Cleo', 'cleo')
    expect((await h.get(`/v1/games/${ids.game}/live-activity`, '000000aa-0000-4000-8000-000000000001')).status).toBe(403)
  })
})

describe('taunt limits', () => {
  test('3 per sender per round, 1 of them custom', async () => {
    const { h, last } = await seeded(2)
    const builder = new OperationBuilder(ids.game, ids.anaPhone, ids.ana, last.hlc.wallMs + 1000)
    builder.sequence = 9500
    const taunt = (n: number, content: unknown) =>
      builder.add('TauntSent', { tauntId: `000000d${n}-0000-4000-8000-000000000001`, roundNumber: 3, from: seats.ana, fromName: 'Ana', target: { kind: 'table' }, content })
    taunt(1, { kind: 'custom', text: 'nice knock' })
    taunt(2, { kind: 'custom', text: 'second custom' })
    taunt(3, { kind: 'canned', id: 'TT-01' })
    taunt(4, { kind: 'canned', id: 'TT-02' })
    taunt(5, { kind: 'canned', id: 'TT-03' })
    const upload = await h.upload(ids.ana, builder.operations)
    expect(upload.body.accepted).toHaveLength(3)
    expect(upload.body.rejected.map((row) => row.reason)).toEqual(['notAllowed', 'notAllowed'])
  })
})
