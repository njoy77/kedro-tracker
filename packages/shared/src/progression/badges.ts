// Badges (design §12.6). A port of the iOS app's `Core/Stats/BadgeCatalog.swift` and
// `BadgeEvaluator.swift`; keep them in step. IDs are the copy deck IDs (BG-01…BG-34).

import { RATING_REVEAL_GAMES } from '../ratings.ts'
import type { UUID } from '../ids.ts'
import { containsRef, isGuestRef, leadersAfter, refsOf, regularKnocker, type Ref, type StatsGame } from './game.ts'
import {
  accountOpponents,
  gamesPlayed,
  isGuestRecord,
  isRanked,
  RATING_START_VALUE,
  tauntsCountedOf,
  wins,
  type PlayerRecord,
} from './record.ts'

export const BADGE_TIERS = ['none', 'silver', 'red', 'gold'] as const
export type BadgeTier = (typeof BADGE_TIERS)[number]
export const BADGE_CATEGORIES = ['milestone', 'knocking', 'cards', 'streaks', 'moments', 'rivalry', 'social', 'learning'] as const
export type BadgeCategory = (typeof BADGE_CATEGORIES)[number]

export type BadgeDefinition = {
  id: BadgeId
  name: string
  category: BadgeCategory
  tier: BadgeTier
  /** The literal rule ("win 3 in a row"). */
  rule: string
  /** Secret badges show as "?" until earned. */
  isSecret: boolean
  /** For counting badges: the target. */
  target: number | null
}

const make = (id: string, name: string, category: BadgeCategory, tier: BadgeTier, rule: string, { secret = false, target = null as number | null } = {}) =>
  ({ id, name, category, tier, rule, isSecret: secret, target }) as const

/** All 34, in design order. */
export const BADGES = [
  make('BG-01', 'Out of the Gate', 'milestone', 'silver', 'finish your first game', { target: 1 }),
  make('BG-02', 'First Blood', 'milestone', 'silver', 'win a game', { target: 1 }),
  make('BG-03', 'On the Board', 'milestone', 'silver', `finish ${RATING_REVEAL_GAMES} games and get a rank`, { target: RATING_REVEAL_GAMES }),
  make('BG-04', 'Regular', 'milestone', 'red', 'finish 25 games', { target: 25 }),
  make('BG-05', 'Touch Grass', 'milestone', 'gold', 'finish 100 games', { target: 100 }),
  make('BG-06', 'Top Dog', 'milestone', 'gold', '#1 by rating among your people (5+ ranked)'),
  make('BG-07', 'Top 100', 'milestone', 'gold', 'global top 100 by rating'),
  make('BG-08', 'Landed It', 'knocking', 'silver', 'land a knock'),
  make('BG-09', 'Found Out', 'knocking', 'silver', 'fail a knock'),
  make('BG-10', 'Dead Heat', 'knocking', 'silver', 'tie a knock'),
  make('BG-11', 'Bold Choice', 'knocking', 'silver', 'knock on 10 or more and fail'),
  make('BG-12', 'Hat Trick', 'knocking', 'red', 'land 3 knocks in one game', { target: 3 }),
  make('BG-13', 'Steady Hand', 'knocking', 'gold', 'land 10 knocks in a row', { target: 10 }),
  make('BG-14', 'Below Zero', 'cards', 'red', 'finish a round with a negative hand'),
  make('BG-15', 'Ghost Hand', 'cards', 'red', 'a hand of exactly 0'),
  make('BG-16', 'Royal Pair', 'cards', 'gold', 'both red Kings in one hand'),
  make('BG-17', 'Nothing to See Here', 'cards', 'gold', 'land a knock on exactly 0', { secret: true }),
  make('BG-18', 'Fat Stack', 'cards', 'silver', 'a hand of 40 or more'),
  make('BG-19', 'Three-Peat', 'streaks', 'red', 'win 3 in a row', { target: 3 }),
  make('BG-20', 'Untouchable', 'streaks', 'gold', 'win 5 in a row', { target: 5 }),
  make('BG-21', 'Comeback Kid', 'moments', 'red', 'win from outside the lead at halfway'),
  make('BG-22', 'Dark Horse', 'moments', 'gold', 'win against a table all rated higher'),
  make('BG-23', 'Never Trailed', 'moments', 'gold', 'lead after every round of a 6+ round game, and win'),
  make('BG-24', 'By a Hair', 'moments', 'red', 'win by exactly 1 point'),
  make('BG-25', 'Shared Spoils', 'moments', 'red', 'share a win'),
  make('BG-26', 'Bottled It', 'moments', 'red', 'lead into the final round, then lose', { secret: true }),
  make('BG-27', 'Nemesis Tamed', 'rivalry', 'silver', 'finish ahead of your nemesis'),
  make('BG-28', 'Grudge Match', 'rivalry', 'red', 'play the same rival 10 times', { target: 10 }),
  make('BG-29', 'Exorcism', 'rivalry', 'gold', 'finish ahead of your nemesis 3 straight times', { secret: true }),
  make('BG-30', 'Plays Well With Others', 'social', 'silver', 'play with 10 different people', { target: 10 }),
  make('BG-31', 'Full House', 'social', 'red', 'finish an 8-player game'),
  make('BG-32', 'Bad Influence', 'social', 'red', 'a guest you played with makes an account and plays'),
  make('BG-33', 'Trash Talker', 'social', 'silver', 'send 50 taunts (3 a game count)', { target: 50 }),
  make('BG-34', 'Did the Reading', 'learning', 'none', 'finish Learn and the Score a Round drill'),
] as const

export type BadgeId = (typeof BADGES)[number]['id']
export const BADGE_IDS: readonly BadgeId[] = BADGES.map((badge) => badge.id)
const CATALOG = new Map<string, BadgeDefinition>(BADGES.map((badge) => [badge.id, badge as BadgeDefinition]))

export function badgeDefinition(id: BadgeId): BadgeDefinition {
  return CATALOG.get(id) as BadgeDefinition
}

export const BADGE = {
  outOfTheGate: 'BG-01', firstBlood: 'BG-02', onTheBoard: 'BG-03', regular: 'BG-04', touchGrass: 'BG-05',
  topDog: 'BG-06', top100: 'BG-07', landedIt: 'BG-08', foundOut: 'BG-09', deadHeat: 'BG-10', boldChoice: 'BG-11',
  hatTrick: 'BG-12', steadyHand: 'BG-13', belowZero: 'BG-14', ghostHand: 'BG-15', royalPair: 'BG-16',
  nothingToSeeHere: 'BG-17', fatStack: 'BG-18', threePeat: 'BG-19', untouchable: 'BG-20', comebackKid: 'BG-21',
  darkHorse: 'BG-22', neverTrailed: 'BG-23', byAHair: 'BG-24', sharedSpoils: 'BG-25', bottledIt: 'BG-26',
  nemesisTamed: 'BG-27', grudgeMatch: 'BG-28', exorcism: 'BG-29', playsWellWithOthers: 'BG-30', fullHouse: 'BG-31',
  badInfluence: 'BG-32', trashTalker: 'BG-33', didTheReading: 'BG-34',
} as const satisfies Record<string, BadgeId>

/** A badge someone has, and the game that earned it. */
export type BadgeAward = {
  badge: BadgeId
  /** null for Did the Reading (not earned at a table). */
  gameId: UUID | null
  tableWord: string | null
  roundNumber: number | null
  dateMs: number | null
  gameIndex: number | null
}

/** Progress toward an unearned counting badge (Next up). */
export type BadgeProgress = { badge: BadgeId; value: number; target: number }

export function progressFraction(progress: BadgeProgress): number {
  return progress.target > 0 ? Math.min(1, progress.value / progress.target) : 0
}

/** Top 100 needs a real global board: never awarded with fewer ranked players than this. */
export const TOP_100_MINIMUM_BOARD = 101

/** Badges a person qualifies for after a game (already-earned ones are left out). */
export function evaluateBadges(
  me: Ref,
  game: StatsGame,
  records: ReadonlyMap<Ref, PlayerRecord>,
  ratingsBefore: ReadonlyMap<Ref, number>,
  nemesisBefore: Ref | null,
): BadgeAward[] {
  const record = records.get(me)
  const result = record?.results.at(-1)
  if (!record || !result || result.gameId !== game.id) return []
  const awards: BadgeAward[] = []
  const award = (badge: BadgeId, round: number | null = null) => {
    if (record.badges.has(badge) || awards.some((existing) => existing.badge === badge)) return
    awards.push({ badge, gameId: game.id, tableWord: game.tableWord, roundNumber: round, dateMs: game.finishedAtMs, gameIndex: game.index })
  }

  // Milestones
  if (gamesPlayed(record) >= 1) award(BADGE.outOfTheGate)
  if (wins(record) >= 1) award(BADGE.firstBlood)
  if (gamesPlayed(record) >= RATING_REVEAL_GAMES) award(BADGE.onTheBoard)
  if (gamesPlayed(record) >= 25) award(BADGE.regular)
  if (gamesPlayed(record) >= 100) award(BADGE.touchGrass)
  if (isTopDog(me, records)) award(BADGE.topDog)
  if (isTop100(me, records)) award(BADGE.top100)

  // Knocking and cards, round by round
  let landedSoFar = 0
  let streak = preGameLandedStreak(record, game.id)
  for (const round of game.rounds) {
    const hand = round.hands.get(me)
    if (hand === undefined) continue
    if (regularKnocker(round) === me && round.outcome) {
      switch (round.outcome) {
        case 'landed':
          award(BADGE.landedIt, round.number)
          landedSoFar += 1
          streak += 1
          if (landedSoFar >= 3) award(BADGE.hatTrick, round.number)
          if (streak >= 10) award(BADGE.steadyHand, round.number)
          if (hand === 0) award(BADGE.nothingToSeeHere, round.number)
          break
        case 'tied':
          award(BADGE.deadHeat, round.number)
          streak = 0
          break
        case 'failed':
          award(BADGE.foundOut, round.number)
          if (hand >= 10) award(BADGE.boldChoice, round.number)
          streak = 0
          break
        case 'noPenalty':
          break
      }
    }
    if (hand < 0) award(BADGE.belowZero, round.number)
    if (hand === 0) award(BADGE.ghostHand, round.number)
    if (hand <= -2) award(BADGE.royalPair, round.number)
    if (hand >= 40) award(BADGE.fatStack, round.number)
  }

  // Streaks
  if (record.currentWinStreak >= 3) award(BADGE.threePeat)
  if (record.currentWinStreak >= 5) award(BADGE.untouchable)

  // Moments
  if (result.isWinner) {
    if (result.isComeback) award(BADGE.comebackKid)
    const mine = ratingsBefore.get(me) ?? RATING_START_VALUE
    const opponents = refsOf(game).filter((ref) => ref !== me)
    if (opponents.length > 0 && opponents.every((ref) => (ratingsBefore.get(ref) ?? RATING_START_VALUE) > mine)) award(BADGE.darkHorse)
    if (game.rounds.length >= 6) {
      let ledEvery = true
      for (let round = 1; round <= game.rounds.length; round++) if (!leadersAfter(game, round).has(me)) ledEvery = false
      if (ledEvery) award(BADGE.neverTrailed)
    }
    if (game.winners.size === 1) {
      let second: number | null = null
      for (const [ref, total] of game.totals) if (ref !== me) second = second === null ? total : Math.min(second, total)
      if (second !== null && second - result.finalScore === 1) award(BADGE.byAHair)
    } else {
      award(BADGE.sharedSpoils)
    }
  }
  if (result.bottledFinalRound) award(BADGE.bottledIt)

  // Rivalry (accounts and claimed guests only)
  if (nemesisBefore && containsRef(game, nemesisBefore)) {
    const theirs = game.totals.get(nemesisBefore) ?? Number.MAX_SAFE_INTEGER
    if (result.finalScore < theirs) award(BADGE.nemesisTamed)
    if ((record.aheadStreak.get(nemesisBefore) ?? 0) >= 3) award(BADGE.exorcism)
  }
  for (const [ref, count] of record.sharedGames) {
    if (!isGuestRef(ref) && count >= 10) {
      award(BADGE.grudgeMatch)
      break
    }
  }

  // Social
  if (accountOpponents(record).length >= 10) award(BADGE.playsWellWithOthers)
  if (game.participants.length >= 8) award(BADGE.fullHouse)
  if (tauntsCountedOf(record) >= 50) award(BADGE.trashTalker)

  return awards
}

/** The landed-knock streak going into a game (knocks are appended in replay order). */
function preGameLandedStreak(record: PlayerRecord, gameId: UUID): number {
  const firstOfGame = record.knockEvents.findIndex((event) => event.gameId === gameId)
  const before = firstOfGame === -1 ? record.knockEvents : record.knockEvents.slice(0, firstOfGame)
  let streak = 0
  for (let i = before.length - 1; i >= 0 && before[i].outcome === 'landed'; i--) streak += 1
  return streak
}

/**
 * Bad Influence: someone who played with a person while that person was a guest gets the badge
 * when the guest, having claimed their history, finishes a game on their own account with at
 * least one other person in it.
 */
export function badInfluenceAwards(game: StatsGame, records: ReadonlyMap<Ref, PlayerRecord>): [Ref, BadgeAward][] {
  const awards: [Ref, BadgeAward][] = []
  for (const participant of game.participants) {
    if (isGuestRef(participant.seatedAs)) continue
    const claimed = records.get(participant.ref)
    if (!claimed || claimed.guestEraCompanions.size === 0) continue
    for (const influencer of [...claimed.guestEraCompanions].sort()) {
      if (isGuestRef(influencer)) continue
      const someoneElse = refsOf(game).some((ref) => ref !== influencer && ref !== participant.ref)
      if (!someoneElse || !records.has(influencer)) continue
      awards.push([influencer, { badge: BADGE.badInfluence, gameId: game.id, tableWord: game.tableWord, roundNumber: null, dateMs: game.finishedAtMs, gameIndex: game.index }])
    }
  }
  return awards
}

/** #1 by rating among the person's people, with at least 5 ranked people (them included). */
export function isTopDog(me: Ref, records: ReadonlyMap<Ref, PlayerRecord>): boolean {
  const record = records.get(me)
  if (!record || !isRanked(record)) return false
  const people = [me, ...[...record.sharedGames.keys()].filter((ref) => !isGuestRef(ref))]
  const ranked = people.flatMap((ref) => records.get(ref) ?? []).filter(isRanked)
  if (ranked.length < 5) return false
  return ranked.every((other) => other.ref === me || other.rating < record.rating)
}

export function isTop100(me: Ref, records: ReadonlyMap<Ref, PlayerRecord>): boolean {
  const record = records.get(me)
  if (!record || !isRanked(record) || isGuestRef(me)) return false
  const ranked = [...records.values()].filter((other) => isRanked(other) && !isGuestRecord(other))
  if (ranked.length < TOP_100_MINIMUM_BOARD) return false
  return ranked.filter((other) => other.rating > record.rating).length < 100
}

/** Progress toward each unearned counting badge, closest first. */
export function badgeProgress(record: PlayerRecord): BadgeProgress[] {
  const bestLandedInGame = Math.max(0, ...record.results.map((result) => result.landed))
  const grudge = Math.max(0, ...[...record.sharedGames].filter(([ref]) => !isGuestRef(ref)).map(([, count]) => count))
  const values: [BadgeId, number][] = [
    [BADGE.outOfTheGate, gamesPlayed(record)], [BADGE.firstBlood, wins(record)], [BADGE.onTheBoard, gamesPlayed(record)],
    [BADGE.regular, gamesPlayed(record)], [BADGE.touchGrass, gamesPlayed(record)],
    [BADGE.hatTrick, bestLandedInGame], [BADGE.steadyHand, record.currentLandedStreak],
    [BADGE.threePeat, record.currentWinStreak], [BADGE.untouchable, record.currentWinStreak],
    [BADGE.grudgeMatch, grudge], [BADGE.playsWellWithOthers, accountOpponents(record).length],
    [BADGE.trashTalker, tauntsCountedOf(record)],
  ]
  const order = new Map(BADGE_IDS.map((id, index) => [id, index]))
  return values
    .filter(([badge]) => !record.badges.has(badge))
    .flatMap(([badge, value]) => {
      const target = badgeDefinition(badge).target
      return target === null ? [] : [{ badge, value, target }]
    })
    .sort((a, b) => {
      const fa = progressFraction(a), fb = progressFraction(b)
      if (fa !== fb) return fb - fa
      const ra = Math.max(0, a.target - a.value), rb = Math.max(0, b.target - b.value)
      if (ra !== rb) return ra - rb
      return (order.get(a.badge) ?? 0) - (order.get(b.badge) ?? 0)
    })
}
