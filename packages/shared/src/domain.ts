// Domain value types that appear inside operations and API bodies, as zod schemas plus their
// TypeScript types. Mirrors apps/ios/Kedro/Core/Domain (Seat, GameConfig, Round, Avatar, Handle,
// TrashTalk) and apps/ios/ARCHITECTURE.md §4.2. JSON keys are camelCase with "Id".
//
// Unknown keys are tolerated (stripped from the parsed value) so older servers accept newer
// clients; the API stores the operation exactly as received.

import { z } from 'zod'
import { SEAT_ID_PATTERN, UUID_PATTERN } from './ids.ts'
import { HAND_MAX, HAND_MIN } from './scoring.ts'

export const uuidSchema = z.string().regex(UUID_PATTERN, 'Expected a UUID').transform((value) => value.toLowerCase())
export const seatIdSchema = z.string().regex(SEAT_ID_PATTERN, 'Expected a seat ID ("p:<uuid>" or "g:<uuid>")')

export const playerRefSchema = z.object({
  kind: z.enum(['player', 'guest']),
  id: uuidSchema,
})

// MARK: Handle (PRD §3.1)

export const HANDLE_PATTERN = /^[a-z0-9._]{3,20}$/

/** A stored handle: lowercase, 3–20 characters from [a-z0-9._], no "@". */
export const handleSchema = z.string().regex(HANDLE_PATTERN, 'Handles are 3–20 characters: a–z, 0–9, "." and "_"')

/** Normalizes user input like Swift's `Handle(_:)`: trims, drops a leading "@", lowercases. */
export function normalizeHandle(input: string): string | null {
  let value = input.trim().toLowerCase()
  if (value.startsWith('@')) value = value.slice(1)
  return HANDLE_PATTERN.test(value) ? value : null
}

// MARK: Avatar (design §3.5)

export const CURATED_AVATAR_IDS = [
  'horse', 'joker', 'skull', 'crown', 'dice', 'glass', 'ghost', 'crow',
  'bull', 'eye', 'flame', 'spade', 'wolf', 'shark', 'hustler', 'ace',
  'redKing', 'lastCall', 'ashtray', 'hourglass', 'cardsFan', 'horseshoe', 'dagger', 'moon',
] as const

export const EMOJI_COLOR_COUNT = 12

/** https anywhere, or http on this machine (local development of the API). */
export function isServablePhotoURL(url: string): boolean {
  return url.startsWith('https://') || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?\//.test(url)
}

export const avatarSchema = z.discriminatedUnion('kind', [
  // Photos are uploaded (PUT /v1/players/me/photo) and referenced by https URL; a phone's local
  // file:// path is never accepted (other phones couldn't load it, and it leaks the path).
  z.object({ kind: z.literal('photo'), url: z.string().url().max(2048).refine(isServablePhotoURL, 'Photos must be https URLs') }),
  z.object({
    kind: z.literal('emoji'),
    emoji: z.string().min(1).max(32),
    colorIndex: z.number().int().min(0).max(EMOJI_COLOR_COUNT - 1),
  }),
  z.object({ kind: z.literal('curated'), id: z.enum(CURATED_AVATAR_IDS) }),
])
export type Avatar = z.infer<typeof avatarSchema>

// MARK: Seats and config

export const LANGUAGE_LEVELS = ['clean', 'spicy', 'unhinged'] as const
export const languageLevelSchema = z.enum(LANGUAGE_LEVELS)
export type LanguageLevel = z.infer<typeof languageLevelSchema>

/** Lowercase hex SHA-256 of a guest's claim token (never the token itself). */
export const claimTokenHashSchema = z.string().regex(/^[0-9a-f]{64}$/, 'Expected a lowercase hex SHA-256')

export const SEAT_LIMITS = { min: 3, max: 8 } as const
export const PLANNED_ROUNDS_LIMITS = { min: 1, max: 50 } as const

/**
 * A finished game counts for stats, ratings and the leaderboard only with at least this many
 * rounds, and a seat counts in it only if it played at least this many (a late joiner may not).
 */
export const COUNTED_MIN_ROUNDS = 3

/**
 * A seat at a table (`PlayerSeated.seat`). Optional keys are omitted when nil.
 * `claimTokenHash` is a server extension: the phone that created a guest identity may include the
 * SHA-256 of its claim token so `POST /v1/claims` can verify it later. Only the hash travels.
 */
export const seatSchema = z.object({
  player: playerRefSchema,
  displayName: z.string().min(1).max(40),
  order: z.number().int().min(0).max(63),
  handle: handleSchema.optional(),
  avatar: avatarSchema.optional(),
  reporter: seatIdSchema.optional(),
  deviceId: uuidSchema.optional(),
  languageLevel: languageLevelSchema.optional(),
  titleId: z.string().max(16).optional(),
  gamesPlayed: z.number().int().min(0).optional(),
  claimTokenHash: claimTokenHashSchema.optional(),
  /** Set by the fold, never trusted from a phone: the first round a late joiner plays. */
  joinedRound: z.number().int().min(1).max(500).optional(),
  /** Set by the fold, never trusted from a phone: a late joiner's score before their first round. */
  startingScore: z.number().int().optional(),
})
export type Seat = z.infer<typeof seatSchema>

export const SCORING_MODES = ['scorekeeper', 'selfReport'] as const

export const gameConfigSchema = z.object({
  plannedRounds: z.number().int().min(PLANNED_ROUNDS_LIMITS.min).max(PLANNED_ROUNDS_LIMITS.max),
  scoringMode: z.enum(SCORING_MODES),
  tableWord: z.string().min(1).max(40),
  firstDealerSeat: seatIdSchema.optional(),
  houseVoiceCap: languageLevelSchema.optional(),
  scorekeeperSeat: seatIdSchema.optional(),
})
export type GameConfig = z.infer<typeof gameConfigSchema>

// MARK: Rounds

export const handSchema = z.number().int().min(HAND_MIN).max(HAND_MAX)

/** One round's inputs. Scores are derived (`roundScores`), never stored. */
export const roundSchema = z.object({
  number: z.number().int().min(1).max(500),
  hands: z.record(seatIdSchema, handSchema),
  knocker: seatIdSchema,
})
export type Round = z.infer<typeof roundSchema>

export const FINISH_REASONS = ['completed', 'endedEarly', 'autoFinished'] as const
export type FinishReason = (typeof FINISH_REASONS)[number]

// MARK: Trash talk

export const CUSTOM_TAUNT_MAX_LENGTH = 80

export const tauntTargetSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('table') }),
  z.object({ kind: z.literal('seat'), seatId: seatIdSchema }),
])
export type TauntTarget = z.infer<typeof tauntTargetSchema>

export const tauntContentSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('canned'), id: z.string().min(1).max(32) }),
  // Measured in characters as the user sees them; a little slack for emoji and combining marks.
  z.object({ kind: z.literal('custom'), text: z.string().min(1).max(CUSTOM_TAUNT_MAX_LENGTH * 4) }),
])
export type TauntContent = z.infer<typeof tauntContentSchema>

export const REACTIONS = ['fire', 'skull', 'clown', 'laugh', 'salute'] as const
export type Reaction = (typeof REACTIONS)[number]
