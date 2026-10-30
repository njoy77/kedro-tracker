// The App Clip's access (design §5.8). The clip has no account: it trades the invite link's
// table token for a short-lived bearer token scoped to one game and one phone, which the ops
// routes and POST /v1/clip/claims accept for that game only.
//
// The table token is the rotating code from the host's QR (`k`). It is an HMAC under a secret
// that lives only on the table's phones, so the server can't check it; it only requires one,
// the same trust as joining by game ID (anyone holding the ID can sit before Round 1). What a clip
// session may do is narrow instead: link its phone to an existing guest seat and act for that
// seat (OpsService.ingestClip).

import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto'
import { foldGame, isoSeconds, parseOperation, seatIdOf, type Operation, type UUID } from '@kedro/shared'
import { HttpError, forbidden, notFound } from '../http.ts'
import { claimTokenHash } from './social.ts'
import type { Store } from '../store/types.ts'

export type ClipSession = { gameId: UUID; deviceId: UUID }

const PREFIX = 'kclip.'
export const CLIP_SESSION_TTL_MS = 6 * 60 * 60 * 1000

/** Signs and checks clip bearer tokens: `kclip.<payload>.<signature>`, base64url. */
export class ClipTokens {
  private readonly secret: Buffer

  constructor(
    secret: string | undefined,
    private readonly now: () => number = Date.now,
  ) {
    // Without a configured secret, tokens last until the server restarts (fine locally).
    this.secret = secret ? Buffer.from(secret, 'utf8') : randomBytes(32)
  }

  static isClipToken(token: string): boolean {
    return token.startsWith(PREFIX)
  }

  issue(session: ClipSession): { accessToken: string; expiresAtMs: number } {
    const expiresAtMs = this.now() + CLIP_SESSION_TTL_MS
    const payload = Buffer.from(JSON.stringify({ g: session.gameId, d: session.deviceId, e: expiresAtMs })).toString('base64url')
    return { accessToken: `${PREFIX}${payload}.${this.sign(payload)}`, expiresAtMs }
  }

  verify(token: string): ClipSession | null {
    if (!ClipTokens.isClipToken(token)) return null
    const [payload, signature] = token.slice(PREFIX.length).split('.')
    if (!payload || !signature) return null
    const expected = Buffer.from(this.sign(payload))
    const given = Buffer.from(signature)
    if (expected.length !== given.length || !timingSafeEqual(expected, given)) return null
    try {
      const body = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as { g?: unknown; d?: unknown; e?: unknown }
      if (typeof body.g !== 'string' || typeof body.d !== 'string' || typeof body.e !== 'number') return null
      if (body.e <= this.now()) return null
      return { gameId: body.g, deviceId: body.d }
    } catch {
      return null
    }
  }

  private sign(payload: string): string {
    return createHmac('sha256', this.secret).update(payload).digest('base64url')
  }
}

export class ClipService {
  constructor(
    private readonly store: Store,
    private readonly tokens: ClipTokens,
  ) {}

  /** POST /v1/clip/sessions */
  async startSession(request: { gameId: UUID; tableToken: string; deviceId: UUID }): Promise<{ accessToken: string; expiresAt: string }> {
    const game = await this.store.getGame(request.gameId)
    if (!game) throw notFound('No such table yet. Ask the host to check their connection.')
    if (game.status === 'abandoned') throw notFound('That table was abandoned')
    const { accessToken, expiresAtMs } = this.tokens.issue({ gameId: request.gameId, deviceId: request.deviceId })
    return { accessToken, expiresAt: isoSeconds(expiresAtMs) }
  }

  /**
   * POST /v1/clip/claims: a claim token for the guest seat this clip's phone sits in. The server
   * keeps only its hash, and the first hash recorded for a guest wins, so asking again after the
   * clip lost its token is refused (409).
   */
  async claim(clip: ClipSession, request: { gameId: UUID; seatId: string }): Promise<{ claimToken: string }> {
    if (request.gameId !== clip.gameId) throw forbidden('This session is for another table')
    const operations = (await this.store.getOps(clip.gameId)).flatMap((wire) => {
      const parsed = parseOperation(wire)
      return parsed.ok ? [parsed.value.operation as Operation] : []
    })
    const seat = foldGame(operations, clip.gameId).seats.find((candidate) => seatIdOf(candidate.player) === request.seatId)
    if (!seat || seat.player.kind !== 'guest') throw notFound('No such guest seat')
    if (seat.deviceId !== clip.deviceId) throw forbidden('Sit in that seat first')
    const guestId = seat.player.id
    const claimToken = randomBytes(24).toString('base64url')
    const hash = claimTokenHash(claimToken)
    await this.store.registerGuests([{ id: guestId, displayName: seat.displayName, createdBy: null, claimTokenHash: hash }])
    if ((await this.store.guestClaimTokenHash(guestId)) !== hash) {
      throw new HttpError(409, 'alreadyClaimed', 'This seat already has a claim code')
    }
    return { claimToken }
  }
}
