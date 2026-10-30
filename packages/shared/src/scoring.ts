// The canonical Cambio scoring rules (PRD §2.6, §2.7).
// Mirrors apps/ios/Kedro/Core/Scoring/Scoring.swift exactly; both sides are tested against the
// sample game in design spec §17.
//
// | Situation               | Knocker    | Everyone else |
// |-------------------------|------------|---------------|
// | Knocker strictly lowest | −10 flat   | hand          |
// | Knocker tied for lowest | hand       | hand          |
// | Someone lower           | hand + 10  | hand          |
//
// An inherent knock (the knocker played all four cards, so their hand is 0 and the knock is
// automatic on their turn) never takes the +10: strictly lowest is −10, otherwise they score 0.

/** `noPenalty`: an inherent knock that someone beat (scores its hand, 0, with no +10). */
export type KnockOutcome = 'landed' | 'tied' | 'failed' | 'noPenalty'

/** A finishing or standings position. `isShared` renders as "2=". */
export type Rank = { position: number; isShared: boolean }

/** What a knocker scores when their hand is strictly lowest. */
export const LANDED_SCORE = -10
/** What a beaten knocker adds to their hand. */
export const FAILED_PENALTY = 10
/** Hands below −2 are impossible; the pad stops at 999. */
export const HAND_MIN = -2
export const HAND_MAX = 999

/** Hand values (or scores, or totals) by seat ID or any other string key. */
export type Hands = Record<string, number>

/** The knock outcome, or null if the knocker has no hand. */
export function knockOutcome(hands: Hands, knocker: string, inherent = false): KnockOutcome | null {
  const knockerHand = hands[knocker]
  if (knockerHand === undefined) return null
  let lowestOther: number | undefined
  for (const [key, value] of entries(hands)) {
    if (key === knocker) continue
    if (lowestOther === undefined || value < lowestOther) lowestOther = value
  }
  if (lowestOther === undefined || knockerHand < lowestOther) return 'landed'
  if (knockerHand === lowestOther) return 'tied'
  return inherent ? 'noPenalty' : 'failed'
}

/** What the knocker scores for a hand and outcome. */
export function knockerScore(hand: number, outcome: KnockOutcome): number {
  switch (outcome) {
    case 'landed':
      return LANDED_SCORE
    case 'tied':
    case 'noPenalty':
      return hand
    case 'failed':
      return hand + FAILED_PENALTY
  }
}

/**
 * Round scores from hand values and the knocker. If the knocker has no hand (an invalid round),
 * the hands are returned unchanged.
 */
export function roundScores(hands: Hands, knocker: string, inherent = false): Record<string, number> {
  const scores = { ...hands } as Record<string, number>
  const knockerHand = hands[knocker]
  const outcome = knockOutcome(hands, knocker, inherent)
  if (knockerHand === undefined || outcome === null) return scores
  scores[knocker] = knockerScore(knockerHand, outcome)
  return scores
}

/**
 * The shape of a round the helpers below read (`Round` in domain.ts). `scores` is set only on
 * rounds imported from the web app, whose saved scores are kept as they were.
 */
export type ScoredRound = { hands: Hands; knocker?: string; inherent?: string; scores?: Hands }

/** A round's scores: imported scores as saved, otherwise derived from the hands and the knock. */
export function scoresOf(round: ScoredRound): Record<string, number> {
  if (round.scores) return { ...round.scores }
  if (!round.knocker) return { ...round.hands }
  return roundScores(round.hands, round.knocker, round.inherent === round.knocker)
}

/** True when the round's knocker went out with an inherent knock. */
export function isInherentKnock(round: ScoredRound): boolean {
  return round.knocker !== undefined && round.inherent === round.knocker
}

/**
 * A round's knock outcome, or null without a knocker. For an imported round it's read from the
 * saved knocker score (−10 landed, hand + 10 failed, otherwise tied or no penalty).
 */
export function outcomeOf(round: ScoredRound): KnockOutcome | null {
  const knocker = round.knocker
  if (!knocker) return null
  const inherent = isInherentKnock(round)
  if (!round.scores) return knockOutcome(round.hands, knocker, inherent)
  const score = round.scores[knocker]
  const hand = round.hands[knocker]
  if (score === undefined || hand === undefined) return null
  if (score === LANDED_SCORE && hand !== LANDED_SCORE) return 'landed'
  if (score === hand + FAILED_PENALTY) return 'failed'
  if (!inherent) return 'tied'
  const others = Object.entries(round.hands).filter(([key]) => key !== knocker).map(([, value]) => value)
  return others.length > 0 && Math.min(...others) < hand ? 'noPenalty' : 'tied'
}

/** Cumulative totals: the sum of each key's round scores. Keys missing from a round add 0. */
export function totals(rounds: Hands[]): Record<string, number> {
  const result = {}  as Record<string, number>
  for (const scores of rounds) {
    for (const [key, score] of entries(scores)) {
      result[key] = (result[key] ?? 0) + score
    }
  }
  return result
}

/** Standard competition ranking, lowest total first: 26, 29, 29, 44 → 1, 2=, 2=, 4. */
export function ranks(totalsByKey: Hands): Record<string, Rank> {
  const values = entries(totalsByKey).map(([, total]) => total)
  const result = {} as Record<string, Rank>
  for (const [key, total] of entries(totalsByKey)) {
    const better = values.filter((value) => value < total).length
    const same = values.filter((value) => value === total).length
    result[key] = { position: better + 1, isShared: same > 1 }
  }
  return result
}

/** Everyone with the lowest total. Ties share the win (PRD §2.7). */
export function winners(totalsByKey: Hands): Set<string> {
  const list = entries(totalsByKey)
  if (list.length === 0) return new Set()
  const best = Math.min(...list.map(([, total]) => total))
  return new Set(list.filter(([, total]) => total === best).map(([key]) => key))
}

/** Keys ordered best first; equal totals keep the order of `tieOrder` (e.g. seat order). */
export function ordered(totalsByKey: Hands, tieOrder: string[]): string[] {
  const position = new Map<string, number>()
  tieOrder.forEach((key, index) => {
    if (!position.has(key)) position.set(key, index)
  })
  return entries(totalsByKey)
    .map(([key]) => key)
    .sort((a, b) => {
      const left = totalsByKey[a] ?? 0
      const right = totalsByKey[b] ?? 0
      if (left !== right) return left - right
      return (position.get(a) ?? Number.MAX_SAFE_INTEGER) - (position.get(b) ?? Number.MAX_SAFE_INTEGER)
    })
}

/** "1", "2=". */
export function rankLabel(rank: Rank): string {
  return rank.isShared ? `${rank.position}=` : `${rank.position}`
}

function entries(record: Hands): [string, number][] {
  return Object.entries(record).filter((entry): entry is [string, number] => typeof entry[1] === 'number')
}
