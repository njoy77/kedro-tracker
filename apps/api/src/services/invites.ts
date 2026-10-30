// Server-checkable table invites (design §5.8). The table secret never leaves the phones; what
// the host registers with PUT /v1/games/:gameId/invite-key is an HMAC key derived from it, the
// same key the phones make the QR's rotating code (`k`) with (iOS `TableKey.inviteKey`). The
// server can then check a code an App Clip or a self-seating phone presents, without being able
// to forge the phones' membership proofs.

import { createHmac, timingSafeEqual } from 'node:crypto'
import type { UUID } from '@kedro/shared'

/** Codes rotate every minute. */
export const INVITE_WINDOW_MS = 60_000

/** Windows accepted around the server's: the next one (a phone clock slightly ahead) and the two before it. */
const ACCEPTED_WINDOW_OFFSETS = [1, 0, -1, -2]

/** The code for one window: the first 12 bytes of HMAC-SHA256(key, "kedro.invite|<GAME ID UPPERCASE>|<window>"), base64url. */
export function inviteCode(key: Buffer, gameId: UUID, window: number): string {
  const message = `kedro.invite|${gameId.toUpperCase()}|${window}`
  return createHmac('sha256', key).update(message, 'utf8').digest().subarray(0, 12).toString('base64url')
}

/** The registered key, from its base64url form. */
export function decodeInviteKey(encoded: string): Buffer | null {
  const key = Buffer.from(encoded, 'base64url')
  return key.length === 32 ? key : null
}

export function isValidInviteCode(code: string, encodedKey: string, gameId: UUID, nowMs: number): boolean {
  const key = decodeInviteKey(encodedKey)
  if (!key || code.length === 0 || code.length > 64) return false
  const window = Math.floor(nowMs / INVITE_WINDOW_MS)
  const given = Buffer.from(code, 'utf8')
  return ACCEPTED_WINDOW_OFFSETS.some((offset) => {
    const expected = Buffer.from(inviteCode(key, gameId, window + offset), 'utf8')
    return expected.length === given.length && timingSafeEqual(expected, given)
  })
}
