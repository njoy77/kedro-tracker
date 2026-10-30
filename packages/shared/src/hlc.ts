// Hybrid logical clock timestamps. Mirrors apps/ios/Kedro/Core/Domain/HLC.swift.
//
// JSON: {"wallMs":1761700000000,"counter":0,"node":"<deviceId>"}
// String form (used by GET /v1/games/:id/ops?after=): "<wallMs, 15 digits>-<counter, 5 digits>-<node>".
// Lexicographic order of the string equals HLC order, so the database sorts on the string.

export type HLC = { wallMs: number; counter: number; node: string }

export function hlcString(hlc: HLC): string {
  return `${String(hlc.wallMs).padStart(15, '0')}-${String(hlc.counter).padStart(5, '0')}-${hlc.node}`
}

/** Parses `hlcString` output. Returns null when malformed. */
export function parseHlc(value: string): HLC | null {
  const match = /^(\d{1,15})-(\d{1,5})-(.*)$/.exec(value)
  if (!match) return null
  return { wallMs: Number(match[1]), counter: Number(match[2]), node: match[3] }
}

/** (wallMs, counter, node), the same order as Swift's `HLC.<`. */
export function compareHlc(a: HLC, b: HLC): number {
  if (a.wallMs !== b.wallMs) return a.wallMs < b.wallMs ? -1 : 1
  if (a.counter !== b.counter) return a.counter < b.counter ? -1 : 1
  return compareStrings(a.node, b.node)
}

/** Code-unit string comparison (matches Swift for the ASCII IDs Kedro uses). */
export function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}
