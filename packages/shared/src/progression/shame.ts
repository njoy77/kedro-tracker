// The Hall of Shame (design §12.8, PRD §5.7): single moments only, never streaks. A port of the
// iOS app's `Core/Stats/HallOfShame.swift`.

import type { UUID } from '../ids.ts'
import type { Rank } from '../scoring.ts'
import { canonical, knockerHand, lowestOtherHand, participantOf, type Participant, type Ref, type StatsGame } from './game.ts'
import type { PlayerGameResult, PlayerRecord } from './record.ts'
import { circleOf, type ProgressionSnapshot } from './snapshot.ts'

export const SHAME_CATEGORIES = ['worstHand', 'worstKnock', 'biggestLoss', 'bottleJob', 'ateIt', 'deepestHole'] as const
export type ShameCategory = (typeof SHAME_CATEGORIES)[number]

export const SHAME_CATEGORY_NAMES: Record<ShameCategory, string> = {
  worstHand: 'Worst Hand',
  worstKnock: 'Worst Knock',
  biggestLoss: 'Biggest Loss',
  bottleJob: 'Bottle Job',
  ateIt: 'Ate It',
  deepestHole: 'Deepest Hole',
}

/** The roast's copy ID. */
export const SHAME_COPY_IDS: Record<ShameCategory, string> = {
  worstHand: 'HS-02', worstKnock: 'HS-03', biggestLoss: 'HS-04', bottleJob: 'HS-05', ateIt: 'HS-06', deepestHole: 'HS-07',
}

/** Players' first 3 games are learner games: they never produce entries for that player. */
export const LEARNER_GAMES = 3

export type ShameScope = 'yourPeople' | 'yours'

export type ShameEntry = {
  category: ShameCategory
  player: Ref
  identity: Participant
  gameId: UUID
  gameIndex: number
  tableWord: string
  dateMs: number
  roundNumber: number | null
  /** The sort key: bigger is worse. */
  value: number
  hand: number | null
  low: number | null
  finish: Rank | null
}

export type ShameBoard = { category: ShameCategory; entries: ShameEntry[] }

const minimumValue = (category: ShameCategory) => (category === 'ateIt' ? 2 : 1)

/** Every candidate moment, one per (category, game, player). */
export function shameMoments(snapshot: ProgressionSnapshot): ShameEntry[] {
  const entries: ShameEntry[] = []
  for (const record of snapshot.records.values()) {
    for (const result of record.results) {
      if (result.gamesBefore < LEARNER_GAMES) continue
      const game = snapshot.games[result.gameIndex]
      if (!game || game.id !== result.gameId) continue
      entries.push(...moments(record, result, game))
    }
  }
  return entries
}

function moments(record: PlayerRecord, result: PlayerGameResult, game: StatsGame): ShameEntry[] {
  const me = record.ref
  const output: ShameEntry[] = []
  const entry = (category: ShameCategory, value: number, extra: Partial<Pick<ShameEntry, 'roundNumber' | 'hand' | 'low' | 'finish'>> = {}) => {
    if (value < minimumValue(category)) return
    output.push({
      category, player: me, identity: participantOf(game, me) ?? record.identity, gameId: game.id, gameIndex: game.index,
      tableWord: game.tableWord, dateMs: game.finishedAtMs, value,
      roundNumber: extra.roundNumber ?? null, hand: extra.hand ?? null, low: extra.low ?? null, finish: extra.finish ?? null,
    })
  }
  // Worst hand: the biggest single hand (earliest round on ties).
  let worstHand: { round: number; hand: number } | null = null
  for (const round of game.rounds) {
    const hand = round.hands.get(me)
    if (hand === undefined) continue
    if (!worstHand || hand > worstHand.hand) worstHand = { round: round.number, hand }
  }
  if (worstHand) entry('worstHand', worstHand.hand, { roundNumber: worstHand.round, hand: worstHand.hand })
  // Worst knock: a failed knock with the biggest gap to the lowest hand (earliest on ties).
  let worstKnock: { round: number; hand: number; low: number } | null = null
  for (const round of game.rounds) {
    const hand = knockerHand(round), low = lowestOtherHand(round)
    if (round.knocker !== me || round.outcome !== 'failed' || hand === null || low === null) continue
    if (!worstKnock || hand - low > worstKnock.hand - worstKnock.low) worstKnock = { round: round.number, hand, low }
  }
  if (worstKnock) entry('worstKnock', worstKnock.hand - worstKnock.low, { roundNumber: worstKnock.round, hand: worstKnock.hand, low: worstKnock.low })
  entry('biggestLoss', result.finalScore)
  if (!result.isWinner) entry('bottleJob', result.biggestLead, { finish: result.rank })
  entry('ateIt', result.failed)
  entry('deepestHole', result.deepestDeficit)
  return output
}

/** The Hall of Shame for a viewer: top 3 per category. A null viewer shows everyone. */
export function hallOfShame(snapshot: ProgressionSnapshot, { scope = 'yourPeople', viewer, limit = 3 }: { scope?: ShameScope; viewer: Ref | null; limit?: number }): ShameBoard[] {
  const me = viewer ? canonical(snapshot.options, viewer) : null
  const allowed = me === null ? null : scope === 'yours' ? new Set([me]) : circleOf(snapshot, me)
  const moments = shameMoments(snapshot).filter((entry) => !snapshot.options.excluded.has(entry.player) && (allowed?.has(entry.player) ?? true))
  return SHAME_CATEGORIES.map((category) => ({
    category,
    entries: moments
      .filter((entry) => entry.category === category)
      .sort((a, b) => b.value - a.value || a.gameIndex - b.gameIndex || (a.player < b.player ? -1 : a.player > b.player ? 1 : 0))
      .slice(0, limit),
  }))
}

/** Every top-3 entry a person holds among their people (or the viewer's). */
export function shameEntriesOf(snapshot: ProgressionSnapshot, ref: Ref, viewer: Ref | null = null): ShameEntry[] {
  const me = canonical(snapshot.options, ref)
  return hallOfShame(snapshot, { viewer: viewer ?? me }).flatMap((board) => board.entries).filter((entry) => entry.player === me)
}
