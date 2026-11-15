// One person's replayed history. A port of the iOS app's `Core/Stats/PlayerRecord.swift`.

import { RATING_REVEAL_GAMES } from '../ratings.ts'
import type { UUID } from '../ids.ts'
import type { KnockOutcome, Rank } from '../scoring.ts'
import { isGuestRef, type Participant, type Ref } from './game.ts'
import type { BadgeAward, BadgeId } from './badges.ts'

export const RATING_START_VALUE = 1000

/** One person's part in one finished game. */
export type PlayerGameResult = {
  gameId: UUID
  gameIndex: number
  dateMs: number
  tableWord: string
  playerCount: number
  finalScore: number
  rank: Rank
  isWinner: boolean
  isSharedWin: boolean
  roundsPlayed: number
  roundScoreSum: number
  knocks: number
  landed: number
  tied: number
  failed: number
  /** Rounds where this player had a lower hand than a beaten knocker (The Snake). */
  knocksBeaten: number
  inherentKnocks: number
  inherentKnocksLanded: number
  redKings: number
  ghostHands: number
  biggestHand: number
  /** Won from outside the lead at the halfway round. */
  isComeback: boolean
  /** Sole leader after the second-to-last round, then didn't win. */
  bottledFinalRound: boolean
  biggestLead: number
  deepestDeficit: number
  ratingBefore: number
  ratingAfter: number
  tauntsSent: number
  /** Taunts that count for Trash Talker (3 a game). */
  tauntsCounted: number
  /** Games played before this one. */
  gamesBefore: number
  neighs: number
}

/** The visible rating change: rounded after minus rounded before. */
export function ratingDelta(result: PlayerGameResult): number {
  return Math.round(result.ratingAfter) - Math.round(result.ratingBefore)
}

export type KnockEvent = {
  gameId: UUID
  gameIndex: number
  dateMs: number
  tableWord: string
  roundNumber: number
  hand: number
  lowestOther: number | null
  outcome: KnockOutcome
}

export const HELD_METRICS = ['knockSuccess', 'knockRate', 'knocksBeaten', 'averageRound', 'redKingsThisYear', 'rating', 'bottledThisYear'] as const
export type HeldMetric = (typeof HELD_METRICS)[number]

export type PlayerRecord = {
  ref: Ref
  /** The latest name and title seen at a table. */
  identity: Participant
  /** Oldest first. */
  results: PlayerGameResult[]
  knockEvents: KnockEvent[]
  finishedAheadOfMe: Map<Ref, number>
  finishedAheadOfMeAt: Map<Ref, number>
  iFinishedAhead: Map<Ref, number>
  iFinishedAheadAt: Map<Ref, number>
  sharedGames: Map<Ref, number>
  /** Consecutive shared games finishing ahead of each opponent (Exorcism). */
  aheadStreak: Map<Ref, number>
  rating: number
  currentWinStreak: number
  longestWinStreak: number
  currentLandedStreak: number
  longestLandedStreak: number
  badges: Map<BadgeId, BadgeAward>
  metricChangedAt: Map<HeldMetric, number>
  /** People who sat with this player while they were still a guest identity (Bad Influence). */
  guestEraCompanions: Set<Ref>
}

export function newRecord(ref: Ref, identity: Participant): PlayerRecord {
  return {
    ref,
    identity,
    results: [],
    knockEvents: [],
    finishedAheadOfMe: new Map(),
    finishedAheadOfMeAt: new Map(),
    iFinishedAhead: new Map(),
    iFinishedAheadAt: new Map(),
    sharedGames: new Map(),
    aheadStreak: new Map(),
    rating: RATING_START_VALUE,
    currentWinStreak: 0,
    longestWinStreak: 0,
    currentLandedStreak: 0,
    longestLandedStreak: 0,
    badges: new Map(),
    metricChangedAt: new Map(),
    guestEraCompanions: new Set(),
  }
}

const sum = (results: readonly PlayerGameResult[], pick: (result: PlayerGameResult) => number) => results.reduce((total, result) => total + pick(result), 0)

export const gamesPlayed = (record: PlayerRecord) => record.results.length
export const wins = (record: PlayerRecord) => record.results.filter((result) => result.isWinner).length
export const roundsPlayedOf = (record: PlayerRecord) => sum(record.results, (result) => result.roundsPlayed)
export const knocksOf = (record: PlayerRecord) => record.knockEvents.length
export const landedOf = (record: PlayerRecord) => record.knockEvents.filter((event) => event.outcome === 'landed').length
export const tiedOf = (record: PlayerRecord) => record.knockEvents.filter((event) => event.outcome === 'tied').length
export const failedOf = (record: PlayerRecord) => record.knockEvents.filter((event) => event.outcome === 'failed').length
export const knocksBeatenOf = (record: PlayerRecord) => sum(record.results, (result) => result.knocksBeaten)
export const tauntsCountedOf = (record: PlayerRecord) => sum(record.results, (result) => result.tauntsCounted)
export const neighsOf = (record: PlayerRecord) => sum(record.results, (result) => result.neighs)

export const isRanked = (record: PlayerRecord) => gamesPlayed(record) >= RATING_REVEAL_GAMES
export const isGuestRecord = (record: PlayerRecord) => isGuestRef(record.ref)

export function averageRoundScore(record: PlayerRecord): number | null {
  const rounds = roundsPlayedOf(record)
  return rounds > 0 ? sum(record.results, (result) => result.roundScoreSum) / rounds : null
}

export function knockRate(record: PlayerRecord): number | null {
  const rounds = roundsPlayedOf(record)
  return rounds > 0 ? knocksOf(record) / rounds : null
}

export function knockSuccessRate(record: PlayerRecord): number | null {
  const knocks = knocksOf(record)
  return knocks > 0 ? landedOf(record) / knocks : null
}

/** Accounts and claimed guests this player has shared a table with (anti-farming). */
export function accountOpponents(record: PlayerRecord): Ref[] {
  return [...record.sharedGames.keys()].filter((ref) => !isGuestRef(ref))
}

function topOpponent(counts: Map<Ref, number>, at: Map<Ref, number>, keep: (ref: Ref) => boolean): { ref: Ref; count: number } | null {
  let best: { ref: Ref; count: number } | null = null
  for (const [ref, count] of counts) {
    if (count <= 0 || !keep(ref)) continue
    if (!best) {
      best = { ref, count }
      continue
    }
    const left = at.get(ref) ?? Number.MAX_SAFE_INTEGER
    const right = at.get(best.ref) ?? Number.MAX_SAFE_INTEGER
    if (count > best.count || (count === best.count && (left < right || (left === right && ref < best.ref)))) best = { ref, count }
  }
  return best
}

/** The opponent who has finished ahead most often; ties go to whoever got there first. */
export function nemesisOf(record: PlayerRecord, { accountsOnly = false, excluded = new Set<Ref>() }: { accountsOnly?: boolean; excluded?: ReadonlySet<Ref> } = {}) {
  return topOpponent(record.finishedAheadOfMe, record.finishedAheadOfMeAt, (ref) => !excluded.has(ref) && (!accountsOnly || !isGuestRef(ref)))
}

/** The opponent this player has finished ahead of most often. */
export function victimOf(record: PlayerRecord, excluded: ReadonlySet<Ref> = new Set()) {
  return topOpponent(record.iFinishedAhead, record.iFinishedAheadAt, (ref) => !excluded.has(ref))
}
