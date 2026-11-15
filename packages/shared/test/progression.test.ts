// Ports of the iOS app's KedroTests/Stats (BadgeTests, TitleTests, HallOfShameTests,
// ProgressionTests' Wrapped, PlayerStatsTests' head-to-head): the same histories must give the
// same badges, titles, entries and recaps on the phone and the server.

import { describe, expect, test } from 'bun:test'
import { foldGame, progression, seatIdOf, type PlayerRef, type WireOperation } from '../src/index.ts'
import { OperationBuilder, ids, parsed, sampleWireOperations, seats } from './fixtures/sampleGame.ts'

const {
  BADGE, BADGES, badgeProgress, buildProgression, buildWrapped, currentWrappedYear, displayTitle, earnedTitles, hallOfShame,
  headToHead, heldTitles, holderOf, recordOf, bestEarnedTitle, wrappedAvailability, zonedMidnight,
} = progression

let uuidCounter = 0
function uuid(kind: number): string {
  uuidCounter += 1
  const hex = uuidCounter.toString(16).padStart(12, '0')
  return `${kind.toString(16).padStart(8, '0')}-0000-4000-8000-${hex}`
}

type Person = { ref: PlayerRef; seat: string; name: string }
const player = (name: string): Person => {
  const ref: PlayerRef = { kind: 'player', id: uuid(0xa1) }
  return { ref, seat: seatIdOf(ref), name }
}
const guest = (name: string): Person => {
  const ref: PlayerRef = { kind: 'guest', id: uuid(0xa2) }
  return { ref, seat: seatIdOf(ref), name }
}

/** Finished games one day apart, like the iOS StatsHistory. */
class History {
  games: WireOperation[][] = []
  private startMs = 1_767_988_800_000 // 2026-01-09 20:00 UTC

  game(people: Person[], rounds: [number[], number][], { taunts = [] as { from: number; to: number | null }[], abandoned = false } = {}): string {
    const gameId = uuid(0xb1)
    const builder = new OperationBuilder(gameId, uuid(0xc1), people[0].ref.kind === 'player' ? people[0].ref.id : null, this.startMs)
    const seatList = people.map((person, order) => ({
      player: person.ref, displayName: person.name, order, ...(person.ref.kind === 'guest' ? {} : { handle: `p${order}x` }),
    }))
    builder.add('GameCreated', { config: { plannedRounds: rounds.length, scoringMode: 'scorekeeper', tableWord: 'Test Table', firstDealerSeat: people[0].seat }, host: people[0].seat })
    for (const seat of seatList) builder.add('PlayerSeated', { seat })
    builder.add('GameStarted', { seatOrder: people.map((person) => person.seat), firstDealer: people[0].seat })
    const recorded = rounds.map(([hands, knocker], index) => ({
      number: index + 1,
      hands: Object.fromEntries(people.map((person, i) => [person.seat, hands[i]])),
      knocker: people[knocker].seat,
    }))
    for (const round of recorded) {
      builder.advance(4)
      builder.add('RoundRecorded', { round })
    }
    for (const taunt of taunts) {
      builder.add('TauntSent', {
        tauntId: uuid(0xd1), roundNumber: 1, from: people[taunt.from].seat, fromName: people[taunt.from].name,
        target: taunt.to === null ? { kind: 'table' } : { kind: 'seat', seatId: people[taunt.to].seat },
        content: { kind: 'canned', id: 'TT-01' },
      })
    }
    builder.advance(1)
    if (abandoned) builder.add('GameAbandoned', {})
    else builder.add('GameFinished', { reason: 'completed', finalRounds: recorded })
    this.games.push(builder.operations)
    this.startMs += 86_400_000
    return gameId
  }

  /** One round: the winner holds 0, everyone else 5. */
  win(people: Person[], winner: number): string {
    return this.game(people, [[people.map((_, i) => (i === winner ? 0 : 5)), winner]])
  }

  /** order[0] finishes first, order[1] second, … */
  ordered(order: Person[]): string {
    return this.game(order, [[order.map((_, i) => i * 2 + 1), 0]])
  }

  states() {
    return this.games.map((operations) => foldGame(parsed(operations), operations[0].gameId))
  }

  /** The fixtures' games are mostly one round, so the 3-round rule is lowered to 1 (as on iOS). */
  snapshot(options: progression.ProgressionOptions = {}) {
    return buildProgression(this.states(), { minimumRounds: 1, timeZone: 'UTC', ...options })
  }
}

const earned = (snapshot: progression.ProgressionSnapshot, person: Person, gameId: string) =>
  new Set(snapshot.badgesEarned.get(gameId)?.get(person.seat)?.map((award) => award.badge) ?? [])

const sample = () => buildProgression([foldGame(parsed(sampleWireOperations()), ids.game)])

describe('Badges (design §12.6)', () => {
  const a = player('A'), b = player('B'), c = player('C')

  test('catalog: 34 badges, 3 secret', () => {
    expect(BADGES).toHaveLength(34)
    expect(BADGES.filter((badge) => badge.isSecret)).toHaveLength(3)
  })

  test("the sample game from scratch: Noah's Ghost Hand and Comeback Kid, Sam's Below Zero", () => {
    const snapshot = sample()
    const badges = (seat: string) => new Set(snapshot.badgesEarned.get(ids.game)?.get(seat)?.map((award) => award.badge) ?? [])
    for (const badge of [BADGE.outOfTheGate, BADGE.firstBlood, BADGE.landedIt, BADGE.foundOut, BADGE.ghostHand, BADGE.comebackKid]) expect(badges(seats.noah).has(badge)).toBe(true)
    expect(badges(seats.sam).has(BADGE.belowZero)).toBe(true)
    expect(badges(seats.sam).has(BADGE.landedIt)).toBe(true)
    expect(badges(seats.ben).has(BADGE.deadHeat)).toBe(true)
    expect(badges(seats.ben).has(BADGE.firstBlood)).toBe(false)
    const ghost = recordOf(snapshot, seats.noah)?.badges.get(BADGE.ghostHand)
    expect(ghost?.roundNumber).toBe(8)
    expect(ghost?.tableWord).toBe('Cold Deck')
    expect(recordOf(snapshot, seats.noah)?.badges.has(BADGE.nothingToSeeHere)).toBe(true)
  })

  test('knocking: Hat Trick, Bold Choice, Steady Hand across games', () => {
    const history = new History()
    const hatTrick = history.game([a, b, c], [[[0, 5, 5], 0], [[1, 5, 5], 0], [[2, 5, 5], 0]])
    const bold = history.game([a, b, c], [[[12, 3, 5], 0]])
    let steadyGame = ''
    for (let i = 0; i < 4; i++) steadyGame = history.game([a, b, c], [[[0, 5, 5], 0], [[0, 5, 5], 0], [[0, 5, 5], 0]])
    const snapshot = history.snapshot()
    expect(earned(snapshot, a, hatTrick).has(BADGE.hatTrick)).toBe(true)
    expect(earned(snapshot, a, bold).has(BADGE.foundOut)).toBe(true)
    expect(earned(snapshot, a, bold).has(BADGE.boldChoice)).toBe(true)
    const steady = recordOf(snapshot, a.seat)?.badges.get(BADGE.steadyHand)
    expect(steady?.roundNumber).toBe(1)
    expect(steady?.gameId).toBe(steadyGame)
  })

  test('cards: Royal Pair at −2, Fat Stack at 40', () => {
    const history = new History()
    const game = history.game([a, b, c], [[[-2, 40, 5], 0]])
    const snapshot = history.snapshot()
    for (const badge of [BADGE.royalPair, BADGE.belowZero, BADGE.landedIt]) expect(earned(snapshot, a, game).has(badge)).toBe(true)
    expect(earned(snapshot, b, game).has(BADGE.fatStack)).toBe(true)
  })

  test('streaks: Three-Peat at 3, Untouchable at 5, On the Board with the ranking game', () => {
    const history = new History()
    const games = Array.from({ length: 10 }, () => history.win([a, b, c], 0))
    const snapshot = history.snapshot()
    expect(earned(snapshot, a, games[2]).has(BADGE.threePeat)).toBe(true)
    expect(earned(snapshot, a, games[1]).has(BADGE.threePeat)).toBe(false)
    expect(earned(snapshot, a, games[4]).has(BADGE.untouchable)).toBe(true)
    expect(earned(snapshot, a, games[4]).has(BADGE.onTheBoard)).toBe(false)
    expect(earned(snapshot, a, games[9]).has(BADGE.onTheBoard)).toBe(true)
    expect(earnedTitles(snapshot, a.seat)).toContain('TI-03')
  })

  test('moments: By a Hair, Shared Spoils, Bottled It, Never Trailed', () => {
    const history = new History()
    const shared = history.game([a, b, c], [[[4, 4, 9], 0]])
    const bottle = history.game([a, b, c], [[[5, 0, 9], 1], [[0, 30, 9], 0]])
    const wire = history.game([a, b, c], Array.from({ length: 6 }, (): [number[], number] => [[0, 5, 5], 0]))
    const snapshot = history.snapshot()
    expect(earned(snapshot, a, shared).has(BADGE.sharedSpoils)).toBe(true)
    expect(earned(snapshot, b, shared).has(BADGE.sharedSpoils)).toBe(true)
    expect(earned(snapshot, b, bottle).has(BADGE.bottledIt)).toBe(true)
    expect(earned(snapshot, a, wire).has(BADGE.neverTrailed)).toBe(true)
    expect(earned(snapshot, a, wire).has(BADGE.byAHair)).toBe(false)
    const close = new History()
    const byOne = close.game([a, b, c], [[[3, 4, 9], 2]])
    expect(earned(close.snapshot(), a, byOne).has(BADGE.byAHair)).toBe(true)
  })

  test('Dark Horse: win against a table all rated higher', () => {
    const history = new History()
    for (let i = 0; i < 3; i++) history.ordered([b, c, a])
    const upset = history.ordered([a, b, c])
    expect(earned(history.snapshot(), a, upset).has(BADGE.darkHorse)).toBe(true)
  })

  test('rivalry: Nemesis Tamed and the secret Exorcism', () => {
    const history = new History()
    history.ordered([b, a, c])
    history.ordered([b, a, c])
    const tamed = history.ordered([a, b, c])
    history.ordered([a, b, c])
    const exorcism = history.ordered([a, b, c])
    const snapshot = history.snapshot()
    expect(earned(snapshot, a, tamed).has(BADGE.nemesisTamed)).toBe(true)
    expect(earned(snapshot, a, exorcism).has(BADGE.exorcism)).toBe(true)
    expect(earnedTitles(snapshot, a.seat)).toContain('TI-08')
  })

  test('social badges count accounts only', () => {
    const history = new History()
    const guests = Array.from({ length: 12 }, (_, i) => guest(`G${i}`))
    for (let start = 0; start < 12; start += 3) history.win([a, ...guests.slice(start, start + 3)], 0)
    expect(recordOf(history.snapshot(), a.seat)?.badges.has(BADGE.playsWellWithOthers)).toBe(false)
    const accounts = Array.from({ length: 10 }, (_, i) => player(`P${i}`))
    const friendly = new History()
    for (let pair = 0; pair < 10; pair += 2) friendly.win([a, accounts[pair], accounts[pair + 1]], 0)
    expect(recordOf(friendly.snapshot(), a.seat)?.badges.has(BADGE.playsWellWithOthers)).toBe(true)
  })

  test('Full House: an 8-player game', () => {
    const history = new History()
    const people = Array.from({ length: 8 }, (_, i) => player(`P${i}`))
    const game = history.win(people, 3)
    const snapshot = history.snapshot()
    for (const person of people) expect(earned(snapshot, person, game).has(BADGE.fullHouse)).toBe(true)
  })

  test('Trash Talker counts at most 3 taunts a game', () => {
    const history = new History()
    for (let i = 0; i < 10; i++) history.game([a, b, c], [[[0, 5, 5], 0]], { taunts: Array.from({ length: 6 }, () => ({ from: 0, to: 1 })) })
    expect(progression.tauntsCountedOf(recordOf(history.snapshot(), a.seat)!)).toBe(30)
    expect(recordOf(history.snapshot(), a.seat)?.badges.has(BADGE.trashTalker)).toBe(false)
    for (let i = 0; i < 7; i++) history.game([a, b, c], [[[0, 5, 5], 0]], { taunts: Array.from({ length: 3 }, () => ({ from: 0, to: null })) })
    const snapshot = history.snapshot()
    expect(recordOf(snapshot, a.seat)?.badges.has(BADGE.trashTalker)).toBe(true)
    expect(earnedTitles(snapshot, a.seat)).toContain('TI-10')
  })

  test('Bad Influence: your guest claims and plays on their own account', () => {
    const history = new History()
    const sam = guest('Sam'), account = player('Sam')
    history.win([a, b, sam], 0)
    const own = history.win([account, b, c], 0)
    const claimed = history.snapshot({ aliases: new Map([[sam.seat, account.seat]]) })
    expect(recordOf(claimed, a.seat)?.badges.get(BADGE.badInfluence)?.gameId).toBe(own)
    expect(recordOf(claimed, b.seat)?.badges.has(BADGE.badInfluence)).toBe(true)
    expect(recordOf(history.snapshot(), a.seat)?.badges.has(BADGE.badInfluence)).toBe(false)
  })

  test('Did the Reading comes from Learn, not a table', () => {
    const history = new History()
    history.win([a, b, c], 0)
    const snapshot = history.snapshot({ didTheReading: new Set([a.seat]) })
    expect(recordOf(snapshot, a.seat)?.badges.has(BADGE.didTheReading)).toBe(true)
    expect(recordOf(snapshot, b.seat)?.badges.has(BADGE.didTheReading)).toBe(false)
  })

  test('a badge is earned once, in the game that earned it', () => {
    const history = new History()
    for (let i = 0; i < 4; i++) history.win([a, b, c], 0)
    const snapshot = history.snapshot()
    expect(snapshot.games.map((game) => earned(snapshot, a, game.id).has(BADGE.landedIt))).toEqual([true, false, false, false])
  })

  test('Next up: closest counting badges first, earned ones dropped', () => {
    const history = new History()
    history.win([a, b, c], 0)
    history.win([a, b, c], 0)
    const progress = badgeProgress(recordOf(history.snapshot(), a.seat)!)
    expect(progress.some((entry) => entry.badge === BADGE.firstBlood)).toBe(false)
    expect(progress[0]).toEqual({ badge: BADGE.threePeat, value: 2, target: 3 })
  })
})

describe('Titles (design §12.7)', () => {
  const people = ['A', 'B', 'C', 'D', 'E', 'F'].map(player)
  const [a, b] = people
  const now = Date.UTC(2026, 6, 1)

  const knock = (history: History, by: number, lands = true) => {
    const hands = people.map(() => 5)
    if (lands) hands[by] = 0
    else {
      hands[by] = 9
      hands[(by + 1) % people.length] = 0
    }
    history.game(people, [[hands, by]])
  }

  test('The Closer: needs 15 knocks, ties go to whoever got there first, and it moves', () => {
    const history = new History()
    for (let i = 0; i < 16; i++) knock(history, 0)
    const aOnly = history.snapshot()
    expect(holderOf(aOnly, 'TI-12', a.seat, now)).toBe(a.seat)
    expect(heldTitles(aOnly, a.seat, now)).toContain('TI-12')
    for (let i = 0; i < 16; i++) knock(history, 1)
    expect(holderOf(history.snapshot(), 'TI-12', b.seat, now)).toBe(a.seat)
    knock(history, 0, false)
    const moved = history.snapshot()
    expect(holderOf(moved, 'TI-12', a.seat, now)).toBe(b.seat)
    expect(displayTitle(moved, a.seat, 'TI-12', now)).toBe(bestEarnedTitle(moved, a.seat))
    expect(displayTitle(moved, b.seat, 'TI-12', now)).toBe('TI-12')
  })

  test('held titles need 5 ranked people and their own minimums', () => {
    const small = new History()
    const four = people.slice(0, 4)
    for (let i = 0; i < 20; i++) small.game(four, [[[0, 5, 5, 5], 0]])
    const tooFew = small.snapshot()
    expect(holderOf(tooFew, 'TI-17', four[0].seat, now)).toBeNull()
    expect(holderOf(tooFew, 'TI-12', four[0].seat, now)).toBeNull()
    const history = new History()
    for (let i = 0; i < 20; i++) knock(history, 0)
    const snapshot = history.snapshot()
    expect(holderOf(snapshot, 'TI-17', a.seat, now)).toBe(a.seat)
    expect(holderOf(snapshot, 'TI-13', a.seat, now)).toBeNull()
    expect(holderOf(snapshot, 'TI-15', a.seat, now)).toBe(a.seat)
  })

  test('earned titles: Fresh Meat for everyone, the rest from badges; nobody is forced', () => {
    const history = new History()
    knock(history, 0)
    const snapshot = history.snapshot()
    expect(earnedTitles(snapshot, a.seat)).toEqual(['TI-01', 'TI-04'])
    expect(earnedTitles(snapshot, b.seat)).toEqual(['TI-01'])
    expect(displayTitle(snapshot, a.seat, null, now)).toBeNull()
    expect(displayTitle(snapshot, a.seat, 'TI-01', now)).toBe('TI-01')
    expect(displayTitle(snapshot, a.seat, 'TI-05', now)).toBeNull()
    expect(displayTitle(snapshot, a.seat, 'nonsense', now)).toBeNull()
  })
})

describe('Hall of Shame (design §12.8)', () => {
  const a = player('A'), b = player('B'), c = player('C'), d = player('D')
  const table = [a, b, c, d]
  const learnerGames = (history: History) => {
    history.game(table, [[[0, 5, 5, 90], 0]])
    history.win(table, 1)
    history.win(table, 2)
  }
  const board = (boards: progression.ShameBoard[], category: progression.ShameCategory) => boards.find((entry) => entry.category === category)?.entries ?? []

  test("each category's moment, with its numbers", () => {
    const history = new History()
    learnerGames(history)
    history.game(table, [[[12, -1, 5, 47], 0], [[9, 2, 6, 8], 0], [[20, 40, 0, 3], 2]])
    const boards = hallOfShame(history.snapshot(), { viewer: a.seat })
    const worstHand = board(boards, 'worstHand')[0]
    expect([worstHand.player, worstHand.value, worstHand.roundNumber]).toEqual([d.seat, 47, 1])
    const worstKnock = board(boards, 'worstKnock')[0]
    expect([worstKnock.player, worstKnock.value, worstKnock.hand, worstKnock.low]).toEqual([a.seat, 13, 12, -1])
    expect([board(boards, 'ateIt')[0].player, board(boards, 'ateIt')[0].value]).toEqual([a.seat, 2])
    expect([board(boards, 'biggestLoss')[0].player, board(boards, 'biggestLoss')[0].value]).toEqual([a.seat, 61])
    const bottle = board(boards, 'bottleJob').find((entry) => entry.player === b.seat)
    expect([bottle?.value, bottle?.finish?.position]).toEqual([10, 2])
    expect([board(boards, 'deepestHole')[0].player, board(boards, 'deepestHole')[0].value]).toEqual([a.seat, 60])
    expect(boards.every((entry) => entry.entries.length <= 3)).toBe(true)
  })

  test('top 3 per category, worst first; ties keep the earlier moment', () => {
    const history = new History()
    learnerGames(history)
    for (const hand of [30, 35, 30, 40, 20]) history.game(table, [[[0, 5, 5, hand], 0]])
    const entries = board(hallOfShame(history.snapshot(), { viewer: a.seat }), 'worstHand')
    expect(entries.map((entry) => entry.value)).toEqual([40, 35, 30])
    expect(entries[2].gameIndex).toBe(3)
  })

  test('scopes: your people, yours, blocked people excluded', () => {
    const history = new History()
    learnerGames(history)
    history.game(table, [[[12, -1, 5, 47], 0]])
    const stranger = player('Stranger'), e = player('E'), f = player('F')
    for (let i = 0; i < 4; i++) history.win([stranger, e, f], 0)
    const snapshot = history.snapshot()
    const mine = hallOfShame(snapshot, { scope: 'yours', viewer: a.seat }).flatMap((entry) => entry.entries)
    expect(mine.length).toBeGreaterThan(0)
    expect(mine.every((entry) => entry.player === a.seat)).toBe(true)
    expect(hallOfShame(snapshot, { viewer: stranger.seat }).flatMap((entry) => entry.entries).every((entry) => entry.player !== a.seat && entry.player !== d.seat)).toBe(true)
    expect(hallOfShame(snapshot, { viewer: a.seat }).flatMap((entry) => entry.entries).every((entry) => entry.player !== stranger.seat)).toBe(true)
    const blocked = history.snapshot({ excluded: new Set([d.seat]) })
    expect(hallOfShame(blocked, { viewer: a.seat }).flatMap((entry) => entry.entries).every((entry) => entry.player !== d.seat)).toBe(true)
  })

  test('learner games and abandoned games never produce entries', () => {
    const history = new History()
    history.game(table, [[[0, 5, 5, 90], 0]])
    expect(hallOfShame(history.snapshot(), { viewer: a.seat }).every((entry) => entry.entries.length === 0)).toBe(true)
    const abandoned = new History()
    learnerGames(abandoned)
    abandoned.game(table, [[[0, 5, 5, 99], 0]], { abandoned: true })
    expect(board(hallOfShame(abandoned.snapshot(), { viewer: a.seat }), 'worstHand')).toHaveLength(0)
  })
})

describe('Head-to-head (design §12.3)', () => {
  test('Noah and Ana in the sample game', () => {
    const h2h = headToHead(sample(), seats.noah, seats.ana)
    expect([h2h.gamesTogether, h2h.aAhead, h2h.bAhead, h2h.aWins, h2h.bWins]).toEqual([1, 1, 0, 1, 0])
    expect(h2h.aKnocks).toEqual({ landed: 2, tied: 0, failed: 1 })
    expect(h2h.bKnocks).toEqual({ landed: 1, tied: 1, failed: 0 })
    expect([h2h.lastMeeting?.aScore, h2h.lastMeeting?.bScore]).toEqual([28, 34])
  })
})

describe('Wrapped (design §12.9)', () => {
  const three = ['A', 'B', 'C'].map(player)
  const me = three[0].seat
  const utc = (year: number, month: number, day: number) => Date.UTC(year, month - 1, day, 12)

  test('10 games, December 1, then it stays until next year', () => {
    const history = new History()
    for (let i = 0; i < 12; i++) history.win(three, 0)
    const snapshot = history.snapshot()
    const release = Date.UTC(2026, 11, 1)
    expect(wrappedAvailability(snapshot, me, 2026, utc(2026, 11, 1))).toEqual({ kind: 'arrives', atMs: release })
    expect(wrappedAvailability(snapshot, me, 2026, utc(2026, 12, 2))).toEqual({ kind: 'available' })
    expect(currentWrappedYear(snapshot, me, utc(2027, 3, 1))).toBe(2026)
    expect(currentWrappedYear(snapshot, me, utc(2026, 6, 1))).toBeNull()

    const summary = buildWrapped(snapshot, me, 2026, { nowMs: utc(2026, 12, 2) })!
    expect(summary.games).toBe(12)
    expect(summary.wins).toBe(12)
    expect(summary.ratingLine).toHaveLength(13)
    expect(summary.ratingStart).toBe(1000)
    expect(summary.ratingPeak).toBe(summary.ratingNow)
    expect(summary.knocks).toBe(12)
    expect(summary.persona).toBe('closer')
    expect(summary.victim).not.toBeNull()
    expect(summary.nemesis).toBeNull()

    const short = new History()
    for (let i = 0; i < 6; i++) short.win(three, 0)
    expect(wrappedAvailability(short.snapshot(), me, 2026, utc(2026, 12, 2))).toEqual({ kind: 'needsGames', played: 6, needed: 10 })
    expect(buildWrapped(short.snapshot(), me, 2026, { nowMs: utc(2026, 12, 2) })).toBeNull()
  })

  test('release is midnight December 1 in the player’s time zone', () => {
    expect(zonedMidnight(2026, 12, 1, 'UTC')).toBe(Date.UTC(2026, 11, 1))
    expect(zonedMidnight(2026, 12, 1, 'America/New_York')).toBe(Date.UTC(2026, 11, 1, 5))
    expect(zonedMidnight(2026, 7, 1, 'America/Los_Angeles')).toBe(Date.UTC(2026, 6, 1, 7))
  })
})
