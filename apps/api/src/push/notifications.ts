// Alert pushes to people (design §5.5, §13.1). Device tokens arrive with POST /v1/push/tokens;
// each alert goes to every token of the player (POST /3/device/<token>, apns-push-type: alert).
// Without APNs keys (config.ts) the stub records the payloads and sends nothing.

import type { UUID } from '@kedro/shared'
import type { Store } from '../store/types.ts'
import { describe, type Apns } from './apns.ts'

/**
 * The APNs payload for an alert. `kedro` is what the app reads to open the right table
 * (iOS `TableInvite(userInfo:)`): `{"kind":"seat","gameId":"…","host":"Maya","word":"Cold Deck"}`.
 */
export type AlertPayload = {
  aps: { alert: { body: string }; sound?: string }
  kedro: { kind: 'seat'; gameId: UUID; host: string; word: string }
}

export type SavedSeat = { playerId: UUID; gameId: UUID; hostName: string; tableWord: string }

export interface Notifier {
  /** N-01: the host saved this player a seat (added them from Played With or Search). */
  savedSeat(seat: SavedSeat): Promise<void>
}

/** N-01 is the same line in every language level. */
export function savedSeatPayload({ gameId, hostName, tableWord }: SavedSeat): AlertPayload {
  return {
    aps: { alert: { body: `${hostName} saved you a seat at ${tableWord}.` } },
    kedro: { kind: 'seat', gameId, host: hostName, word: tableWord },
  }
}

/** Builds each payload and the tokens it would go to, but sends nothing until APNs exists. */
export class StubNotifier implements Notifier {
  readonly sent: { playerId: UUID; tokens: string[]; payload: AlertPayload }[] = []

  constructor(
    private readonly store: Store,
    private readonly log: (message: string) => void = () => {},
  ) {}

  async savedSeat(seat: SavedSeat): Promise<void> {
    const tokens = (await this.store.pushTokens({ playerIds: [seat.playerId], kind: 'apns' })).map((row) => row.token)
    const payload = savedSeatPayload(seat)
    if (this.sent.length > 1000) this.sent.splice(0, this.sent.length)
    this.sent.push({ playerId: seat.playerId, tokens, payload })
    this.log(`N-01 for ${seat.playerId} at ${seat.gameId} (${tokens.length} tokens; not sent: APNs is not configured)`)
  }
}

/** N-01 stops mattering once the table has dealt; an hour is plenty for a lobby. */
const SAVED_SEAT_EXPIRY_SECONDS = 60 * 60

/** Sends alerts over APNs. The sends run after the response (`defer`, Vercel's `waitUntil`). */
export class ApnsNotifier implements Notifier {
  private readonly now: () => number
  private readonly log: (message: string) => void

  constructor(
    private readonly deps: {
      apns: Apns
      store: Store
      defer?: (work: Promise<unknown>) => void
      now?: () => number
      log?: (message: string) => void
    },
  ) {
    this.now = deps.now ?? Date.now
    this.log = deps.log ?? (() => {})
  }

  async savedSeat(seat: SavedSeat): Promise<void> {
    const tokens = (await this.deps.store.pushTokens({ playerIds: [seat.playerId], kind: 'apns' })).map((row) => row.token)
    if (tokens.length === 0) return
    const payload = savedSeatPayload(seat)
    const expiration = Math.floor(this.now() / 1000) + SAVED_SEAT_EXPIRY_SECONDS
    // One N-01 per table on the phone, however often the host re-adds the seat.
    const options = { pushType: 'alert', priority: 10, expiration, collapseId: `seat:${seat.gameId}` } as const
    const work = Promise.all(tokens.map((token) => this.send(token, payload, options, `N-01 for ${seat.playerId}`)))
    this.deps.defer?.(work)
  }

  /** Never throws: a failed push is logged, and a token APNs no longer knows is forgotten. */
  private async send(token: string, payload: AlertPayload, options: Parameters<Apns['sendToDevice']>[2], label: string): Promise<void> {
    try {
      const result = await this.deps.apns.sendToDevice(token, payload, options)
      if (result.ok) return
      // 410: the app was uninstalled or the token rotated. (BadDeviceToken is often a Debug
      // build's sandbox token sent to production, so those are kept.)
      if (result.status === 410) await this.deps.store.removePushToken(token, 'apns')
      this.log(`${label} to ${token.slice(0, 8)}… failed: ${describe(result)}`)
    } catch (error) {
      this.log(`${label} to ${token.slice(0, 8)}… failed: ${String(error)}`)
    }
  }
}
