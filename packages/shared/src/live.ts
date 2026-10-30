// The Live Activity content state the server broadcasts to a game's APNs broadcast channel
// (design §13.2: "Online updates go server → APNs broadcast channel per game").
//
// The JSON is exactly the iOS `LiveGameAttributes.ContentState` (apps/ios/Shared/LiveActivity/
// LiveGameAttributes.swift, built on the phone by `LiveActivityContent`), so a push can replace
// what the phone rendered itself. A broadcast reaches every phone at the table, so it is the same
// for everyone: rows carry `isMe: false`, and `actionSeats` names the seats whose phones show the
// button; each phone resolves both against its own seat (`ContentState.resolved(for:)`).
//
// Every string here is literal or identical in all three language levels (the metadata line, the
// fact line, K-23, N-06, button titles), so the server can render it once. Keep it small: APNs
// payloads are limited to 4 KB.

import { dealerForRound, standings, type FoldedGame } from './fold.ts'
import { seatIdOf, type SeatId } from './ids.ts'
import type { Avatar, Seat } from './domain.ts'
import { FAILED_PENALTY, LANDED_SCORE, knockOutcome, rankLabel, roundScores, type KnockOutcome } from './scoring.ts'

export type LiveGamePhase = 'active' | 'finished' | 'abandoned'

export type LiveAvatar =
  | { emoji: { emoji: string; colorIndex: number } }
  | { curated: { id: string } }
  | { initial: { letter: string; isGuest: boolean } }

export type LiveStandingRow = {
  id: SeatId
  name: string
  rankLabel: string
  ordinal: string
  score: string
  delta?: string
  outcome?: KnockOutcome
  isMe: boolean
  isLeader: boolean
  isDealer: boolean
  avatar: LiveAvatar
}

export type LiveActivityButton = { kind: 'recordRound' | 'reportHand'; title: string }

export type LiveActivityContentState = {
  phase: LiveGamePhase
  roundNumber: number
  plannedRounds: number
  metadataLine: string
  rows: LiveStandingRow[]
  factLine?: string
  liveKnockLine?: string
  staleTemplate: string
  action?: LiveActivityButton
  /** The seats whose phones show `action` (broadcasts only). */
  actionSeats?: SeatId[]
  /** Whole seconds since 1970. */
  updatedAt: number
}

/** N-06, identical in every level; the phone fills in `{time}`. */
export const STALE_TEMPLATE = 'Last update {time} · Open Kedro to catch up'

const MINUS = '−'

/** A score with a true minus ("−10"), as the phones print it. */
export function scoreString(value: number): string {
  return value < 0 ? `${MINUS}${Math.abs(value)}` : String(value)
}

/** "+9", "−10", "0". */
export function signedScore(value: number): string {
  return value > 0 ? `+${value}` : scoreString(value)
}

/** "1st", "2nd", "3rd", "11th". */
export function ordinal(position: number): string {
  const tens = position % 100
  const suffix = tens >= 11 && tens <= 13 ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' } as Record<number, string>)[position % 10] ?? 'th'
  return `${position}${suffix}`
}

/** The broadcast content for a folded game; null in the lobby (no Live Activity before Deal). */
export function liveActivityContentState(game: FoldedGame, nowMs: number = game.latestHlc?.wallMs ?? 0): LiveActivityContentState | null {
  if (game.status === 'lobby') return null
  const phase: LiveGamePhase = game.status
  const played = game.rounds.length
  const planned = game.config.plannedRounds
  const awaitingFinish = game.status === 'active' && played >= planned
  const roundNumber = Math.min(played + 1, planned)
  const nextRound = played + 1
  const dealer = game.status === 'active' && !awaitingFinish ? dealerForRound(game, nextRound) : null
  const names = new Map(game.seats.map((seat) => [seatIdOf(seat.player), seat.displayName]))
  const name = (seat: SeatId) => names.get(seat) ?? 'Someone'

  const last = game.rounds[played - 1]
  const lastScores = last ? roundScores(last.hands, last.knocker) : undefined
  const lastOutcome = last ? knockOutcome(last.hands, last.knocker) : null
  const table = standings(game)
  const best = table[0]?.total

  const roundOf = `ROUND ${roundNumber} OF ${planned}`
  const state: LiveActivityContentState = {
    phase,
    roundNumber,
    plannedRounds: planned,
    metadataLine: dealer ? `${roundOf} · ${name(dealer).toUpperCase()} DEALS` : roundOf,
    rows: table.map(({ seat, total, rank }) => {
      const id = seatIdOf(seat.player)
      const row: LiveStandingRow = {
        id,
        name: seat.displayName,
        rankLabel: rankLabel(rank),
        ordinal: ordinal(rank.position),
        score: scoreString(total),
        isMe: false,
        isLeader: played > 0 && total === best,
        isDealer: dealer === id,
        avatar: liveAvatar(seat),
      }
      if (last && lastScores && lastScores[id] !== undefined) {
        const hand = last.hands[id] ?? 0
        if (id === last.knocker && lastOutcome) {
          row.outcome = lastOutcome
          row.delta = knockerDelta(lastOutcome, hand)
        } else {
          row.delta = signedScore(lastScores[id])
        }
      }
      return row
    }),
    staleTemplate: STALE_TEMPLATE,
    updatedAt: Math.floor(nowMs / 1000),
  }
  if (last) state.factLine = `Round ${last.number}. ${name(last.knocker)} knocked on ${scoreString(last.hands[last.knocker] ?? 0)}.`
  if (game.status === 'active' && game.liveKnock && game.liveKnock.roundNumber === nextRound) {
    state.liveKnockLine = `${name(game.liveKnock.knocker)} knocked · last turns`
  }
  if (game.status === 'active' && !awaitingFinish) {
    if (game.config.scoringMode === 'scorekeeper') {
      const keeper = game.config.scorekeeperSeat ?? game.hostSeat
      if (keeper) {
        state.action = { kind: 'recordRound', title: `Record Round ${nextRound}` }
        state.actionSeats = [keeper]
      }
    } else {
      const reported = new Set(game.reportedSeats)
      const owing = game.seats.filter((seat) => !reported.has(seatIdOf(seat.player)))
      // A seat's own phone and its reporter (guests without the app) both owe the hand.
      const phones = new Set(owing.flatMap((seat) => [seatIdOf(seat.player), ...(seat.reporter ? [seat.reporter] : [])]))
      if (phones.size > 0) {
        state.action = { kind: 'reportHand', title: 'Report Your Hand' }
        state.actionSeats = [...phones]
      }
    }
  }
  return state
}

/** The knocker's delta next to the outcome glyph: "−10" landed, "5" tied, "2 + 10" failed. */
function knockerDelta(outcome: KnockOutcome, hand: number): string {
  switch (outcome) {
    case 'landed':
      return scoreString(LANDED_SCORE)
    case 'tied':
      return scoreString(hand)
    case 'failed':
      return `${scoreString(hand)} + ${FAILED_PENALTY}`
  }
}

/** Photos can't load in the extension, so they fall back to the initial. */
function liveAvatar(seat: Seat): LiveAvatar {
  const avatar: Avatar | undefined = seat.avatar
  if (avatar?.kind === 'emoji') return { emoji: { emoji: avatar.emoji, colorIndex: avatar.colorIndex } }
  if (avatar?.kind === 'curated') return { curated: { id: avatar.id } }
  const letter = seat.displayName.trim().charAt(0).toUpperCase() || '?'
  return { initial: { letter, isGuest: seat.player.kind === 'guest' } }
}

