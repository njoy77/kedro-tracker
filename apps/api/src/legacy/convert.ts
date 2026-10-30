// The legacy web app's history (`kedro_kv`: `kedro_players`, `kedro_games`) as v3 operation logs
// (PRD §3.2, §9, decision 7). Every legacy username becomes a guest identity with a claim code,
// so its owner can claim the history from the iOS app ("Got a claim code?"); once claimed, the
// games count for their account like any finished game.
//
// The legacy app stored round *scores*, with the knock result marked by the scorekeeper, and let
// a round be saved with no knocker. Imported rounds keep those saved scores exactly (the game is
// created with `config.imported`, the only kind of game whose rounds may carry `scores`), with
// hands filled in from them (`legacyHands`). A round with no knocker recorded credits no knock to
// anyone; the web app's inherent knock ("IK") is kept. Rounds where everyone scored 0 were the
// web app being tested and are dropped. A game that was abandoned, has fewer than 3 players, or
// has no rounds left is skipped and reported.

import { createHash } from 'node:crypto'
import {
  EMOJI_COLOR_COUNT,
  HAND_MAX,
  HAND_MIN,
  SEAT_LIMITS,
  FAILED_PENALTY,
  LANDED_SCORE,
  seatIdOf,
  type Round,
  type Seat,
  type WireOperation,
} from '@kedro/shared'

export type LegacyPlayer = { id: string; username: string; emoji?: string; deleted?: boolean }
export type LegacyRound = {
  id?: string
  timestamp?: number
  scores: { playerId: string; score: number }[]
  knockedBy?: string | null
  /** 'correct' | 'tied' | 'incorrect', marked by the scorekeeper (absent before tied knocks existed). */
  knockResult?: string | null
  /** Who went out with an inherent knock (all four cards played), if anyone. */
  inherentKnock?: string | null
}
export type LegacyGame = {
  id: string
  startedAt?: number
  endedAt?: number
  status?: string
  players: { id: string; username: string; emoji?: string; total?: number }[]
  rounds: LegacyRound[]
}

export type LegacyExport = { players: LegacyPlayer[]; games: LegacyGame[] }

/** The importer's device ID on every legacy op. */
export const LEGACY_DEVICE_ID = '00000000-0000-4000-8000-000000001e9a'

export type ConvertedGame = { legacyId: string; gameId: string; operations: WireOperation[]; guests: string[] }
export type SkippedGame = { legacyId: string; reason: 'abandoned' | 'tooFewPlayers' | 'tooManyPlayers' | 'noRounds' | 'unknownPlayer' }
export type LegacyGuest = { legacyId: string; guestId: string; displayName: string; claimTokenHash: string }

/** A stable v4-shaped UUID from a name (re-running the import produces the same IDs, so ops stay idempotent). */
export function stableUUID(namespace: string, name: string): string {
  const hex = createHash('sha256').update(`kedro.legacy|${namespace}|${name}`, 'utf8').digest('hex')
  const variant = ((parseInt(hex[16], 16) & 0x3) | 0x8).toString(16)
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-${variant}${hex.slice(17, 20)}-${hex.slice(20, 32)}`
}

/** Reads a `kedro_kv` export: either `[{key, value}]` rows or `{kedro_players, kedro_games}`. */
export function readLegacyExport(json: unknown): LegacyExport {
  const lookup = (key: string): unknown => {
    if (Array.isArray(json)) return (json as { key?: string; value?: unknown }[]).find((row) => row.key === key)?.value
    if (json && typeof json === 'object') return (json as Record<string, unknown>)[key]
    return undefined
  }
  const players = Array.isArray(lookup('kedro_players')) ? (lookup('kedro_players') as LegacyPlayer[]) : []
  const games = Array.isArray(lookup('kedro_games')) ? (lookup('kedro_games') as LegacyGame[]) : []
  return { players, games }
}

/**
 * Hand values for an imported round, whose saved scores are kept as they were. The web app saved
 * scores, not hands: everyone else's score is their hand; an inherent knocker's hand is 0; a
 * beaten knocker's is their score − 10; a tied knocker's is their score. A landed knocker's hand
 * wasn't saved, so it's the lowest hand that still landed (one under the next lowest).
 */
function legacyHands(scores: Record<string, number>, order: readonly string[], knocker: string | null, inherent: string | null, result: string | null | undefined): Record<string, number> {
  const clamp = (hand: number) => Math.min(Math.max(hand, HAND_MIN), HAND_MAX)
  const hands: Record<string, number> = {}
  for (const seat of order) hands[seat] = clamp(scores[seat])
  if (inherent) hands[inherent] = 0
  if (knocker && knocker !== inherent) {
    const score = scores[knocker]
    const others = order.filter((seat) => seat !== knocker).map((seat) => hands[seat])
    if (score === LANDED_SCORE) hands[knocker] = clamp(Math.min(...others) - 1)
    else if (result === 'incorrect' || (result == null && score - FAILED_PENALTY >= HAND_MIN && score - FAILED_PENALTY > Math.min(...others))) hands[knocker] = clamp(score - FAILED_PENALTY)
  }
  return hands
}

export function convertLegacy(
  data: LegacyExport,
  claimTokenHashFor: (legacyPlayerId: string) => string,
): { games: ConvertedGame[]; skipped: SkippedGame[]; guests: LegacyGuest[] } {
  const guests = new Map<string, LegacyGuest>()
  const names = new Map(data.players.map((player) => [player.id, player.username]))
  const guestFor = (legacyId: string, fallbackName: string): LegacyGuest => {
    let guest = guests.get(legacyId)
    if (!guest) {
      const displayName = (names.get(legacyId) ?? fallbackName).trim().slice(0, 40) || 'Guest'
      guest = { legacyId, guestId: stableUUID('player', legacyId), displayName, claimTokenHash: claimTokenHashFor(legacyId) }
      guests.set(legacyId, guest)
    }
    return guest
  }

  const games: ConvertedGame[] = []
  const skipped: SkippedGame[] = []
  for (const game of data.games) {
    const skip = (reason: SkippedGame['reason']) => skipped.push({ legacyId: game.id, reason })
    if (game.status !== 'complete') { skip('abandoned'); continue }
    if (game.players.length < SEAT_LIMITS.min) { skip('tooFewPlayers'); continue }
    if (game.players.length > SEAT_LIMITS.max) { skip('tooManyPlayers'); continue }
    if (game.rounds.length === 0) { skip('noRounds'); continue }

    const seatIdByLegacy = new Map(game.players.map((player) => [player.id, seatIdOf({ kind: 'guest', id: stableUUID('player', player.id) })]))
    const order = game.players.map((player) => seatIdByLegacy.get(player.id) ?? '')
    const rounds: Round[] = []
    const timestamps: (number | undefined)[] = []
    let failed: SkippedGame['reason'] | null = null
    for (const legacyRound of game.rounds) {
      const scores: Record<string, number> = {}
      for (const { playerId, score } of legacyRound.scores) {
        const seat = seatIdByLegacy.get(playerId)
        if (!seat) { failed = 'unknownPlayer'; break }
        scores[seat] = score
      }
      if (failed) break
      if (!order.every((seat) => scores[seat] !== undefined)) { failed = 'unknownPlayer'; break }
      // Rounds where everyone scored 0 were the web app being tested, not play.
      if (order.every((seat) => scores[seat] === 0)) continue
      const seatOf = (legacyId: string | null | undefined) => (legacyId ? seatIdByLegacy.get(legacyId) ?? null : null)
      const knocker = seatOf(legacyRound.knockedBy) ?? seatOf(legacyRound.inherentKnock)
      const inherent = seatOf(legacyRound.inherentKnock)
      if ((legacyRound.knockedBy && !seatOf(legacyRound.knockedBy)) || (legacyRound.inherentKnock && !inherent)) { failed = 'unknownPlayer'; break }
      const round: Round = { number: rounds.length + 1, hands: legacyHands(scores, order, knocker, inherent, legacyRound.knockResult), scores }
      if (knocker) round.knocker = knocker
      if (inherent) round.inherent = inherent
      rounds.push(round)
      timestamps.push(legacyRound.timestamp)
    }
    if (!failed && rounds.length === 0) failed = 'noRounds'
    if (failed) { skip(failed); continue }

    const gameId = stableUUID('game', game.id)
    const startMs = game.startedAt ?? game.rounds[0]?.timestamp ?? 0
    let wallMs = startMs
    let sequence = 0
    const operations: WireOperation[] = []
    const add = (type: WireOperation['type'], payload: unknown, atMs?: number) => {
      wallMs = Math.max(wallMs + 1, atMs ?? wallMs + 1)
      sequence += 1
      operations.push({
        opId: stableUUID('op', `${game.id}|${sequence}`),
        gameId,
        deviceId: LEGACY_DEVICE_ID,
        hlc: { wallMs, counter: 0, node: LEGACY_DEVICE_ID },
        actorPlayerId: null,
        type,
        payload,
      })
    }

    const seats: Seat[] = game.players.map((player, order) => {
      const guest = guestFor(player.id, player.username)
      const seat: Seat = { player: { kind: 'guest', id: guest.guestId }, displayName: guest.displayName, order, claimTokenHash: guest.claimTokenHash }
      if (player.emoji) seat.avatar = { kind: 'emoji', emoji: player.emoji, colorIndex: parseInt(guest.guestId.slice(0, 2), 16) % EMOJI_COLOR_COUNT }
      return seat
    })
    add('GameCreated', { config: { plannedRounds: Math.min(Math.max(rounds.length, 1), 50), scoringMode: 'scorekeeper', tableWord: 'Legacy', imported: true }, host: order[0] }, startMs)
    for (const seat of seats) add('PlayerSeated', { seat })
    add('GameStarted', { seatOrder: order, firstDealer: order[0] })
    for (const [index, round] of rounds.entries()) add('RoundRecorded', { round }, timestamps[index])
    add('GameFinished', { reason: 'completed', finalRounds: rounds }, game.endedAt)
    games.push({ legacyId: game.id, gameId, operations, guests: seats.map((seat) => seat.player.id) })
  }
  return { games, skipped, guests: [...guests.values()] }
}
