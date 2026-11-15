// Titles (design §12.7). A port of the iOS app's `Core/Stats/TitleCatalog.swift` and
// `TitleHolders.swift`. IDs are copy deck IDs (TI-01…TI-18).

import { badgeDefinition, BADGE, BADGE_TIERS, type BadgeId } from './badges.ts'
import { canonical, isGuestRef, type Ref } from './game.ts'
import {
  averageRoundScore,
  gamesPlayed,
  isRanked,
  knockRate,
  knockSuccessRate,
  knocksBeatenOf,
  knocksOf,
  roundsPlayedOf,
  type HeldMetric,
  type PlayerRecord,
} from './record.ts'
import { circleOf, recordOf, resultsIn, yearOf, type ProgressionSnapshot } from './snapshot.ts'

type TitleKind = { kind: 'earned'; badge: BadgeId | null } | { kind: 'held'; metric: HeldMetric }

/** Every title, in catalog order (later = harder), with its clean-level name and profile line (copy deck TI-xx). */
export const TITLES = [
  { id: 'TI-01', name: 'Fresh Meat', tagline: 'First ten games. Be gentle.', kind: { kind: 'earned', badge: null } },
  { id: 'TI-02', name: 'Regular', tagline: 'Twenty-five games and counting.', kind: { kind: 'earned', badge: BADGE.regular } },
  { id: 'TI-03', name: 'Untouchable', tagline: 'Five straight wins. Once.', kind: { kind: 'earned', badge: BADGE.untouchable } },
  { id: 'TI-04', name: 'The Ghost', tagline: 'Has held a hand worth nothing.', kind: { kind: 'earned', badge: BADGE.ghostHand } },
  { id: 'TI-05', name: 'Royalty', tagline: 'Both red Kings. One hand.', kind: { kind: 'earned', badge: BADGE.royalPair } },
  { id: 'TI-06', name: 'Comeback Kid', tagline: 'Never count them out.', kind: { kind: 'earned', badge: BADGE.comebackKid } },
  { id: 'TI-07', name: 'Dark Horse', tagline: 'Beat a table rated higher across the board.', kind: { kind: 'earned', badge: BADGE.darkHorse } },
  { id: 'TI-08', name: 'Exorcist', tagline: 'Beat the nemesis three straight.', kind: { kind: 'earned', badge: BADGE.exorcism } },
  { id: 'TI-09', name: 'Bad Influence', tagline: 'Dragged a guest into this for good.', kind: { kind: 'earned', badge: BADGE.badInfluence } },
  { id: 'TI-10', name: 'The Stirrer', tagline: 'Fifty taunts sent.', kind: { kind: 'earned', badge: BADGE.trashTalker } },
  { id: 'TI-11', name: 'Touch Grass', tagline: 'A hundred games. Concerning.', kind: { kind: 'earned', badge: BADGE.touchGrass } },
  { id: 'TI-12', name: 'The Closer', tagline: 'Best knock success among their people.', kind: { kind: 'held', metric: 'knockSuccess' } },
  { id: 'TI-13', name: 'Knock Merchant', tagline: 'Knocks more than anyone they play with.', kind: { kind: 'held', metric: 'knockRate' } },
  { id: 'TI-14', name: 'The Snake', tagline: "Beats other people's knocks for sport.", kind: { kind: 'held', metric: 'knocksBeaten' } },
  { id: 'TI-15', name: 'The Accountant', tagline: 'Lowest average round. Boring. Effective.', kind: { kind: 'held', metric: 'averageRound' } },
  { id: 'TI-16', name: 'Red King Magnet', tagline: 'Red Kings just find them.', kind: { kind: 'held', metric: 'redKingsThisYear' } },
  { id: 'TI-17', name: 'Top Dog', tagline: '#1 among their people.', kind: { kind: 'held', metric: 'rating' } },
  { id: 'TI-18', name: 'The Bottler', tagline: 'Blew more final-round leads than anyone. Wears it proudly.', kind: { kind: 'held', metric: 'bottledThisYear' } },
] as const satisfies readonly { id: string; name: string; tagline: string; kind: TitleKind }[]

export type TitleId = (typeof TITLES)[number]['id']
export const TITLE_IDS: readonly TitleId[] = TITLES.map((title) => title.id)
const BY_ID = new Map<string, (typeof TITLES)[number]>(TITLES.map((title) => [title.id, title]))

export function isTitleId(value: string): value is TitleId {
  return BY_ID.has(value)
}

function kindOf(id: TitleId): TitleKind {
  return (BY_ID.get(id) as { kind: TitleKind }).kind
}

export function isHeldTitle(id: TitleId): boolean {
  return kindOf(id).kind === 'held'
}

export function titleBadge(id: TitleId): BadgeId | null {
  const kind = kindOf(id)
  return kind.kind === 'earned' ? kind.badge : null
}

/** The title a badge unlocks. */
export function titleUnlockedBy(badge: BadgeId): TitleId | null {
  return TITLE_IDS.find((id) => titleBadge(id) === badge) ?? null
}

/** Rarest badge's title first, then catalog order: where a lost held title falls back to. */
export function earnedRank(id: TitleId): number {
  const badge = titleBadge(id)
  const tier = badge ? BADGE_TIERS.indexOf(badgeDefinition(badge).tier) : 0
  return tier * 100 + TITLE_IDS.indexOf(id)
}

/** Held titles need a real crowd: at least this many ranked people in your circle. */
export const TITLE_MINIMUM_RANKED_PEOPLE = 5

const higherIsBetter = (metric: HeldMetric) => metric !== 'averageRound'

function qualifies(snapshot: ProgressionSnapshot, metric: HeldMetric, record: PlayerRecord, year: number): boolean {
  if (!isRanked(record)) return false
  switch (metric) {
    case 'knockSuccess': return knocksOf(record) >= 15
    case 'knockRate': return roundsPlayedOf(record) >= 50
    case 'knocksBeaten': return gamesPlayed(record) >= 10 && knocksBeatenOf(record) > 0
    case 'averageRound': return gamesPlayed(record) >= 20
    case 'rating': return true
    case 'redKingsThisYear': {
      const games = resultsIn(snapshot, record, year)
      return games.length >= 10 && games.reduce((total, result) => total + result.redKings, 0) > 0
    }
    case 'bottledThisYear': {
      const games = resultsIn(snapshot, record, year)
      return games.length >= 10 && games.some((result) => result.bottledFinalRound)
    }
  }
}

function metricValue(snapshot: ProgressionSnapshot, metric: HeldMetric, record: PlayerRecord, year: number): number {
  switch (metric) {
    case 'knockSuccess': return knockSuccessRate(record) ?? 0
    case 'knockRate': return knockRate(record) ?? 0
    case 'knocksBeaten': return knocksBeatenOf(record)
    case 'averageRound': return averageRoundScore(record) ?? Number.POSITIVE_INFINITY
    case 'rating': return record.rating
    case 'redKingsThisYear': return resultsIn(snapshot, record, year).reduce((total, result) => total + result.redKings, 0)
    case 'bottledThisYear': return resultsIn(snapshot, record, year).filter((result) => result.bottledFinalRound).length
  }
}

function reachedAt(snapshot: ProgressionSnapshot, metric: HeldMetric, record: PlayerRecord, year: number): number {
  const none = Number.MAX_SAFE_INTEGER
  switch (metric) {
    case 'redKingsThisYear': return [...resultsIn(snapshot, record, year)].reverse().find((result) => result.redKings > 0)?.gameIndex ?? none
    case 'bottledThisYear': return [...resultsIn(snapshot, record, year)].reverse().find((result) => result.bottledFinalRound)?.gameIndex ?? none
    default: return record.metricChangedAt.get(metric) ?? none
  }
}

/** Who holds a held title among someone's people (them included); null when the circle is too small or nobody qualifies. */
export function holderOf(snapshot: ProgressionSnapshot, title: TitleId, viewer: Ref, nowMs: number): Ref | null {
  const kind = kindOf(title)
  if (kind.kind !== 'held') return null
  const metric = kind.metric
  const year = yearOf(snapshot, nowMs)
  const pool = [...circleOf(snapshot, viewer)].flatMap((ref) => snapshot.records.get(ref) ?? []).filter((record) => !isGuestRef(record.ref) && isRanked(record))
  if (pool.length < TITLE_MINIMUM_RANKED_PEOPLE) return null
  let best: PlayerRecord | null = null
  for (const candidate of pool) {
    if (!qualifies(snapshot, metric, candidate, year)) continue
    if (!best) {
      best = candidate
      continue
    }
    const a = metricValue(snapshot, metric, candidate, year), b = metricValue(snapshot, metric, best, year)
    if (a !== b) {
      if (higherIsBetter(metric) ? a > b : a < b) best = candidate
      continue
    }
    const atA = reachedAt(snapshot, metric, candidate, year), atB = reachedAt(snapshot, metric, best, year)
    if (atA !== atB) {
      if (atA < atB) best = candidate
      continue
    }
    if (candidate.ref < best.ref) best = candidate
  }
  return best?.ref ?? null
}

/** Held titles a person holds right now, among their own people. */
export function heldTitles(snapshot: ProgressionSnapshot, ref: Ref, nowMs: number): TitleId[] {
  const me = canonical(snapshot.options, ref)
  return TITLE_IDS.filter((title) => isHeldTitle(title) && holderOf(snapshot, title, me, nowMs) === me)
}

/** Permanent titles a person has unlocked. Everyone who has played has Fresh Meat. */
export function earnedTitles(snapshot: ProgressionSnapshot, ref: Ref): TitleId[] {
  const record = recordOf(snapshot, ref)
  if (!record) return ['TI-01']
  return TITLE_IDS.filter((title) => {
    const kind = kindOf(title)
    if (kind.kind !== 'earned') return false
    return kind.badge === null || record.badges.has(kind.badge)
  })
}

/** Everything a person may display, in catalog order (the title picker). */
export function availableTitles(snapshot: ProgressionSnapshot, ref: Ref, nowMs: number): TitleId[] {
  const available = new Set([...earnedTitles(snapshot, ref), ...heldTitles(snapshot, ref, nowMs)])
  return TITLE_IDS.filter((title) => available.has(title))
}

export function bestEarnedTitle(snapshot: ProgressionSnapshot, ref: Ref): TitleId | null {
  const earned = earnedTitles(snapshot, ref)
  return earned.reduce<TitleId | null>((best, title) => (best === null || earnedRank(title) > earnedRank(best) ? title : best), null)
}

/** The title to show for a chosen one: a lost held title falls back to the best earned title; unknown or unearned shows nothing. */
export function displayTitle(snapshot: ProgressionSnapshot, ref: Ref, chosen: string | null, nowMs: number): TitleId | null {
  if (!chosen || !isTitleId(chosen)) return null
  if (isHeldTitle(chosen) && !heldTitles(snapshot, ref, nowMs).includes(chosen)) return bestEarnedTitle(snapshot, ref)
  if (!isHeldTitle(chosen) && !earnedTitles(snapshot, ref).includes(chosen)) return null
  return chosen
}
