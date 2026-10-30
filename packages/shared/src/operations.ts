// The operation log: the wire contract shared by the iOS app (`GameOperation`) and the API.
// See apps/ios/ARCHITECTURE.md §4.2 and apps/ios/Kedro/Core/Domain/GameOperation.swift.
//
// {"opId":"<uuid>","gameId":"<uuid>","deviceId":"<uuid>",
//  "hlc":{"wallMs":1761700000000,"counter":0,"node":"<deviceId>"},
//  "actorPlayerId":"<uuid>|null","type":"RoundRecorded","payload":{…}}

import { z } from 'zod'
import {
  FINISH_REASONS,
  REACTIONS,
  gameConfigSchema,
  roundSchema,
  seatIdSchema,
  seatSchema,
  tauntContentSchema,
  tauntTargetSchema,
  uuidSchema,
} from './domain.ts'
import { compareHlc, compareStrings, type HLC } from './hlc.ts'
import type { UUID } from './ids.ts'

const roundNumber = z.number().int().min(1).max(500)

/** Payload schemas by operation type: all 23 of Swift's `OperationType.allCases`. */
export const payloadSchemas = {
  GameCreated: z.object({ config: gameConfigSchema, host: seatIdSchema }),
  GameStarted: z.object({ seatOrder: z.array(seatIdSchema).max(16), firstDealer: seatIdSchema }),
  /** Lobby only: replaces the table word, scoring mode and house voice cap (no cap clears it). */
  GameConfigured: z.object({
    tableWord: gameConfigSchema.shape.tableWord,
    scoringMode: gameConfigSchema.shape.scoringMode,
    houseVoiceCap: gameConfigSchema.shape.houseVoiceCap,
  }),
  PlayerSeated: z.object({ seat: seatSchema }),
  SeatRemoved: z.object({ seatId: seatIdSchema }),
  ScorekeeperChanged: z.object({ seatId: seatIdSchema }),
  RoundRecorded: z.object({ round: roundSchema }),
  RoundEdited: z.object({ round: roundSchema }),
  RoundUndone: z.object({ roundNumber }),
  KnockMarked: z.object({ roundNumber, knocker: seatIdSchema.nullable().optional() }),
  KnockerProposed: z.object({ roundNumber, knocker: seatIdSchema }),
  KnockerResolved: z.object({ roundNumber, knocker: seatIdSchema }),
  HandReported: z.object({
    roundNumber,
    seatId: seatIdSchema,
    hand: z.number().int(),
    knocked: z.boolean(),
  }),
  RoundsChanged: z.object({ plannedRounds: z.number().int() }),
  DealerChanged: z.object({ roundNumber, dealer: seatIdSchema }),
  TauntSent: z.object({
    tauntId: uuidSchema,
    roundNumber: z.number().int().min(0).max(500),
    from: seatIdSchema.nullable().optional(),
    fromName: z.string().min(1).max(40),
    target: tauntTargetSchema,
    content: tauntContentSchema,
  }),
  TauntRetracted: z.object({ tauntId: uuidSchema, reason: z.string().max(64).optional() }),
  ReactionAdded: z.object({ roundNumber, seatId: seatIdSchema, reaction: z.enum(REACTIONS) }),
  ReceiptSent: z.object({ fromSeat: seatIdSchema, toSeat: seatIdSchema, receiptKey: z.string().min(1).max(32) }),
  TableSpeakerClaimed: z.object({ deviceId: uuidSchema }),
  GameFinished: z.object({ reason: z.enum(FINISH_REASONS), finalRounds: z.array(roundSchema).max(500).default([]) }),
  GameAbandoned: z.object({}),
  GameRestored: z.object({}),
} as const

export type OperationType = keyof typeof payloadSchemas
export type PayloadByType = { [T in OperationType]: z.infer<(typeof payloadSchemas)[T]> }

export const OPERATION_TYPES = Object.keys(payloadSchemas) as OperationType[]

/**
 * Operations that change scores, seats or the game's shape. Refused after a game is finished or
 * abandoned. The rest (taunts, retractions, reactions, receipts, speaker claims) are not.
 */
export function isStateChanging(type: OperationType): boolean {
  return !NON_STATE_CHANGING.has(type)
}

const NON_STATE_CHANGING = new Set<OperationType>([
  'TauntSent', 'TauntRetracted', 'ReactionAdded', 'ReceiptSent', 'TableSpeakerClaimed',
])

/** Accepted after `GameFinished` (the fold applies these to a finished game). */
export const ALLOWED_AFTER_FINISH = new Set<OperationType>([
  'ReceiptSent', 'ReactionAdded', 'TableSpeakerClaimed', 'TauntRetracted',
])

/** An operation with a typed payload. */
export type Operation<T extends OperationType = OperationType> = {
  [K in T]: {
    opId: UUID
    gameId: UUID
    deviceId: UUID
    hlc: HLC
    /** The signed-in player who did it; null for guest-mode phones and system actions. */
    actorPlayerId: UUID | null
    type: K
    payload: PayloadByType[K]
  }
}[T]

export const hlcSchema = z.object({
  wallMs: z.number().int().min(0).max(999_999_999_999_999),
  counter: z.number().int().min(0).max(99_999),
  node: z.string().min(1).max(64),
})

const envelopeSchema = z.object({
  opId: uuidSchema,
  gameId: uuidSchema,
  deviceId: uuidSchema,
  hlc: hlcSchema,
  actorPlayerId: uuidSchema.nullable().optional(),
  type: z.enum(OPERATION_TYPES as [OperationType, ...OperationType[]]),
  payload: z.unknown(),
})

export type ParsedOperation = {
  /** The validated, typed operation (IDs lowercased, unknown keys stripped). */
  operation: Operation
  /** The payload exactly as received, which is what gets stored and served. */
  rawPayload: unknown
}

export type OperationParseResult =
  | { ok: true; value: ParsedOperation }
  | { ok: false; opId: string | null; error: string }

/** Validates one wire operation. */
export function parseOperation(input: unknown): OperationParseResult {
  const envelope = envelopeSchema.safeParse(input)
  const opId = typeof (input as { opId?: unknown })?.opId === 'string' ? (input as { opId: string }).opId.toLowerCase() : null
  if (!envelope.success) return { ok: false, opId, error: formatZodError(envelope.error) }
  const { type, payload, ...rest } = envelope.data
  const parsedPayload = payloadSchemas[type].safeParse(payload ?? {})
  if (!parsedPayload.success) return { ok: false, opId, error: `${type}: ${formatZodError(parsedPayload.error)}` }
  const operation = { ...rest, actorPlayerId: rest.actorPlayerId ?? null, type, payload: parsedPayload.data } as Operation
  return { ok: true, value: { operation, rawPayload: payload ?? {} } }
}

/** The fold order: HLC, then device ID, then operation ID (all total, so every device agrees). */
export function compareFoldOrder(a: Operation, b: Operation): number {
  return compareHlc(a.hlc, b.hlc) || compareStrings(a.deviceId, b.deviceId) || compareStrings(a.opId, b.opId)
}

export function formatZodError(error: z.ZodError): string {
  return error.issues
    .slice(0, 3)
    .map((issue) => `${issue.path.join('.') || '(root)'}: ${issue.message}`)
    .join('; ')
}
