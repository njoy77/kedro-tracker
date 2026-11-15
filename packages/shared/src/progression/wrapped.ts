// Kedro Wrapped (design §12.9, PRD §5.8): one person's year. A port of the iOS app's
// `Core/Stats/WrappedSummary.swift`. Everything comes from finished, non-abandoned games in the
// calendar year; other people appear only if they shared games; blocked people never.

import type { TauntContent } from '../domain.ts'
import type { Rank } from '../scoring.ts'
import { type BadgeAward } from './badges.ts'
import { canonical, durationMs, refsOf, type Participant, type Ref } from './game.ts'
import type { KnockEvent } from './record.ts'
import { shameEntriesOf, type ShameEntry } from './shame.ts'
import { circleOf, nameOf, recordOf, resultsIn, yearOf, type ProgressionSnapshot, type RatingPoint } from './snapshot.ts'
import { heldTitles, titleUnlockedBy, TITLE_IDS, type TitleId } from './titles.ts'

export const WRAPPED_MINIMUM_GAMES = 10

export const WRAPPED_PERSONAS = ['menace', 'closer', 'gambler', 'snake', 'comeback', 'accountant', 'regular', 'wildcard'] as const
export type WrappedPersona = (typeof WRAPPED_PERSONAS)[number]

export const PERSONA_COPY: Record<WrappedPersona, { copyId: string; name: string }> = {
  gambler: { copyId: 'WR-15', name: 'The Gambler' },
  snake: { copyId: 'WR-16', name: 'The Snake' },
  accountant: { copyId: 'WR-17', name: 'The Accountant' },
  menace: { copyId: 'WR-18', name: 'The Menace' },
  closer: { copyId: 'WR-19', name: 'The Closer' },
  comeback: { copyId: 'WR-20', name: 'The Comeback' },
  regular: { copyId: 'WR-21', name: 'The Regular' },
  wildcard: { copyId: 'WR-22', name: 'The Wildcard' },
}

export type WrappedPerson = { ref: Ref; name: string; count: number }

export type WrappedAvailability =
  | { kind: 'available' }
  | { kind: 'needsGames'; played: number; needed: number }
  | { kind: 'arrives'; atMs: number }

export type WrappedSummary = {
  year: number
  player: Ref
  identity: Participant
  games: number
  rounds: number
  hours: number
  people: number
  wins: number
  winRate: number
  /** Finishing position → games. */
  finishes: Record<number, number>
  isWinRateHigh: boolean
  ratingLine: RatingPoint[]
  ratingStart: number
  ratingPeak: number
  ratingNow: number
  currentRank: Rank | null
  knocks: number
  knockSuccess: number
  favoriteKnockValue: number | null
  bestKnock: KnockEvent | null
  worstKnock: KnockEvent | null
  nemesis: WrappedPerson | null
  victim: WrappedPerson | null
  redKings: number
  ghostHands: number
  biggestHand: number
  tauntsSent: number
  favoriteTaunt: TauntContent | null
  mostTaunted: WrappedPerson | null
  badges: BadgeAward[]
  titles: TitleId[]
  shame: ShameEntry[]
  persona: WrappedPersona
}

/** Midnight at the start of a day in a time zone, as ms since the epoch. */
export function zonedMidnight(year: number, month: number, day: number, timeZone: string): number {
  const guess = Date.UTC(year, month - 1, day)
  const offset = (ms: number) => {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit',
    }).formatToParts(new Date(ms))
    const get = (type: string) => Number(parts.find((part) => part.type === type)?.value)
    return Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second')) - ms
  }
  const first = guess - offset(guess)
  return guess - offset(first)
}

/** Wrapped for a year arrives on December 1 of that year. */
export function wrappedRelease(snapshot: ProgressionSnapshot, year: number): number {
  return zonedMidnight(year, 12, 1, snapshot.options.timeZone)
}

export function wrappedAvailability(snapshot: ProgressionSnapshot, ref: Ref, year: number, nowMs: number): WrappedAvailability {
  const record = recordOf(snapshot, ref)
  const played = record ? resultsIn(snapshot, record, year).length : 0
  if (played < WRAPPED_MINIMUM_GAMES) return { kind: 'needsGames', played, needed: WRAPPED_MINIMUM_GAMES }
  const release = wrappedRelease(snapshot, year)
  return nowMs >= release ? { kind: 'available' } : { kind: 'arrives', atMs: release }
}

/** The Wrapped a person should see now: this year's from December 1, otherwise last year's. */
export function currentWrappedYear(snapshot: ProgressionSnapshot, ref: Ref, nowMs: number): number | null {
  const year = yearOf(snapshot, nowMs)
  for (const candidate of [year, year - 1]) if (wrappedAvailability(snapshot, ref, candidate, nowMs).kind === 'available') return candidate
  return null
}

function maxBy<T>(items: readonly T[], better: (a: T, b: T) => boolean): T | null {
  let best: T | null = null
  for (const item of items) if (best === null || better(item, best)) best = item
  return best
}

/**
 * Builds a year's recap; null with fewer than 10 games that year. The release date is the
 * caller's to enforce. `currentRank` is the person's rank on the global board, when ranked.
 */
export function buildWrapped(snapshot: ProgressionSnapshot, ref: Ref, year: number, { nowMs, currentRank = null }: { nowMs: number; currentRank?: Rank | null }): WrappedSummary | null {
  const me = canonical(snapshot.options, ref)
  const record = recordOf(snapshot, me)
  if (!record) return null
  const results = resultsIn(snapshot, record, year)
  if (results.length < WRAPPED_MINIMUM_GAMES) return null
  const indices = new Set(results.map((result) => result.gameIndex))
  const yearGames = snapshot.games.filter((game) => indices.has(game.index))
  const knocks = record.knockEvents.filter((event) => indices.has(event.gameIndex))
  const excluded = snapshot.options.excluded

  // Volume
  const people = new Set(yearGames.flatMap(refsOf).filter((other) => other !== me && !excluded.has(other)))
  const hours = yearGames.reduce((total, game) => total + durationMs(game), 0) / 3_600_000

  // Record
  const wins = results.filter((result) => result.isWinner).length
  const winRate = wins / results.length
  const evenShare = results.reduce((total, result) => total + 1 / Math.max(1, result.playerCount), 0) / results.length
  const finishes: Record<number, number> = {}
  for (const result of results) finishes[result.rank.position] = (finishes[result.rank.position] ?? 0) + 1

  // Rating: the journey starts an hour before the year's first game.
  const first = results[0]
  const line: RatingPoint[] = [
    { gameIndex: first.gameIndex - 1, dateMs: first.dateMs - 3_600_000, rating: first.ratingBefore },
    ...results.map((result) => ({ gameIndex: result.gameIndex, dateMs: result.dateMs, rating: result.ratingAfter })),
  ]
  const peak = Math.max(...line.map((point) => point.rating))

  // Knocks
  const landed = knocks.filter((event) => event.outcome === 'landed').length
  const byHand = new Map<number, number>()
  for (const event of knocks) byHand.set(event.hand, (byHand.get(event.hand) ?? 0) + 1)
  const favorite = maxBy([...byHand], (a, b) => a[1] > b[1] || (a[1] === b[1] && a[0] < b[0]))?.[0] ?? null
  const best = maxBy(knocks.filter((event) => event.outcome === 'landed'), (a, b) => a.hand > b.hand || (a.hand === b.hand && a.gameIndex < b.gameIndex))
  const gap = (event: KnockEvent) => event.hand - (event.lowestOther ?? event.hand)
  const worst = maxBy(knocks.filter((event) => event.outcome === 'failed'), (a, b) => gap(a) > gap(b) || (gap(a) === gap(b) && a.gameIndex < b.gameIndex))

  // Nemesis and victim within the year
  const aheadOfMe = new Map<Ref, number>(), iWasAhead = new Map<Ref, number>()
  for (const game of yearGames) {
    const mine = game.totals.get(me) ?? 0
    for (const other of refsOf(game)) {
      if (other === me || excluded.has(other)) continue
      const theirs = game.totals.get(other) ?? 0
      if (theirs < mine) aheadOfMe.set(other, (aheadOfMe.get(other) ?? 0) + 1)
      if (mine < theirs) iWasAhead.set(other, (iWasAhead.get(other) ?? 0) + 1)
    }
  }
  const top = (counts: Map<Ref, number>): WrappedPerson | null => {
    const winner = maxBy([...counts], (a, b) => a[1] > b[1] || (a[1] === b[1] && a[0] < b[0]))
    return winner ? { ref: winner[0], name: nameOf(snapshot, winner[0]), count: winner[1] } : null
  }

  // The mouth
  const myTaunts = yearGames.flatMap((game) => game.taunts).filter((taunt) => taunt.from === me)
  const tauntCounts = new Map<string, { content: TauntContent; count: number; first: number }>()
  myTaunts.forEach((taunt, index) => {
    const key = JSON.stringify(taunt.content)
    const existing = tauntCounts.get(key)
    tauntCounts.set(key, existing ? { ...existing, count: existing.count + 1 } : { content: taunt.content, count: 1, first: index })
  })
  const favoriteTaunt = maxBy([...tauntCounts.values()], (a, b) => a.count > b.count || (a.count === b.count && a.first < b.first))?.content ?? null
  const targets = new Map<Ref, number>()
  for (const taunt of myTaunts) if (taunt.target && !excluded.has(taunt.target)) targets.set(taunt.target, (targets.get(taunt.target) ?? 0) + 1)

  // Badges and titles this year
  const badges = [...record.badges.values()]
    .filter((award) => award.dateMs !== null && yearOf(snapshot, award.dateMs) === year)
    .sort((a, b) => (a.gameIndex ?? 0) - (b.gameIndex ?? 0) || (a.badge < b.badge ? -1 : a.badge > b.badge ? 1 : 0))
  const unlocked = badges.flatMap((award) => titleUnlockedBy(award.badge) ?? [])
  const titleSet = new Set([...unlocked, ...heldTitles(snapshot, me, nowMs)])
  const titles = TITLE_IDS.filter((title) => titleSet.has(title))

  const shame = shameEntriesOf(snapshot, me, me).filter((entry) => yearOf(snapshot, entry.dateMs) === year)
  const last = line.at(-1) ?? line[0]

  return {
    year, player: me, identity: record.identity,
    games: results.length, rounds: results.reduce((total, result) => total + result.roundsPlayed, 0), hours, people: people.size,
    wins, winRate, finishes, isWinRateHigh: winRate >= evenShare,
    ratingLine: line, ratingStart: Math.round(line[0].rating), ratingPeak: Math.round(peak), ratingNow: Math.round(last.rating),
    currentRank,
    knocks: knocks.length, knockSuccess: knocks.length === 0 ? 0 : landed / knocks.length,
    favoriteKnockValue: favorite, bestKnock: best, worstKnock: worst,
    nemesis: top(aheadOfMe), victim: top(iWasAhead),
    redKings: results.reduce((total, result) => total + result.redKings, 0),
    ghostHands: results.reduce((total, result) => total + result.ghostHands, 0),
    biggestHand: Math.max(0, ...results.map((result) => result.biggestHand)),
    tauntsSent: myTaunts.length, favoriteTaunt, mostTaunted: top(targets),
    badges, titles, shame,
    persona: personaFor(snapshot, me, year),
  }
}

/** One of 8 archetypes: the first one the person tops among their people that year. */
export function personaFor(snapshot: ProgressionSnapshot, ref: Ref, year: number): WrappedPersona {
  const me = canonical(snapshot.options, ref)
  type YearLine = { games: number; rounds: number; roundScore: number; knocks: number; landed: number; beaten: number; taunts: number; comebacks: number }
  const lines = new Map<Ref, YearLine>()
  for (const person of circleOf(snapshot, me)) {
    const record = snapshot.records.get(person)
    if (!record) continue
    const results = resultsIn(snapshot, record, year)
    if (results.length < 5) continue
    const indices = new Set(results.map((result) => result.gameIndex))
    const knocks = record.knockEvents.filter((event) => indices.has(event.gameIndex))
    const sum = (pick: (result: (typeof results)[number]) => number) => results.reduce((total, result) => total + pick(result), 0)
    lines.set(person, {
      games: results.length, rounds: sum((result) => result.roundsPlayed), roundScore: sum((result) => result.roundScoreSum),
      knocks: knocks.length, landed: knocks.filter((event) => event.outcome === 'landed').length,
      beaten: sum((result) => result.knocksBeaten), taunts: sum((result) => result.tauntsSent),
      comebacks: results.filter((result) => result.isComeback).length,
    })
  }
  const mine = lines.get(me)
  if (!mine || lines.size < 2) return mine ? 'regular' : 'wildcard'

  const tops = (metric: (line: YearLine) => number, minimum: number, { higher = true, eligible = (_: YearLine): boolean => true }: { higher?: boolean; eligible?: (line: YearLine) => boolean } = {}) => {
    const pool = [...lines.values()].filter(eligible)
    if (!eligible(mine) || !(metric(mine) >= minimum || !higher)) return false
    if (pool.length === 0) return false
    const values = pool.map(metric)
    const best = higher ? Math.max(...values) : Math.min(...values)
    return metric(mine) === best
  }
  if (tops((line) => line.taunts, 10)) return 'menace'
  if (tops((line) => (line.knocks > 0 ? line.landed / line.knocks : 0), 0.5, { eligible: (line) => line.knocks >= 10 })) return 'closer'
  if (tops((line) => (line.rounds > 0 ? line.knocks / line.rounds : 0), 0.2)) return 'gambler'
  if (tops((line) => line.beaten, 5)) return 'snake'
  if (tops((line) => line.comebacks, 2)) return 'comeback'
  if (tops((line) => (line.rounds > 0 ? line.roundScore / line.rounds : Number.POSITIVE_INFINITY), 0, { higher: false })) return 'accountant'
  if (tops((line) => line.games, 10)) return 'regular'
  return 'wildcard'
}
