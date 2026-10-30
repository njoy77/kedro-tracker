import { describe, expect, test } from 'bun:test'
import { LEADERBOARD_SORTS, foldGame, gameTotals, legacyFinishedAtMs, legacyLeaderboard, legacyRounds, outcomeOf, parseOperation, projectFinishedGame, seatIdOf, type Operation } from '@kedro/shared'
import { convertLegacy, readLegacyExport, type LegacyExport } from '../src/legacy/convert.ts'
import { importLegacy } from '../src/legacy/importer.ts'
import { seedFromLegacy } from '../src/dev/seed.ts'
import { harness } from './support.ts'

const players = [
  { id: 'lp1', username: 'noah', emoji: '🐴' },
  { id: 'lp2', username: 'ana', emoji: '🦄' },
  { id: 'lp3', username: 'ben', emoji: '🎯' },
]

/** A legacy game: scores per round (as the web app stored them) and who knocked. */
function legacyGame(id: string, rounds: { scores: number[]; knockedBy?: string | null; knockResult?: string; inherentKnock?: string }[], status = 'complete') {
  return {
    id,
    startedAt: 1_700_000_000_000,
    endedAt: 1_700_000_900_000,
    status,
    players: players.map((player) => ({ ...player, total: 0 })),
    rounds: rounds.map((round, index) => ({
      id: `${id}-r${index}`,
      timestamp: 1_700_000_000_000 + (index + 1) * 60_000,
      scores: round.scores.map((score, seat) => ({ playerId: players[seat].id, score })),
      knockedBy: round.knockedBy ?? null,
      knockResult: round.knockResult ?? null,
      inherentKnock: round.inherentKnock ?? null,
    })),
  }
}

function fold(game: { gameId: string; operations: unknown[] }) {
  const ops = game.operations.map((wire) => {
    const parsed = parseOperation(wire)
    if (!parsed.ok) throw new Error(parsed.error)
    return parsed.value.operation as Operation
  })
  return foldGame(ops, game.gameId)
}

describe('legacy web history', () => {
  test('converts finished games into valid op logs and skips what it cannot import', () => {
    const data = readLegacyExport([
      { key: 'kedro_players', value: players },
      {
        key: 'kedro_games',
        value: [
          legacyGame('g1', [{ scores: [-10, 6, 9], knockedBy: 'lp1' }, { scores: [5, 5, 12] }, { scores: [14, 1, 3], knockedBy: 'lp1' }]),
          legacyGame('g2', [{ scores: [1, 2, 3] }]),
          legacyGame('g3', [{ scores: [1, 2, 3] }], 'abandoned'),
          legacyGame('g4', [{ scores: [0, 0, 0] }]),
        ],
      },
    ])
    const result = convertLegacy(data, (id) => `${id}`.padEnd(64, '0').replace(/[^0-9a-f]/g, 'a'))
    expect(result.games).toHaveLength(2)
    expect(result.skipped.map((row) => row.reason).sort()).toEqual(['abandoned', 'noRounds'])
    const folded = fold(result.games[0])
    expect(folded.status).toBe('finished')
    expect(folded.config.tableWord).toBe('Web · Nov 14') // 1_700_000_000_000 is Nov 14, 2023 in New York
    // Totals match the legacy totals: 9, 12, 24.
    const totals = gameTotals(folded)
    expect(folded.seats.map((seat) => totals[seatIdOf(seat.player)])).toEqual([9, 12, 24])
  })

  test('keeps the web scores exactly, credits no unrecorded knock, keeps inherent knocks, drops test rounds', () => {
    const data: LegacyExport = {
      players,
      games: [legacyGame('g1', [
        { scores: [0, 6, 8], knockedBy: 'lp1', knockResult: 'tied' }, // marked tied, though lowest alone
        { scores: [4, 5, -1] }, // nobody recorded as knocking
        { scores: [0, 0, 0] }, // testing
        { scores: [7, 0, -2], inherentKnock: 'lp2' }, // inherent knock, beaten: no penalty
        { scores: [10, 0, 4], knockedBy: 'lp1', knockResult: 'incorrect' }, // marked failed, though tied
      ])],
    }
    const game = convertLegacy(data, () => 'a'.repeat(64)).games[0]
    const folded = fold(game)
    expect(folded.rounds).toHaveLength(4)
    const [tied, unknown, inherent, failed] = folded.rounds
    const [a, b, c] = [0, 1, 2].map((index) => seatIdOf(folded.seats[index].player))
    expect(tied.knocker).toBe(a)
    expect(outcomeOf(tied)).toBe('tied')
    expect(unknown.knocker).toBeUndefined()
    expect(outcomeOf(unknown)).toBeNull()
    expect(inherent.knocker).toBe(b)
    expect(inherent.inherent).toBe(b)
    expect(inherent.hands[b]).toBe(0)
    expect(outcomeOf(failed)).toBe('failed')
    const totals = gameTotals(folded)
    expect([totals[a], totals[b], totals[c]]).toEqual([0 + 4 + 7 + 10, 6 + 5 + 0 + 0, 8 - 1 - 2 + 4])
    // Knock stats count only recorded regular knocks.
    const projection = projectFinishedGame(folded)
    const row = projection?.seats.find((entry) => entry.seatId === a)
    expect([row?.knocks, row?.knocksTied, row?.knocksFailed]).toEqual([2, 1, 1])
    expect(projection?.seats.find((entry) => entry.seatId === b)?.knocks).toBe(0)
  })

  test('imported games are claimable: a code moves the history onto the account', async () => {
    const h = harness()
    const data = { players, games: [legacyGame('g1', [{ scores: [-10, 6, 9], knockedBy: 'lp1' }, { scores: [5, 5, 12] }, { scores: [14, 1, 3], knockedBy: 'lp1' }])] }
    const report = await importLegacy(data, { store: h.store, services: h.services, apply: true })
    expect(report.imported).toBe(1)
    expect(h.store.finished.size).toBe(1)
    // Idempotent.
    const codes = Object.fromEntries(report.codes.map((row) => [row.legacyId, row.claimCode]))
    expect((await importLegacy(data, { store: h.store, services: h.services, existingCodes: codes, apply: true })).alreadyImported).toBe(1)

    const me = '000000aa-0000-4000-8000-000000000042'
    await h.profile(me, 'Noah', 'noah')
    const noahCode = report.codes.find((row) => row.legacyId === 'lp1')?.claimCode ?? ''
    const claim = await h.post<{ gamesClaimed: number; guestId: string }>('/v1/claims', me, { claimToken: noahCode })
    expect(claim.status).toBe(200)
    expect(claim.body.gamesClaimed).toBe(1)
    const mine = await h.get<{ games: { gameId: string }[]; claimedGuestIds: string[] }>('/v1/players/me/games', me)
    expect(mine.body.games).toHaveLength(1)
    expect(mine.body.claimedGuestIds).toEqual([claim.body.guestId])
    // The claimer's phone can now pull the game's log.
    expect((await h.get(`/v1/games/${mine.body.games[0].gameId}/ops`, me)).status).toBe(200)
  })

  test('a game under 3 rounds is imported as history but not counted for stats', async () => {
    const h = harness()
    const data = { players, games: [legacyGame('g1', [{ scores: [-10, 6, 9], knockedBy: 'lp1' }, { scores: [5, 5, 12] }])] }
    const report = await importLegacy(data, { store: h.store, services: h.services, apply: true })
    expect(report.imported).toBe(1)
    expect(h.store.finished.size).toBe(0)
  })

  test("the web app's leaderboard (legacyLeaderboard) is the server's board for the same history", async () => {
    // Six varied games with a tie, a knock of each kind, an inherent knock, a deleted player's
    // seat and a short game, so ratings, minimums and Not Yet Ranked all come into play.
    const dan = { id: 'lp4', username: 'dan', emoji: '🎲', deleted: true }
    const scores = [[3, 9, 5], [-10, 4, 6], [7, 7, 2], [0, 5, -1], [16, 2, 8], [4, 4, 9]]
    const games = Array.from({ length: 7 }, (_, index) =>
      legacyGame(`g${index}`, scores.slice(0, index === 6 ? 2 : 3 + (index % 3)).map((round, r) => ({
        scores: round.map((score) => score + index - r),
        knockedBy: r === 1 ? players[index % 3].id : null,
        knockResult: r === 1 ? 'incorrect' : undefined,
      }))),
    )
    games[2].players[2] = { ...dan, total: 0 }
    for (const round of games[2].rounds) round.scores[2].playerId = dan.id
    games[3].rounds[0].inherentKnock = 'lp1'
    const data = { players: [...players, dan], games }

    const h = harness()
    await seedFromLegacy({ kedro_players: data.players, kedro_games: data.games }, h)
    const viewer = (await h.store.listPlayers({ offset: 0, limit: 10 }))[0].id
    const names = new Map(data.players.map((player) => [player.id, player.username]))
    for (const sort of LEADERBOARD_SORTS) {
      const server = (await h.get(`/v1/leaderboard?scope=global&sort=${sort}`, viewer)).body
      const web = legacyLeaderboard(data, sort)
      const webRows = web.rows.map((row) => [names.get(row.subject.slice(2)), row.rank, row.value, row.rating, row.stats.wins, row.stats.knocks] as const)
      const serverRows = server.rows.map((row: any) => [row.player.displayName, row.rank, row.value, row.rating, row.wins, row.knocks] as const)
      // Same rows with the same ranks. Within a tie the order falls back to IDs, which differ
      // between the legacy history and the server, so tied rows are compared as a group.
      const grouped = (rows: readonly (readonly unknown[])[]) => rows.map((row) => `${row[1] ?? '–'}|${row.join('|')}`).sort()
      expect(grouped(webRows)).toEqual(grouped(serverRows))
      expect(webRows.map((row) => row[1])).toEqual(serverRows.map((row: any) => row[1]))
      expect(web.notYetRanked.map((row) => names.get(row.subject.slice(2))).sort()).toEqual(server.notYetRanked.map((row: any) => row.player.displayName).sort())
    }
    expect(legacyLeaderboard(data, 'rating').rows.length).toBeGreaterThan(0)
  })

  test('legacyFinishedAtMs matches the finish time the imported op log folds to', () => {
    const game = legacyGame('timing', [{ scores: [3, 9, 5] }, { scores: [4, 2, 6] }, { scores: [5, 7, 1] }])
    const [converted] = convertLegacy({ players, games: [game] }, () => 'a'.repeat(64)).games
    const rounds = legacyRounds(game, (id) => seatIdOf({ kind: 'guest', id }))
    if ('skipped' in rounds) throw new Error(rounds.skipped)
    expect(fold(converted).finishedAtMs).toBe(legacyFinishedAtMs(game, rounds.timestamps))
    expect(fold(converted).finishedAtMs).toBe(game.endedAt)
    const unended = { ...game, endedAt: undefined }
    expect(fold(convertLegacy({ players, games: [unended] }, () => 'a'.repeat(64)).games[0]).finishedAtMs).toBe(legacyFinishedAtMs(unended, rounds.timestamps))
  })
})
