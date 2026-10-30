// Live Activity updates over APNs broadcast channels (design §13.2): one channel per game, and
// every seated phone's Live Activity subscribes to it, so the server sends one push per change
// instead of one per phone.
//
// TODO(apns): not wired up. Needs an APNs auth key (.p8), key ID, team ID and the app's bundle
// ID, plus the channel management API:
//   1. On a game's first state-changing op, create a channel
//      (POST https://api-manage-broadcast.push.apple.com:2196/1/apps/<bundleId>/channels,
//      "push-type": "LiveActivity", message-storage-policy 0) and store its ID in
//      games.live_activity_channel_id (the phones read it from the game to subscribe).
//   2. On every change, POST https://api.push.apple.com/4/broadcasts/apps/<bundleId> with
//      apns-channel-id, apns-push-type: liveactivity, apns-priority: 5 (10 for a live knock) and
//      {"aps":{"timestamp":…,"event":"update","content-state":<LiveActivityContentState>,"stale-date":+180s}}.
//   3. On finish or abandon, send "event":"end" with a dismissal-date, then delete the channel.
// The keys belong in Vercel (APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_BUNDLE_ID) and in
// scripts/env.ts TARGETS for apps/api once they exist.

import { isLive, liveActivityContentState, type FoldedGame, type LiveActivityContentState } from '@kedro/shared'

export type LiveActivityEvent = 'update' | 'end'

export interface LiveActivityBroadcaster {
  /** Called after a game's projection changes (best effort; never throws into the request). */
  gameChanged(game: FoldedGame): Promise<void>
}

export type BroadcastMessage = { gameId: string; event: LiveActivityEvent; contentState: LiveActivityContentState }

/** Builds the message for a game; null when there is nothing to show (lobby). */
export function broadcastMessage(game: FoldedGame): BroadcastMessage | null {
  if (game.status === 'lobby' && game.rounds.length === 0) return null
  return {
    gameId: game.gameId,
    event: isLive(game.status) ? 'update' : 'end',
    contentState: liveActivityContentState(game),
  }
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
    // TODO(apns): send `message` to the game's broadcast channel (see the header).
    this.log(`live activity ${message.event} for ${game.gameId} (not sent: APNs is not configured)`)
  }
}
