// APNs with token-based auth (design §13). Bun's `fetch` speaks HTTP/1.1 only and APNs requires
// HTTP/2, so requests go through `node:http2`, which Bun implements: one session per APNs host,
// reused while the instance is warm and closed after a minute without requests.
//
// Hosts (Apple: "Sending channel management requests to APNs", "Sending broadcast push
// notification requests to APNs", "Sending notification requests to APNs"):
//   device pushes and broadcasts  api.push.apple.com                      api.sandbox.push.apple.com
//   channel management            api-manage-broadcast.push.apple.com:2196  api-manage-broadcast.sandbox.push.apple.com:2195
//
// Configuration (config.ts): APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (the .p8 auth key),
// APNS_BUNDLE_ID, APNS_ENVIRONMENT (`production` for TestFlight and App Store builds, `sandbox`
// for Debug builds; tokens and channels from one environment don't work in the other).

import { connect, constants, type ClientHttp2Session } from 'node:http2'
import { importPKCS8, SignJWT } from 'jose'

export type ApnsEnvironment = 'production' | 'sandbox'

export type ApnsConfig = {
  keyId: string
  teamId: string
  /** The .p8 auth key (PKCS#8 PEM). */
  privateKey: string
  bundleId: string
  environment: ApnsEnvironment
}

export const APNS_ORIGINS: Record<ApnsEnvironment, { push: string; manage: string }> = {
  production: { push: 'https://api.push.apple.com', manage: 'https://api-manage-broadcast.push.apple.com:2196' },
  sandbox: { push: 'https://api.sandbox.push.apple.com', manage: 'https://api-manage-broadcast.sandbox.push.apple.com:2195' },
}

// MARK: Transport

export type ApnsRequest = { origin: string; method: 'GET' | 'POST' | 'DELETE'; path: string; headers: Record<string, string>; body?: string }
export type ApnsResponse = { status: number; headers: Record<string, string>; body: string }

export interface ApnsTransport {
  /** Sends one request. Throws only when no response came back (connection lost, timeout). */
  send(request: ApnsRequest): Promise<ApnsResponse>
}

export class ApnsTimeoutError extends Error {
  constructor(request: ApnsRequest) {
    super(`APNs ${request.method} ${request.path} timed out`)
  }
}

type SessionEntry = { session: ClientHttp2Session; active: number; idle?: ReturnType<typeof setTimeout> }

/** HTTP/2 to APNs over `node:http2`, one session per origin. */
export class Http2Transport implements ApnsTransport {
  private readonly sessions = new Map<string, SessionEntry>()
  private readonly timeoutMs: number
  private readonly idleMs: number

  constructor(options: { timeoutMs?: number; idleMs?: number } = {}) {
    this.timeoutMs = options.timeoutMs ?? 10_000
    this.idleMs = options.idleMs ?? 60_000
  }

  send(request: ApnsRequest): Promise<ApnsResponse> {
    const entry = this.session(request.origin)
    clearTimeout(entry.idle)
    entry.active += 1
    return new Promise<ApnsResponse>((resolve, reject) => {
      const stream = entry.session.request({ ':method': request.method, ':path': request.path, ...request.headers })
      const timer = setTimeout(() => {
        stream.close(constants.NGHTTP2_CANCEL)
        reject(new ApnsTimeoutError(request))
      }, this.timeoutMs)
      let status = 0
      const headers: Record<string, string> = {}
      let body = ''
      stream.on('response', (incoming) => {
        status = Number(incoming[':status'])
        for (const [name, value] of Object.entries(incoming)) {
          if (!name.startsWith(':') && value !== undefined) headers[name] = Array.isArray(value) ? value.join(', ') : String(value)
        }
      })
      stream.setEncoding('utf8')
      stream.on('data', (chunk: string) => (body += chunk))
      stream.on('end', () => {
        clearTimeout(timer)
        if (status === 0) reject(new Error(`APNs ${request.method} ${request.path}: stream ended without a response`))
        else resolve({ status, headers, body })
      })
      stream.on('error', (error) => {
        clearTimeout(timer)
        reject(error)
      })
      stream.end(request.body)
    }).finally(() => {
      entry.active -= 1
      if (entry.active > 0) return
      // node:http2's session.setTimeout doesn't fire under Bun, so idle sessions close on a timer.
      entry.idle = setTimeout(() => this.drop(request.origin, entry), this.idleMs)
      entry.idle.unref?.()
    })
  }

  /** Closes every session (tests, shutdown). */
  close(): void {
    for (const [origin, entry] of this.sessions) this.drop(origin, entry)
  }

  private session(origin: string): SessionEntry {
    const existing = this.sessions.get(origin)
    if (existing && !existing.session.closed && !existing.session.destroyed) return existing
    const entry: SessionEntry = { session: connect(origin), active: 0 }
    const forget = () => {
      if (this.sessions.get(origin) === entry) this.sessions.delete(origin)
    }
    // Errors also reach the open streams; the listener keeps them from crashing the process.
    entry.session.on('error', forget)
    entry.session.on('goaway', forget)
    entry.session.on('close', forget)
    this.sessions.set(origin, entry)
    return entry
  }

  private drop(origin: string, entry: SessionEntry): void {
    clearTimeout(entry.idle)
    if (this.sessions.get(origin) === entry) this.sessions.delete(origin)
    if (!entry.session.closed) entry.session.close()
  }
}

// MARK: Provider token

/** Apple accepts a provider token for an hour and rejects refreshing more than every 20 minutes. */
export const PROVIDER_TOKEN_LIFETIME_MS = 50 * 60 * 1000

/** The ES256 JWT in every request's `authorization` header, signed once per 50 minutes. */
export class ProviderToken {
  private cached: { token: string; issuedAtMs: number } | null = null
  private key: Promise<CryptoKey> | null = null

  constructor(
    private readonly config: Pick<ApnsConfig, 'keyId' | 'teamId' | 'privateKey'>,
    private readonly now: () => number = Date.now,
  ) {}

  async get(): Promise<string> {
    const nowMs = this.now()
    if (this.cached && nowMs - this.cached.issuedAtMs < PROVIDER_TOKEN_LIFETIME_MS) return this.cached.token
    this.key ??= importPKCS8(this.config.privateKey, 'ES256')
    const token = await new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: this.config.keyId })
      .setIssuer(this.config.teamId)
      .setIssuedAt(Math.floor(nowMs / 1000))
      .sign(await this.key)
    this.cached = { token, issuedAtMs: nowMs }
    return token
  }

  /** After APNs answers ExpiredProviderToken: the next `get` signs a new one. */
  reset(): void {
    this.cached = null
  }
}

// MARK: Client

export type ApnsResult = { ok: boolean; status: number; reason?: string; headers: Record<string, string> }

export type DevicePushOptions = {
  pushType: 'alert' | 'background' | 'liveactivity'
  /** 10 sends now, 5 when the device's power allows. */
  priority?: 5 | 10
  /** Seconds since 1970 until which APNs retries delivery; 0 (the default) tries once. */
  expiration?: number
  /** Replaces an earlier notification with the same ID on the device (64 bytes at most). */
  collapseId?: string
}

/** What the senders use; `ApnsClient` is the real one, tests use fakes. */
export interface Apns {
  /** POST /3/device/<token>. */
  sendToDevice(token: string, payload: unknown, options: DevicePushOptions): Promise<ApnsResult>
  /** Creates a Live Activity broadcast channel (no message storage) and returns its ID. */
  createChannel(): Promise<string>
  deleteChannel(channelId: string): Promise<ApnsResult>
  /** POST /4/broadcasts/apps/<bundleId> to every Live Activity subscribed to the channel. */
  broadcast(channelId: string, payload: unknown, options: { priority: 5 | 10 }): Promise<ApnsResult>
}

export class ApnsClient implements Apns {
  private readonly token: ProviderToken

  constructor(
    private readonly config: ApnsConfig,
    private readonly transport: ApnsTransport = new Http2Transport(),
    now: () => number = Date.now,
  ) {
    this.token = new ProviderToken(config, now)
  }

  sendToDevice(token: string, payload: unknown, options: DevicePushOptions): Promise<ApnsResult> {
    const topic = options.pushType === 'liveactivity' ? `${this.config.bundleId}.push-type.liveactivity` : this.config.bundleId
    const headers: Record<string, string> = {
      'apns-topic': topic,
      'apns-push-type': options.pushType,
      'apns-priority': String(options.priority ?? 10),
      'apns-expiration': String(options.expiration ?? 0),
    }
    if (options.collapseId) headers['apns-collapse-id'] = options.collapseId
    return this.request('push', 'POST', `/3/device/${token}`, headers, JSON.stringify(payload))
  }

  async createChannel(): Promise<string> {
    // No message storage: a higher publishing budget, and every update supersedes the last.
    const body = JSON.stringify({ 'message-storage-policy': 0, 'push-type': 'LiveActivity' })
    const result = await this.request('manage', 'POST', this.channelsPath, {}, body)
    const channelId = result.headers['apns-channel-id']
    if (!result.ok || !channelId) throw new Error(`APNs channel create failed: ${describe(result)}`)
    return channelId
  }

  deleteChannel(channelId: string): Promise<ApnsResult> {
    return this.request('manage', 'DELETE', this.channelsPath, { 'apns-channel-id': channelId })
  }

  broadcast(channelId: string, payload: unknown, options: { priority: 5 | 10 }): Promise<ApnsResult> {
    const headers = {
      'apns-channel-id': channelId,
      'apns-push-type': 'liveactivity',
      'apns-priority': String(options.priority),
      // Channels without message storage reject a nonzero expiration.
      'apns-expiration': '0',
    }
    return this.request('push', 'POST', `/4/broadcasts/apps/${this.config.bundleId}`, headers, JSON.stringify(payload))
  }

  private get channelsPath(): string {
    return `/1/apps/${this.config.bundleId}/channels`
  }

  private async request(host: 'push' | 'manage', method: ApnsRequest['method'], path: string, headers: Record<string, string>, body?: string): Promise<ApnsResult> {
    const origin = APNS_ORIGINS[this.config.environment][host]
    for (let attempt = 1; ; attempt++) {
      const authorization = `bearer ${await this.token.get()}`
      const allHeaders = body === undefined ? { authorization, ...headers } : { authorization, 'content-type': 'application/json', ...headers }
      let response: ApnsResponse
      try {
        response = await this.transport.send({ origin, method, path, headers: allHeaders, body })
      } catch (error) {
        // A session that died while the instance slept: retry once on a fresh one. Not after a
        // timeout, when APNs may already have sent it.
        if (attempt === 1 && !(error instanceof ApnsTimeoutError)) continue
        throw error
      }
      const reason = errorReason(response.body)
      if (attempt === 1 && response.status === 403 && reason === 'ExpiredProviderToken') {
        this.token.reset()
        continue
      }
      return { ok: response.status >= 200 && response.status < 300, status: response.status, reason, headers: response.headers }
    }
  }
}

/** "410 Unregistered", for logs. */
export function describe(result: ApnsResult): string {
  return result.reason ? `${result.status} ${result.reason}` : String(result.status)
}

function errorReason(body: string): string | undefined {
  if (!body) return undefined
  try {
    const parsed = JSON.parse(body) as { reason?: unknown }
    return typeof parsed.reason === 'string' ? parsed.reason : undefined
  } catch {
    return undefined
  }
}
