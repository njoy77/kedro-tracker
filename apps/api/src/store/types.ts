// The persistence boundary. Route handlers and services only talk to `Store`, so the same logic
// runs on Supabase (production) and in memory (tests, local development without credentials).

import type {
  Avatar,
  FinishedGameProjection,
  GameStatus,
  PlayerStats,
  PushTokenRequest,
  RatingChange,
  Rating,
  ReportRequest,
  UUID,
  WireOperation,
} from '@kedro/shared'

/** An operation row as stored. `operation.payload` is exactly what the client sent. */
export type OpRow = {
  operation: WireOperation
  hlc: string
  receivedBy: UUID | null
}

export type GameRow = {
  id: UUID
  createdBy: UUID | null
  status: GameStatus
  tableWord: string | null
  plannedRounds: number | null
  scoringMode: string | null
  hostSeat: string | null
  roundsPlayed: number
  startedAt: string | null
  finishedAt: string | null
  finishReason: string | null
  abandonedAt: string | null
  lastHlc: string | null
  liveActivityChannelId: string | null
}

export type SeatRow = {
  seatId: string
  playerId: UUID | null
  guestId: UUID | null
  displayName: string
  seatOrder: number
  deviceId: UUID | null
}

export type PlayerRow = {
  id: UUID
  displayName: string
  handle: string
  avatar: Avatar
  titleId: string | null
  createdAt: string
}

export type PlayerUpdate = { displayName: string; handle: string; avatar: Avatar; titleId?: string | null }

export type GuestRegistration = { id: UUID; displayName: string; createdBy: UUID | null; claimTokenHash: string | null }

/** A seat in a finished, non-abandoned game: the input to the rating replay. */
export type FinishedSeatRow = {
  gameId: UUID
  finishedAtMs: number
  seatId: string
  playerId: UUID | null
  guestId: UUID | null
  total: number
}

export type ClaimResult =
  | { ok: true; guestId: UUID; gamesClaimed: number }
  | { ok: false; reason: 'notFound' | 'alreadyClaimed' }

export type PlayedWithRow = { playerId: UUID; gamesTogether: number; lastPlayedMs: number }
export type GuestSuggestionRow = { guestId: UUID; name: string; gamesTogether: number }

export type PushTokenRow = { playerId: UUID; token: string; kind: PushTokenRequest['kind']; gameId: UUID | null }

export class HandleTakenError extends Error {
  constructor() {
    super('That handle is taken')
  }
}

export interface Store {
  // Ops (append-only)
  /** Ops for a game in fold order, optionally only those with an HLC string after `after`. */
  getOps(gameId: UUID, options?: { after?: string; limit?: number }): Promise<WireOperation[]>
  /** Which of these op IDs are already stored. */
  existingOpIds(opIds: readonly UUID[]): Promise<Set<UUID>>
  /** Inserts ops, skipping any op ID already stored. Returns the op IDs actually inserted. */
  insertOps(rows: readonly OpRow[]): Promise<UUID[]>

  // Games
  getGame(gameId: UUID): Promise<GameRow | null>
  /** Creates the game row if it doesn't exist (first uploader becomes its creator). */
  ensureGame(gameId: UUID, createdBy: UUID): Promise<void>
  /** Replaces a game's live projection (row fields and seats). */
  syncGame(game: GameRow, seats: readonly SeatRow[]): Promise<void>
  /** True when the player is seated in the game (directly or as a guest they claimed) or created it. */
  isSeated(gameId: UUID, playerId: UUID): Promise<boolean>

  // Finished games and ratings
  projectFinishedGame(projection: FinishedGameProjection): Promise<void>
  setFinishedGameAbandoned(gameId: UUID, abandoned: boolean): Promise<void>
  finishedSeatRows(): Promise<FinishedSeatRow[]>
  replaceRatings(ratings: readonly Rating[], changes: readonly RatingChange[]): Promise<void>
  /** Ratings by subject ("p:<id>"); all players when `subjects` is omitted. */
  ratings(subjects?: readonly string[]): Promise<Map<string, Rating>>
  /** Lifetime stats per player; all players with a finished game when `playerIds` is omitted. */
  playerStats(playerIds?: readonly UUID[]): Promise<PlayerStats[]>
  playedWith(playerId: UUID): Promise<PlayedWithRow[]>
  guestSuggestions(playerId: UUID, name: string): Promise<GuestSuggestionRow[]>

  // Players
  getPlayer(id: UUID): Promise<PlayerRow | null>
  getPlayers(ids: readonly UUID[]): Promise<PlayerRow[]>
  /** Creates or updates a profile. Throws `HandleTakenError` when another player holds the handle. */
  upsertPlayer(id: UUID, update: PlayerUpdate): Promise<PlayerRow>
  isHandleAvailable(handle: string, exceptPlayerId?: UUID): Promise<boolean>
  /** Display name contains `query`, or handle starts with it. */
  searchPlayers(query: string, options: { limit: number; excludeIds: readonly UUID[]; handleOnly: boolean }): Promise<PlayerRow[]>

  // Guests
  /** Records a guest seen in a game. The first claim token hash recorded wins. */
  registerGuests(guests: readonly GuestRegistration[]): Promise<void>
  claimGuest(claimTokenHash: string, playerId: UUID): Promise<ClaimResult>

  // Safety
  addBlock(blockerId: UUID, blockedId: UUID): Promise<void>
  removeBlock(blockerId: UUID, blockedId: UUID): Promise<void>
  /** Players this player blocked, and players who blocked them. */
  blockRelations(playerId: UUID): Promise<{ blocked: Set<UUID>; blockedBy: Set<UUID> }>
  addReport(reporterId: UUID, report: ReportRequest): Promise<void>
  blocklistTerms(): Promise<string[]>

  // Receipts and push
  /** Returns false when this sender already sent this rival a receipt for the game. */
  addReceipt(receipt: { gameId: UUID; fromPlayerId: UUID; toPlayerId: UUID; receiptKey: string }): Promise<boolean>
  upsertPushToken(token: PushTokenRow): Promise<void>
  pushTokens(filter: { gameId?: UUID; playerIds?: readonly UUID[]; kind: PushTokenRow['kind'] }): Promise<PushTokenRow[]>
}
