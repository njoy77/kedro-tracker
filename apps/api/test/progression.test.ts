import { describe, expect, test } from 'bun:test'
import type { HallOfShameResponse, HeadToHeadResponse, PlayerProgressionResponse, WireOperation, WrappedResponse } from '@kedro/shared'
import { fixedUUID, ids, sampleWireOperations } from '../../../packages/shared/test/fixtures/sampleGame.ts'
import { claimTokenHash } from '../src/services/social.ts'
import { cloneGame, gameUUID, harness } from './support.ts'

const NOV_14_2026 = Date.UTC(2026, 10, 14, 17)
const DEC_2_2026 = Date.UTC(2026, 11, 2, 17)

/** Twelve copies of the sample game a day apart, ending on its day (Oct 24, 2026), uploaded by Noah. */
async function history({ now = NOV_14_2026, games = 12, ops = sampleWireOperations() }: { now?: number; games?: number; ops?: WireOperation[] } = {}) {
  let clock = now
  const h = harness({ now: () => clock })
  for (const [id, name, handle] of [[ids.noah, 'Noah', 'noah'], [ids.ana, 'Ana', 'ana.k'], [ids.ben, 'Ben', 'ben'], [ids.cleo, 'Cleo', 'cleo']]) {
    await h.profile(id, name, handle)
  }
  // Uploads happen "on the day"; the clock then moves to `now` for the reads.
  clock = Date.UTC(2026, 9, 25)
  for (let index = 0; index < games; index++) {
    const result = await h.upload(ids.noah, cloneGame(ops, gameUUID(index + 1), (index - games + 1) * 86_400_000))
    if (result.body.rejected.length > 0) throw new Error(JSON.stringify(result.body.rejected))
  }
  clock = now
  return { ...h, setNow: (ms: number) => { clock = ms } }
}

describe('progression', () => {
  test("a player's badges, next-up and titles, readable by anyone they haven't blocked", async () => {
    const h = await history()
    const mine = await h.get<PlayerProgressionResponse>('/v1/players/me/progression', ids.noah)
    expect(mine.status).toBe(200)
    expect(mine.body.playerId).toBe(ids.noah)
    const badges = mine.body.badges.map((badge) => badge.badge)
    // The sample game: Out of the Gate, First Blood, Ghost Hand, Comeback Kid; 12 straight wins.
    for (const badge of ['BG-01', 'BG-02', 'BG-15', 'BG-21', 'BG-19', 'BG-20', 'BG-03']) expect(badges).toContain(badge)
    expect(mine.body.badges[0]).toMatchObject({ badge: 'BG-01', gameId: gameUUID(1), tableWord: 'Cold Deck' })
    expect(mine.body.titles.earned).toEqual(expect.arrayContaining(['TI-01', 'TI-03', 'TI-04', 'TI-06']))
    expect(mine.body.titles.display).toBeNull()
    expect(mine.body.nextUp.length).toBeLessThanOrEqual(3)
    expect(mine.body.rivals.map((rival) => rival.games)).toEqual([12, 12, 12])

    // Ana sees Noah's, and her own.
    const seen = await h.get<PlayerProgressionResponse>(`/v1/players/${ids.noah}/progression`, ids.ana)
    expect(seen.body.badges).toEqual(mine.body.badges)
    const ana = await h.get<PlayerProgressionResponse>(`/v1/players/${ids.ana}/progression`, ids.noah)
    expect(ana.body.badges.map((badge) => badge.badge)).not.toContain('BG-02')

    // A chosen title shows only once it's earned.
    await h.put('/v1/players/me', ids.noah, { displayName: 'Noah', handle: 'noah', avatar: { kind: 'emoji', emoji: '🦊', colorIndex: 1 }, titleId: 'TI-04' })
    expect((await h.get<PlayerProgressionResponse>('/v1/players/me/progression', ids.noah)).body.titles.display).toBe('TI-04')

    // Blocked people can't read it.
    await h.post('/v1/blocks', ids.noah, { playerId: ids.ana })
    expect((await h.get(`/v1/players/${ids.noah}/progression`, ids.ana)).status).toBe(404)
  })

  test("a claimed guest's games count for the account from game 1", async () => {
    const token = 'kedro-legacy-sam-claim-token'
    const ops = sampleWireOperations().map((op) => {
      if (op.type !== 'PlayerSeated') return op
      const payload = op.payload as { seat: { player: { kind: string } } }
      return payload.seat.player.kind === 'guest' ? { ...op, payload: { seat: { ...payload.seat, claimTokenHash: claimTokenHash(token) } } } : op
    })
    const h = await history({ games: 3, ops })
    const sam = fixedUUID(1, 9)
    await h.profile(sam, 'Sam', 'sam')
    expect((await h.post('/v1/claims', sam, { claimToken: token })).status).toBe(200)
    const progression = await h.get<PlayerProgressionResponse>('/v1/players/me/progression', sam)
    // Sam's −1 in round 4 (Below Zero) came while seated as a guest.
    expect(progression.body.badges.map((badge) => badge.badge)).toEqual(expect.arrayContaining(['BG-01', 'BG-14']))
    expect(progression.body.rivals[0].games).toBe(3)
  })

  test('head-to-head from the caller’s games', async () => {
    const h = await history({ games: 3 })
    const h2h = await h.get<HeadToHeadResponse>(`/v1/players/me/head-to-head/${ids.ana}`, ids.noah)
    expect(h2h.status).toBe(200)
    expect(h2h.body).toMatchObject({ gamesTogether: 3, aAhead: 3, bAhead: 0, aWins: 3, bWins: 0 })
    expect(h2h.body.a).toMatchObject({ kind: 'player', id: ids.noah, displayName: 'Noah' })
    expect(h2h.body.b.displayName).toBe('Ana')
    expect(h2h.body.aKnocks).toEqual({ landed: 6, tied: 0, failed: 3 })
    expect(h2h.body.lastMeeting).toMatchObject({ gameId: gameUUID(3), aScore: 28, bScore: 34 })
  })

  test('the Hall of Shame: six categories, your people or yours', async () => {
    const h = await history({ games: 5 })
    const all = await h.get<HallOfShameResponse>('/v1/players/me/hall-of-shame', ids.noah)
    expect(all.status).toBe(200)
    expect(all.body.boards.map((board) => board.category)).toEqual(['worstHand', 'worstKnock', 'biggestLoss', 'bottleJob', 'ateIt', 'deepestHole'])
    // Learner games (each person's first 3) never count: games 4 and 5 do.
    const worstHand = all.body.boards[0].entries[0]
    expect(worstHand).toMatchObject({ person: { kind: 'guest', displayName: 'Sam' }, value: 21, roundNumber: 8, gameId: gameUUID(4) })
    const mine = await h.get<HallOfShameResponse>('/v1/players/me/hall-of-shame?scope=yours', ids.noah)
    expect(mine.body.boards.flatMap((board) => board.entries).every((entry) => entry.person.id === ids.noah)).toBe(true)
    expect((await h.get('/v1/players/me/hall-of-shame?scope=everyone', ids.noah)).status).toBe(400)
  })

  test('Wrapped: arrives December 1 in the player’s time zone, with 10+ games', async () => {
    const h = await history()
    const early = await h.get<WrappedResponse>('/v1/players/me/wrapped?tz=America/Los_Angeles', ids.noah)
    expect(early.body).toEqual({ year: 2026, availability: { kind: 'arrives', at: '2026-12-01T08:00:00.000Z' } })

    h.setNow(DEC_2_2026)
    const ready = await h.get<WrappedResponse>('/v1/players/me/wrapped', ids.noah)
    expect(ready.body.availability).toEqual({ kind: 'available' })
    const summary = ready.body.summary!
    expect(summary).toMatchObject({ year: 2026, games: 12, wins: 12, people: 4, ratingStart: 1000, currentRank: 1 })
    expect(summary.ratingLine).toHaveLength(13)
    expect(summary.knocks).toBe(36)
    expect(summary.victim?.person.kind).toBeDefined()
    expect(summary.nemesis).toBeNull()
    expect(summary.persona.name).toMatch(/^The /)
    expect(summary.badges.map((badge) => badge.badge)).toContain('BG-01')

    // Under 10 games: how many to go.
    const ana = await h.get<WrappedResponse>('/v1/players/me/wrapped?year=2025', ids.ana)
    expect(ana.body).toEqual({ year: 2025, availability: { kind: 'needsGames', played: 0, needed: 10 } })
    expect((await h.get('/v1/players/me/wrapped?tz=Mars/Base', ids.noah)).status).toBe(400)
    expect((await h.get('/v1/players/me/wrapped?year=26', ids.noah)).status).toBe(400)
  })
})
