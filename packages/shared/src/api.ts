// The HTTP API contract (apps/api). The Swift client (apps/ios Core/Networking) must match these
// shapes exactly. All bodies are JSON; every /v1 route needs `Authorization: Bearer <Supabase JWT>`.
// Dates are ISO 8601 with whole seconds ("2026-10-24T21:00:00Z"), which Swift's `.iso8601`
// strategy decodes. Optional keys are omitted rather than sent as null unless noted.

import { z } from 'zod'
import { avatarSchema, handleSchema, seatIdSchema, uuidSchema, type Avatar } from './domain.ts'
import type { UUID } from './ids.ts'
import type { LeaderboardScope, LeaderboardSort } from './leaderboard.ts'
import type { RecordKind } from './records.ts'
import type { HLC } from './hlc.ts'
import type { OperationType } from './operations.ts'
import type { TauntCheckReason } from './taunts.ts'

// MARK: Errors

export type ApiErrorCode =
  | 'unauthorized'
  | 'forbidden'
  | 'notFound'
  | 'invalidRequest'
  | 'handleTaken'
  | 'profileRequired'
  | 'alreadyClaimed'
  | 'tooManyOps'
  | 'payloadTooLarge'
  | 'unavailable'
  | 'internal'

/** Every non-2xx response. */
export type ApiError = { error: ApiErrorCode; message: string }

export type OkResponse = { ok: true }

// MARK: Operations

/** An operation as it travels (see operations.ts for the typed form). */
export type WireOperation = {
  opId: UUID
  gameId: UUID
  deviceId: UUID
  hlc: HLC
  /** Always present: null for guest-mode phones and system actions. */
  actorPlayerId: UUID | null
  type: OperationType
  payload: unknown
}

export const MAX_OPS_PER_REQUEST = 500

/**
 * POST /v1/ops. `invites` maps a game ID to the table's current rotating invite code (the QR's
 * `k`, see InviteKeyRequest): a phone seating itself at a game the server doesn't seat it in yet
 * must send one that matches the key the table registered.
 */
export type PostOpsRequest = { ops: WireOperation[]; invites?: Record<UUID, string> }

/** How far ahead of the server's clock an op's HLC may be (clock skew); later ops are refused as `clockAhead`. */
export const MAX_CLOCK_AHEAD_MS = 5 * 60 * 1000

export type OpRejectionReason =
  /** Malformed, or a payload that doesn't match its type. Retrying won't help. */
  | 'invalid'
  /** The game is finished; only reactions, receipts, speaker claims and retractions are accepted (and an abandon within 15 minutes). */
  | 'gameFinished'
  /** The game is abandoned: only a GameRestored within 15 minutes of the abandon is accepted. */
  | 'gameAbandoned'
  /**
   * The caller isn't seated in (or hosting) the game. A player joins by uploading their own
   * PlayerSeated (the game ID is the join secret, shared by QR code or nearby discovery); the
   * fold must actually take the seat, so seats lock after Round 1.
   */
  | 'notSeated'
  /** `actorPlayerId` is neither the caller nor a player seated in the game. */
  | 'invalidActor'
  /** The first ops for a game must include its GameCreated. */
  | 'unknownGame'
  /**
   * An App Clip session may only link its phone to a guest seat and act for that seat (report a
   * hand, react, send a canned taunt).
   */
  | 'notAllowed'
  /**
   * Seating would put people who blocked each other at one table (design §5.9 "Rules"), or the
   * seat is for the uploader's blocker.
   */
  | 'blocked'
  /** The op's HLC is more than MAX_CLOCK_AHEAD_MS ahead of the server's clock. Retry once the phone's clock is right. */
  | 'clockAhead'
  /** Seating yourself needs the table's current invite code (`invites`). */
  | 'inviteRequired'

export type RejectedOp = { opId: string | null; reason: OpRejectionReason; message?: string }

/**
 * Idempotent by opId: an op already stored is a duplicate (never an error). `rejected` is an
 * addition to the original contract; clients should treat rejected ops as settled (don't retry).
 */
export type PostOpsResponse = { accepted: UUID[]; duplicates: UUID[]; rejected: RejectedOp[] }

/**
 * GET /v1/games/:gameId/ops?after=<hlcString>[&limit=] (ops strictly after that HLC, in fold order:
 * HLC, deviceId, opId). Pages hold at most `limit` ops (default 2000, max 5000); a full page means
 * there may be more, so ask again with the last op's HLC. Only seated players (and the creator) may read.
 */
export type GetOpsResponse = { ops: WireOperation[] }

// MARK: Players

/** GET/PUT /v1/players/me */
export type Player = {
  id: UUID
  displayName: string
  handle: string
  avatar: Avatar
  titleId?: string
  createdAt?: string
}

export type PlayerSummary = {
  id: UUID
  displayName: string
  handle: string
  avatar: Avatar
  titleId?: string
  /** Finished, non-abandoned games. */
  gamesPlayed?: number
}

export const updateProfileSchema = z.object({
  displayName: z.string().trim().min(1).max(40),
  handle: z.string().transform((value) => value.trim().toLowerCase().replace(/^@/, '')).pipe(handleSchema),
  avatar: avatarSchema,
  /** A `TI-xx` copy ID, or null to show no title. Omit to keep the current one. */
  titleId: z.string().regex(/^TI-\d{2}$/).nullable().optional(),
})
export type UpdateProfileRequest = z.input<typeof updateProfileSchema>

/** GET /v1/players/search?q= */
export type SearchPlayersResponse = { players: PlayerSummary[] }

/**
 * GET /v1/players?cursor=&limit= (an addition: the Add Player list, design §5.6). Every player
 * A–Z by display name, blocked players (either way) and the caller left out. Pass `next` back as
 * `cursor` for the following page; null at the end. A page can come back short of `limit`.
 */
export type PlayerDirectoryResponse = { players: PlayerSummary[]; next: string | null }

/** GET /v1/handles/:handle (an addition: availability check for onboarding). */
export type HandleAvailabilityResponse = { handle: string; available: boolean }

/** GET /v1/players/:playerId (an addition: `PlayerDirectory.player`). 404 when unknown or blocked. */
export type GetPlayerResponse = PlayerSummary

/** GET /v1/players/me/played-with (an addition: `PlayerDirectory.playedWith`), most recent first. */
export type PlayedWithRow = { player: PlayerSummary; gamesTogether: number; lastPlayedAt: string }
export type PlayedWithResponse = { players: PlayedWithRow[] }

/** GET /v1/players/me/guests?name= (an addition: `PlayerDirectory.guestSuggestions`). */
export type GuestSuggestion = { guestId: UUID; name: string; gamesTogether: number }
export type GuestSuggestionsResponse = { guests: GuestSuggestion[] }

/**
 * GET /v1/players/:playerId/profile: the public profile with server-computed stats (one source of
 * truth for every phone, PRD §5.1). `stats`/`rating` are absent before the first finished game;
 * `globalRank` is null until ranked (5 games).
 */
export type PlayerProfileResponse = {
  player: PlayerSummary
  rating: number | null
  globalRank: number | null
  stats?: {
    gamesPlayed: number
    wins: number
    winRate: number
    avgScore: number
    knocks: number
    knocksLanded: number
    knockSuccess: number | null
  }
}

/** GET /v1/players/me/games: every game the caller is seated in (directly or through a claimed guest), newest first. */
export type MyGamesResponse = {
  games: { gameId: UUID; status: string; finishedAt?: string }[]
  /** Guests the caller claimed: the phone counts those seats as the caller's (stats aliases). */
  claimedGuestIds: UUID[]
}

/** PUT /v1/players/me/photo: a JPEG or PNG body (≤ 512 KB). The response's avatar is what to send in profile updates and seats. */
export const MAX_PHOTO_BYTES = 512 * 1024
export type PhotoUploadResponse = { avatar: Avatar }

// MARK: Tables

/**
 * PUT /v1/games/:gameId/invite-key: the table registers the key its rotating invite codes are
 * made with (an HMAC key derived from the table secret on the phones, never the secret itself),
 * so the server can check the codes phones and App Clips present when they seat themselves.
 * Only the game's creator or someone seated may register it, and the first key stays.
 */
export const inviteKeySchema = z.object({ key: z.string().regex(/^[A-Za-z0-9_-]{43}$/, 'Expected 32 bytes, base64url') })
export type InviteKeyRequest = z.infer<typeof inviteKeySchema>

/**
 * POST /v1/link/attestations: a short-lived, server-signed statement that this account owns the
 * device key `publicKey` (Ed25519, raw 32 bytes base64url). Hubs check it offline against the key
 * from GET /link/key before admitting a phone by identity (design §5.3).
 */
export const linkAttestationSchema = z.object({
  deviceId: uuidSchema,
  publicKey: z.string().regex(/^[A-Za-z0-9_-]{43}$/, 'Expected 32 bytes, base64url'),
})
export type LinkAttestationRequest = z.infer<typeof linkAttestationSchema>
/** `attestation` is `<payload>.<signature>`, both base64url; payload JSON `{p, d, k, e}` (player, device, device key, expiry ms). */
export type LinkAttestationResponse = { attestation: string; expiresAt: string }
/** GET /link/key (no auth): the server's Ed25519 attestation key, raw 32 bytes base64url. */
export type LinkKeyResponse = { publicKey: string }

// MARK: Claims

export const claimSchema = z.object({ claimToken: z.string().min(16).max(256) })
/** POST /v1/claims */
export type ClaimRequest = z.infer<typeof claimSchema>
export type ClaimResponse = { guestId: UUID; gamesClaimed: number }

// MARK: App Clip (additions: the clip has no account)

/**
 * POST /v1/clip/sessions (no Authorization): trades the invite link's table token for a
 * game-scoped bearer token, accepted only by GET /v1/games/:gameId/ops, POST /v1/ops and
 * POST /v1/clip/claims for that game.
 */
export const clipSessionSchema = z.object({
  gameId: uuidSchema,
  tableToken: z.string().min(4).max(256),
  deviceId: uuidSchema,
})
export type ClipSessionRequest = z.infer<typeof clipSessionSchema>
export type ClipSessionResponse = { accessToken: string; expiresAt: string }

/** POST /v1/clip/claims: a claim token for the guest seat this clip sat in (redeemed later with POST /v1/claims). */
export const clipClaimSchema = z.object({ gameId: uuidSchema, seatId: seatIdSchema })
export type ClipClaimRequest = z.infer<typeof clipClaimSchema>
export type ClipClaimResponse = { claimToken: string }

/** GET /v1/games/:gameId/live-activity: the game's APNs broadcast channel, once the server made one. */
export type LiveActivityChannelResponse = { channelId: string | null }

// MARK: Moderation

export const tauntCheckSchema = z.object({ text: z.string().max(2000) })
/** POST /v1/taunts/check */
export type TauntCheckRequest = z.infer<typeof tauntCheckSchema>
export type TauntCheckResponse = { allowed: boolean; reason?: TauntCheckReason }

export const REPORT_TARGET_TYPES = ['taunt', 'player', 'photo'] as const
export const reportSchema = z.object({
  targetType: z.enum(REPORT_TARGET_TYPES),
  targetId: z.string().min(1).max(200),
  reason: z.string().trim().min(1).max(500),
  /** Optional context: the game a taunt was sent in. */
  gameId: uuidSchema.optional(),
})
/** POST /v1/reports -> OkResponse */
export type ReportRequest = z.input<typeof reportSchema>

export const blockSchema = z.object({ playerId: uuidSchema })
/** POST /v1/blocks, DELETE /v1/blocks/:playerId -> OkResponse */
export type BlockRequest = z.infer<typeof blockSchema>

// MARK: Receipts and push

export const receiptSchema = z.object({
  gameId: uuidSchema,
  toPlayerId: uuidSchema,
  receiptKey: z.string().regex(/^RC-\d{2}$/),
})
/** POST /v1/receipts -> OkResponse */
export type ReceiptRequest = z.infer<typeof receiptSchema>

export const PUSH_TOKEN_KINDS = ['apns', 'liveactivity'] as const
export const pushTokenSchema = z.object({
  token: z.string().regex(/^[0-9a-fA-F]{32,512}$/, 'Expected a hex device token'),
  kind: z.enum(PUSH_TOKEN_KINDS),
  gameId: uuidSchema.optional(),
})
/** POST /v1/push/tokens -> OkResponse */
export type PushTokenRequest = z.infer<typeof pushTokenSchema>

// MARK: Leaderboard

/** GET /v1/leaderboard?scope=global|playedWith&sort=rating|winRate|wins|avgScore|knockSuccess[&limit=][&around=me] */
export type LeaderboardRow = {
  /** The rank for this sort; null when the player is below the sort's minimum (listed last). */
  rank: number | null
  player: PlayerSummary
  /** The value being sorted on; null when below the sort's minimum. */
  value: number | null
  rating: number
  gamesPlayed: number
  wins: number
  winRate: number
  avgScore: number
  knocks: number
  knocksLanded: number
  knockSuccess: number | null
  isMe: boolean
  /** Below a sort's minimum: what's still needed ("needs 10 games for this one"). */
  needs?: { games?: number; knocks?: number }
}

export type NotYetRankedRow = { player: PlayerSummary; gamesPlayed: number; gamesToRank: number; isMe: boolean }

export type LeaderboardResponse = {
  scope: LeaderboardScope
  sort: LeaderboardSort
  rows: LeaderboardRow[]
  notYetRanked: NotYetRankedRow[]
  /** Everyone still in their first five, in this scope ("1,214 people are still in their first five."). */
  notYetRankedCount: number
  /** The caller's own row wherever it is (pinned row), if they have played. */
  me?: LeaderboardRow | NotYetRankedRow
}

// MARK: Records

/**
 * GET /v1/records?scope=global|playedWith[&limit=]: every record's top holders (default 25 each)
 * over the scope's players, computed from every finished game on the server (design §12.4).
 */
export type RecordRow = {
  /** Competition ranking: ties share a number. */
  rank: number
  player: PlayerSummary
  value: number
  isMe: boolean
  /** Where the record was set (best game only). */
  game?: { gameId: UUID; tableWord: string; finishedAt: string }
}

export type RecordsResponse = {
  scope: LeaderboardScope
  records: { kind: RecordKind; rows: RecordRow[] }[]
}

// MARK: Health

export type HealthResponse = { status: 'ok'; version: string }

/** ISO 8601 with whole seconds and a Z ("2026-10-24T21:00:00Z"), which Swift's `.iso8601` decodes. */
export function isoSeconds(date: Date | number | string): string {
  return new Date(date).toISOString().replace(/\.\d{3}Z$/, 'Z')
}
