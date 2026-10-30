// Alert pushes to people (design §5.5, §13.1). Device tokens arrive with POST /v1/push/tokens.
//
// TODO(apns): not wired up, like the Live Activity broadcasts (push/liveActivity.ts): needs the
// APNs auth key in Vercel (APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_BUNDLE_ID) and a
// sender for POST https://api.push.apple.com/3/device/<token> with apns-push-type: alert.

import type { UUID } from '@kedro/shared'
import type { Store } from '../store/types.ts'

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
    // TODO(apns): send `payload` to each token.
    this.log(`N-01 for ${seat.playerId} at ${seat.gameId} (${tokens.length} tokens; not sent: APNs is not configured)`)
  }
}
