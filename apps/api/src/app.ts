// The Kedro API (contract: packages/shared/src/api.ts). Every /v1 route needs a Supabase access
// token: `Authorization: Bearer <jwt>`. Errors are `{error, message}` (ApiError).

import { Hono } from 'hono'
import { bodyLimit } from 'hono/body-limit'
import { cors } from 'hono/cors'
import { logger } from 'hono/logger'
import { z } from 'zod'
import {
  API_VERSION,
  LEADERBOARD_SCOPES,
  LEADERBOARD_SORTS,
  MAX_OPS_PER_REQUEST,
  blockSchema,
  claimSchema,
  clipClaimSchema,
  clipSessionSchema,
  inviteKeySchema,
  isoSeconds,
  linkAttestationSchema,
  MAX_PHOTO_BYTES,
  pushTokenSchema,
  receiptSchema,
  reportSchema,
  tauntCheckSchema,
  updateProfileSchema,
  type ClaimResponse,
  type ClipClaimResponse,
  type ClipSessionResponse,
  type LiveActivityChannelResponse,
  type GetOpsResponse,
  type GuestSuggestionsResponse,
  type HandleAvailabilityResponse,
  type HealthResponse,
  type LeaderboardResponse,
  type RecordsResponse,
  type LinkAttestationResponse,
  type LinkKeyResponse,
  type MyGamesResponse,
  type OkResponse,
  type PhotoUploadResponse,
  type PlayerProfileResponse,
  type Player,
  type PlayedWithResponse,
  type PlayerSummary,
  type PostOpsResponse,
  type PlayerDirectoryResponse,
  type SearchPlayersResponse,
  type TauntCheckResponse,
} from '@kedro/shared'
import { requireAuth, type AuthEnv, type TokenVerifier } from './auth.ts'
import { HttpError, badRequest, errorBody, readJson, uuidParam } from './http.ts'
import { StubLiveActivityBroadcaster, type LiveActivityBroadcaster } from './push/liveActivity.ts'
import { StubNotifier, type Notifier } from './push/notifications.ts'
import { ClipService, ClipTokens } from './services/clip.ts'
import { decodeInviteKey } from './services/invites.ts'
import { LeaderboardService } from './services/leaderboard.ts'
import { LinkAttestor } from './services/link.ts'
import { TauntFilter } from './services/moderation.ts'
import { OpsService } from './services/ops.ts'
import { PlayersService } from './services/players.ts'
import { RatingsService } from './services/ratings.ts'
import { SocialService } from './services/social.ts'
import type { Store } from './store/types.ts'

export type AppDeps = {
  store: Store
  verifier: TokenVerifier
  broadcaster?: LiveActivityBroadcaster
  notifier?: Notifier
  /** Signs App Clip session tokens (KEDRO_CLIP_SECRET); a random per-process secret when unset. */
  clipSecret?: string
  /** Signs table-link identity attestations (KEDRO_LINK_SIGNING_KEY, base64 PKCS#8 Ed25519); per-process when unset. */
  linkSigningKey?: string
  /** The API's public origin for photo URLs (KEDRO_PUBLIC_URL); the request's origin when unset. */
  publicUrl?: string
  now?: () => number
  log?: (message: string) => void
  /** Log every request (the server entry turns this on; tests leave it off). */
  logRequests?: boolean
}

export type Services = {
  ops: OpsService
  players: PlayersService
  leaderboard: LeaderboardService
  social: SocialService
  ratings: RatingsService
  filter: TauntFilter
  clip: ClipService
  clipTokens: ClipTokens
  notifier: Notifier
  link: LinkAttestor
}

const OK: OkResponse = { ok: true }
const HLC_STRING = /^[0-9]{15}-[0-9]{5}-.{1,64}$/

export function createServices({ store, broadcaster, notifier, clipSecret, linkSigningKey, now, log }: Omit<AppDeps, 'verifier'>): Services {
  const ratings = new RatingsService(store)
  const filter = new TauntFilter(store, now)
  const players = new PlayersService(store)
  const clipTokens = new ClipTokens(clipSecret, now)
  const alerts = notifier ?? new StubNotifier(store, log)
  return {
    ratings,
    filter,
    players,
    clipTokens,
    notifier: alerts,
    clip: new ClipService(store, clipTokens, now),
    link: new LinkAttestor(linkSigningKey, now),
    ops: new OpsService({ store, ratings, filter, broadcaster: broadcaster ?? new StubLiveActivityBroadcaster(log), notifier: alerts, now, log }),
    leaderboard: new LeaderboardService(store, players),
    social: new SocialService(store, players, ratings),
  }
}

export function createApp(deps: AppDeps) {
  const services = createServices(deps)
  const { ops, players, leaderboard, social, filter, clip, clipTokens, link } = services
  const now = deps.now ?? Date.now
  const log = deps.log ?? console.error

  const app = new Hono<AuthEnv>()

  app.onError((error, c) => {
    if (error instanceof HttpError) return c.json(errorBody(error.code, error.message), error.status)
    log(`unhandled error on ${c.req.method} ${c.req.path}: ${error instanceof Error ? error.stack ?? error.message : String(error)}`)
    return c.json(errorBody('internal', 'Something went wrong'), 500)
  })
  app.notFound((c) => c.json(errorBody('notFound', 'No such route'), 404))
  if (deps.logRequests) app.use('*', logger())

  // The iOS app doesn't need CORS; this lets the web app call the API later.
  app.use('/v1/*', cors({ origin: '*', allowHeaders: ['authorization', 'content-type'], allowMethods: ['GET', 'POST', 'PUT', 'DELETE'] }))

  app.get('/health', (c) => c.json<HealthResponse>({ status: 'ok', version: API_VERSION }))

  // Public: the key hubs check table-link attestations with (they cache it for offline tables).
  app.get('/link/key', (c) => c.json<LinkKeyResponse>({ publicKey: link.publicKey }))

  // Public: profile photos (public profile data, PRD §3.3), so AsyncImage on any phone loads them.
  app.get('/photos/:playerId', async (c) => {
    const photo = await deps.store.getPhoto(uuidParam(c.req.param('playerId'), 'playerId'))
    if (!photo) return c.json(errorBody('notFound', 'No photo'), 404)
    return c.body(Buffer.from(photo.bytes), 200, {
      'content-type': photo.contentType,
      'cache-control': 'public, max-age=86400',
      etag: `"${photo.version}"`,
    })
  })

  const v1 = new Hono<AuthEnv>()
  v1.use('*', requireAuth(deps.verifier, clipTokens))
  v1.use('*', bodyLimit({ maxSize: 2 * 1024 * 1024, onError: (c) => c.json(errorBody('payloadTooLarge', 'Request body too large'), 413) }))

  // MARK: Operations

  v1.post('/ops', async (c) => {
    const body = await readJson(c, z.object({ ops: z.array(z.unknown()), invites: z.record(z.string().max(64), z.string().max(64)).optional() }))
    if (body.ops.length > MAX_OPS_PER_REQUEST) {
      throw new HttpError(413, 'tooManyOps', `Send at most ${MAX_OPS_PER_REQUEST} operations per request`)
    }
    const clipSession = c.get('clip')
    if (clipSession) return c.json<PostOpsResponse>(await ops.ingestClip(clipSession, body.ops))
    const caller = c.get('user').id
    await players.requireProfile(caller)
    const invites = Object.fromEntries(Object.entries(body.invites ?? {}).map(([gameId, code]) => [gameId.toLowerCase(), code]))
    return c.json<PostOpsResponse>(await ops.ingest(caller, body.ops, invites))
  })

  v1.get('/games/:gameId/ops', async (c) => {
    const gameId = uuidParam(c.req.param('gameId'), 'gameId')
    const after = c.req.query('after') || undefined
    if (after !== undefined && !HLC_STRING.test(after)) throw badRequest('after must be an HLC string')
    const limit = optionalInt(c.req.query('limit'), 'limit')
    const clipSession = c.get('clip')
    if (clipSession) return c.json<GetOpsResponse>({ ops: await ops.operationsForClip(clipSession, gameId, { after, limit }) })
    return c.json<GetOpsResponse>({ ops: await ops.operationsAfter(c.get('user').id, gameId, { after, limit }) })
  })

  v1.get('/games/:gameId/live-activity', async (c) => {
    const gameId = uuidParam(c.req.param('gameId'), 'gameId')
    return c.json<LiveActivityChannelResponse>({ channelId: await ops.liveActivityChannel(c.get('user').id, gameId) })
  })

  v1.put('/games/:gameId/invite-key', async (c) => {
    const gameId = uuidParam(c.req.param('gameId'), 'gameId')
    const { key } = await readJson(c, inviteKeySchema)
    if (!decodeInviteKey(key)) throw badRequest('key must be 32 bytes')
    const caller = c.get('user').id
    if (!(await deps.store.getGame(gameId))) throw notFoundError('No such game yet. Upload its operations first.')
    if (!(await deps.store.isSeated(gameId, caller))) throw new HttpError(403, 'forbidden', 'You are not seated in this game')
    const stored = await deps.store.setInviteKey(gameId, key, caller)
    if (stored !== key) throw new HttpError(409, 'alreadyClaimed', 'This table already registered its invite key')
    return c.json(OK)
  })

  // MARK: Table link

  v1.post('/link/attestations', async (c) => {
    const { deviceId, publicKey } = await readJson(c, linkAttestationSchema)
    const caller = c.get('user').id
    await players.requireProfile(caller)
    return c.json<LinkAttestationResponse>(link.issue(caller, deviceId, publicKey))
  })

  // MARK: App Clip

  v1.post('/clip/sessions', async (c) => {
    const request = await readJson(c, clipSessionSchema)
    return c.json<ClipSessionResponse>(await clip.startSession({ ...request, gameId: request.gameId.toLowerCase(), deviceId: request.deviceId.toLowerCase() }))
  })

  v1.post('/clip/claims', async (c) => {
    const clipSession = c.get('clip')
    if (!clipSession) throw new HttpError(403, 'forbidden', 'Only the App Clip claims seats this way')
    const request = await readJson(c, clipClaimSchema)
    return c.json<ClipClaimResponse>(await clip.claim(clipSession, { gameId: request.gameId.toLowerCase(), seatId: request.seatId }))
  })

  // MARK: Players

  v1.get('/players/me', async (c) => c.json<Player>(await players.me(c.get('user').id)))

  v1.put('/players/me', async (c) => {
    const update = await readJson(c, updateProfileSchema)
    return c.json<Player>(await players.updateMe(c.get('user').id, update))
  })

  v1.get('/players', async (c) => {
    const limit = optionalInt(c.req.query('limit'), 'limit')
    return c.json<PlayerDirectoryResponse>(await players.directory(c.get('user').id, c.req.query('cursor'), limit))
  })

  v1.get('/players/search', async (c) => {
    const limit = optionalInt(c.req.query('limit'), 'limit')
    return c.json<SearchPlayersResponse>({ players: await players.search(c.get('user').id, c.req.query('q') ?? '', limit) })
  })

  v1.get('/players/me/played-with', async (c) => c.json<PlayedWithResponse>({ players: await players.playedWith(c.get('user').id) }))

  v1.get('/players/me/guests', async (c) => {
    return c.json<GuestSuggestionsResponse>({ guests: await players.guestSuggestions(c.get('user').id, c.req.query('name') ?? '') })
  })

  v1.get('/players/me/games', async (c) => {
    const caller = c.get('user').id
    const games = await deps.store.gamesFor(caller)
    return c.json<MyGamesResponse>({
      games: games.map((game) => (game.finishedAt ? { gameId: game.gameId, status: game.status, finishedAt: isoSeconds(game.finishedAt) } : { gameId: game.gameId, status: game.status })),
      claimedGuestIds: await deps.store.claimedGuestIds(caller),
    })
  })

  v1.put('/players/me/photo', async (c) => {
    const caller = c.get('user').id
    await players.requireProfile(caller)
    const contentType = (c.req.header('content-type') ?? '').split(';')[0].trim().toLowerCase()
    if (contentType !== 'image/jpeg' && contentType !== 'image/png') throw badRequest('Send a JPEG or PNG')
    const bytes = new Uint8Array(await c.req.arrayBuffer())
    if (bytes.length === 0) throw badRequest('Empty photo')
    if (bytes.length > MAX_PHOTO_BYTES) throw new HttpError(413, 'payloadTooLarge', 'Photos are at most 512 KB')
    if (!looksLikeImage(bytes, contentType)) throw badRequest('That is not a JPEG or PNG')
    const version = await deps.store.putPhoto(caller, { bytes, contentType })
    const origin = (deps.publicUrl ?? new URL(c.req.url).origin).replace(/\/+$/, '')
    return c.json<PhotoUploadResponse>({ avatar: { kind: 'photo', url: `${origin}/photos/${caller}?v=${version}` } })
  })

  v1.get('/players/:playerId/profile', async (c) => {
    const playerId = uuidParam(c.req.param('playerId'), 'playerId')
    return c.json<PlayerProfileResponse>(await leaderboard.profile(c.get('user').id, playerId))
  })

  v1.get('/players/:playerId', async (c) => {
    const playerId = uuidParam(c.req.param('playerId'), 'playerId')
    return c.json<PlayerSummary>(await players.player(c.get('user').id, playerId))
  })

  v1.get('/handles/:handle', async (c) => {
    return c.json<HandleAvailabilityResponse>(await players.handleAvailable(c.get('user').id, c.req.param('handle')))
  })

  // MARK: Claims

  v1.post('/claims', async (c) => {
    const { claimToken } = await readJson(c, claimSchema)
    return c.json<ClaimResponse>(await social.claim(c.get('user').id, claimToken))
  })

  // MARK: Moderation

  v1.post('/taunts/check', async (c) => {
    const { text } = await readJson(c, tauntCheckSchema)
    const check = await filter.check(text)
    return c.json<TauntCheckResponse>(check.allowed ? { allowed: true } : { allowed: false, reason: check.reason })
  })

  v1.post('/reports', async (c) => {
    await social.report(c.get('user').id, await readJson(c, reportSchema))
    return c.json(OK)
  })

  v1.post('/blocks', async (c) => {
    const { playerId } = await readJson(c, blockSchema)
    await social.block(c.get('user').id, playerId)
    return c.json(OK)
  })

  v1.delete('/blocks/:playerId', async (c) => {
    await social.unblock(c.get('user').id, uuidParam(c.req.param('playerId'), 'playerId'))
    return c.json(OK)
  })

  // MARK: Receipts and push

  v1.post('/receipts', async (c) => {
    await social.receipt(c.get('user').id, await readJson(c, receiptSchema))
    return c.json(OK)
  })

  v1.post('/push/tokens', async (c) => {
    await social.registerPushToken(c.get('user').id, await readJson(c, pushTokenSchema))
    return c.json(OK)
  })

  // MARK: Leaderboard

  v1.get('/leaderboard', async (c) => {
    const scope = oneOf(c.req.query('scope') ?? 'global', LEADERBOARD_SCOPES, 'scope')
    const sort = oneOf(c.req.query('sort') ?? 'rating', LEADERBOARD_SORTS, 'sort')
    const limit = optionalInt(c.req.query('limit'), 'limit')
    return c.json<LeaderboardResponse>(await leaderboard.leaderboard(c.get('user').id, { scope, sort, limit }))
  })

  v1.get('/records', async (c) => {
    const scope = oneOf(c.req.query('scope') ?? 'global', LEADERBOARD_SCOPES, 'scope')
    const limit = optionalInt(c.req.query('limit'), 'limit')
    return c.json<RecordsResponse>(await leaderboard.records(c.get('user').id, { scope, limit }))
  })

  app.route('/v1', v1)
  return { app, services }
}

const notFoundError = (message: string) => new HttpError(404, 'notFound', message)

/** JPEG starts FF D8 FF; PNG with its 8-byte signature. */
function looksLikeImage(bytes: Uint8Array, contentType: string): boolean {
  if (contentType === 'image/jpeg') return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
  return png.every((byte, index) => bytes[index] === byte)
}

function optionalInt(value: string | undefined, name: string): number | undefined {
  if (value === undefined || value === '') return undefined
  if (!/^\d{1,6}$/.test(value)) throw badRequest(`${name} must be a positive integer`)
  return Number(value)
}

function oneOf<T extends string>(value: string, allowed: readonly T[], name: string): T {
  if ((allowed as readonly string[]).includes(value)) return value as T
  throw badRequest(`${name} must be one of ${allowed.join(', ')}`)
}
