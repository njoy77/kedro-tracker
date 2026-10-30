// The legacy web app's history (`kedro_kv`: `kedro_players`, `kedro_games`) as v3 operation logs
// (PRD §3.2, §9, decision 7). Every legacy username becomes a guest identity with a claim code,
// so its owner can claim the history from the iOS app ("Got a claim code?"); once claimed, the
// games count for their account like any finished game.
//
// The legacy app stored round *scores*. v3 stores hands and the knocker and derives scores
// (PRD §2.6), so each round is solved for hands that give exactly the legacy scores: everyone
// but the knocker scores their hand; the knocker's hand is the one that produces their legacy
// score under the knock rules. Rounds with no knocker (allowed in the web app) get the knocker
// whose hand reproduces the scores too (a tied-lowest seat, or one beaten by 10). A game whose
// rounds can't be reproduced exactly, with fewer than 3 players, or that was abandoned, is
// skipped and reported, never approximated.

import { createHash } from 'node:crypto'
import {
  EMOJI_COLOR_COUNT,
  HAND_MAX,
  HAND_MIN,
  SEAT_LIMITS,
  roundScores,
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
export type SkippedGame = { legacyId: string; reason: 'abandoned' | 'tooFewPlayers' | 'tooManyPlayers' | 'noRounds' | 'unrepresentableRound' | 'unknownPlayer' }
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

/** Solves one round: hands for every seat and a knocker whose v3 scores equal the legacy scores. */
export function solveRound(scores: Record<string, number>, order: readonly string[], knockedBy: string | null): { hands: Record<string, number>; knocker: string } | null {
  const inRange = (hand: number) => Number.isInteger(hand) && hand >= HAND_MIN && hand <= HAND_MAX
  const candidatesFor = (knocker: string): number[] => {
    const target = scores[knocker]
    const others = order.filter((seat) => seat !== knocker).map((seat) => scores[seat])
    const lowestOther = Math.min(...others)
    // Tied (score = hand), beaten (hand + 10), or strictly lowest (flat −10, any hand below the rest).
    const options = [target, target - 10]
    if (target === -10) options.push(lowestOther - 1, HAND_MIN)
    return options
  }
  const tryKnocker = (knocker: string) => {
    if (!order.includes(knocker) || !order.every((seat) => seat === knocker || inRange(scores[seat]))) return null
    for (const hand of candidatesFor(knocker)) {
      if (!inRange(hand)) continue
      const hands = { ...scores, [knocker]: hand }
      const result = roundScores(hands, knocker)
      if (order.every((seat) => result[seat] === scores[seat])) return { hands, knocker }
    }
    return null
  }
  if (knockedBy) return tryKnocker(knockedBy)
  // No knocker recorded: prefer a seat tied for lowest (its score is its hand), then the highest scores (beaten by 10).
  const lowest = Math.min(...order.map((seat) => scores[seat]))
  const preferred = [...order].sort((a, b) => Number(scores[b] === lowest) - Number(scores[a] === lowest) || scores[b] - scores[a])
  for (const knocker of preferred) {
    const solved = tryKnocker(knocker)
    if (solved) return solved
  }
  return null
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
    let failed: SkippedGame['reason'] | null = null
    for (const [index, legacyRound] of game.rounds.entries()) {
      const scores: Record<string, number> = {}
      for (const { playerId, score } of legacyRound.scores) {
        const seat = seatIdByLegacy.get(playerId)
        if (!seat) { failed = 'unknownPlayer'; break }
        scores[seat] = score
      }
      if (failed) break
      if (!order.every((seat) => scores[seat] !== undefined)) { failed = 'unknownPlayer'; break }
      const knocker = legacyRound.knockedBy ? seatIdByLegacy.get(legacyRound.knockedBy) ?? null : null
      if (legacyRound.knockedBy && !knocker) { failed = 'unknownPlayer'; break }
      const solved = solveRound(scores, order, knocker)
      if (!solved) { failed = 'unrepresentableRound'; break }
      rounds.push({ number: index + 1, hands: solved.hands, knocker: solved.knocker })
    }
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
    add('GameCreated', { config: { plannedRounds: Math.min(Math.max(rounds.length, 1), 50), scoringMode: 'scorekeeper', tableWord: 'Legacy' }, host: order[0] }, startMs)
    for (const seat of seats) add('PlayerSeated', { seat })
    add('GameStarted', { seatOrder: order, firstDealer: order[0] })
    for (const [index, round] of rounds.entries()) add('RoundRecorded', { round }, game.rounds[index].timestamp)
    add('GameFinished', { reason: 'completed', finalRounds: rounds }, game.endedAt)
    games.push({ legacyId: game.id, gameId, operations, guests: seats.map((seat) => seat.player.id) })
  }
  return { games, skipped, guests: [...guests.values()] }
}
