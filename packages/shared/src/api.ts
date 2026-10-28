// The HTTP API contract (apps/api). The Swift client (apps/ios Core/Networking) must match these
// shapes exactly. All bodies are JSON; every /v1 route needs `Authorization: Bearer <Supabase JWT>`.
// Dates are ISO 8601 with whole seconds ("2026-10-24T21:00:00Z"), which Swift's `.iso8601`
// strategy decodes. Optional keys are omitted rather than sent as null unless noted.

import { z } from 'zod'
import { avatarSchema, handleSchema, uuidSchema, type Avatar } from './domain.ts'
import type { UUID } from './ids.ts'
import type { LeaderboardScope, LeaderboardSort } from './leaderboard.ts'
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

/** POST /v1/ops */
export type PostOpsRequest = { ops: WireOperation[] }

export type OpRejectionReason =
  /** Malformed, or a payload that doesn't match its type. Retrying won't help. */
  | 'invalid'
  /** The game is finished; only reactions, receipts, speaker claims and retractions are accepted (and an abandon within 15 minutes). */
  | 'gameFinished'
  /** The game was abandoned and the 15-minute restore window has passed. */
  | 'gameAbandoned'
  /** The caller isn't seated in (or hosting) the game. */
  | 'notSeated'
  /** `actorPlayerId` is neither the caller nor a player seated in the game. */
  | 'invalidActor'
  /** The first ops for a game must include its GameCreated. */
  | 'unknownGame'

export type RejectedOp = { opId: string | null; reason: OpRejectionReason; message?: string }

/**
 * Idempotent by opId: an op already stored is a duplicate (never an error). `rejected` is an
 * addition to the original contract; clients should treat rejected ops as settled (don't retry).
 */
export type PostOpsResponse = { accepted: UUID[]; duplicates: UUID[]; rejected: RejectedOp[] }

/** GET /v1/games/:gameId/ops?after=<hlcString> (ops strictly after that HLC, in HLC order). */
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

/** GET /v1/handles/:handle (an addition: availability check for onboarding). */
export type HandleAvailabilityResponse = { handle: string; available: boolean }

// MARK: Claims

export const claimSchema = z.object({ claimToken: z.string().min(16).max(256) })
/** POST /v1/claims */
export type ClaimRequest = z.infer<typeof claimSchema>
export type ClaimResponse = { guestId: UUID; gamesClaimed: number }

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

// MARK: Health

export type HealthResponse = { status: 'ok'; version: string }
