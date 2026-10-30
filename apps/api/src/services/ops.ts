// Operation ingest (POST /v1/ops) and catch-up reads (GET /v1/games/:gameId/ops).
//
// The op log is the source of truth. Ingest validates each op against the wire contract,
// de-duplicates by opId (a re-upload is a duplicate, never an error), refuses ops a finished or
// abandoned game no longer takes, appends the rest, and then rebuilds the game's projections
// (games, seats, finished_games, ratings) by folding the whole log with packages/shared.

import {
  ALLOWED_AFTER_FINISH,
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
import type { GameRow, GuestRegistration, OpRow, SeatRow, Store } from '../store/types.ts'
import { KeyedLock } from './lock.ts'
import type { TauntFilter } from './moderation.ts'
import type { RatingsService } from './ratings.ts'

/** The device ID on operations the server itself writes (filter retractions). */
export const SERVER_DEVICE_ID = '00000000-0000-4000-8000-00000000c0de'

/** The retraction reason when the server's taunt filter blocks a custom taunt. */
export const FILTER_RETRACTION_REASON = 'filtered'

export const DEFAULT_OPS_PAGE = 2000
export const MAX_OPS_PAGE = 5000

/** Ops that can change whether a game is finished or abandoned (the admission check re-folds after them). */
const STATUS_TYPES = new Set<OperationType>(['GameCreated', 'GameStarted', 'GameFinished', 'GameAbandoned', 'GameRestored'])

type Deps = {
  store: Store
  ratings: RatingsService
  filter: TauntFilter
  broadcaster: LiveActivityBroadcaster
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

  async ingest(caller: UUID, input: readonly unknown[]): Promise<PostOpsResponse> {
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
      const result = await this.lock.run(gameId, () => this.ingestGame(caller, gameId, ops))
      response.accepted.push(...result.accepted)
      response.duplicates.push(...result.duplicates)
      response.rejected.push(...result.rejected)
    }
    return response
  }

  private async ingestGame(caller: UUID, gameId: UUID, ops: ParsedOperation[]): Promise<PostOpsResponse> {
    const { store } = this.deps
    const result: PostOpsResponse = { accepted: [], duplicates: [], rejected: [] }
    const reject = (op: Operation, reason: OpRejectionReason, message?: string) => {
      const row: RejectedOp = { opId: op.opId, reason }
      if (message) row.message = message
      result.rejected.push(row)
    }

    const existing = await store.existingOpIds(ops.map(({ operation }) => operation.opId))
    const fresh = ops.filter(({ operation }) => {
      if (!existing.has(operation.opId)) return true
      result.duplicates.push(operation.opId)
      return false
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
      // Joining: whoever holds the game ID (shared by QR code or nearby discovery) may seat
      // themselves, as long as the fold actually takes the seat (seats lock after Round 1).
      const joins = fresh.map(({ operation }) => operation).filter((op) => isSeatFor(op, caller))
      const joined = joins.length > 0 && foldGame([...stored, ...joins], gameId).seats.some((seat) => isPlayer(seat.player, caller))
      if (!joined && !(await store.isSeated(gameId, caller))) {
        for (const { operation } of fresh) reject(operation, 'notSeated')
        return result
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
    for (const parsed of [...fresh].sort((a, b) => compareFoldOrder(a.operation, b.operation))) {
      const op = parsed.operation
      if (op.actorPlayerId && !actors.has(op.actorPlayerId)) {
        reject(op, 'invalidActor', 'actorPlayerId is not seated in this game')
        continue
      }
      const refusal = admission(state, op)
      if (refusal) {
        reject(op, refusal.reason, refusal.message)
        continue
      }
      admitted.push(parsed)
      if (STATUS_TYPES.has(op.type)) state = foldGame([...stored, ...admitted.map(({ operation }) => operation)], gameId)
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
    await this.reproject(gameId, {
      previousStatus: game?.status ?? null,
      changedShape: insertedOps.some((op) => isStateChanging(op.type)),
      uploader: caller,
    })
    return result
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

/** Why a game in this state refuses this op, or null to admit it. */
export function admission(state: FoldedGame, op: Operation): { reason: OpRejectionReason; message: string } | null {
  if (state.status === 'finished') {
    if (ALLOWED_AFTER_FINISH.has(op.type) || op.type === 'GameFinished') return null
    if (op.type === 'GameAbandoned' && state.finishedAtMs !== null && op.hlc.wallMs - state.finishedAtMs <= RESTORE_WINDOW_MS) return null
    return { reason: 'gameFinished', message: 'This game is finished' }
  }
  if (state.status === 'abandoned') {
    if (op.type === 'GameAbandoned' || op.type === 'TauntRetracted') return null
    if (op.type === 'GameRestored') {
      if (state.abandonedAtMs !== null && op.hlc.wallMs - state.abandonedAtMs <= RESTORE_WINDOW_MS) return null
      return { reason: 'gameAbandoned', message: 'The 15-minute restore window has passed' }
    }
    return { reason: 'gameAbandoned', message: 'This game was abandoned' }
  }
  return null
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

function opRow({ operation, rawPayload }: ParsedOperation, receivedBy: UUID): OpRow {
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
