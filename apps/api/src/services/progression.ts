// Badges, titles, the Hall of Shame, head-to-head and Wrapped (design §12.3, §12.6–§12.9), served
// so the web app and other people's profiles show what each player's own phone computes. Every
// answer replays one player's finished games (claimed guests included) with `progression`, the
// TypeScript port of the iOS app's Core/Stats.

import {
  foldGame,
  parseOperation,
  playerSeatId,
  guestSeatId,
  isoSeconds,
  progression,
  type EarnedBadge,
  type HallOfShameResponse,
  type HeadToHeadResponse,
  type Operation,
  type PlayerProgressionResponse,
  type ProgressionPerson,
  type ShameEntryDTO,
  type FoldedGame,
  type UUID,
  type WrappedResponse,
  type WrappedSummaryDTO,
} from '@kedro/shared'
import { badRequest, notFound } from '../http.ts'
import type { Store } from '../store/types.ts'
import type { LeaderboardService } from './leaderboard.ts'
import type { PlayersService } from './players.ts'

type Snapshot = progression.ProgressionSnapshot
type Ref = progression.Ref

/** Whole-second ISO 8601, like every other API date (the iPhone app's decoder takes no fractions). */
const iso = (ms: number) => isoSeconds(ms)

/** A valid IANA time zone, or the default. */
export function timeZoneParam(value: string | undefined): string {
  if (!value) return progression.DEFAULT_TIME_ZONE
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value })
    return value
  } catch {
    throw badRequest('Unknown time zone')
  }
}

export class ProgressionService {
  /** Folded finished games, reused while a game's log is unchanged (per server instance). */
  private readonly folded = new Map<UUID, { lastHlc: string | null; state: FoldedGame }>()

  constructor(
    private readonly store: Store,
    private readonly players: PlayersService,
    private readonly leaderboard: LeaderboardService,
    private readonly now: () => number = Date.now,
  ) {}

  /** The replay of everything a player has finished, as their own phone sees it. */
  private async snapshotFor(playerId: UUID, { timeZone, excluded = new Set() }: { timeZone: string; excluded?: ReadonlySet<UUID> }) {
    const games = (await this.store.gamesFor(playerId)).filter((game) => game.status === 'finished')
    const stale = games.filter((game) => this.folded.get(game.gameId)?.lastHlc !== game.lastHlc || !this.folded.has(game.gameId))
    if (stale.length > 0) {
      const logs = await this.store.opsForGames(stale.map((game) => game.gameId))
      for (const game of stale) {
        const operations = (logs.get(game.gameId) ?? []).flatMap((entry) => {
          const parsed = parseOperation(entry)
          return parsed.ok ? [parsed.value.operation as Operation] : []
        })
        this.folded.set(game.gameId, { lastHlc: game.lastHlc, state: foldGame(operations, game.gameId) })
      }
    }
    const states = games.flatMap((game) => this.folded.get(game.gameId)?.state ?? [])
    // Every claimed guest counts as the account that claimed it, from game 1.
    const guestIds = new Set<UUID>()
    for (const state of states) for (const seat of state.seats) if (seat.player.kind === 'guest') guestIds.add(seat.player.id)
    const claims = await this.store.guestClaims([...guestIds])
    const aliases = new Map<Ref, Ref>([...claims].map(([guestId, claimer]) => [guestSeatId(guestId), playerSeatId(claimer)]))
    const snapshot = progression.buildProgression(states, {
      aliases,
      excluded: new Set([...excluded].map(playerSeatId)),
      timeZone,
    })
    // Accounts show their current name; guests the name they were seated under.
    const accountIds = [...snapshot.records.keys()].flatMap((ref) => (ref.startsWith('p:') ? [ref.slice(2)] : []))
    const names = new Map<Ref, string>((await this.store.getPlayers(accountIds)).map((row) => [playerSeatId(row.id), row.displayName]))
    return { snapshot, names }
  }

  private person(ref: Ref, snapshot: Snapshot, names: Map<Ref, string>): ProgressionPerson {
    return {
      kind: ref.startsWith('g:') ? 'guest' : 'player',
      id: ref.slice(2),
      displayName: names.get(ref) ?? progression.nameOf(snapshot, ref),
    }
  }

  private shameDTO(entry: progression.ShameEntry, snapshot: Snapshot, names: Map<Ref, string>): ShameEntryDTO {
    return {
      person: this.person(entry.player, snapshot, names),
      gameId: entry.gameId,
      tableWord: entry.tableWord,
      finishedAt: iso(entry.dateMs),
      roundNumber: entry.roundNumber,
      value: entry.value,
      hand: entry.hand,
      low: entry.low,
      finishPosition: entry.finish?.position ?? null,
    }
  }

  /** GET /v1/players/:playerId/progression */
  async progression(caller: UUID, playerId: UUID, timeZone: string): Promise<PlayerProgressionResponse> {
    const hidden = await this.players.hiddenFrom(caller)
    const row = hidden.has(playerId) ? null : await this.store.getPlayer(playerId)
    if (!row) throw notFound('No such player')
    const { snapshot, names } = await this.snapshotFor(playerId, { timeZone })
    const me = playerSeatId(playerId)
    const record = progression.recordOf(snapshot, me)
    const nowMs = this.now()
    const badges: EarnedBadge[] = record
      ? [...record.badges.values()]
        .sort((a, b) => (a.gameIndex ?? Number.MAX_SAFE_INTEGER) - (b.gameIndex ?? Number.MAX_SAFE_INTEGER) || progression.BADGE_IDS.indexOf(a.badge) - progression.BADGE_IDS.indexOf(b.badge))
        .map(earnedBadge)
      : []
    return {
      playerId,
      badges,
      nextUp: record ? progression.badgeProgress(record).slice(0, 3) : [],
      titles: {
        earned: progression.earnedTitles(snapshot, me),
        held: progression.heldTitles(snapshot, me, nowMs),
        display: progression.displayTitle(snapshot, me, row.titleId, nowMs),
      },
      hallOfShameEntries: record ? progression.shameEntriesOf(snapshot, me).length : 0,
      rivals: progression.rivalsOf(snapshot, me).map((ref) => ({
        person: this.person(ref, snapshot, names),
        games: record?.sharedGames.get(ref) ?? 0,
      })).filter((rival) => !(rival.person.kind === 'player' && hidden.has(rival.person.id))),
    }
  }

  /** GET /v1/players/me/hall-of-shame */
  async hallOfShame(caller: UUID, scope: 'yourPeople' | 'yours', timeZone: string): Promise<HallOfShameResponse> {
    const { snapshot, names } = await this.snapshotFor(caller, { timeZone, excluded: await this.players.hiddenFrom(caller) })
    const boards = progression.hallOfShame(snapshot, { scope, viewer: playerSeatId(caller) })
    return {
      scope,
      boards: boards.map((board) => ({
        category: board.category,
        name: progression.SHAME_CATEGORY_NAMES[board.category],
        entries: board.entries.map((entry) => this.shameDTO(entry, snapshot, names)),
      })),
    }
  }

  /** GET /v1/players/me/head-to-head/:playerId */
  async headToHead(caller: UUID, other: UUID, timeZone: string): Promise<HeadToHeadResponse> {
    const hidden = await this.players.hiddenFrom(caller)
    if (hidden.has(other) || !(await this.store.getPlayer(other))) throw notFound('No such player')
    const { snapshot, names } = await this.snapshotFor(caller, { timeZone })
    const h2h = progression.headToHead(snapshot, playerSeatId(caller), playerSeatId(other))
    const me = await this.store.getPlayer(caller)
    const them = await this.store.getPlayer(other)
    const person = (ref: Ref, displayName: string | undefined): ProgressionPerson => ({ ...this.person(ref, snapshot, names), ...(displayName ? { displayName } : {}) })
    return {
      a: person(h2h.a, me?.displayName),
      b: person(h2h.b, them?.displayName),
      gamesTogether: h2h.gamesTogether,
      aAhead: h2h.aAhead,
      bAhead: h2h.bAhead,
      aWins: h2h.aWins,
      bWins: h2h.bWins,
      aKnocks: h2h.aKnocks,
      bKnocks: h2h.bKnocks,
      aAverageFinal: h2h.aAverageFinal,
      bAverageFinal: h2h.bAverageFinal,
      lastMeeting: h2h.lastMeeting && {
        gameId: h2h.lastMeeting.gameId,
        tableWord: h2h.lastMeeting.tableWord,
        finishedAt: iso(h2h.lastMeeting.dateMs),
        aScore: h2h.lastMeeting.aScore,
        bScore: h2h.lastMeeting.bScore,
      },
    }
  }

  /** GET /v1/players/me/wrapped */
  async wrapped(caller: UUID, year: number | null, timeZone: string): Promise<WrappedResponse> {
    const { snapshot, names } = await this.snapshotFor(caller, { timeZone, excluded: await this.players.hiddenFrom(caller) })
    const me = playerSeatId(caller)
    const nowMs = this.now()
    const chosen = year ?? progression.currentWrappedYear(snapshot, me, nowMs) ?? progression.yearOf(snapshot, nowMs)
    const availability = progression.wrappedAvailability(snapshot, me, chosen, nowMs)
    const response: WrappedResponse = {
      year: chosen,
      availability: availability.kind === 'arrives' ? { kind: 'arrives', at: iso(availability.atMs) } : availability,
    }
    if (availability.kind !== 'available') return response
    const rank = (await this.leaderboard.profile(caller, caller)).globalRank
    const summary = progression.buildWrapped(snapshot, me, chosen, { nowMs, currentRank: rank === null ? null : { position: rank, isShared: false } })
    if (summary) response.summary = this.wrappedDTO(summary, snapshot, names)
    return response
  }

  private wrappedDTO(summary: progression.WrappedSummary, snapshot: Snapshot, names: Map<Ref, string>): WrappedSummaryDTO {
    const person = (entry: progression.WrappedPerson | null) => entry && { person: this.person(entry.ref, snapshot, names), count: entry.count }
    const knock = (event: progression.KnockEvent | null) =>
      event && { gameId: event.gameId, tableWord: event.tableWord, date: iso(event.dateMs), roundNumber: event.roundNumber, hand: event.hand, lowestOther: event.lowestOther }
    return {
      year: summary.year,
      games: summary.games,
      rounds: summary.rounds,
      hours: summary.hours,
      people: summary.people,
      wins: summary.wins,
      winRate: summary.winRate,
      finishes: Object.fromEntries(Object.entries(summary.finishes).map(([position, count]) => [String(position), count])),
      isWinRateHigh: summary.isWinRateHigh,
      ratingLine: summary.ratingLine.map((point) => ({ date: iso(point.dateMs), rating: Math.round(point.rating) })),
      ratingStart: summary.ratingStart,
      ratingPeak: summary.ratingPeak,
      ratingNow: summary.ratingNow,
      currentRank: summary.currentRank?.position ?? null,
      knocks: summary.knocks,
      knockSuccess: summary.knockSuccess,
      favoriteKnockValue: summary.favoriteKnockValue,
      bestKnock: knock(summary.bestKnock),
      worstKnock: knock(summary.worstKnock),
      nemesis: person(summary.nemesis),
      victim: person(summary.victim),
      redKings: summary.redKings,
      ghostHands: summary.ghostHands,
      biggestHand: summary.biggestHand,
      tauntsSent: summary.tauntsSent,
      favoriteTaunt: summary.favoriteTaunt,
      mostTaunted: person(summary.mostTaunted),
      badges: summary.badges.map(earnedBadge),
      titles: summary.titles,
      shame: summary.shame.map((entry) => ({ ...this.shameDTO(entry, snapshot, names), category: entry.category })),
      persona: { id: summary.persona, ...progression.PERSONA_COPY[summary.persona] },
    }
  }
}

function earnedBadge(award: progression.BadgeAward): EarnedBadge {
  return {
    badge: award.badge,
    gameId: award.gameId,
    tableWord: award.tableWord,
    roundNumber: award.roundNumber,
    earnedAt: award.dateMs === null ? null : iso(award.dateMs),
  }
}
