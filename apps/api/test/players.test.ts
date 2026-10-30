import { describe, expect, test } from 'bun:test'
import { replayRatings, displayRating, type WireOperation } from '@kedro/shared'
import { ratedGames } from '../src/services/ratings.ts'
import { claimTokenHash } from '../src/services/social.ts'
import { cloneGame, fixedUUID, gameUUID, harness, ids, sampleWireOperations, seats } from './support.ts'

const avatar = { kind: 'curated', id: 'horse' } as const

async function table() {
  const h = harness()
  await h.profile(ids.noah, 'Noah', 'noah')
  await h.profile(ids.ana, 'Ana', 'ana.k')
  await h.profile(ids.ben, 'Ben', 'ben')
  await h.profile(ids.cleo, 'Cleo', 'cleo')
  return h
}

/** The sample game with Sam's seat carrying a claim token hash. */
function sampleWithClaimToken(token: string): WireOperation[] {
  return sampleWireOperations().map((op) => {
    if (op.type !== 'PlayerSeated') return op
    const payload = op.payload as { seat: { player: { kind: string } } }
    if (payload.seat.player.kind !== 'guest') return op
    return { ...op, payload: { seat: { ...payload.seat, claimTokenHash: claimTokenHash(token) } } }
  })
}

describe('players', () => {
  test('GET /me before a profile exists is profileRequired; PUT creates it', async () => {
    const h = harness()
    const before = await h.get('/v1/players/me', ids.noah)
    expect(before.status).toBe(404)
    expect(before.body.error).toBe('profileRequired')

    const put = await h.put('/v1/players/me', ids.noah, { displayName: ' Noah ', handle: '@Noah', avatar })
    expect(put.status).toBe(200)
    expect(put.body).toMatchObject({ id: ids.noah, displayName: 'Noah', handle: 'noah', avatar })
    expect(put.body.createdAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
    expect((await h.get('/v1/players/me', ids.noah)).body.handle).toBe('noah')
  })

  test('handles are unique and validated', async () => {
    const h = harness()
    await h.profile(ids.noah, 'Noah', 'noah')
    const taken = await h.put('/v1/players/me', ids.ana, { displayName: 'Ana', handle: 'noah', avatar })
    expect(taken.status).toBe(409)
    expect(taken.body.error).toBe('handleTaken')
    expect((await h.put('/v1/players/me', ids.ana, { displayName: 'Ana', handle: 'no', avatar })).status).toBe(400)
    expect((await h.put('/v1/players/me', ids.ana, { displayName: 'Ana', handle: 'ana-k', avatar })).status).toBe(400)
    // Keeping your own handle is fine.
    expect((await h.put('/v1/players/me', ids.noah, { displayName: 'Noah J', handle: 'noah', avatar })).status).toBe(200)
    expect((await h.get('/v1/handles/NOAH', ids.ana)).body).toEqual({ handle: 'noah', available: false })
    expect((await h.get('/v1/handles/noah', ids.noah)).body).toEqual({ handle: 'noah', available: true })
  })

  test('search by name or @handle, excluding yourself and blocked players both ways', async () => {
    const h = await table()
    const byName = await h.get('/v1/players/search?q=an', ids.noah)
    expect(byName.body.players.map((p: { handle: string }) => p.handle)).toEqual(['ana.k'])
    expect((await h.get('/v1/players/search?q=@be', ids.noah)).body.players.map((p: { handle: string }) => p.handle)).toEqual(['ben'])
    expect((await h.get('/v1/players/search?q=noah', ids.noah)).body.players).toEqual([])
    expect((await h.get('/v1/players/search?q=', ids.noah)).body.players).toEqual([])

    expect((await h.post('/v1/blocks', ids.ana, { playerId: ids.noah })).body).toEqual({ ok: true })
    expect((await h.get('/v1/players/search?q=an', ids.noah)).body.players).toEqual([])
    expect((await h.get(`/v1/players/${ids.ana}`, ids.noah)).status).toBe(404)
    expect((await h.del(`/v1/blocks/${ids.noah.toUpperCase()}`, ids.ana)).body).toEqual({ ok: true })
    expect((await h.get('/v1/players/search?q=an', ids.noah)).body.players).toHaveLength(1)
  })

  test('the directory lists everyone A–Z in pages, without you or blocked players', async () => {
    const h = await table()
    const all = await h.get('/v1/players', ids.noah)
    expect(all.status).toBe(200)
    const names = all.body.players.map((p: { displayName: string }) => p.displayName)
    expect(names).not.toContain('Noah')
    expect(names).toEqual([...names].sort((a: string, b: string) => a.toLowerCase().localeCompare(b.toLowerCase())))
    expect(all.body.next).toBeNull()

    const first = await h.get('/v1/players?limit=1', ids.noah)
    expect(first.body.next).toBe('1')
    const pages: string[] = []
    let cursor: string | null = ''
    while (cursor !== null) {
      const page: { body: { players: { displayName: string }[]; next: string | null } } = await h.get(`/v1/players?limit=1&cursor=${cursor}`, ids.noah)
      pages.push(...page.body.players.map((p) => p.displayName))
      cursor = page.body.next
    }
    expect(pages).toEqual(names)

    await h.post('/v1/blocks', ids.ana, { playerId: ids.noah })
    expect((await h.get('/v1/players', ids.noah)).body.players.map((p: { handle: string }) => p.handle)).not.toContain('ana.k')
    expect((await h.get('/v1/players?cursor=nope', ids.noah)).status).toBe(400)
  })

  test('blocking yourself or nobody is refused', async () => {
    const h = await table()
    expect((await h.post('/v1/blocks', ids.ana, { playerId: ids.ana })).status).toBe(400)
    expect((await h.post('/v1/blocks', ids.ana, { playerId: fixedUUID(1, 66) })).status).toBe(404)
  })

  test('played with and guest suggestions come from finished games', async () => {
    const h = await table()
    await h.upload(ids.noah, sampleWireOperations())
    const playedWith = await h.get('/v1/players/me/played-with', ids.noah)
    expect(playedWith.body.players.map((row: { player: { handle: string }; gamesTogether: number }) => [row.player.handle, row.gamesTogether])).toEqual([
      ['ana.k', 1],
      ['ben', 1],
      ['cleo', 1],
    ])
    expect(playedWith.body.players[0].lastPlayedAt).toMatch(/Z$/)
    const guests = await h.get('/v1/players/me/guests?name=sa', ids.noah)
    expect(guests.body.guests).toEqual([{ guestId: ids.sam, name: 'Sam', gamesTogether: 1 }])
    const summary = await h.get(`/v1/players/${ids.ana}`, ids.noah)
    expect(summary.body).toMatchObject({ id: ids.ana, handle: 'ana.k', gamesPlayed: 1 })
  })
})

describe('claims', () => {
  test("claiming a guest moves their finished games to the player, once", async () => {
    const h = await table()
    const token = 'sam-claim-token-0123456789abcdef'
    await h.upload(ids.noah, sampleWithClaimToken(token))
    const samAccount = fixedUUID(1, 5)
    await h.profile(samAccount, 'Sam', 'sam')

    const claim = await h.post('/v1/claims', samAccount, { claimToken: token })
    expect(claim.status).toBe(200)
    expect(claim.body).toEqual({ guestId: ids.sam, gamesClaimed: 1 })

    // Sam's game now counts for the account, and the account can read the game.
    const me = await h.get(`/v1/players/${samAccount}`, ids.noah)
    expect(me.body.gamesPlayed).toBe(1)
    expect(h.store.ratingRows.get(`p:${samAccount}`)?.rating).toBeLessThan(1000)
    expect(h.store.ratingRows.has(seats.sam)).toBe(false)
    expect((await h.get(`/v1/games/${ids.game}/ops`, samAccount)).status).toBe(200)

    const again = await h.post('/v1/claims', fixedUUID(1, 6), { claimToken: token })
    expect(again.status).toBe(404) // no profile yet → profileRequired
    await h.profile(fixedUUID(1, 6), 'Imposter', 'imposter')
    const twice = await h.post('/v1/claims', fixedUUID(1, 6), { claimToken: token })
    expect(twice.status).toBe(409)
    expect(twice.body.error).toBe('alreadyClaimed')
  })

  test('an unknown claim token is 404', async () => {
    const h = await table()
    const response = await h.post('/v1/claims', ids.noah, { claimToken: 'nothing-matches-this-token' })
    expect(response.status).toBe(404)
    expect(response.body.error).toBe('notFound')
  })
})

describe('taunts, reports, receipts, push', () => {
  test('POST /v1/taunts/check: profanity is fine, listed terms and long text are not', async () => {
    const h = await table()
    h.store.blocklist = ['zorpface']
    expect((await h.post('/v1/taunts/check', ids.noah, { text: 'Damn, Ana. Pay up.' })).body).toEqual({ allowed: true })
    expect((await h.post('/v1/taunts/check', ids.noah, { text: 'z.o.r.p.f.a.c.e' })).body).toEqual({ allowed: false, reason: 'blockedTerm' })
    expect((await h.post('/v1/taunts/check', ids.noah, { text: 'x'.repeat(81) })).body).toEqual({ allowed: false, reason: 'tooLong' })
    expect((await h.post('/v1/taunts/check', ids.noah, { text: '   ' })).body).toEqual({ allowed: false, reason: 'empty' })
  })

  test('reports are stored for review', async () => {
    const h = await table()
    const response = await h.post('/v1/reports', ids.ana, { targetType: 'taunt', targetId: fixedUUID(5, 1), reason: 'Not funny', gameId: ids.game })
    expect(response.body).toEqual({ ok: true })
    expect(h.store.reports).toHaveLength(1)
    expect(h.store.reports[0]).toMatchObject({ reporterId: ids.ana, targetType: 'taunt', reason: 'Not funny' })
    expect('gameId' in h.store.reports[0]).toBe(false) // the game isn't known to the server, so the context is dropped
    expect((await h.post('/v1/reports', ids.ana, { targetType: 'cat', targetId: 'x', reason: 'y' })).status).toBe(400)
  })

  test('receipts: one per rival per game, only between people at the table', async () => {
    const h = await table()
    await h.upload(ids.noah, sampleWireOperations())
    const body = { gameId: ids.game, toPlayerId: ids.ana, receiptKey: 'RC-03' }
    expect((await h.post('/v1/receipts', ids.noah, body)).body).toEqual({ ok: true })
    expect((await h.post('/v1/receipts', ids.noah, body)).body).toEqual({ ok: true })
    expect(h.store.receipts.size).toBe(1)
    expect((await h.post('/v1/receipts', ids.noah, { ...body, toPlayerId: ids.noah })).status).toBe(400)
    const stranger = fixedUUID(1, 40)
    await h.profile(stranger, 'Stranger', 'stranger')
    expect((await h.post('/v1/receipts', stranger, body)).status).toBe(403)
    expect((await h.post('/v1/receipts', ids.noah, { ...body, toPlayerId: stranger })).status).toBe(400)
  })

  test('push tokens: hex only; per-game Live Activity tokens need a seat', async () => {
    const h = await table()
    await h.upload(ids.noah, sampleWireOperations({ throughRound: 2, finished: false }))
    const token = 'AB'.repeat(32)
    expect((await h.post('/v1/push/tokens', ids.noah, { token, kind: 'apns' })).body).toEqual({ ok: true })
    expect((await h.post('/v1/push/tokens', ids.noah, { token, kind: 'apns' })).body).toEqual({ ok: true })
    expect((await h.post('/v1/push/tokens', ids.noah, { token, kind: 'liveactivity', gameId: ids.game })).body).toEqual({ ok: true })
    expect(h.store.tokens.size).toBe(2)
    expect([...h.store.tokens.values()][0].token).toBe(token.toLowerCase())
    expect((await h.post('/v1/push/tokens', ids.noah, { token: 'not hex', kind: 'apns' })).status).toBe(400)
    const stranger = fixedUUID(1, 41)
    await h.profile(stranger, 'Stranger', 'stranger2')
    expect((await h.post('/v1/push/tokens', stranger, { token, kind: 'liveactivity', gameId: ids.game })).status).toBe(403)
  })
})

describe('GET /v1/leaderboard', () => {
  async function history(games: number) {
    const h = await table()
    const base = sampleWireOperations()
    for (let index = 0; index < games; index++) {
      // A day apart, ending on the sample game's day (later ones would be in the future).
      await h.upload(ids.noah, cloneGame(base, gameUUID(index + 1), (index - games + 1) * 86_400_000))
    }
    return h
  }

  test('under ten games everyone is Not Yet Ranked', async () => {
    const h = await history(1)
    const response = await h.get('/v1/leaderboard', ids.noah)
    expect(response.status).toBe(200)
    expect(response.body.rows).toEqual([])
    expect(response.body.notYetRankedCount).toBe(4) // Sam is an unclaimed guest: never listed
    expect(response.body.notYetRanked.map((row: { player: { handle: string }; gamesToRank: number }) => [row.player.handle, row.gamesToRank])).toEqual([
      ['noah', 9],
      ['ana.k', 9],
      ['ben', 9],
      ['cleo', 9],
    ])
    expect(response.body.me).toMatchObject({ isMe: true, gamesPlayed: 1 })
  })

  test('ten games: ranked by the replayed rating, other sorts and minimums apply', async () => {
    const h = await history(10)
    const response = await h.get('/v1/leaderboard?scope=global&sort=rating', ids.ana)
    const rows = response.body.rows as { rank: number; value: number; rating: number; player: { id: string }; isMe: boolean; wins: number }[]
    expect(rows.map((row) => row.player.id)).toEqual([ids.noah, ids.ana, ids.cleo, ids.ben])
    expect(rows.map((row) => row.rank)).toEqual([1, 2, 3, 4])
    expect(rows[0].wins).toBe(10)
    expect(response.body.me.player.id).toBe(ids.ana)

    // The ratings match a replay of the same games.
    const expected = replayRatings(ratedGames(await h.store.finishedSeatRows())).ratings
    expect(rows[0].rating).toBe(displayRating(expected.get(seats.noah)?.rating ?? 0))

    // Win rate's 10-game minimum is the same as ranking's, so everyone ranked has a win rate.
    const winRate = await h.get('/v1/leaderboard?sort=winRate', ids.ana)
    expect(winRate.body.rows.map((row: { rank: number | null; value: number }) => [row.rank, row.value])).toEqual([[1, 1], [2, 0], [2, 0], [2, 0]])
    const knocks = await h.get('/v1/leaderboard?sort=knockSuccess', ids.ana)
    expect(knocks.body.rows.some((row: { rank: number | null; needs?: { knocks: number } }) => row.rank === null && (row.needs?.knocks ?? 0) > 0)).toBe(true)
    const avg = await h.get('/v1/leaderboard?sort=avgScore', ids.ana)
    expect(avg.body.rows.map((row: { value: number }) => row.value)).toEqual([28, 34, 65, 67])
  })

  test('played-with scope and validation', async () => {
    const h = await history(1)
    const loner = fixedUUID(1, 30)
    await h.profile(loner, 'Loner', 'loner')
    const response = await h.get('/v1/leaderboard?scope=playedWith', loner)
    expect(response.body.rows).toEqual([])
    expect(response.body.notYetRanked).toEqual([])
    expect((await h.get('/v1/leaderboard?sort=vibes', ids.noah)).status).toBe(400)
    expect((await h.get('/v1/leaderboard?scope=playedWith', ids.noah)).body.notYetRankedCount).toBe(4)
  })
})

describe('GET /v1/records', () => {
  type Row = { rank: number; value: number; isMe: boolean; player: { id: string }; game?: { gameId: string; tableWord: string; finishedAt: string } }
  type Records = { scope: string; records: { kind: string; rows: Row[] }[] }

  async function history(games: number) {
    const h = await table()
    const base = sampleWireOperations()
    for (let index = 0; index < games; index++) {
      // A day apart, ending on the sample game's day (later ones would be in the future).
      await h.upload(ids.noah, cloneGame(base, gameUUID(index + 1), (index - games + 1) * 86_400_000))
    }
    return h
  }
  const rows = (body: Records, kind: string) => body.records.find((record) => record.kind === kind)?.rows ?? []

  test('every record over everyone with a finished game, before anyone is ranked', async () => {
    const h = await history(2)
    const response = await h.get<Records>('/v1/records?scope=playedWith', ids.ana)
    expect(response.status).toBe(200)
    expect(response.body.scope).toBe('playedWith')
    expect(response.body.records.map((record) => record.kind)).toEqual(['bestGame', 'longestStreak', 'mostLandedKnocks', 'mostGames'])

    // Best game: lowest final score, with the game it was set in (the earliest when tied).
    const best = rows(response.body, 'bestGame')
    expect(best.map((row) => [row.player.id, row.value, row.rank])).toEqual([
      [ids.noah, 28, 1],
      [ids.ana, 34, 2],
      [ids.cleo, 65, 3],
      [ids.ben, 67, 4],
    ])
    expect(best[0].game).toEqual({ gameId: gameUUID(1), tableWord: 'Cold Deck', finishedAt: expect.any(String) })
    expect(best[1].isMe).toBe(true)

    // Only people with something toward a record are listed for it.
    expect(rows(response.body, 'longestStreak').map((row) => [row.player.id, row.value])).toEqual([[ids.noah, 2]])
    expect(rows(response.body, 'mostLandedKnocks').map((row) => [row.player.id, row.value])).toEqual([
      [ids.noah, 4],
      [ids.ana, 2],
    ])
    expect(rows(response.body, 'longestStreak')[0].game).toBeUndefined()

    // Ties share a rank. Sam, an unclaimed guest, is never listed.
    const games = rows(response.body, 'mostGames')
    expect(games).toHaveLength(4)
    expect(games.every((row) => row.rank === 1 && row.value === 2)).toBe(true)
  })

  test('played-with scope, blocks, limit and validation', async () => {
    const h = await history(1)
    const loner = fixedUUID(1, 30)
    await h.profile(loner, 'Loner', 'loner')
    const lonely = await h.get<Records>('/v1/records?scope=playedWith', loner)
    expect(lonely.body.records.every((record) => record.rows.length === 0)).toBe(true)
    // Global covers everyone.
    expect(rows((await h.get<Records>('/v1/records', loner)).body, 'mostGames')).toHaveLength(4)

    expect((await h.post('/v1/blocks', ids.ana, { playerId: ids.noah })).status).toBe(200)
    const blocked = await h.get<Records>('/v1/records?scope=global', ids.ana)
    expect(blocked.body.records.flatMap((record) => record.rows).some((row) => row.player.id === ids.noah)).toBe(false)

    expect(rows((await h.get<Records>('/v1/records?limit=1', ids.cleo)).body, 'bestGame').map((row) => row.player.id)).toEqual([ids.noah])
    expect((await h.get('/v1/records?scope=everyone', ids.noah)).status).toBe(400)
    expect((await h.get('/v1/records', null)).status).toBe(401)
  })
})
