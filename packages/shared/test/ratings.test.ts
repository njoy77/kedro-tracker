import { describe, expect, test } from 'bun:test'
import {
  RATING_START,
  aggregateStats,
  buildLeaderboard,
  buildRecords,
  expectedScore,
  foldGame,
  kFactor,
  projectFinishedGame,
  replayRatings,
  statsRowsFromProjection,
  type RatedGame,
  type StatsRow,
} from '../src/index.ts'
import { sampleOperations } from './fixtures/sampleGame.ts'

const game = (gameId: string, finishedAtMs: number, totals: Record<string, number>): RatedGame => ({
  gameId,
  finishedAtMs,
  placements: Object.entries(totals).map(([subject, total]) => ({ subject, total })),
})

describe('Elo replay', () => {
  test('K is scaled by 1/(n−1) and doubled for the first 10 games', () => {
    expect(kFactor(0, 5)).toBe(16)
    expect(kFactor(9, 5)).toBe(16)
    expect(kFactor(10, 5)).toBe(8)
    expect(kFactor(10, 3)).toBe(16)
  })

  test('equal ratings expect a coin flip', () => {
    expect(expectedScore(1000, 1000)).toBe(0.5)
    expect(expectedScore(1400, 1000)).toBeCloseTo(10 / 11, 10)
  })

  test('first game from 1,000: pairwise wins and draws', () => {
    const { ratings, changes } = replayRatings([game('g1', 1, { a: 10, b: 20, c: 20, d: 30 })])
    // n = 4, provisional K = 64 / 3 per pair; everyone starts equal (E = 0.5).
    const k = 64 / 3
    expect(ratings.get('a')?.rating).toBeCloseTo(RATING_START + k * 1.5, 10)
    expect(ratings.get('b')?.rating).toBeCloseTo(RATING_START + k * 0, 10) // beat d, drew c, lost a
    expect(ratings.get('c')?.rating).toBeCloseTo(RATING_START, 10)
    expect(ratings.get('d')?.rating).toBeCloseTo(RATING_START - k * 1.5, 10)
    expect(changes).toHaveLength(4)
    // Zero-sum when everyone shares the same K.
    expect(changes.reduce((sum, change) => sum + change.delta, 0)).toBeCloseTo(0, 10)
  })

  test('replay is deterministic and order-independent', () => {
    const games = [
      game('g2', 2, { a: 30, b: 10, c: 20 }),
      game('g1', 1, { a: 10, b: 20, c: 30 }),
      game('g3', 2, { a: 15, b: 15, c: 40 }),
    ]
    const forward = replayRatings(games)
    const backward = replayRatings([...games].reverse())
    expect([...forward.ratings.entries()]).toEqual([...backward.ratings.entries()])
    expect(forward.changes.map((change) => change.gameId)).toEqual(['g1', 'g1', 'g1', 'g2', 'g2', 'g2', 'g3', 'g3', 'g3'])
    expect(forward.ratings.get('a')?.games).toBe(3)
  })

  test('after 10 games K halves', () => {
    const games = Array.from({ length: 12 }, (_, i) => game(`g${String(i).padStart(2, '0')}`, i, { a: 1, b: 2, c: 3 }))
    const { changes } = replayRatings(games)
    const aDeltas = changes.filter((change) => change.subject === 'a').map((change) => change.delta)
    // Game 11 (index 10) uses K = 32 instead of 64; same opponents, so the step drops sharply.
    expect(aDeltas[10]).toBeLessThan(aDeltas[9] * 0.6)
  })

  test('the sample game: Noah gains the most, Sam loses the most', () => {
    const projection = projectFinishedGame(foldGame(sampleOperations()))
    if (!projection) throw new Error('expected a finished game')
    const rows = statsRowsFromProjection(projection)
    const { ratings } = replayRatings([
      { gameId: projection.gameId, finishedAtMs: projection.finishedAtMs, placements: rows.map((row) => ({ subject: row.subject, total: row.total })) },
    ])
    const sorted = [...ratings.values()].sort((a, b) => b.rating - a.rating).map((rating) => rating.subject)
    expect(sorted[0]).toBe(rows.find((row) => row.total === 28)?.subject ?? 'missing')
    expect(sorted[4]).toBe(rows.find((row) => row.total === 70)?.subject ?? 'missing')
    expect(Math.round(ratings.get(sorted[0])?.rating ?? 0)).toBe(1032) // 1000 + 16 × 4 × 0.5
  })
})

describe('stats and leaderboard', () => {
  const row = (subject: string, gameId: string, at: number, total: number, isWinner: boolean, knocks = 1, landed = 1): StatsRow => ({
    gameId, finishedAtMs: at, subject, total, isWinner, roundsPlayed: 6, knocks, knocksLanded: landed, knocksTied: 0, knocksFailed: knocks - landed,
  })

  test('aggregates lifetime stats with streaks', () => {
    const rows = [
      row('p:a', 'g1', 1, 30, true),
      row('p:a', 'g2', 2, 50, false),
      row('p:a', 'g3', 3, 20, true),
      row('p:a', 'g4', 4, 25, true),
    ]
    const stats = aggregateStats(rows).get('p:a')
    expect(stats).toMatchObject({ gamesPlayed: 4, wins: 3, winRate: 0.75, avgScore: 31.25, bestGame: 20, worstGame: 50, currentWinStreak: 2, longestWinStreak: 2, knockSuccess: 1 })
    expect(stats).toMatchObject({ bestGameId: 'g3', bestGameAtMs: 3, longestWinStreakAtMs: 4, lastPlayedMs: 4 })
    expect(stats?.avgPerRound).toBeCloseTo(125 / 24, 10)
  })

  test('10-game eligibility, per-sort minimums and shared ranks', () => {
    const rows: StatsRow[] = []
    const add = (subject: string, games: number, wins: number, knocks: number) => {
      for (let i = 0; i < games; i++) rows.push(row(subject, `${subject}-${i}`, i, 20, i < wins, i < knocks ? 1 : 0, i < knocks ? 1 : 0))
    }
    add('p:a', 16, 6, 16)
    add('p:b', 12, 6, 3)
    add('p:c', 6, 6, 0)
    add('p:d', 3, 3, 0)
    const stats = aggregateStats(rows)
    // Six games, all won, is still unranked: one hot streak isn't a placement.
    const board = buildLeaderboard({ stats: stats.values(), ratings: new Map(), sort: 'winRate' })
    expect(board.rows.map((entry) => [entry.subject, entry.rank])).toEqual([['p:b', 1], ['p:a', 2]])
    expect(board.notYetRanked).toEqual([
      { subject: 'p:c', gamesPlayed: 6, gamesToRank: 4 },
      { subject: 'p:d', gamesPlayed: 3, gamesToRank: 7 },
    ])

    // Knock success still needs 15 knocks on top of ranking.
    const knock = buildLeaderboard({ stats: stats.values(), ratings: new Map(), sort: 'knockSuccess' })
    expect(knock.rows.map((entry) => [entry.subject, entry.rank])).toEqual([['p:a', 1], ['p:b', null]])
    expect(knock.rows[1].needs).toEqual({ knocks: 12 })
    const wins = buildLeaderboard({ stats: stats.values(), ratings: new Map(), sort: 'wins' })
    expect(wins.rows.map((entry) => [entry.subject, entry.rank, entry.value])).toEqual([['p:a', 1, 6], ['p:b', 1, 6]])
  })

  test('avg score sorts ascending (lower is better)', () => {
    const rows: StatsRow[] = []
    for (let i = 0; i < 10; i++) {
      rows.push(row('p:low', `l${i}`, i, 10, false))
      rows.push(row('p:high', `h${i}`, i, 40, false))
    }
    const board = buildLeaderboard({ stats: aggregateStats(rows).values(), ratings: new Map(), sort: 'avgScore' })
    expect(board.rows.map((entry) => entry.subject)).toEqual(['p:low', 'p:high'])
  })
})

describe('records', () => {
  const row = (subject: string, gameId: string, at: number, total: number, isWinner: boolean, landed = 0): StatsRow => ({
    gameId, finishedAtMs: at, subject, total, isWinner, roundsPlayed: 6, knocks: landed, knocksLanded: landed, knocksTied: 0, knocksFailed: 0,
  })
  const stats = [
    ...aggregateStats([
      row('p:a', 'g1', 1, 20, true, 1),
      row('p:a', 'g2', 2, 40, false),
      row('p:b', 'g1', 1, 30, false),
      row('p:b', 'g2', 2, 20, true, 2),
      row('p:b', 'g3', 3, 25, true),
      row('p:c', 'g3', 3, 60, false),
    ]).values(),
  ]

  test('best game: lowest first, ties by who set it first, with the game', () => {
    expect(buildRecords(stats, 'bestGame')).toEqual([
      { subject: 'p:a', rank: 1, value: 20, gameId: 'g1', atMs: 1 },
      { subject: 'p:b', rank: 1, value: 20, gameId: 'g2', atMs: 2 },
      { subject: 'p:c', rank: 3, value: 60, gameId: 'g3', atMs: 3 },
    ])
  })

  test('streaks, landed knocks and games leave out people with none; limit trims', () => {
    expect(buildRecords(stats, 'longestStreak').map((entry) => [entry.subject, entry.value, entry.atMs])).toEqual([
      ['p:b', 2, 3],
      ['p:a', 1, 1],
    ])
    expect(buildRecords(stats, 'mostLandedKnocks').map((entry) => [entry.subject, entry.value])).toEqual([
      ['p:b', 2],
      ['p:a', 1],
    ])
    expect(buildRecords(stats, 'mostGames').map((entry) => [entry.subject, entry.rank])).toEqual([
      ['p:b', 1],
      ['p:a', 2],
      ['p:c', 3],
    ])
    expect(buildRecords(stats, 'mostGames', 1)).toHaveLength(1)
  })
})
