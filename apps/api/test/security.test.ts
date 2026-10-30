// The server-side safeguards: clock bounds, server-time windows, blocks at the table, and the
// table-link attestation.

import { describe, expect, test } from 'bun:test'
import { createPublicKey, generateKeyPairSync, verify } from 'node:crypto'
import { MAX_CLOCK_AHEAD_MS, type WireOperation } from '@kedro/shared'
import { StubNotifier } from '../src/push/notifications.ts'
import { OperationBuilder, harness, ids, sampleWireOperations } from './support.ts'

async function seededHarness() {
  const h = harness()
  await h.profile(ids.noah, 'Noah', 'noah')
  await h.profile(ids.ana, 'Ana', 'ana.k')
  await h.profile(ids.ben, 'Ben', 'ben')
  await h.profile(ids.cleo, 'Cleo', 'cleo')
  return h
}

function after(base: WireOperation[], build: (builder: OperationBuilder) => void, startMs?: number): WireOperation[] {
  const last = base[base.length - 1]
  const builder = new OperationBuilder(ids.game, ids.noahPhone, ids.noah, startMs ?? last.hlc.wallMs)
  builder.sequence = 7000 + base.length
  build(builder)
  return builder.operations
}

describe('op time', () => {
  test('an op dated well ahead of the server clock is refused', async () => {
    const h = await seededHarness()
    const ops = sampleWireOperations({ throughRound: 1, finished: false })
    await h.upload(ids.noah, ops)
    const future = after(ops, (b) => b.add('RoundsChanged', { plannedRounds: 9 }), Date.now() + MAX_CLOCK_AHEAD_MS + 60_000)
    expect((await h.upload(ids.noah, future)).body.rejected.map((row) => row.reason)).toEqual(['clockAhead'])
  })

  test('a backdated abandon long after the finish arrived is refused', async () => {
    const h = await seededHarness()
    let receiveClock = Date.now() - 3 * 24 * 60 * 60 * 1000 // the finish arrived three days ago
    h.store.clock = () => receiveClock
    const ops = sampleWireOperations()
    await h.upload(ids.noah, ops)
    receiveClock = Date.now()
    // Dated one second after the finish, but sent days later.
    const finish = ops[ops.length - 1]
    const abandon = after(ops, (b) => b.add('GameAbandoned', {}), finish.hlc.wallMs + 1)
    expect((await h.upload(ids.noah, abandon)).body.rejected.map((row) => row.reason)).toEqual(['gameFinished'])
    expect((await h.store.getGame(ids.game))?.status).toBe('finished')
    expect(h.store.ratingRows.size).toBe(5)
  })
})

describe('blocks at the table', () => {
  test('a blocked player cannot be seated with their blocker, and gets no saved-seat push', async () => {
    const h = await seededHarness()
    // Ben blocked Noah (the host).
    expect((await h.post('/v1/blocks', ids.ben, { playerId: ids.noah })).status).toBe(200)
    const lobby = sampleWireOperations({ throughRound: 0, finished: false }).filter((op) => op.type !== 'GameStarted')
    const response = await h.upload(ids.noah, lobby)
    expect(response.body.rejected.map((row) => row.reason)).toContain('blocked')
    const seated = h.store.seats.get(ids.game) ?? []
    expect(seated.map((seat) => seat.playerId)).not.toContain(ids.ben)
    const notifier = h.services.notifier as StubNotifier
    expect(notifier.sent.map((row) => row.playerId)).not.toContain(ids.ben)
  })
})

describe('player data for every phone', () => {
  test('GET /v1/players/me/games lists games seated in, including claimed guest seats', async () => {
    const h = await seededHarness()
    await h.upload(ids.noah, sampleWireOperations())
    const mine = await h.get<{ games: { gameId: string; status: string }[] }>('/v1/players/me/games', ids.ana)
    expect(mine.status).toBe(200)
    expect(mine.body.games.map((game) => game.gameId)).toEqual([ids.game])
    expect(mine.body.games[0].status).toBe('finished')
    const stranger = '000000aa-0000-4000-8000-000000000009'
    await h.profile(stranger, 'Pat', 'pat')
    expect((await h.get<{ games: unknown[] }>('/v1/players/me/games', stranger)).body.games).toEqual([])
  })

  test('GET /v1/players/:id/profile gives every phone the same server rating', async () => {
    const h = await seededHarness()
    await h.upload(ids.noah, sampleWireOperations())
    const stranger = '000000aa-0000-4000-8000-000000000009'
    await h.profile(stranger, 'Pat', 'pat')
    const fromNoah = await h.get<{ rating: number; stats: { gamesPlayed: number } }>(`/v1/players/${ids.ana}/profile`, ids.noah)
    const fromStranger = await h.get<{ rating: number; stats: { gamesPlayed: number } }>(`/v1/players/${ids.ana}/profile`, stranger)
    expect(fromNoah.status).toBe(200)
    expect(fromStranger.body).toEqual(fromNoah.body)
    expect(fromNoah.body.stats.gamesPlayed).toBe(1)
    expect(typeof fromNoah.body.rating).toBe('number')
  })

  test('photos upload as an https-servable avatar and load without auth', async () => {
    const h = await seededHarness()
    const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4])
    const response = await h.app.request('/v1/players/me/photo', {
      method: 'PUT',
      headers: { authorization: `Bearer dev:${ids.ana}`, 'content-type': 'image/jpeg' },
      body: jpeg,
    })
    expect(response.status).toBe(200)
    const { avatar } = (await response.json()) as { avatar: { kind: string; url: string } }
    expect(avatar.kind).toBe('photo')
    const path = new URL(avatar.url).pathname
    const served = await h.app.request(path)
    expect(served.status).toBe(200)
    expect(served.headers.get('content-type')).toBe('image/jpeg')
    expect(new Uint8Array(await served.arrayBuffer())).toEqual(jpeg)
    // Not an image.
    const bad = await h.app.request('/v1/players/me/photo', {
      method: 'PUT',
      headers: { authorization: `Bearer dev:${ids.ana}`, 'content-type': 'image/jpeg' },
      body: new Uint8Array([1, 2, 3]),
    })
    expect(bad.status).toBe(400)
  })

  test('a file:// photo is never accepted in a profile', async () => {
    const h = await seededHarness()
    const update = { displayName: 'Ana', handle: 'ana.k', avatar: { kind: 'photo', url: 'file:///var/mobile/Containers/avatar.jpg' } }
    expect((await h.put('/v1/players/me', ids.ana, update)).status).toBe(400)
  })
})

describe('table-link attestation', () => {
  test('the server signs account + device key; the signature checks against GET /link/key', async () => {
    const h = await seededHarness()
    const device = generateKeyPairSync('ed25519')
    const devicePublic = device.publicKey.export({ format: 'jwk' }).x as string
    const response = await h.post<{ attestation: string }>('/v1/link/attestations', ids.ana, { deviceId: ids.anaPhone, publicKey: devicePublic })
    expect(response.status).toBe(200)
    const [payload, signature] = response.body.attestation.split('.')
    const body = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'))
    expect(body.p).toBe(ids.ana)
    expect(body.k).toBe(devicePublic)
    const key = (await h.get<{ publicKey: string }>('/link/key', null)).body.publicKey
    const serverKey = createPublicKey({ key: { kty: 'OKP', crv: 'Ed25519', x: key }, format: 'jwk' })
    expect(verify(null, Buffer.from(payload, 'utf8'), serverKey, Buffer.from(signature, 'base64url'))).toBe(true)
  })
})
