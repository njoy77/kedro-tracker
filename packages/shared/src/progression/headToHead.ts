// Two people's shared record (PRD §5.2, design §12.3). A port of the iOS app's
// `Core/Stats/HeadToHead.swift`.

import type { UUID } from '../ids.ts'
import { canonical, containsRef, regularKnocker, type Ref } from './game.ts'
import { recordOf, type ProgressionSnapshot } from './snapshot.ts'

export type KnockTally = { landed: number; tied: number; failed: number }

export type HeadToHead = {
  a: Ref
  b: Ref
  gamesTogether: number
  /** Games where a finished ahead of b, and the reverse. Equal totals count for neither. */
  aAhead: number
  bAhead: number
  aWins: number
  bWins: number
  aKnocks: KnockTally
  bKnocks: KnockTally
  aAverageFinal: number | null
  bAverageFinal: number | null
  lastMeeting: { gameId: UUID; tableWord: string; dateMs: number; aScore: number; bScore: number } | null
}

export function headToHead(snapshot: ProgressionSnapshot, first: Ref, second: Ref): HeadToHead {
  const a = canonical(snapshot.options, first), b = canonical(snapshot.options, second)
  const tally = (): KnockTally => ({ landed: 0, tied: 0, failed: 0 })
  const h2h: HeadToHead = {
    a, b, gamesTogether: 0, aAhead: 0, bAhead: 0, aWins: 0, bWins: 0,
    aKnocks: tally(), bKnocks: tally(), aAverageFinal: null, bAverageFinal: null, lastMeeting: null,
  }
  if (a === b) return h2h
  let aSum = 0, bSum = 0
  for (const game of snapshot.games) {
    if (!containsRef(game, a) || !containsRef(game, b)) continue
    const aTotal = game.totals.get(a) ?? 0, bTotal = game.totals.get(b) ?? 0
    h2h.gamesTogether += 1
    aSum += aTotal
    bSum += bTotal
    if (aTotal < bTotal) h2h.aAhead += 1
    if (bTotal < aTotal) h2h.bAhead += 1
    if (game.winners.has(a)) h2h.aWins += 1
    if (game.winners.has(b)) h2h.bWins += 1
    for (const round of game.rounds) {
      if (!round.outcome || round.outcome === 'noPenalty') continue
      const knocker = regularKnocker(round)
      if (knocker === a) h2h.aKnocks[round.outcome] += 1
      if (knocker === b) h2h.bKnocks[round.outcome] += 1
    }
    h2h.lastMeeting = { gameId: game.id, tableWord: game.tableWord, dateMs: game.finishedAtMs, aScore: aTotal, bScore: bTotal }
  }
  if (h2h.gamesTogether > 0) {
    h2h.aAverageFinal = aSum / h2h.gamesTogether
    h2h.bAverageFinal = bSum / h2h.gamesTogether
  }
  return h2h
}

/** The people someone has played with most, most games first. */
export function rivalsOf(snapshot: ProgressionSnapshot, ref: Ref, limit = 3): Ref[] {
  const record = recordOf(snapshot, ref)
  if (!record) return []
  return [...record.sharedGames]
    .filter(([other]) => !snapshot.options.excluded.has(other))
    .sort((x, y) => y[1] - x[1] || (x[0] < y[0] ? -1 : x[0] > y[0] ? 1 : 0))
    .slice(0, limit)
    .map(([other]) => other)
}
