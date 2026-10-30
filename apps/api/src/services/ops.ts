// Operation ingest (POST /v1/ops) and catch-up reads (GET /v1/games/:gameId/ops).
//
// The op log is the source of truth. Ingest validates each op against the wire contract,
// de-duplicates by opId (a re-upload is a duplicate, never an error), refuses ops a finished or
// abandoned game no longer takes, appends the rest, and then rebuilds the game's projections
// (games, seats, finished_games, ratings) by folding the whole log with packages/shared.

import {
  ALLOWED_AFTER_FINISH,
  MAX_CLOCK_AHEAD_MS,
  RESTORE_WINDOW_MS,
  compareFoldOrder,
  compareHlc,
  foldGame,
  hlcString,
  isStateChanging,
  isoSeconds,
  parseOperation,
  projectFinishedGame,
  seatIdOf,
  type FoldedGame,
  type GameStatus,
  type HLC,
  type OpRejectionReason,
  type Operation,
  type OperationType,
  type ParsedOperation,
  type PostOpsResponse,
  type RejectedOp,
  type UUID,
  type WireOperation,
} from '@kedro/shared'
import { forbidden, notFound } from '../http.ts'
import type { LiveActivityBroadcaster } from '../push/liveActivity.ts'
import type { Notifier } from '../push/notifications.ts'
import type { ClipSession } from './clip.ts'
import type { GameRow, GuestRegistration, OpRow, SeatRow, Store } from '../store/types.ts'
import { isValidInviteCode } from './invites.ts'
import { KeyedLock } from './lock.ts'
import type { TauntFilter } from './moderation.ts'
import type { RatingsService } from './ratings.ts'

/** The device ID on operations the server itself writes (filter retractions). */
export const SERVER_DEVICE_ID = '00000000-0000-4000-8000-00000000c0de'

/** The retraction reason when the server's taunt filter blocks a custom taunt. */
export const FILTER_RETRACTION_REASON = 'filtered'

export const DEFAULT_OPS_PAGE = 2000
export const MAX_OPS_PAGE = 5000

/**
 * Slack on the 15-minute windows when they're judged by the server's receive times (upload
 * latency from a phone that was briefly offline).
 */
export const RECEIVE_GRACE_MS = 5 * 60 * 1000

/** Server receive times the finish/abandon windows are judged against (see `admission`). */
export type AdmissionTiming = {
  nowMs: number
  /** When the server received the op that finished the game (null when not finished). */
  finishReceivedMs: number | null
  /** When the server received the op that abandoned the game (null when not abandoned). */
  abandonReceivedMs: number | null
}

/** Ops that can change whether a game is finished or abandoned (the admission check re-folds after them). */
const STATUS_TYPES = new Set<OperationType>(['GameCreated', 'GameStarted', 'GameFinished', 'GameAbandoned', 'GameRestored'])

type Deps = {
  store: Store
  ratings: RatingsService
  filter: TauntFilter
  broadcaster: LiveActivityBroadcaster
  notifier?: Notifier
  now?: () => number
  log?: (message: string) => void
}

export class OpsService {
  private readonly lock = new KeyedLock()
  private readonly now: () => number
  private readonly log: (message: string) => void

  constructor(private readonly deps: Deps) {
    this.now = deps.now ?? Date.now
    this.log = deps.log ?? (() => {})
  }

  // MARK: Ingest

  async ingest(caller: UUID, input: readonly unknown[], invites: Readonly<Record<string, string>> = {}): Promise<PostOpsResponse> {
    const response: PostOpsResponse = { accepted: [], duplicates: [], rejected: [] }
    const byGame = new Map<UUID, ParsedOperation[]>()
    const seen = new Set<UUID>()
    for (const raw of input) {
      const result = parseOperation(raw)
      if (!result.ok) {
        response.rejected.push({ opId: result.opId, reason: 'invalid', message: result.error })
        continue
      }
      const { opId, gameId } = result.value.operation
      if (seen.has(opId)) continue // listed twice in one request: settled with the first copy
      seen.add(opId)
      byGame.set(gameId, [...(byGame.get(gameId) ?? []), result.value])
    }

    for (const [gameId, ops] of byGame) {
      const invite = invites[gameId] ?? invites[gameId.toUpperCase()]
      const result = await this.lock.run(gameId, () => this.ingestGame(caller, gameId, ops, invite))
      response.accepted.push(...result.accepted)
      response.duplicates.push(...result.duplicates)
      response.rejected.push(...result.rejected)
    }
    return response
  }

  private async ingestGame(caller: UUID, gameId: UUID, ops: ParsedOperation[], invite: string | undefined): Promise<PostOpsResponse> {
    const { store } = this.deps
    const result: PostOpsResponse = { accepted: [], duplicates: [], rejected: [] }
    const reject = (op: Operation, reason: OpRejectionReason, message?: string) => {
      const row: RejectedOp = { opId: op.opId, reason }
      if (message) row.message = message
      result.rejected.push(row)
    }

    const existing = await store.existingOpIds(ops.map(({ operation }) => operation.opId))
    const nowMs = this.now()
    const fresh = ops.filter(({ operation }) => {
      if (existing.has(operation.opId)) {
        result.duplicates.push(operation.opId)
        return false
      }
      // Every time window (and the rating replay order) hangs off op time, so an op dated in the
      // future is refused rather than allowed to hold a window open.
      if (operation.hlc.wallMs > nowMs + MAX_CLOCK_AHEAD_MS) {
        reject(operation, 'clockAhead', "This phone's clock is ahead of the server's")
        return false
      }
      return true
    })
    if (fresh.length === 0) return result

    const game = await store.getGame(gameId)
    const stored = game ? await this.loadOperations(gameId) : []

    if (!game) {
      if (!fresh.some(({ operation }) => operation.type === 'GameCreated')) {
        for (const { operation } of fresh) reject(operation, 'unknownGame', 'Upload the GameCreated operation first')
        return result
      }
    } else {
      // Joining: a phone may seat itself with the table's current invite code (the QR's `k`,
      // which every admitted phone can make), checked against the key the table registered. The
      // game ID alone is public (it's in the Bonjour record), so it is not enough. The fold must
      // also actually take the seat (seats lock after Round 1).
      if (!(await store.isSeated(gameId, caller))) {
        const joins = fresh.map(({ operation }) => operation).filter((op) => isSeatFor(op, caller))
        const takesSeat = joins.length > 0 && foldGame([...stored, ...joins], gameId).seats.some((seat) => isPlayer(seat.player, caller))
        if (!takesSeat) {
          for (const { operation } of fresh) reject(operation, 'notSeated')
          return result
        }
        const key = await store.inviteKey(gameId)
        if (!invite || !key || !isValidInviteCode(invite, key, gameId, nowMs)) {
          for (const { operation } of fresh) reject(operation, 'inviteRequired', 'Scan the table code again to sit down')
          return result
        }
      }
    }

    // Actors: the caller, nobody (guest-mode phones, system actions), or anyone ever seated here
    // (a phone at the table relays everyone's ops).
    const actors = new Set<UUID>([caller])
    if (game?.createdBy) actors.add(game.createdBy)
    for (const op of [...stored, ...fresh.map(({ operation }) => operation)]) {
      if (op.type === 'PlayerSeated' && op.payload.seat.player.kind === 'player') actors.add(op.payload.seat.player.id)
    }

    const admitted: ParsedOperation[] = []
    let state = foldGame(stored, gameId)
    const received = await store.receivedAt(stored.filter((op) => op.type === 'GameFinished' || op.type === 'GameAbandoned').map((op) => op.opId))
    const timing = (): AdmissionTiming => ({
      nowMs,
      finishReceivedMs: receivedTime(state.finishedAtMs, 'GameFinished', stored, received, nowMs),
      abandonReceivedMs: receivedTime(state.abandonedAtMs, 'GameAbandoned', stored, received, nowMs),
    })
    const blocks = new BlockCheck(store, caller)
    for (const parsed of [...fresh].sort((a, b) => compareFoldOrder(a.operation, b.operation))) {
      const op = parsed.operation
      if (op.actorPlayerId && !actors.has(op.actorPlayerId)) {
        reject(op, 'invalidActor', 'actorPlayerId is not seated in this game')
        continue
      }
      const refusal = admission(state, op, timing()) ?? tauntLimitRefusal(state, admitted, op) ?? (await blocks.refusal(state, op))
      if (refusal) {
        reject(op, refusal.reason, refusal.message)
        continue
      }
      admitted.push(parsed)
      if (STATUS_TYPES.has(op.type) || op.type === 'PlayerSeated') state = foldGame([...stored, ...admitted.map(({ operation }) => operation)], gameId)
    }
    if (admitted.length === 0) return result

    if (!game) await store.ensureGame(gameId, caller)
    const inserted = new Set(await store.insertOps(admitted.map((parsed) => opRow(parsed, caller))))
    for (const { operation } of admitted) {
      if (inserted.has(operation.opId)) result.accepted.push(operation.opId)
      else result.duplicates.push(operation.opId) // another request stored it first
    }
    if (inserted.size === 0) return result

    const insertedOps = admitted.map(({ operation }) => operation).filter((op) => inserted.has(op.opId))
    await this.moderate(gameId, insertedOps, state.latestHlc)
    const before = foldGame(stored, gameId)
    const folded = await this.reproject(gameId, {
      previousStatus: game?.status ?? null,
      changedShape: insertedOps.some((op) => isStateChanging(op.type)),
      uploader: caller,
    })
    await this.notifySavedSeats(before, folded, caller)
    return result
  }

  /**
   * N-01 "Maya saved you a seat at Cold Deck": a player the host added from Played With or
   * Search (a seat for a registered player with no phone linked yet) while the table is in the
   * lobby. Never for the uploader's own seat.
   */
  private async notifySavedSeats(before: FoldedGame, after: FoldedGame, caller: UUID): Promise<void> {
    const { notifier } = this.deps
    if (!notifier || after.status !== 'lobby' || !after.created) return
    const known = new Set(before.seats.map((seat) => seatIdOf(seat.player)))
    const host = after.seats.find((seat) => seatIdOf(seat.player) === after.hostSeat)
    // Never across a block, either way, with the uploader or the host (it would be a channel
    // for the blocked person to reach their blocker).
    const hidden = await hiddenFrom(this.deps.store, caller)
    if (host?.player.kind === 'player' && host.player.id !== caller) {
      for (const id of await hiddenFrom(this.deps.store, host.player.id)) hidden.add(id)
    }
    for (const seat of after.seats) {
      if (known.has(seatIdOf(seat.player)) || seat.player.kind !== 'player' || seat.deviceId || seat.player.id === caller) continue
      if (hidden.has(seat.player.id)) continue
      await notifier
        .savedSeat({ playerId: seat.player.id, gameId: after.gameId, hostName: host?.displayName ?? 'Someone', tableWord: after.config.tableWord })
        .catch((error: unknown) => this.log(`saved-seat push failed: ${String(error)}`))
    }
  }

  // MARK: App Clip

  /**
   * POST /v1/ops from an App Clip session (services/clip.ts). The clip may only, for its own game:
   * link its phone to an existing guest seat (a PlayerSeated that changes nothing but the
   * deviceId), and act for the seat linked to its phone (HandReported, ReactionAdded, a canned
   * TauntSent from that seat). Everything else is refused as `notAllowed`.
   */
  async ingestClip(clip: ClipSession, input: readonly unknown[]): Promise<PostOpsResponse> {
    const response: PostOpsResponse = { accepted: [], duplicates: [], rejected: [] }
    const ops: ParsedOperation[] = []
    const seen = new Set<UUID>()
    for (const raw of input) {
      const result = parseOperation(raw)
      if (!result.ok) {
        response.rejected.push({ opId: result.opId, reason: 'invalid', message: result.error })
        continue
      }
      const op = result.value.operation
      if (seen.has(op.opId)) continue
      seen.add(op.opId)
      if (op.gameId !== clip.gameId) {
        response.rejected.push({ opId: op.opId, reason: 'notAllowed', message: 'This session is for another table' })
        continue
      }
      ops.push(result.value)
    }
    if (ops.length === 0) return response
    const result = await this.lock.run(clip.gameId, () => this.ingestClipGame(clip, ops))
    response.accepted.push(...result.accepted)
    response.duplicates.push(...result.duplicates)
    response.rejected.push(...result.rejected)
    return response
  }

  private async ingestClipGame(clip: ClipSession, ops: ParsedOperation[]): Promise<PostOpsResponse> {
    const { store } = this.deps
    const result: PostOpsResponse = { accepted: [], duplicates: [], rejected: [] }
    const existing = await store.existingOpIds(ops.map(({ operation }) => operation.opId))
    const fresh = ops.filter(({ operation }) => {
      if (!existing.has(operation.opId)) return true
      result.duplicates.push(operation.opId)
      return false
    })
    if (fresh.length === 0) return result
    const game = await store.getGame(clip.gameId)
    if (!game) {
      for (const { operation } of fresh) result.rejected.push({ opId: operation.opId, reason: 'unknownGame' })
      return result
    }
    const stored = await this.loadOperations(clip.gameId)
    const admitted: ParsedOperation[] = []
    let state = foldGame(stored, clip.gameId)
    for (const parsed of [...fresh].sort((a, b) => compareFoldOrder(a.operation, b.operation))) {
      const op = parsed.operation
      const refusal = clipRefusal(state, op, clip) ?? admission(state, op) ?? tauntLimitRefusal(state, admitted, op)
      if (refusal) {
        result.rejected.push({ opId: op.opId, reason: refusal.reason, message: refusal.message })
        continue
      }
      admitted.push(parsed)
      state = foldGame([...stored, ...admitted.map(({ operation }) => operation)], clip.gameId)
    }
    if (admitted.length === 0) return result
    const inserted = new Set(await store.insertOps(admitted.map((parsed) => opRow(parsed, null))))
    for (const { operation } of admitted) {
      if (inserted.has(operation.opId)) result.accepted.push(operation.opId)
      else result.duplicates.push(operation.opId)
    }
    if (inserted.size === 0) return result
    const insertedOps = admitted.map(({ operation }) => operation).filter((op) => inserted.has(op.opId))
    await this.reproject(clip.gameId, {
      previousStatus: game.status,
      changedShape: insertedOps.some((op) => isStateChanging(op.type)),
      uploader: null,
    })
    return result
  }

  /** The APNs broadcast channel for a game's Live Activity (null until APNs creates one). */
  async liveActivityChannel(caller: UUID, gameId: UUID): Promise<string | null> {
    const game = await this.deps.store.getGame(gameId)
    if (!game) throw notFound('No such game')
    if (!(await this.deps.store.isSeated(gameId, caller))) throw forbidden('You are not seated in this game')
    return game.liveActivityChannelId
  }

  /** GET /v1/games/:gameId/ops for an App Clip session. */
  async operationsForClip(clip: ClipSession, gameId: UUID, options: { after?: string; limit?: number }): Promise<WireOperation[]> {
    if (gameId !== clip.gameId) throw forbidden('This session is for another table')
    if (!(await this.deps.store.getGame(gameId))) throw notFound('No such game')
    const limit = Math.min(Math.max(1, options.limit ?? DEFAULT_OPS_PAGE), MAX_OPS_PAGE)
    return this.deps.store.getOps(gameId, { after: options.after, limit })
  }

  // MARK: Reads

  async operationsAfter(caller: UUID, gameId: UUID, options: { after?: string; limit?: number }): Promise<WireOperation[]> {
    const { store } = this.deps
    const game = await store.getGame(gameId)
    if (!game) throw notFound('No such game')
    if (!(await store.isSeated(gameId, caller))) throw forbidden('You are not seated in this game')
    const limit = Math.min(Math.max(1, options.limit ?? DEFAULT_OPS_PAGE), MAX_OPS_PAGE)
    return store.getOps(gameId, { after: options.after, limit })
  }

  // MARK: Projection

  /** Rebuilds a game's projections from its whole log. Also used after claims and by maintenance. */
  async reproject(
    gameId: UUID,
    { previousStatus, changedShape, uploader }: { previousStatus: GameStatus | null; changedShape: boolean; uploader: UUID | null },
  ): Promise<FoldedGame> {
    const { store, ratings, broadcaster } = this.deps
    const folded = foldGame(await this.loadOperations(gameId), gameId)
    const current = await store.getGame(gameId)

    const guests: GuestRegistration[] = folded.seats
      .filter((seat) => seat.player.kind === 'guest')
      .map((seat) => ({ id: seat.player.id, displayName: seat.displayName, createdBy: uploader, claimTokenHash: seat.claimTokenHash ?? null }))
    if (guests.length > 0) await store.registerGuests(guests)
    await store.syncGame(gameRow(folded, current), seatRows(folded))

    const wasFinished = previousStatus === 'finished'
    let ratingsChanged = false
    if (folded.status === 'finished') {
      const projection = projectFinishedGame(folded)
      if (projection && (!wasFinished || changedShape)) {
        await store.projectFinishedGame(projection)
        ratingsChanged = true
      }
    } else if (folded.status === 'abandoned' && folded.finishedAtMs !== null && wasFinished) {
      await store.setFinishedGameAbandoned(gameId, true)
      ratingsChanged = true
    }
    if (ratingsChanged) await ratings.replay()

    broadcaster.gameChanged(folded).catch((error: unknown) => this.log(`live activity broadcast failed: ${String(error)}`))
    return folded
  }

  private async loadOperations(gameId: UUID): Promise<Operation[]> {
    const wire = await this.deps.store.getOps(gameId)
    return wire.flatMap((op) => {
      const result = parseOperation(op)
      if (result.ok) return [result.value.operation]
      this.log(`stored op ${op.opId} no longer parses: ${result.error}`)
      return []
    })
  }

  // MARK: Moderation

  /**
   * Re-checks custom taunts with the server's filter. A blocked one is retracted for every phone
   * by a server-written TauntRetracted op.
   */
  private async moderate(gameId: UUID, ops: Operation[], latest: HLC | null): Promise<void> {
    const retractions: OpRow[] = []
    let clock = latest
    for (const op of ops) {
      if (op.type !== 'TauntSent' || op.payload.content.kind !== 'custom') continue
      const check = await this.deps.filter.check(op.payload.content.text)
      if (check.allowed) continue
      clock = nextServerHlc(this.now(), clock && compareHlc(clock, op.hlc) > 0 ? clock : op.hlc)
      const operation: WireOperation = {
        opId: crypto.randomUUID(),
        gameId,
        deviceId: SERVER_DEVICE_ID,
        hlc: clock,
        actorPlayerId: null,
        type: 'TauntRetracted',
        payload: { tauntId: op.payload.tauntId, reason: FILTER_RETRACTION_REASON },
      }
      retractions.push({ operation, hlc: hlcString(clock), receivedBy: null })
    }
    if (retractions.length > 0) await this.deps.store.insertOps(retractions)
  }
}

// MARK: Rules

/**
 * Why a game in this state refuses this op, or null to admit it.
 *
 * The 15-minute windows (abandon a finished game, restore an abandoned one) must hold both by the
 * ops' own clocks (as the phones' folds judge them) and, when `timing` is given, by the server's
 * receive times: op time comes from the phone, so a backdated abandon days later would otherwise
 * void a finished game's ratings.
 */
export function admission(state: FoldedGame, op: Operation, timing?: AdmissionTiming): { reason: OpRejectionReason; message: string } | null {
  const withinReceiveWindow = (since: number | null | undefined) =>
    !timing || since === null || since === undefined || timing.nowMs - since <= RESTORE_WINDOW_MS + RECEIVE_GRACE_MS
  if (state.status === 'finished') {
    if (ALLOWED_AFTER_FINISH.has(op.type) || op.type === 'GameFinished') return null
    if (
      op.type === 'GameAbandoned' &&
      state.finishedAtMs !== null &&
      op.hlc.wallMs - state.finishedAtMs <= RESTORE_WINDOW_MS &&
      withinReceiveWindow(timing?.finishReceivedMs)
    ) return null
    return { reason: 'gameFinished', message: 'This game is finished' }
  }
  if (state.status === 'abandoned') {
    if (op.type === 'GameAbandoned' || op.type === 'TauntRetracted') return null
    if (op.type === 'GameRestored') {
      if (state.abandonedAtMs !== null && op.hlc.wallMs - state.abandonedAtMs <= RESTORE_WINDOW_MS && withinReceiveWindow(timing?.abandonReceivedMs)) return null
      return { reason: 'gameAbandoned', message: 'The 15-minute restore window has passed' }
    }
    return { reason: 'gameAbandoned', message: 'This game was abandoned' }
  }
  return null
}

/**
 * When the server received the op that set a finish/abandon time: the earliest-received stored op
 * of that type at that time, or now when it is in this request (not stored yet).
 */
function receivedTime(atMs: number | null, type: 'GameFinished' | 'GameAbandoned', stored: readonly Operation[], received: ReadonlyMap<UUID, number>, nowMs: number): number | null {
  if (atMs === null) return null
  const times = stored.filter((op) => op.type === type && op.hlc.wallMs === atMs).flatMap((op) => {
    const time = received.get(op.opId)
    return time === undefined ? [] : [time]
  })
  return times.length > 0 ? Math.min(...times) : nowMs
}

/** Players `playerId` blocked or was blocked by. */
async function hiddenFrom(store: Store, playerId: UUID): Promise<Set<UUID>> {
  const { blocked, blockedBy } = await store.blockRelations(playerId)
  return new Set([...blocked, ...blockedBy])
}

/**
 * The block safeguard (design §5.9 "Rules", §8.3): someone can never be seated at a table with a
 * person they blocked or who blocked them, whoever uploads the seat.
 */
class BlockCheck {
  private readonly cache = new Map<UUID, Promise<Set<UUID>>>()

  constructor(
    private readonly store: Store,
    private readonly caller: UUID,
  ) {}

  async refusal(state: FoldedGame, op: Operation): Promise<{ reason: OpRejectionReason; message: string } | null> {
    if (op.type !== 'PlayerSeated' || op.payload.seat.player.kind !== 'player') return null
    const newcomer = op.payload.seat.player.id
    if (state.seats.some((seat) => isPlayer(seat.player, newcomer))) return null // an update to an existing seat
    const hidden = await this.hidden(newcomer)
    const others = new Set<UUID>([this.caller])
    for (const seat of state.seats) if (seat.player.kind === 'player') others.add(seat.player.id)
    others.delete(newcomer)
    for (const other of others) {
      if (hidden.has(other)) return { reason: 'blocked', message: 'They can’t be seated at this table' }
    }
    return null
  }

  private hidden(playerId: UUID): Promise<Set<UUID>> {
    let entry = this.cache.get(playerId)
    if (!entry) {
      entry = hiddenFrom(this.store, playerId)
      this.cache.set(playerId, entry)
    }
    return entry
  }
}

/** Taunts per sender per round (design §8.3), the same limits the phones apply on receipt. */
export const TAUNTS_PER_ROUND = 3
export const CUSTOM_TAUNTS_PER_ROUND = 1

/**
 * Refuses a taunt over the limits: 3 per sender per round, at most 1 of them custom. Senders are
 * keyed by seat, or by name for watchers (as iOS `TauntRateLimit`). Counts what the game already
 * holds plus what this request admitted before it.
 */
export function tauntLimitRefusal(state: FoldedGame, admitted: readonly ParsedOperation[], op: Operation): { reason: OpRejectionReason; message: string } | null {
  if (op.type !== 'TauntSent') return null
  const sender = (from: string | null | undefined, name: string) => from ?? `watcher:${name}`
  const key = sender(op.payload.from, op.payload.fromName)
  const earlier = [
    ...state.taunts.map((taunt) => ({ round: taunt.roundNumber, sender: sender(taunt.from, taunt.fromName), custom: taunt.content.kind === 'custom' })),
    ...admitted.flatMap(({ operation }) =>
      operation.type === 'TauntSent'
        ? [{ round: operation.payload.roundNumber, sender: sender(operation.payload.from, operation.payload.fromName), custom: operation.payload.content.kind === 'custom' }]
        : [],
    ),
  ].filter((taunt) => taunt.round === op.payload.roundNumber && taunt.sender === key)
  if (earlier.length >= TAUNTS_PER_ROUND) return { reason: 'notAllowed', message: 'Three taunts a round' }
  if (op.payload.content.kind === 'custom' && earlier.filter((taunt) => taunt.custom).length >= CUSTOM_TAUNTS_PER_ROUND) {
    return { reason: 'notAllowed', message: 'One custom taunt a round' }
  }
  return null
}

/** What an App Clip session may not upload (see `OpsService.ingestClip`), or null. */
export function clipRefusal(state: FoldedGame, op: Operation, clip: ClipSession): { reason: OpRejectionReason; message: string } | null {
  const refuse = (message: string) => ({ reason: 'notAllowed' as const, message })
  if (op.actorPlayerId !== null) return refuse('A clip acts for a guest seat only')
  const mine = state.seats.find((seat) => seat.deviceId === clip.deviceId)
  const mySeat = mine ? seatIdOf(mine.player) : null
  switch (op.type) {
    case 'PlayerSeated': {
      if (state.status === 'finished' || state.status === 'abandoned') return refuse('This table is closed')
      const next = op.payload.seat
      const current = state.seats.find((seat) => seatIdOf(seat.player) === seatIdOf(next.player))
      if (!current || current.player.kind !== 'guest') return refuse('Pick one of the guest seats')
      if (current.deviceId && current.deviceId !== clip.deviceId) return refuse('Someone else sits there')
      if (mySeat && mySeat !== seatIdOf(current.player)) return refuse('This phone already has a seat')
      if (next.deviceId !== clip.deviceId) return refuse('Link the seat to this phone')
      // The phone link and its language level (the clip is Clean) are all a clip may change.
      const { deviceId: _next, claimTokenHash: _hash, languageLevel: _level, ...rest } = next
      const { deviceId: _current, claimTokenHash: _currentHash, languageLevel: _currentLevel, ...currentRest } = current
      if (JSON.stringify(sortKeys(rest)) !== JSON.stringify(sortKeys(currentRest))) return refuse('Only the phone link can change')
      return null
    }
    case 'HandReported':
      if (!mySeat || op.payload.seatId !== mySeat) return refuse('Report your own hand')
      return null
    case 'ReactionAdded':
      if (!mySeat || op.payload.seatId !== mySeat) return refuse('React from your own seat')
      return null
    case 'TauntSent':
      if (!mySeat || op.payload.from !== mySeat) return refuse('Taunt from your own seat')
      if (op.payload.content.kind !== 'canned') return refuse('Canned taunts only in the clip')
      return null
    default:
      return refuse('Get Kedro to do this')
  }
}

function sortKeys(value: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(value).filter(([, v]) => v !== undefined).sort(([a], [b]) => a.localeCompare(b)))
}

function isSeatFor(op: Operation, playerId: UUID): boolean {
  return op.type === 'PlayerSeated' && isPlayer(op.payload.seat.player, playerId)
}

function isPlayer(ref: { kind: 'player' | 'guest'; id: UUID }, playerId: UUID): boolean {
  return ref.kind === 'player' && ref.id === playerId
}

/** A server HLC after `after`, on the server's wall clock. */
export function nextServerHlc(nowMs: number, after: HLC | null): HLC {
  if (!after || nowMs > after.wallMs) return { wallMs: nowMs, counter: 0, node: SERVER_DEVICE_ID }
  if (after.counter >= 99_999) return { wallMs: after.wallMs + 1, counter: 0, node: SERVER_DEVICE_ID }
  return { wallMs: after.wallMs, counter: after.counter + 1, node: SERVER_DEVICE_ID }
}

function opRow({ operation, rawPayload }: ParsedOperation, receivedBy: UUID | null): OpRow {
  const wire: WireOperation = {
    opId: operation.opId,
    gameId: operation.gameId,
    deviceId: operation.deviceId,
    hlc: operation.hlc,
    actorPlayerId: operation.actorPlayerId,
    type: operation.type,
    payload: rawPayload,
  }
  return { operation: wire, hlc: hlcString(operation.hlc), receivedBy }
}

function gameRow(game: FoldedGame, current: GameRow | null): GameRow {
  const iso = (ms: number | null) => (ms === null ? null : isoSeconds(ms))
  return {
    id: game.gameId,
    createdBy: current?.createdBy ?? null,
    status: game.status,
    tableWord: game.created ? game.config.tableWord : null,
    plannedRounds: game.created ? game.config.plannedRounds : null,
    scoringMode: game.created ? game.config.scoringMode : null,
    hostSeat: game.hostSeat,
    roundsPlayed: game.rounds.length,
    startedAt: iso(game.startedAtMs),
    finishedAt: game.status === 'finished' || game.status === 'abandoned' ? iso(game.finishedAtMs) : null,
    finishReason: game.finishReason,
    abandonedAt: iso(game.abandonedAtMs),
    lastHlc: game.latestHlc ? hlcString(game.latestHlc) : null,
    liveActivityChannelId: current?.liveActivityChannelId ?? null,
  }
}

function seatRows(game: FoldedGame): SeatRow[] {
  return game.seats.map((seat) => ({
    seatId: seatIdOf(seat.player),
    playerId: seat.player.kind === 'player' ? seat.player.id : null,
    guestId: seat.player.kind === 'guest' ? seat.player.id : null,
    displayName: seat.displayName,
    seatOrder: seat.order,
    deviceId: seat.deviceId ?? null,
  }))
}
