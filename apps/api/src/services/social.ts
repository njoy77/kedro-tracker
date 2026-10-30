// Claims, blocks, reports, receipts and push tokens.

import { createHash } from 'node:crypto'
import type { ClaimResponse, PushTokenRequest, ReceiptRequest, ReportRequest, UUID } from '@kedro/shared'
import { HttpError, badRequest, forbidden, notFound } from '../http.ts'
import type { Store } from '../store/types.ts'
import type { PlayersService } from './players.ts'
import type { RatingsService } from './ratings.ts'

/** Lowercase hex SHA-256: how claim tokens are stored (only the hash ever leaves the phone in a seat). */
export function claimTokenHash(token: string): string {
  return createHash('sha256').update(token, 'utf8').digest('hex')
}

export class SocialService {
  constructor(
    private readonly store: Store,
    private readonly players: PlayersService,
    private readonly ratings: RatingsService,
  ) {}

  /** Moves a guest's history to the caller (PRD §3.2). One claim per guest, ever. */
  async claim(caller: UUID, token: string): Promise<ClaimResponse> {
    await this.players.requireProfile(caller)
    const result = await this.store.claimGuest(claimTokenHash(token), caller)
    if (!result.ok) {
      if (result.reason === 'alreadyClaimed') throw new HttpError(409, 'alreadyClaimed', 'Someone already claimed this history')
      throw notFound('That claim code does not match a guest')
    }
    // Stats and ratings now count the guest's games for the caller.
    await this.ratings.replay()
    // TODO(push): notify the host who created the guest (design §13.4 #5, N-04) once APNs is configured.
    return { guestId: result.guestId, gamesClaimed: result.gamesClaimed }
  }

  async block(caller: UUID, playerId: UUID): Promise<void> {
    if (playerId === caller) throw badRequest('You cannot block yourself')
    await this.players.requireProfile(caller)
    if (!(await this.store.getPlayer(playerId))) throw notFound('No such player')
    await this.store.addBlock(caller, playerId)
  }

  async unblock(caller: UUID, playerId: UUID): Promise<void> {
    await this.store.removeBlock(caller, playerId)
  }

  async report(caller: UUID, report: ReportRequest): Promise<void> {
    await this.players.requireProfile(caller)
    if (report.gameId && !(await this.store.getGame(report.gameId))) delete report.gameId
    await this.store.addReport(caller, report)
  }

  /** A receipt to a rival you just played (design §8.5). Idempotent: one per rival per game. */
  async receipt(caller: UUID, receipt: ReceiptRequest): Promise<void> {
    if (receipt.toPlayerId === caller) throw badRequest('You cannot send yourself a receipt')
    await this.players.requireProfile(caller)
    if (!(await this.store.getGame(receipt.gameId))) throw notFound('No such game')
    if (!(await this.store.isSeated(receipt.gameId, caller))) throw forbidden('You are not seated in this game')
    if (!(await this.store.isSeated(receipt.gameId, receipt.toPlayerId))) throw badRequest('They were not seated in this game')
    if (!(await this.store.getPlayer(receipt.toPlayerId))) throw notFound('No such player')
    if ((await this.players.hiddenFrom(caller)).has(receipt.toPlayerId)) return // silently dropped across a block
    const added = await this.store.addReceipt({ gameId: receipt.gameId, fromPlayerId: caller, toPlayerId: receipt.toPlayerId, receiptKey: receipt.receiptKey })
    if (added) {
      // TODO(push): notify the recipient (design §13.4 #6, N-08) once APNs is configured.
    }
  }

  async registerPushToken(caller: UUID, request: PushTokenRequest): Promise<void> {
    await this.players.requireProfile(caller)
    if (request.gameId) {
      if (!(await this.store.getGame(request.gameId))) throw notFound('No such game')
      if (!(await this.store.isSeated(request.gameId, caller))) throw forbidden('You are not seated in this game')
    }
    await this.store.upsertPushToken({ playerId: caller, token: request.token.toLowerCase(), kind: request.kind, gameId: request.gameId ?? null })
  }
}
