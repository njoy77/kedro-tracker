// The legacy web app's history (`kedro_kv`: `kedro_players`, `kedro_games`) as v3 operation logs
// (PRD §3.2, §9, decision 7). Every legacy username becomes a guest identity with a claim code,
// so its owner can claim the history from the iOS app ("Got a claim code?"); once claimed, the
// games count for their account like any finished game. How legacy rounds become v3 rounds (and
// which games are skipped) lives in packages/shared `legacyRounds`, which the web app's
// leaderboard uses too.

import { createHash } from 'node:crypto'
import {
  EMOJI_COLOR_COUNT,
  legacyRounds,
  seatIdOf,
  type LegacyExport,
  type LegacySkipReason,
  type Seat,
  type WireOperation,
} from '@kedro/shared'

export { readLegacyExport, type LegacyExport, type LegacyGame, type LegacyPlayer, type LegacyRound } from '@kedro/shared'

/** The importer's device ID on every legacy op. */
export const LEGACY_DEVICE_ID = '00000000-0000-4000-8000-000000001e9a'

export type ConvertedGame = { legacyId: string; gameId: string; operations: WireOperation[]; guests: string[] }
export type SkippedGame = { legacyId: string; reason: LegacySkipReason }
export type LegacyGuest = { legacyId: string; guestId: string; displayName: string; claimTokenHash: string }

/** A stable v4-shaped UUID from a name (re-running the import produces the same IDs, so ops stay idempotent). */
export function stableUUID(namespace: string, name: string): string {
  const hex = createHash('sha256').update(`kedro.legacy|${namespace}|${name}`, 'utf8').digest('hex')
  const variant = ((parseInt(hex[16], 16) & 0x3) | 0x8).toString(16)
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-${variant}${hex.slice(17, 20)}-${hex.slice(20, 32)}`
}

/**
 * An imported game's table word: "Web · Oct 25" (the day it started, Eastern time, where the
 * group plays), so a history of web games doesn't read as one word over and over.
 */
export function legacyTitle(startMs: number): string {
  if (!startMs) return 'Web game'
  const day = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', timeZone: 'America/New_York' }).format(new Date(startMs))
  return `Web · ${day}`
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
    const converted = legacyRounds(game, (legacyId) => seatIdOf({ kind: 'guest', id: stableUUID('player', legacyId) }))
    if ('skipped' in converted) {
      skipped.push({ legacyId: game.id, reason: converted.skipped })
      continue
    }
    const { order, rounds, timestamps } = converted

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
    add('GameCreated', { config: { plannedRounds: Math.min(Math.max(rounds.length, 1), 50), scoringMode: 'scorekeeper', tableWord: legacyTitle(startMs), imported: true }, host: order[0] }, startMs)
    for (const seat of seats) add('PlayerSeated', { seat })
    add('GameStarted', { seatOrder: order, firstDealer: order[0] })
    for (const [index, round] of rounds.entries()) add('RoundRecorded', { round }, timestamps[index])
    add('GameFinished', { reason: 'completed', finalRounds: rounds }, game.endedAt)
    games.push({ legacyId: game.id, gameId, operations, guests: seats.map((seat) => seat.player.id) })
  }
  return { games, skipped, guests: [...guests.values()] }
}
