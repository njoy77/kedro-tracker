import { describe, expect, test } from 'bun:test'
import { createServer, type Http2Session, type ServerHttp2Stream } from 'node:http2'
import type { WireOperation } from '@kedro/shared'
import { decodeProtectedHeader, exportPKCS8, exportSPKI, generateKeyPair, importSPKI, jwtVerify } from 'jose'
import { loadConfig } from '../src/config.ts'
import {
  ApnsClient,
  ApnsTimeoutError,
  Http2Transport,
  PROVIDER_TOKEN_LIFETIME_MS,
  ProviderToken,
  type Apns,
  type ApnsConfig,
  type ApnsRequest,
  type ApnsResponse,
  type ApnsResult,
  type ApnsTransport,
  type DevicePushOptions,
} from '../src/push/apns.ts'
import type { BroadcastPayload } from '../src/push/liveActivity.ts'
import { harness, ids, OperationBuilder, sampleWireOperations } from './support.ts'

const { privateKey, publicKey } = await generateKeyPair('ES256', { extractable: true })
const config: ApnsConfig = {
  keyId: 'ABC123DEFG',
  teamId: '2RXNMCM34K',
  privateKey: await exportPKCS8(privateKey),
  bundleId: 'com.njoy77.kedro',
  environment: 'sandbox',
}
const OK: ApnsResult = { ok: true, status: 200, headers: {} }

/** Answers requests from a script (the next answer, or 200) and records them. */
class FakeTransport implements ApnsTransport {
  readonly requests: ApnsRequest[] = []
  constructor(private readonly answers: (ApnsResponse | Error)[] = []) {}
  async send(request: ApnsRequest): Promise<ApnsResponse> {
    this.requests.push(request)
    const answer = this.answers.shift() ?? { status: 200, headers: {}, body: '' }
    if (answer instanceof Error) throw answer
    return answer
  }
}

/** Records what the senders ask APNs for. */
class FakeApns implements Apns {
  readonly device: { token: string; payload: any; options: DevicePushOptions }[] = []
  readonly broadcasts: { channelId: string; payload: BroadcastPayload; priority: number }[] = []
  readonly deleted: string[] = []
  created = 0
  broadcastResult: ApnsResult = OK
  readonly deviceResults = new Map<string, ApnsResult>()

  async sendToDevice(token: string, payload: unknown, options: DevicePushOptions): Promise<ApnsResult> {
    this.device.push({ token, payload, options })
    return this.deviceResults.get(token) ?? OK
  }
  async createChannel(): Promise<string> {
    this.created += 1
    const id = `channel-${this.created}`
    await Bun.sleep(1)
    return id
  }
  async deleteChannel(channelId: string): Promise<ApnsResult> {
    this.deleted.push(channelId)
    return OK
  }
  async broadcast(channelId: string, payload: unknown, options: { priority: 5 | 10 }): Promise<ApnsResult> {
    this.broadcasts.push({ channelId, payload: payload as BroadcastPayload, priority: options.priority })
    return this.broadcastResult
  }
}

describe('provider token', () => {
  test('an ES256 JWT with the key ID, team ID and issue time', async () => {
    const token = await new ProviderToken(config, () => 1_800_000_000_000).get()
    expect(decodeProtectedHeader(token)).toEqual({ alg: 'ES256', kid: 'ABC123DEFG' })
    const { payload } = await jwtVerify(token, await importSPKI(await exportSPKI(publicKey), 'ES256'), { currentDate: new Date(1_800_000_000_000) })
    expect(payload).toEqual({ iss: '2RXNMCM34K', iat: 1_800_000_000 })
  })

  test('is reused for 50 minutes, then signed again', async () => {
    let now = 1_800_000_000_000
    const provider = new ProviderToken(config, () => now)
    const first = await provider.get()
    now += PROVIDER_TOKEN_LIFETIME_MS - 1000
    expect(await provider.get()).toBe(first)
    now += 1000
    const second = await provider.get()
    expect(second).not.toBe(first)
    provider.reset()
    now += 1000
    expect(await provider.get()).not.toBe(second)
  })
})

describe('APNs client', () => {
  test('alerts go to /3/device/<token> with the bundle ID as topic', async () => {
    const transport = new FakeTransport()
    const client = new ApnsClient(config, transport)
    const result = await client.sendToDevice('abcd', { aps: { alert: { body: 'hi' } } }, { pushType: 'alert', expiration: 123, collapseId: 'seat:1' })
    expect(result.ok).toBe(true)
    const [request] = transport.requests
    expect(request.origin).toBe('https://api.sandbox.push.apple.com')
    expect(request.method).toBe('POST')
    expect(request.path).toBe('/3/device/abcd')
    expect(request.headers.authorization).toStartWith('bearer ey')
    expect(request.headers).toMatchObject({
      'apns-topic': 'com.njoy77.kedro',
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'apns-expiration': '123',
      'apns-collapse-id': 'seat:1',
    })
    expect(JSON.parse(request.body!)).toEqual({ aps: { alert: { body: 'hi' } } })

    await client.sendToDevice('abcd', {}, { pushType: 'liveactivity' })
    expect(transport.requests[1].headers['apns-topic']).toBe('com.njoy77.kedro.push-type.liveactivity')
  })

  test('channels are created and deleted on the management host; broadcasts go to /4/broadcasts', async () => {
    const transport = new FakeTransport([{ status: 201, headers: { 'apns-channel-id': 'dHN0LXNyY2gtY2hubA==' }, body: '' }])
    const client = new ApnsClient({ ...config, environment: 'production' }, transport)
    expect(await client.createChannel()).toBe('dHN0LXNyY2gtY2hubA==')
    await client.broadcast('dHN0LXNyY2gtY2hubA==', { aps: { event: 'update' } }, { priority: 5 })
    await client.deleteChannel('dHN0LXNyY2gtY2hubA==')
    const [create, broadcast, remove] = transport.requests
    expect([create.origin, create.method, create.path]).toEqual(['https://api-manage-broadcast.push.apple.com:2196', 'POST', '/1/apps/com.njoy77.kedro/channels'])
    expect(JSON.parse(create.body!)).toEqual({ 'message-storage-policy': 0, 'push-type': 'LiveActivity' })
    expect([broadcast.origin, broadcast.path]).toEqual(['https://api.push.apple.com', '/4/broadcasts/apps/com.njoy77.kedro'])
    expect(broadcast.headers).toMatchObject({ 'apns-channel-id': 'dHN0LXNyY2gtY2hubA==', 'apns-push-type': 'liveactivity', 'apns-priority': '5', 'apns-expiration': '0' })
    expect([remove.method, remove.headers['apns-channel-id'], remove.body]).toEqual(['DELETE', 'dHN0LXNyY2gtY2hubA==', undefined])
  })

  test('a failed channel create throws with the reason', async () => {
    const client = new ApnsClient(config, new FakeTransport([{ status: 400, headers: {}, body: '{"reason":"BadRequestParams"}' }]))
    await expect(client.createChannel()).rejects.toThrow('400 BadRequestParams')
  })

  test('errors come back with their reason', async () => {
    const client = new ApnsClient(config, new FakeTransport([{ status: 410, headers: {}, body: '{"reason":"Unregistered","timestamp":1}' }]))
    expect(await client.sendToDevice('abcd', {}, { pushType: 'alert' })).toEqual({ ok: false, status: 410, reason: 'Unregistered', headers: {} })
  })

  test('an expired provider token is signed again and the request retried once', async () => {
    let now = 1_800_000_000_000
    const expired = { status: 403, headers: {}, body: '{"reason":"ExpiredProviderToken"}' }
    const transport = new FakeTransport([expired, { status: 200, headers: {}, body: '' }, expired, expired])
    const client = new ApnsClient(config, transport, () => (now += 1000))
    expect((await client.sendToDevice('abcd', {}, { pushType: 'alert' })).ok).toBe(true)
    expect(transport.requests[0].headers.authorization).not.toBe(transport.requests[1].headers.authorization)
    expect((await client.sendToDevice('abcd', {}, { pushType: 'alert' })).reason).toBe('ExpiredProviderToken')
    expect(transport.requests).toHaveLength(4)
  })

  test('a lost connection is retried once; a timeout is not', async () => {
    const lost = new FakeTransport([new Error('ERR_HTTP2_GOAWAY_SESSION')])
    expect((await new ApnsClient(config, lost).sendToDevice('abcd', {}, { pushType: 'alert' })).ok).toBe(true)
    expect(lost.requests).toHaveLength(2)

    const request = { origin: '', method: 'POST', path: '/3/device/abcd', headers: {} } as const
    const slow = new FakeTransport([new ApnsTimeoutError(request)])
    await expect(new ApnsClient(config, slow).sendToDevice('abcd', {}, { pushType: 'alert' })).rejects.toThrow('timed out')
    expect(slow.requests).toHaveLength(1)
  })
})

describe('HTTP/2 transport', () => {
  test('sends over one reused session and reads status, headers and body', async () => {
    const server = createServer()
    const sessions = new Set<Http2Session>()
    server.on('session', (session) => sessions.add(session))
    server.on('stream', (stream: ServerHttp2Stream, headers) => {
      let body = ''
      stream.setEncoding('utf8')
      stream.on('data', (chunk: string) => (body += chunk))
      stream.on('end', () => {
        stream.respond({ ':status': 201, 'apns-channel-id': 'abc==', 'x-auth': String(headers.authorization) })
        stream.end(JSON.stringify({ path: headers[':path'], method: headers[':method'], body }))
      })
    })
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
    const origin = `http://127.0.0.1:${(server.address() as { port: number }).port}`
    const transport = new Http2Transport()
    try {
      const first = await transport.send({ origin, method: 'POST', path: '/1/apps/x/channels', headers: { authorization: 'bearer t' }, body: '{"a":1}' })
      expect(first.status).toBe(201)
      expect(first.headers['apns-channel-id']).toBe('abc==')
      expect(first.headers['x-auth']).toBe('bearer t')
      expect(JSON.parse(first.body)).toEqual({ path: '/1/apps/x/channels', method: 'POST', body: '{"a":1}' })
      const second = await transport.send({ origin, method: 'DELETE', path: '/1/apps/x/channels', headers: {} })
      expect(JSON.parse(second.body)).toMatchObject({ method: 'DELETE', body: '' })
      expect(sessions.size).toBe(1)
    } finally {
      transport.close()
      server.close()
    }
  })

  test('times out when the server never answers', async () => {
    const server = createServer()
    server.on('stream', () => {})
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
    const origin = `http://127.0.0.1:${(server.address() as { port: number }).port}`
    const transport = new Http2Transport({ timeoutMs: 50 })
    try {
      await expect(transport.send({ origin, method: 'POST', path: '/3/device/x', headers: {}, body: '{}' })).rejects.toBeInstanceOf(ApnsTimeoutError)
    } finally {
      transport.close()
      server.close()
    }
  })
})

const NOW = 1_900_000_000_000

/** A harness on a fake APNs whose background work can be awaited. */
async function apnsHarness() {
  const apns = new FakeApns()
  const deferred: Promise<unknown>[] = []
  const h = harness({ apns, now: () => NOW, defer: (work) => deferred.push(work) })
  await h.profile(ids.noah, 'Noah', 'noah')
  await h.profile(ids.ana, 'Ana', 'ana.k')
  await h.profile(ids.ben, 'Ben', 'ben')
  const settle = async () => {
    while (deferred.length > 0) await Promise.all(deferred.splice(0))
  }
  return { h, apns, settle }
}

function after(base: WireOperation[], build: (builder: OperationBuilder) => void): WireOperation[] {
  const last = base[base.length - 1]
  const builder = new OperationBuilder(ids.game, ids.noahPhone, ids.noah, last.hlc.wallMs)
  builder.sequence = 5000 + base.length
  builder.advance(1)
  build(builder)
  return builder.operations
}

const channelOf = async (h: ReturnType<typeof harness>, as = ids.ana) =>
  (await h.get<{ channelId: string | null }>(`/v1/games/${ids.game}/live-activity`, as)).body.channelId

describe('Live Activity broadcasts', () => {
  test('a phone asking at Deal gets a channel, created once and kept on the game', async () => {
    const { h, apns, settle } = await apnsHarness()
    await h.upload(ids.noah, sampleWireOperations({ throughRound: 0, finished: false }))
    const [a, b] = await Promise.all([channelOf(h, ids.ana), channelOf(h, ids.noah)])
    await settle()
    expect(a).toBe('channel-1')
    expect(b).toBe('channel-1')
    expect(apns.created).toBe(1)
    expect((await h.store.getGame(ids.game))?.liveActivityChannelId).toBe('channel-1')
  })

  test('every change is broadcast to the channel after the response', async () => {
    const { h, apns, settle } = await apnsHarness()
    await h.upload(ids.noah, sampleWireOperations({ throughRound: 2, finished: false }))
    await settle()
    expect(apns.created).toBe(1)
    expect(apns.broadcasts).toHaveLength(1)
    const [update] = apns.broadcasts
    expect(update.channelId).toBe('channel-1')
    expect(update.priority).toBe(5)
    expect(update.payload.aps).toMatchObject({ event: 'update', timestamp: NOW / 1000, 'stale-date': NOW / 1000 + 180 })
    expect(update.payload.aps['content-state'].roundNumber).toBe(3)

    // A live knock goes out at priority 10.
    await h.upload(ids.noah, sampleWireOperations({ throughRound: 5, finished: false, liveKnock: true }))
    await settle()
    expect(apns.broadcasts.at(-1)?.priority).toBe(10)
    expect(apns.broadcasts.at(-1)?.payload.aps['content-state'].liveKnockLine).toBe('Sam knocked · last turns')
    expect(apns.created).toBe(1)
  })

  test('the finish ends the activity 15 minutes later and deletes the channel', async () => {
    const { h, apns, settle } = await apnsHarness()
    await h.upload(ids.noah, sampleWireOperations({ throughRound: 5, finished: false }))
    await settle()
    await h.upload(ids.noah, sampleWireOperations())
    await settle()
    const end = apns.broadcasts.at(-1)!
    expect(end.channelId).toBe('channel-1')
    expect(end.payload.aps).toMatchObject({ event: 'end', 'dismissal-date': NOW / 1000 + 15 * 60 })
    expect(end.payload.aps['content-state'].phase).toBe('finished')
    expect(apns.deleted).toEqual(['channel-1'])
    expect(await channelOf(h)).toBeNull()
    expect(apns.created).toBe(1)
  })

  test('an abandon ends the activity at once', async () => {
    const { h, apns, settle } = await apnsHarness()
    const ops = sampleWireOperations({ throughRound: 3, finished: false })
    await h.upload(ids.noah, ops)
    await settle()
    await h.upload(ids.noah, after(ops, (b) => b.add('GameAbandoned', {})))
    await settle()
    expect(apns.broadcasts.at(-1)?.payload.aps).toMatchObject({ event: 'end', 'dismissal-date': NOW / 1000 })
    expect(apns.deleted).toEqual(['channel-1'])
  })

  test('nothing is sent for the lobby, for a repeat of the same state, or to end a game that never had a channel', async () => {
    const { h, apns, settle } = await apnsHarness()
    const lobby = sampleWireOperations({ throughRound: 0, finished: false }).filter((op) => op.type !== 'GameStarted')
    await h.upload(ids.noah, lobby)
    await settle()
    expect(apns.broadcasts).toHaveLength(0)
    expect(apns.created).toBe(0)

    const services = h.services.ops
    await h.upload(ids.noah, sampleWireOperations({ throughRound: 1, finished: false }))
    await settle()
    expect(apns.broadcasts).toHaveLength(1)
    await services.reproject(ids.game, { previousStatus: 'active', changedShape: false, uploader: null })
    await settle()
    expect(apns.broadcasts).toHaveLength(1)

    const other = harness({ apns: new FakeApns(), now: () => NOW })
    await other.profile(ids.noah, 'Noah', 'noah')
    const quiet = other.services.ops
    await other.upload(ids.noah, sampleWireOperations())
    await quiet.reproject(ids.game, { previousStatus: 'finished', changedShape: false, uploader: null })
    expect(await channelOf(other, ids.noah)).toBeNull()
  })

  test('a channel recorded by another instance first wins, and ours is deleted', async () => {
    const { h, apns, settle } = await apnsHarness()
    await h.upload(ids.noah, sampleWireOperations({ throughRound: 0, finished: false }).filter((op) => op.type !== 'GameStarted'))
    await settle()
    const claim = h.store.claimLiveActivityChannel.bind(h.store)
    h.store.claimLiveActivityChannel = async (gameId, _channelId) => claim(gameId, 'theirs')
    expect(await channelOf(h)).toBe('theirs')
    expect(apns.deleted).toEqual(['channel-1'])
  })

  test('a channel APNs no longer knows is forgotten, and the failure logged', async () => {
    const { h, apns, settle } = await apnsHarness()
    apns.broadcastResult = { ok: false, status: 400, reason: 'BadChannelId', headers: {} }
    await h.upload(ids.noah, sampleWireOperations({ throughRound: 1, finished: false }))
    await settle()
    expect(h.logs.some((line) => line.includes('400 BadChannelId'))).toBe(true)
    expect((await h.store.getGame(ids.game))?.liveActivityChannelId).toBeNull()
    // The next phone to ask gets a new one.
    expect(await channelOf(h)).toBe('channel-2')
  })

  test('without APNs the channel stays null', async () => {
    const h = harness()
    await h.profile(ids.noah, 'Noah', 'noah')
    await h.upload(ids.noah, sampleWireOperations({ throughRound: 1, finished: false }))
    expect(await channelOf(h, ids.noah)).toBeNull()
  })
})

describe('alert pushes (N-01)', () => {
  test('a saved seat is sent to each of the player\'s tokens after the response', async () => {
    const { h, apns, settle } = await apnsHarness()
    expect((await h.post('/v1/push/tokens', ids.ben, { token: 'AA'.repeat(32), kind: 'apns' })).status).toBe(200)
    expect((await h.post('/v1/push/tokens', ids.ben, { token: 'bb'.repeat(32), kind: 'apns' })).status).toBe(200)
    const lobby = sampleWireOperations({ throughRound: 0, finished: false }).filter((op) => op.type !== 'GameStarted')
    await h.upload(ids.noah, lobby)
    await settle()
    expect(apns.device.map((push) => push.token).sort()).toEqual(['aa'.repeat(32), 'bb'.repeat(32)])
    const [push] = apns.device
    expect(push.payload).toEqual({
      aps: { alert: { body: 'Noah saved you a seat at Cold Deck.' } },
      kedro: { kind: 'seat', gameId: ids.game, host: 'Noah', word: 'Cold Deck' },
    })
    expect(push.options).toEqual({ pushType: 'alert', priority: 10, expiration: NOW / 1000 + 3600, collapseId: `seat:${ids.game}` })
  })

  test('a token APNs answers 410 for is deleted; other failures are only logged', async () => {
    const { h, apns, settle } = await apnsHarness()
    const gone = 'cc'.repeat(32)
    const sandbox = 'dd'.repeat(32)
    await h.post('/v1/push/tokens', ids.ben, { token: gone, kind: 'apns' })
    await h.post('/v1/push/tokens', ids.ben, { token: sandbox, kind: 'apns' })
    apns.deviceResults.set(gone, { ok: false, status: 410, reason: 'Unregistered', headers: {} })
    apns.deviceResults.set(sandbox, { ok: false, status: 400, reason: 'BadDeviceToken', headers: {} })
    await h.upload(ids.noah, sampleWireOperations({ throughRound: 0, finished: false }).filter((op) => op.type !== 'GameStarted'))
    await settle()
    expect((await h.store.pushTokens({ playerIds: [ids.ben], kind: 'apns' })).map((row) => row.token)).toEqual([sandbox])
    expect(h.logs.filter((line) => line.startsWith('N-01'))).toHaveLength(2)
  })
})

describe('APNs configuration', () => {
  test('on with a key ID and key; team and bundle ID default; sandbox only locally', () => {
    expect(loadConfig({}).apns).toBeUndefined()
    expect(loadConfig({ APNS_KEY_ID: 'K' }).apns).toBeUndefined()
    const key = '-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----'
    expect(loadConfig({ APNS_KEY_ID: 'K', APNS_PRIVATE_KEY: key }).apns).toEqual({
      keyId: 'K',
      teamId: '2RXNMCM34K',
      privateKey: '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----',
      bundleId: 'com.njoy77.kedro',
      environment: 'sandbox',
    })
    expect(loadConfig({ VERCEL_ENV: 'production', APNS_KEY_ID: 'K', APNS_PRIVATE_KEY: key }).apns?.environment).toBe('production')
    expect(loadConfig({ VERCEL_ENV: 'production', APNS_KEY_ID: 'K', APNS_PRIVATE_KEY: key, APNS_ENVIRONMENT: 'development' }).apns?.environment).toBe('sandbox')
    expect(loadConfig({ APNS_KEY_ID: 'K', APNS_PRIVATE_KEY: key, APNS_ENVIRONMENT: 'production', APNS_TEAM_ID: 'T', APNS_BUNDLE_ID: 'b' }).apns).toMatchObject({
      teamId: 'T',
      bundleId: 'b',
      environment: 'production',
    })
  })
})
