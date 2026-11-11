// Live Activity updates over APNs broadcast channels (design §13.2): one channel per game, and
// every seated phone's Live Activity subscribes to it, so the server sends one push per change
// instead of one per phone.
//
//   1. A live game gets a channel the first time a phone asks for it
//      (GET /v1/games/:gameId/live-activity, at Deal) or the game changes, whichever comes first
//      (POST …/1/apps/<bundleId>/channels, no message storage). Its ID is kept in
//      games.live_activity_channel_id; the first instance to record one wins.
//   2. On every change, a broadcast (POST /4/broadcasts/apps/<bundleId>) with apns-priority 5
//      (10 for a live knock) and {"aps":{"timestamp","event":"update","content-state","stale-date"}}.
//      The content state is the iOS `LiveGameAttributes.ContentState` JSON (packages/shared/src/live.ts).
//   3. On finish or abandon, "event":"end" with a dismissal-date (15 minutes after a finish, at
//      once after an abandon, as the phones do it), then the channel is deleted.
//
// Without APNs keys (config.ts) the stub records the messages and sends nothing.

import { isLive, liveActivityContentState, type FoldedGame, type LiveActivityContentState, type UUID } from '@kedro/shared'
import type { Store } from '../store/types.ts'
import { describe, type Apns } from './apns.ts'

export type LiveActivityEvent = 'update' | 'end'

export interface LiveActivityBroadcaster {
  /** Called after a game's projection changes (best effort; never throws into the request). */
  gameChanged(game: FoldedGame): Promise<void>
  /** The broadcast channel for a live game, created on first use; null without APNs or for an ended game. */
  channel(gameId: UUID): Promise<string | null>
}

export type BroadcastMessage = { gameId: string; event: LiveActivityEvent; contentState: LiveActivityContentState }

/** Builds the message for a game; null when there is nothing to show (lobby). */
export function broadcastMessage(game: FoldedGame, nowMs?: number): BroadcastMessage | null {
  const contentState = liveActivityContentState(game, nowMs)
  if (!contentState) return null
  return { gameId: game.gameId, event: isLive(game.status) ? 'update' : 'end', contentState }
}

/** Content without an update for this long dims on the phone (iOS `LiveActivityController.staleInterval`). */
export const STALE_SECONDS = 3 * 60
/** How long a finished game stays on the Lock Screen (iOS `finishedDismissalDelay`). */
export const FINISHED_DISMISSAL_SECONDS = 15 * 60

export type BroadcastPayload = {
  aps: {
    timestamp: number
    event: LiveActivityEvent
    'content-state': LiveActivityContentState
    'stale-date'?: number
    'dismissal-date'?: number
  }
}

/** The APNs payload for a message sent at `nowMs`. */
export function broadcastPayload(message: BroadcastMessage, nowMs: number): BroadcastPayload {
  const timestamp = Math.floor(nowMs / 1000)
  const aps: BroadcastPayload['aps'] = { timestamp, event: message.event, 'content-state': message.contentState }
  if (message.event === 'update') aps['stale-date'] = timestamp + STALE_SECONDS
  else aps['dismissal-date'] = message.contentState.phase === 'finished' ? timestamp + FINISHED_DISMISSAL_SECONDS : timestamp
  return { aps }
}

/**
 * The stub sender: builds the exact content state and records it, but sends nothing until APNs
 * credentials exist. `sent` keeps the latest message per game for tests and debugging.
 */
export class StubLiveActivityBroadcaster implements LiveActivityBroadcaster {
  readonly sent = new Map<string, BroadcastMessage>()

  constructor(private readonly log: (message: string) => void = () => {}) {}

  async gameChanged(game: FoldedGame): Promise<void> {
    const message = broadcastMessage(game)
    if (!message) return
    const previous = this.sent.get(game.gameId)
    if (previous && JSON.stringify(previous) === JSON.stringify(message)) return
    if (this.sent.size > 1000) this.sent.clear()
    this.sent.set(game.gameId, message)
    this.log(`live activity ${message.event} for ${game.gameId} (not sent: APNs is not configured)`)
  }

  async channel(): Promise<string | null> {
    return null
  }
}

/** APNs reasons for a channel that no longer exists (deleted, or from the other environment). */
const GONE_CHANNEL = new Set(['BadChannelId', 'ChannelNotRegistered', 'ChannelNotFound'])

/** Sends each game's Live Activity content to its APNs broadcast channel. */
export class ApnsLiveActivityBroadcaster implements LiveActivityBroadcaster {
  /** The last content sent per game on this instance, to skip changes the phones can't see. */
  private readonly lastSent = new Map<UUID, string>()
  private readonly creating = new Map<UUID, Promise<string>>()
  /** Sends for a game run one at a time, in order, so an update never lands after its end. */
  private readonly queues = new Map<UUID, Promise<void>>()
  private readonly now: () => number
  private readonly log: (message: string) => void

  constructor(private readonly deps: { apns: Apns; store: Store; now?: () => number; log?: (message: string) => void }) {
    this.now = deps.now ?? Date.now
    this.log = deps.log ?? (() => {})
  }

  gameChanged(game: FoldedGame): Promise<void> {
    const next = (this.queues.get(game.gameId) ?? Promise.resolve()).then(() => this.send(game))
    const tail = next.catch(() => {})
    this.queues.set(game.gameId, tail)
    void tail.then(() => {
      if (this.queues.get(game.gameId) === tail) this.queues.delete(game.gameId)
    })
    return next
  }

  async channel(gameId: UUID): Promise<string | null> {
    const game = await this.deps.store.getGame(gameId)
    if (!game) return null
    if (game.liveActivityChannelId) return game.liveActivityChannelId
    if (!isLive(game.status)) return null
    return this.createChannel(gameId)
  }

  private async send(game: FoldedGame): Promise<void> {
    const { apns, store } = this.deps
    const message = broadcastMessage(game)
    if (!message) return
    const key = JSON.stringify(message)
    if (this.lastSent.get(game.gameId) === key) return

    let channelId = (await store.getGame(game.gameId))?.liveActivityChannelId ?? null
    if (!channelId) {
      if (message.event === 'end') return // no phone ever subscribed
      channelId = await this.createChannel(game.gameId)
    }

    const priority = message.contentState.liveKnockLine ? 10 : 5
    const result = await apns.broadcast(channelId, broadcastPayload(message, this.now()), { priority })
    if (!result.ok) {
      if (result.status === 404 || (result.reason && GONE_CHANNEL.has(result.reason))) {
        // Phones subscribed to it get no more updates; new Live Activities get a new channel.
        await store.clearLiveActivityChannel(game.gameId, channelId)
      }
      throw new Error(`APNs broadcast for ${game.gameId} failed: ${describe(result)}`)
    }
    if (this.lastSent.size > 1000) this.lastSent.clear()
    this.lastSent.set(game.gameId, key)

    if (message.event === 'end') {
      await store.clearLiveActivityChannel(game.gameId, channelId)
      const deleted = await apns.deleteChannel(channelId)
      if (!deleted.ok) this.log(`APNs channel delete for ${game.gameId} failed: ${describe(deleted)}`)
    }
  }

  /** Creates a channel and records it, unless another request (or instance) got there first. */
  private createChannel(gameId: UUID): Promise<string> {
    const pending = this.creating.get(gameId)
    if (pending) return pending
    const created = (async () => {
      const { apns, store } = this.deps
      const channelId = await apns.createChannel()
      const recorded = await store.claimLiveActivityChannel(gameId, channelId)
      if (recorded === channelId) return channelId
      const deleted = await apns.deleteChannel(channelId)
      if (!deleted.ok) this.log(`APNs channel delete (lost the race) for ${gameId} failed: ${describe(deleted)}`)
      if (!recorded) throw new Error(`no game ${gameId} to record a channel for`)
      return recorded
    })().finally(() => this.creating.delete(gameId))
    this.creating.set(gameId, created)
    return created
  }
}
