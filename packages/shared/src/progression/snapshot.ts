// Every badge, title, Hall of Shame entry and Wrapped number, derived by replaying finished games
// in order (PRD §5: derived, never stored). A port of the iOS app's `Core/Stats/StatsSnapshot.swift`
// and `Ratings.swift`; the same games give the same results on the phone and the server.

import type { FoldedGame } from '../fold.ts'
import type { UUID } from '../ids.ts'
import { badInfluenceAwards, BADGE, evaluateBadges, type BadgeAward } from './badges.ts'
import {
  canonical,
  leadersAfter,
  normalizeGames,
  redKingsInHand,
  refsOf,
  regularKnocker,
  knockerHand,
  lowestOtherHand,
  resolveOptions,
  isInherentKnockRound,
  isGuestRef,
  type Participant,
  type ProgressionOptions,
  type Ref,
  type ResolvedOptions,
  type StatsGame,
} from './game.ts'
import {
  averageRoundScore,
  gamesPlayed,
  knockRate,
  knockSuccessRate,
  knocksBeatenOf,
  nemesisOf,
  newRecord,
  RATING_START_VALUE,
  type HeldMetric,
  type PlayerGameResult,
  type PlayerRecord,
} from './record.ts'

const BASE_K = 32
const PROVISIONAL_GAMES = 10

function kFor(gamesBefore: number): number {
  return gamesBefore < PROVISIONAL_GAMES ? BASE_K * 2 : BASE_K
}

function expected(rating: number, opponent: number): number {
  return 1 / (1 + 10 ** ((opponent - rating) / 400))
}

/** Pairwise Elo deltas in seat order (iOS `Ratings.deltas`): zero-sum, one K per pair. */
export function ratingDeltas(order: readonly Ref[], totals: ReadonlyMap<Ref, number>, ratings: ReadonlyMap<Ref, number>, gamesBefore: ReadonlyMap<Ref, number>): Map<Ref, number> {
  const seen = new Set<Ref>()
  const players = order.filter((ref) => totals.has(ref) && !seen.has(ref) && seen.add(ref))
  const deltas = new Map(players.map((ref) => [ref, 0]))
  if (players.length < 2) return deltas
  const scale = 1 / (players.length - 1)
  for (let a = 0; a < players.length; a++) {
    for (let b = a + 1; b < players.length; b++) {
      const i = players[a], j = players[b]
      const ri = ratings.get(i) ?? RATING_START_VALUE, rj = ratings.get(j) ?? RATING_START_VALUE
      const ti = totals.get(i) ?? 0, tj = totals.get(j) ?? 0
      const actual = ti < tj ? 1 : ti === tj ? 0.5 : 0
      const pairK = Math.max(kFor(gamesBefore.get(i) ?? 0), kFor(gamesBefore.get(j) ?? 0))
      const change = pairK * scale * (actual - expected(ri, rj))
      deltas.set(i, (deltas.get(i) ?? 0) + change)
      deltas.set(j, (deltas.get(j) ?? 0) - change)
    }
  }
  return deltas
}

export type RatingPoint = { gameIndex: number; dateMs: number; rating: number }

export type ProgressionSnapshot = {
  options: ResolvedOptions
  /** Oldest first; `games[i].index === i`. */
  games: StatsGame[]
  records: Map<Ref, PlayerRecord>
  /** Badges earned by game (the game-end card). */
  badgesEarned: Map<UUID, Map<Ref, BadgeAward[]>>
  ratingHistory: Map<Ref, RatingPoint[]>
}

/** Builds a snapshot from folded games (any order; unfinished and uncounted ones are ignored). */
export function buildProgression(states: readonly FoldedGame[], options: ProgressionOptions = {}): ProgressionSnapshot {
  const resolved = resolveOptions(options)
  return replay(normalizeGames(states, resolved), resolved)
}

/** The replay over already-normalized games (re-indexed so prefixes stay consistent). */
export function replay(input: readonly StatsGame[], options: ResolvedOptions): ProgressionSnapshot {
  const games = input.map((game, index) => ({ ...game, index }))
  const records = new Map<Ref, PlayerRecord>()
  const badgesEarned = new Map<UUID, Map<Ref, BadgeAward[]>>()
  const ratingHistory = new Map<Ref, RatingPoint[]>()

  for (const game of games) {
    for (const participant of game.participants) if (!records.has(participant.ref)) records.set(participant.ref, newRecord(participant.ref, participant))
    const refs = refsOf(game)
    const before = new Map(refs.map((ref) => [ref, records.get(ref)?.rating ?? RATING_START_VALUE]))
    const gamesBefore = new Map(refs.map((ref) => [ref, records.get(ref)?.results.length ?? 0]))
    const deltas = ratingDeltas(refs, game.totals, before, gamesBefore)
    const nemesisBefore = new Map(refs.map((ref) => {
      const record = records.get(ref)
      return [ref, record ? (nemesisOf(record, { accountsOnly: true })?.ref ?? null) : null] as const
    }))

    for (const participant of game.participants) {
      const record = records.get(participant.ref)
      if (!record) continue
      const ratingBefore = before.get(participant.ref) ?? RATING_START_VALUE
      const ratingAfter = ratingBefore + (deltas.get(participant.ref) ?? 0)
      apply(game, participant, record, ratingBefore, ratingAfter)
      const history = ratingHistory.get(participant.ref) ?? []
      history.push({ gameIndex: game.index, dateMs: game.finishedAtMs, rating: ratingAfter })
      ratingHistory.set(participant.ref, history)
    }

    const earnedHere = new Map<Ref, BadgeAward[]>()
    const grant = (ref: Ref, award: BadgeAward) => {
      const record = records.get(ref)
      if (!record || record.badges.has(award.badge)) return
      record.badges.set(award.badge, award)
      earnedHere.set(ref, [...(earnedHere.get(ref) ?? []), award])
    }
    for (const ref of refs) {
      for (const award of evaluateBadges(ref, game, records, before, nemesisBefore.get(ref) ?? null)) grant(ref, award)
    }
    for (const [ref, award] of badInfluenceAwards(game, records)) grant(ref, award)
    if (earnedHere.size > 0) badgesEarned.set(game.id, earnedHere)
  }

  for (const reader of options.didTheReading) {
    const record = records.get(canonical(options, reader))
    if (!record || record.badges.has(BADGE.didTheReading)) continue
    record.badges.set(BADGE.didTheReading, { badge: BADGE.didTheReading, gameId: null, tableWord: null, roundNumber: null, dateMs: null, gameIndex: null })
  }

  return { options, games, records, badgesEarned, ratingHistory }
}

/** Folds one game into one person's record. */
function apply(game: StatsGame, participant: Participant, record: PlayerRecord, ratingBefore: number, ratingAfter: number) {
  const me = participant.ref
  const myTotal = game.totals.get(me) ?? 0
  const isWinner = game.winners.has(me)
  const rounds = game.rounds
  const previous = {
    knockSuccess: knockSuccessRate(record),
    knockRate: knockRate(record),
    beaten: knocksBeatenOf(record),
    average: averageRoundScore(record),
    rating: record.rating,
  }

  let knocks = 0, landed = 0, tied = 0, failed = 0, beaten = 0, redKings = 0, ghosts = 0, inherentKnocks = 0, inherentLanded = 0
  let biggestHand: number | null = null, roundsPlayed = 0, roundScoreSum = 0
  for (const round of rounds) {
    const hand = round.hands.get(me)
    if (hand === undefined) continue
    roundsPlayed += 1
    roundScoreSum += round.scores.get(me) ?? hand
    redKings += redKingsInHand(hand)
    if (hand === 0) ghosts += 1
    biggestHand = biggestHand === null ? hand : Math.max(biggestHand, hand)
    if (round.inherent === me) {
      inherentKnocks += 1
      if (isInherentKnockRound(round) && round.outcome === 'landed') inherentLanded += 1
    }
    const knockersHand = knockerHand(round)
    if (regularKnocker(round) === me && round.outcome) {
      knocks += 1
      switch (round.outcome) {
        case 'landed':
          landed += 1
          record.currentLandedStreak += 1
          record.longestLandedStreak = Math.max(record.longestLandedStreak, record.currentLandedStreak)
          break
        case 'tied':
        case 'noPenalty':
          tied += 1
          record.currentLandedStreak = 0
          break
        case 'failed':
          failed += 1
          record.currentLandedStreak = 0
          break
      }
      record.knockEvents.push({
        gameId: game.id, gameIndex: game.index, dateMs: game.finishedAtMs, tableWord: game.tableWord,
        roundNumber: round.number, hand, lowestOther: lowestOtherHand(round), outcome: round.outcome,
      })
    } else if (round.outcome === 'failed' && knockersHand !== null && hand < knockersHand) {
      beaten += 1
    }
  }

  // Leads and holes.
  const half = Math.floor(rounds.length / 2)
  const ledAtHalf = half >= 1 && leadersAfter(game, half).has(me)
  let biggestLead = 0, deepest = 0
  for (const totals of game.cumulative) {
    const mine = totals.get(me)
    if (mine === undefined) continue
    let bestOther: number | null = null, best: number | null = null
    for (const [ref, total] of totals) {
      best = best === null ? total : Math.min(best, total)
      if (ref !== me) bestOther = bestOther === null ? total : Math.min(bestOther, total)
    }
    if (bestOther !== null && mine < bestOther) biggestLead = Math.max(biggestLead, bestOther - mine)
    if (best !== null) deepest = Math.max(deepest, mine - best)
  }
  const leadersBeforeLast = leadersAfter(game, rounds.length - 1)
  const bottled = rounds.length >= 2 && leadersBeforeLast.size === 1 && leadersBeforeLast.has(me) && !isWinner

  const taunts = game.taunts.filter((taunt) => taunt.from === me).length
  const result: PlayerGameResult = {
    gameId: game.id, gameIndex: game.index, dateMs: game.finishedAtMs, tableWord: game.tableWord,
    playerCount: game.participants.length, finalScore: myTotal,
    rank: game.ranks.get(me) ?? { position: game.participants.length, isShared: false },
    isWinner, isSharedWin: isWinner && game.winners.size > 1,
    roundsPlayed, roundScoreSum, knocks, landed, tied, failed, knocksBeaten: beaten,
    inherentKnocks, inherentKnocksLanded: inherentLanded,
    redKings, ghostHands: ghosts, biggestHand: biggestHand ?? 0,
    isComeback: isWinner && half >= 1 && !ledAtHalf, bottledFinalRound: bottled,
    biggestLead, deepestDeficit: deepest, ratingBefore, ratingAfter,
    tauntsSent: taunts, tauntsCounted: Math.min(3, taunts), gamesBefore: gamesPlayed(record),
    neighs: game.neighs.get(me) ?? 0,
  }
  record.results.push(result)
  record.identity = participant
  record.rating = ratingAfter

  if (isWinner) {
    record.currentWinStreak += 1
    record.longestWinStreak = Math.max(record.longestWinStreak, record.currentWinStreak)
  } else {
    record.currentWinStreak = 0
  }

  for (const other of game.participants) {
    const them = other.ref
    if (them === me) continue
    const theirTotal = game.totals.get(them) ?? 0
    record.sharedGames.set(them, (record.sharedGames.get(them) ?? 0) + 1)
    if (theirTotal < myTotal) {
      record.finishedAheadOfMe.set(them, (record.finishedAheadOfMe.get(them) ?? 0) + 1)
      record.finishedAheadOfMeAt.set(them, game.index)
    }
    if (myTotal < theirTotal) {
      record.iFinishedAhead.set(them, (record.iFinishedAhead.get(them) ?? 0) + 1)
      record.iFinishedAheadAt.set(them, game.index)
      record.aheadStreak.set(them, (record.aheadStreak.get(them) ?? 0) + 1)
    } else {
      record.aheadStreak.set(them, 0)
    }
    if (isGuestRef(participant.seatedAs) && !isGuestRef(participant.ref)) record.guestEraCompanions.add(them)
  }

  // When each held metric last changed ("ties go to whoever got there first").
  const mark = (metric: HeldMetric, changed: boolean) => {
    if (changed || !record.metricChangedAt.has(metric)) record.metricChangedAt.set(metric, game.index)
  }
  mark('knockSuccess', previous.knockSuccess !== knockSuccessRate(record))
  mark('knockRate', previous.knockRate !== knockRate(record))
  mark('knocksBeaten', previous.beaten !== knocksBeatenOf(record))
  mark('averageRound', previous.average !== averageRoundScore(record))
  mark('rating', previous.rating !== record.rating)
}

// MARK: Queries

export function recordOf(snapshot: ProgressionSnapshot, ref: Ref): PlayerRecord | undefined {
  return snapshot.records.get(canonical(snapshot.options, ref))
}

/** Everyone a person has shared a finished game with (not including them). */
export function peopleOf(snapshot: ProgressionSnapshot, ref: Ref): Set<Ref> {
  const keys = recordOf(snapshot, ref)?.sharedGames.keys() ?? []
  return new Set([...keys].filter((other) => !snapshot.options.excluded.has(other)))
}

/** The person and everyone they've played with. */
export function circleOf(snapshot: ProgressionSnapshot, ref: Ref): Set<Ref> {
  return new Set([...peopleOf(snapshot, ref), canonical(snapshot.options, ref)])
}

export function nameOf(snapshot: ProgressionSnapshot, ref: Ref): string {
  return recordOf(snapshot, ref)?.identity.name ?? 'Someone'
}

/** The calendar year of a moment in the snapshot's time zone. */
export function yearOf(snapshot: ProgressionSnapshot | ResolvedOptions, ms: number): number {
  const timeZone = 'options' in snapshot ? snapshot.options.timeZone : snapshot.timeZone
  return Number(new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric' }).format(new Date(ms)))
}

export function resultsIn(snapshot: ProgressionSnapshot, record: PlayerRecord, year: number): PlayerGameResult[] {
  return record.results.filter((result) => yearOf(snapshot, result.dateMs) === year)
}
