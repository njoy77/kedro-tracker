// An in-memory Store with the same semantics as the Supabase schema. Used by tests and by
// `bun run dev` when no Supabase credentials are configured.

import {
  aggregateStats,
  compareStrings,
  hlcString,
  type FinishedGameProjection,
  type FinishedSeatResult,
  type PlayerStats,
  type Rating,
  type RatingChange,
  type ReportRequest,
  type UUID,
  type WireOperation,
} from '@kedro/shared'
import {
  HandleTakenError,
  type ClaimResult,
  type FinishedSeatRow,
  type GameRow,
  type GuestRegistration,
  type GuestSuggestionRow,
  type OpRow,
  type PlayedWithRow,
  type PlayerRow,
  type PlayerUpdate,
  type PushTokenRow,
  type SeatRow,
  type Store,
} from './types.ts'
import { guestSuggestionsFrom, orderStatsRows, playedWithFrom, type FinishedSeatDetail } from './shared.ts'

type StoredOp = OpRow & { receivedAt: number }
type GuestRow = GuestRegistration & { claimedBy: UUID | null; claimedAt: number | null }
type FinishedGameRow = { projection: FinishedGameProjection; isAbandoned: boolean; seats: FinishedSeatResult[] }

export class MemoryStore implements Store {
  readonly ops = new Map<UUID, StoredOp>()
  readonly games = new Map<UUID, GameRow>()
  readonly seats = new Map<UUID, SeatRow[]>()
  readonly players = new Map<UUID, PlayerRow>()
  readonly guests = new Map<UUID, GuestRow>()
  readonly finished = new Map<UUID, FinishedGameRow>()
  ratingRows = new Map<string, Rating>()
  ratingChanges: RatingChange[] = []
  readonly blocks = new Set<string>()
  readonly reports: (ReportRequest & { reporterId: UUID })[] = []
  readonly receipts = new Map<string, { gameId: UUID; fromPlayerId: UUID; toPlayerId: UUID; receiptKey: string }>()
  readonly tokens = new Map<string, PushTokenRow>()
  blocklist: string[] = []

  // MARK: Ops

  async getOps(gameId: UUID, options: { after?: string; limit?: number } = {}): Promise<WireOperation[]> {
    const rows = [...this.ops.values()]
      .filter((row) => row.operation.gameId === gameId && (options.after === undefined || row.hlc > options.after))
      .sort((a, b) =>
        compareStrings(a.hlc, b.hlc) ||
        compareStrings(a.operation.deviceId, b.operation.deviceId) ||
        compareStrings(a.operation.opId, b.operation.opId),
      )
    return rows.slice(0, options.limit ?? rows.length).map((row) => structuredClone(row.operation))
  }

  async existingOpIds(opIds: readonly UUID[]): Promise<Set<UUID>> {
    return new Set(opIds.filter((id) => this.ops.has(id)))
  }

  async insertOps(rows: readonly OpRow[]): Promise<UUID[]> {
    const inserted: UUID[] = []
    for (const row of rows) {
      const id = row.operation.opId
      if (this.ops.has(id)) continue
      if (!this.games.has(row.operation.gameId)) throw new Error(`Foreign key: game ${row.operation.gameId} does not exist`)
      this.ops.set(id, { ...structuredClone(row), hlc: hlcString(row.operation.hlc), receivedAt: Date.now() })
      inserted.push(id)
    }
    return inserted
  }

  // MARK: Games

  async getGame(gameId: UUID): Promise<GameRow | null> {
    return structuredClone(this.games.get(gameId) ?? null)
  }

  async ensureGame(gameId: UUID, createdBy: UUID): Promise<void> {
    if (this.games.has(gameId)) return
    this.games.set(gameId, {
      id: gameId, createdBy, status: 'lobby', tableWord: null, plannedRounds: null, scoringMode: null, hostSeat: null,
      roundsPlayed: 0, startedAt: null, finishedAt: null, finishReason: null, abandonedAt: null, lastHlc: null,
      liveActivityChannelId: null,
    })
  }

  async syncGame(game: GameRow, seats: readonly SeatRow[]): Promise<void> {
    const existing = this.games.get(game.id)
    if (!existing) return
    this.games.set(game.id, { ...game, createdBy: existing.createdBy, liveActivityChannelId: existing.liveActivityChannelId })
    this.seats.set(game.id, structuredClone([...seats]))
  }

  async isSeated(gameId: UUID, playerId: UUID): Promise<boolean> {
    if (this.games.get(gameId)?.createdBy === playerId) return true
    return (this.seats.get(gameId) ?? []).some(
      (seat) => seat.playerId === playerId || (seat.guestId !== null && this.guests.get(seat.guestId)?.claimedBy === playerId),
    )
  }

  // MARK: Finished games and ratings

  async projectFinishedGame(projection: FinishedGameProjection): Promise<void> {
    const seats = projection.seats.map((seat) => ({
      ...seat,
      playerId: seat.playerId ?? (seat.guestId ? this.guests.get(seat.guestId)?.claimedBy ?? null : null),
    }))
    this.finished.set(projection.gameId, { projection: structuredClone(projection), isAbandoned: false, seats })
  }

  async setFinishedGameAbandoned(gameId: UUID, abandoned: boolean): Promise<void> {
    const row = this.finished.get(gameId)
    if (row) row.isAbandoned = abandoned
  }

  async finishedSeatRows(): Promise<FinishedSeatRow[]> {
    return this.liveFinished().flatMap(({ projection, seats }) =>
      seats.map((seat) => ({
        gameId: projection.gameId,
        finishedAtMs: projection.finishedAtMs,
        seatId: seat.seatId,
        playerId: seat.playerId,
        guestId: seat.guestId,
        seatOrder: seat.seatOrder,
        total: seat.total,
      })),
    )
  }

  async replaceRatings(ratings: readonly Rating[], changes: readonly RatingChange[]): Promise<void> {
    this.ratingRows = new Map(ratings.map((rating) => [rating.subject, { ...rating }]))
    this.ratingChanges = [...changes]
  }

  async ratings(subjects?: readonly string[]): Promise<Map<string, Rating>> {
    if (!subjects) return new Map([...this.ratingRows].filter(([subject]) => subject.startsWith('p:')))
    return new Map(subjects.flatMap((subject) => {
      const rating = this.ratingRows.get(subject)
      return rating ? [[subject, rating] as const] : []
    }))
  }

  async playerStats(playerIds?: readonly UUID[]): Promise<PlayerStats[]> {
    const wanted = playerIds ? new Set(playerIds.map((id) => `p:${id}`)) : null
    const rows = orderStatsRows(this.finishedSeatDetails().filter((seat) => seat.playerId !== null))
    return [...aggregateStats(rows).values()].filter((entry) => !wanted || wanted.has(entry.subject))
  }

  async playedWith(playerId: UUID): Promise<PlayedWithRow[]> {
    return playedWithFrom(this.finishedSeatDetails(), playerId)
  }

  async guestSuggestions(playerId: UUID, name: string): Promise<GuestSuggestionRow[]> {
    return guestSuggestionsFrom(this.finishedSeatDetails(), playerId, name)
  }

  private finishedSeatDetails(): FinishedSeatDetail[] {
    return this.liveFinished().flatMap(({ projection, seats }) =>
      seats.map((seat) => ({
        gameId: projection.gameId,
        finishedAtMs: projection.finishedAtMs,
        seatId: seat.seatId,
        playerId: seat.playerId,
        guestId: seat.guestId,
        displayName: seat.displayName,
        seatOrder: seat.seatOrder,
        total: seat.total,
        isWinner: seat.isWinner,
        roundsPlayed: seat.roundsPlayed,
        knocks: seat.knocks,
        knocksLanded: seat.knocksLanded,
        knocksTied: seat.knocksTied,
        knocksFailed: seat.knocksFailed,
      })),
    )
  }

  private liveFinished(): FinishedGameRow[] {
    return [...this.finished.values()].filter((row) => !row.isAbandoned)
  }

  // MARK: Players

  async getPlayer(id: UUID): Promise<PlayerRow | null> {
    return structuredClone(this.players.get(id) ?? null)
  }

  async getPlayers(ids: readonly UUID[]): Promise<PlayerRow[]> {
    return ids.flatMap((id) => {
      const player = this.players.get(id)
      return player ? [structuredClone(player)] : []
    })
  }

  async upsertPlayer(id: UUID, update: PlayerUpdate): Promise<PlayerRow> {
    if (!(await this.isHandleAvailable(update.handle, id))) throw new HandleTakenError()
    const existing = this.players.get(id)
    const row: PlayerRow = {
      id,
      displayName: update.displayName,
      handle: update.handle,
      avatar: update.avatar,
      titleId: update.titleId === undefined ? existing?.titleId ?? null : update.titleId,
      createdAt: existing?.createdAt ?? new Date().toISOString(),
    }
    this.players.set(id, row)
    return structuredClone(row)
  }

  async isHandleAvailable(handle: string, exceptPlayerId?: UUID): Promise<boolean> {
    return ![...this.players.values()].some((player) => player.handle === handle && player.id !== exceptPlayerId)
  }

  async searchPlayers(query: string, options: { limit: number; excludeIds: readonly UUID[]; handleOnly: boolean }): Promise<PlayerRow[]> {
    const q = query.toLowerCase()
    const excluded = new Set(options.excludeIds)
    return [...this.players.values()]
      .filter((player) => !excluded.has(player.id))
      .filter((player) => player.handle.startsWith(q) || (!options.handleOnly && player.displayName.toLowerCase().includes(q)))
      .sort((a, b) => Number(b.handle === q) - Number(a.handle === q) || compareStrings(a.displayName.toLowerCase(), b.displayName.toLowerCase()))
      .slice(0, options.limit)
      .map((player) => structuredClone(player))
  }

  // MARK: Guests

  async registerGuests(guests: readonly GuestRegistration[]): Promise<void> {
    for (const guest of guests) {
      const existing = this.guests.get(guest.id)
      if (!existing) {
        const hashTaken = guest.claimTokenHash !== null && [...this.guests.values()].some((row) => row.claimTokenHash === guest.claimTokenHash)
        this.guests.set(guest.id, { ...guest, claimTokenHash: hashTaken ? null : guest.claimTokenHash, claimedBy: null, claimedAt: null })
      } else if (existing.claimTokenHash === null && guest.claimTokenHash !== null) {
        existing.claimTokenHash = guest.claimTokenHash
      }
    }
  }

  async guestClaimTokenHash(guestId: UUID): Promise<string | null | undefined> {
    const guest = this.guests.get(guestId)
    return guest ? guest.claimTokenHash : undefined
  }

  async claimGuest(claimTokenHash: string, playerId: UUID): Promise<ClaimResult> {
    const guest = [...this.guests.values()].find((row) => row.claimTokenHash === claimTokenHash)
    if (!guest) return { ok: false, reason: 'notFound' }
    if (guest.claimedBy) return { ok: false, reason: 'alreadyClaimed' }
    guest.claimedBy = playerId
    guest.claimedAt = Date.now()
    let gamesClaimed = 0
    for (const row of this.finished.values()) {
      let found = false
      for (const seat of row.seats) {
        if (seat.guestId !== guest.id) continue
        seat.playerId = playerId
        found = true
      }
      if (found && !row.isAbandoned) gamesClaimed += 1
    }
    return { ok: true, guestId: guest.id, gamesClaimed }
  }

  // MARK: Safety

  async addBlock(blockerId: UUID, blockedId: UUID): Promise<void> {
    this.blocks.add(`${blockerId}|${blockedId}`)
  }

  async removeBlock(blockerId: UUID, blockedId: UUID): Promise<void> {
    this.blocks.delete(`${blockerId}|${blockedId}`)
  }

  async blockRelations(playerId: UUID): Promise<{ blocked: Set<UUID>; blockedBy: Set<UUID> }> {
    const blocked = new Set<UUID>()
    const blockedBy = new Set<UUID>()
    for (const key of this.blocks) {
      const [blocker, target] = key.split('|')
      if (blocker === playerId) blocked.add(target)
      if (target === playerId) blockedBy.add(blocker)
    }
    return { blocked, blockedBy }
  }

  async addReport(reporterId: UUID, report: ReportRequest): Promise<void> {
    this.reports.push({ ...report, reporterId })
  }

  async blocklistTerms(): Promise<string[]> {
    return [...this.blocklist]
  }

  // MARK: Receipts and push

  async addReceipt(receipt: { gameId: UUID; fromPlayerId: UUID; toPlayerId: UUID; receiptKey: string }): Promise<boolean> {
    const key = `${receipt.gameId}|${receipt.fromPlayerId}|${receipt.toPlayerId}`
    if (this.receipts.has(key)) return false
    this.receipts.set(key, receipt)
    return true
  }

  async upsertPushToken(token: PushTokenRow): Promise<void> {
    this.tokens.set(`${token.playerId}|${token.kind}|${token.token}|${token.gameId ?? ''}`, { ...token })
  }

  async pushTokens(filter: { gameId?: UUID; playerIds?: readonly UUID[]; kind: PushTokenRow['kind'] }): Promise<PushTokenRow[]> {
    const players = filter.playerIds ? new Set(filter.playerIds) : null
    return [...this.tokens.values()].filter(
      (token) =>
        token.kind === filter.kind &&
        (filter.gameId === undefined || token.gameId === filter.gameId) &&
        (!players || players.has(token.playerId)),
    )
  }
}
