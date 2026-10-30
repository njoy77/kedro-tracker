// Identifiers shared by every Kedro client and the API.
//
// Mirrors apps/ios/Kedro/Core/Domain/Identifiers.swift. IDs travel as lowercase UUID strings.
// A seat is derived from the person sitting in it: "p:<playerId>" or "g:<guestId>", so the same
// person has the same seat ID in every game and stats are a simple group-by.

/** A lowercase UUID string. */
export type UUID = string

/** `"p:<uuid>"` for a signed-up player, `"g:<uuid>"` for a guest. */
export type SeatId = string

/** Who someone is, independent of any game. JSON: `{"kind":"player","id":"…"}`. */
export type PlayerRef = { kind: 'player' | 'guest'; id: UUID }

/** Any-case UUID (what Swift's `UUID(uuidString:)` accepts). */
export const UUID_PATTERN = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/

/** A seat ID as the clients encode it (always lowercase). */
export const SEAT_ID_PATTERN = /^[pg]:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

export function isUUID(value: unknown): value is UUID {
  return typeof value === 'string' && UUID_PATTERN.test(value)
}

export function seatIdOf(ref: PlayerRef): SeatId {
  return `${ref.kind === 'player' ? 'p' : 'g'}:${ref.id.toLowerCase()}`
}

export function playerSeatId(playerId: UUID): SeatId {
  return seatIdOf({ kind: 'player', id: playerId })
}

export function guestSeatId(guestId: UUID): SeatId {
  return seatIdOf({ kind: 'guest', id: guestId })
}

/** Parses `"p:<uuid>"` / `"g:<uuid>"`; null when malformed. */
export function parseSeatId(seatId: string): PlayerRef | null {
  const match = /^([pg]):(.+)$/.exec(seatId)
  if (!match || !UUID_PATTERN.test(match[2])) return null
  return { kind: match[1] === 'p' ? 'player' : 'guest', id: match[2].toLowerCase() }
}

/** The player ID behind a seat, or null for a guest seat. */
export function seatPlayerId(seatId: SeatId): UUID | null {
  const ref = parseSeatId(seatId)
  return ref?.kind === 'player' ? ref.id : null
}

/** The guest ID behind a seat, or null for a player seat. */
export function seatGuestId(seatId: SeatId): UUID | null {
  const ref = parseSeatId(seatId)
  return ref?.kind === 'guest' ? ref.id : null
}
