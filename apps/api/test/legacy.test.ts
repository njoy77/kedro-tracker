import { describe, expect, test } from 'bun:test'
import { foldGame, gameTotals, parseOperation, roundScores, seatIdOf, type Operation } from '@kedro/shared'
import { convertLegacy, readLegacyExport, solveRound } from '../src/legacy/convert.ts'
import { importLegacy } from '../src/legacy/importer.ts'
import { harness } from './support.ts'

const players = [
  { id: 'lp1', username: 'noah', emoji: '🐴' },
  { id: 'lp2', username: 'ana', emoji: '🦄' },
  { id: 'lp3', username: 'ben', emoji: '🎯' },
]

/** A legacy game: scores per round (as the web app stored them) and who knocked. */
function legacyGame(id: string, rounds: { scores: number[]; knockedBy?: string | null }[], status = 'complete') {
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
    })),
  }
}

describe('legacy web history', () => {
  test('rounds are solved for hands that reproduce the legacy scores exactly', () => {
    const order = ['a', 'b', 'c']
    // Knocker strictly lowest (−10), tied (hand), beaten (hand + 10), and no knocker at all.
    for (const [scores, knocker] of [
      [{ a: -10, b: 4, c: 7 }, 'a'],
      [{ a: 3, b: 3, c: 9 }, 'a'],
      [{ a: 15, b: 2, c: 6 }, 'a'],
      [{ a: 4, b: 4, c: 8 }, null],
      [{ a: 2, b: 5, c: 18 }, null],
    ] as [Record<string, number>, string | null][]) {
      const solved = solveRound(scores, order, knocker)
      expect(solved).not.toBeNull()
      if (!solved) continue
      expect(roundScores(solved.hands, solved.knocker)).toEqual(scores)
    }
    // No knocker and no way to reproduce: a unique lowest, everyone else too close to be "beaten".
    expect(solveRound({ a: 1, b: 2, c: 3 }, order, null)).toBeNull()
  })

  test('converts finished games into valid op logs and skips what it cannot import', () => {
    const data = readLegacyExport([
      { key: 'kedro_players', value: players },
      {
        key: 'kedro_games',
        value: [
          legacyGame('g1', [{ scores: [-10, 6, 9], knockedBy: 'lp1' }, { scores: [5, 5, 12] }, { scores: [14, 1, 3], knockedBy: 'lp1' }]),
          legacyGame('g2', [{ scores: [1, 2, 3] }]),
          legacyGame('g3', [{ scores: [1, 2, 3] }], 'abandoned'),
        ],
      },
    ])
    const result = convertLegacy(data, (id) => `${id}`.padEnd(64, '0').replace(/[^0-9a-f]/g, 'a'))
    expect(result.games).toHaveLength(1)
    expect(result.skipped.map((row) => row.reason).sort()).toEqual(['abandoned', 'unrepresentableRound'])
    const ops = result.games[0].operations.map((wire) => {
      const parsed = parseOperation(wire)
      if (!parsed.ok) throw new Error(parsed.error)
      return parsed.value.operation as Operation
    })
    const folded = foldGame(ops, result.games[0].gameId)
    expect(folded.status).toBe('finished')
    // Totals match the legacy totals: 9, 12, 24.
    const totals = gameTotals(folded)
    expect(folded.seats.map((seat) => totals[seatIdOf(seat.player)])).toEqual([9, 12, 24])
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
})
