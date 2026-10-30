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
  type OkResponse,
  type Player,
  type PlayedWithResponse,
  type PlayerSummary,
  type PostOpsResponse,
  type SearchPlayersResponse,
  type TauntCheckResponse,
} from '@kedro/shared'
import { requireAuth, type AuthEnv, type TokenVerifier } from './auth.ts'
import { HttpError, badRequest, errorBody, readJson, uuidParam } from './http.ts'
import { StubLiveActivityBroadcaster, type LiveActivityBroadcaster } from './push/liveActivity.ts'
import { StubNotifier, type Notifier } from './push/notifications.ts'
import { ClipService, ClipTokens } from './services/clip.ts'
import { LeaderboardService } from './services/leaderboard.ts'
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
}

const OK: OkResponse = { ok: true }
const HLC_STRING = /^[0-9]{15}-[0-9]{5}-.{1,64}$/

export function createServices({ store, broadcaster, notifier, clipSecret, now, log }: Omit<AppDeps, 'verifier'>): Services {
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
    clip: new ClipService(store, clipTokens),
    ops: new OpsService({ store, ratings, filter, broadcaster: broadcaster ?? new StubLiveActivityBroadcaster(log), notifier: alerts, now, log }),
    leaderboard: new LeaderboardService(store, players),
    social: new SocialService(store, players, ratings),
  }
}

export function createApp(deps: AppDeps) {
  const services = createServices(deps)
  const { ops, players, leaderboard, social, filter, clip, clipTokens } = services
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

  const v1 = new Hono<AuthEnv>()
  v1.use('*', requireAuth(deps.verifier, clipTokens))
  v1.use('*', bodyLimit({ maxSize: 2 * 1024 * 1024, onError: (c) => c.json(errorBody('payloadTooLarge', 'Request body too large'), 413) }))

  // MARK: Operations

  v1.post('/ops', async (c) => {
    const body = await readJson(c, z.object({ ops: z.array(z.unknown()) }))
    if (body.ops.length > MAX_OPS_PER_REQUEST) {
      throw new HttpError(413, 'tooManyOps', `Send at most ${MAX_OPS_PER_REQUEST} operations per request`)
    }
    const clipSession = c.get('clip')
    if (clipSession) return c.json<PostOpsResponse>(await ops.ingestClip(clipSession, body.ops))
    const caller = c.get('user').id
    await players.requireProfile(caller)
    return c.json<PostOpsResponse>(await ops.ingest(caller, body.ops))
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

  v1.get('/players/search', async (c) => {
    const limit = optionalInt(c.req.query('limit'), 'limit')
    return c.json<SearchPlayersResponse>({ players: await players.search(c.get('user').id, c.req.query('q') ?? '', limit) })
  })

  v1.get('/players/me/played-with', async (c) => c.json<PlayedWithResponse>({ players: await players.playedWith(c.get('user').id) }))

  v1.get('/players/me/guests', async (c) => {
    return c.json<GuestSuggestionsResponse>({ guests: await players.guestSuggestions(c.get('user').id, c.req.query('name') ?? '') })
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

  app.route('/v1', v1)
  return { app, services }
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
