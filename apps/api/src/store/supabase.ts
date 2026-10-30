// The production Store: Supabase Postgres (supabase/migrations/0002_kedro_v3.sql) through
// PostgREST with the service-role key. The service role bypasses RLS, so every access rule is
// enforced by the services before they get here.

import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import {
  aggregateStats,
  parseHlc,
  type Avatar,
  type FinishedGameProjection,
  type GameStatus,
  type OperationType,
  type PlayerStats,
  type Rating,
  type RatingChange,
  type ReportRequest,
  type StatsRow,
  type UUID,
  type WireOperation,
} from '@kedro/shared'
import {
  HandleTakenError,
  type ClaimResult,
  type FinishedSeatRow,
  type GameRow,
  type GuestRegistration,
  type GuestSuggestionRow,
  type OpRow,
  type PlayedWithRow,
  type PlayerGameRow,
  type PlayerRow,
  type PlayerUpdate,
  type PushTokenRow,
  type SeatRow,
  type Store,
} from './types.ts'
import { orderStatsRows, guestSuggestionsFrom, playedWithFrom, type FinishedSeatDetail } from './shared.ts'

const PAGE = 1000
/** PostgREST `in.(…)` filters travel in the URL; keep lists comfortably short. */
const IN_CHUNK = 150
const UNIQUE_VIOLATION = '23505'

type Row = Record<string, unknown>

export class SupabaseStore implements Store {
  private readonly db: SupabaseClient

  constructor(options: { url: string; serviceRoleKey: string } | { client: SupabaseClient }) {
    this.db =
      'client' in options
        ? options.client
        : createClient(options.url, options.serviceRoleKey, {
            auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
          })
  }

  // MARK: Ops

  async getOps(gameId: UUID, options: { after?: string; limit?: number } = {}): Promise<WireOperation[]> {
    const rows: Row[] = []
    const wanted = options.limit ?? Number.POSITIVE_INFINITY
    for (let from = 0; rows.length < wanted; from += PAGE) {
      let query = this.db
        .from('ops')
        .select('op_id, game_id, hlc, device_id, actor, type, payload')
        .eq('game_id', gameId)
        .order('hlc')
        .order('device_id')
        .order('op_id')
      if (options.after !== undefined) query = query.gt('hlc', options.after)
      const to = from + Math.min(PAGE, wanted - rows.length) - 1
      const page = must(await query.range(from, to))
      rows.push(...page)
      if (page.length < to - from + 1) break
    }
    return rows.map(toWireOperation)
  }

  async existingOpIds(opIds: readonly UUID[]): Promise<Set<UUID>> {
    const found = new Set<UUID>()
    for (const ids of chunks(opIds, IN_CHUNK)) {
      const rows = must(await this.db.from('ops').select('op_id').in('op_id', ids))
      for (const row of rows) found.add(String(row.op_id))
    }
    return found
  }

  async insertOps(rows: readonly OpRow[]): Promise<UUID[]> {
    if (rows.length === 0) return []
    const inserted: UUID[] = []
    for (const batch of chunks(rows, 500)) {
      const records = batch.map(({ operation, hlc, receivedBy }) => ({
        op_id: operation.opId,
        game_id: operation.gameId,
        hlc,
        device_id: operation.deviceId,
        actor: operation.actorPlayerId,
        type: operation.type,
        payload: operation.payload ?? {},
        received_by: receivedBy,
      }))
      // ON CONFLICT DO NOTHING: RETURNING lists only the rows actually inserted.
      const result = must(await this.db.from('ops').upsert(records, { onConflict: 'op_id', ignoreDuplicates: true }).select('op_id'))
      for (const row of result) inserted.push(String(row.op_id))
    }
    return inserted
  }

  // MARK: Games

  async getGame(gameId: UUID): Promise<GameRow | null> {
    const row = maybe(await this.db.from('games').select('*').eq('id', gameId).maybeSingle())
    return row ? toGameRow(row) : null
  }

  async ensureGame(gameId: UUID, createdBy: UUID | null): Promise<void> {
    must(await this.db.from('games').upsert({ id: gameId, created_by: createdBy }, { onConflict: 'id', ignoreDuplicates: true }))
  }

  async syncGame(game: GameRow, seats: readonly SeatRow[]): Promise<void> {
    must(
      await this.db.rpc('kedro_sync_game', {
        p_game: {
          id: game.id,
          status: game.status,
          table_word: game.tableWord,
          planned_rounds: game.plannedRounds,
          scoring_mode: game.scoringMode,
          host_seat: game.hostSeat,
          rounds_played: game.roundsPlayed,
          started_at: game.startedAt,
          finished_at: game.finishedAt,
          finish_reason: game.finishReason,
          abandoned_at: game.abandonedAt,
          last_hlc: game.lastHlc,
        },
        p_seats: seats.map((seat) => ({
          seat_id: seat.seatId,
          player_id: seat.playerId,
          guest_id: seat.guestId,
          display_name: seat.displayName,
          seat_order: seat.seatOrder,
          device_id: seat.deviceId,
        })),
      }),
    )
  }

  async isSeated(gameId: UUID, playerId: UUID): Promise<boolean> {
    const game = maybe(await this.db.from('games').select('created_by').eq('id', gameId).maybeSingle())
    if (!game) return false
    if (game.created_by === playerId) return true
    const seats = must(await this.db.from('seats').select('player_id, guest_id').eq('game_id', gameId))
    if (seats.some((seat) => seat.player_id === playerId)) return true
    const guestIds = seats.map((seat) => seat.guest_id).filter((id): id is string => typeof id === 'string')
    if (guestIds.length === 0) return false
    const claimed = must(await this.db.from('guests').select('id').in('id', guestIds).eq('claimed_by', playerId).limit(1))
    return claimed.length > 0
  }

  async gamesFor(playerId: UUID): Promise<PlayerGameRow[]> {
    const direct = must(await this.db.from('seats').select('game_id').eq('player_id', playerId))
    const guests = must(await this.db.from('guests').select('id').eq('claimed_by', playerId))
    const guestIds = guests.map((row) => String(row.id))
    const viaGuests: Row[] = []
    for (const ids of chunks(guestIds, IN_CHUNK)) {
      viaGuests.push(...must(await this.db.from('seats').select('game_id').in('guest_id', ids)))
    }
    const gameIds = [...new Set([...direct, ...viaGuests].map((row) => String(row.game_id)))]
    const games: PlayerGameRow[] = []
    for (const ids of chunks(gameIds, IN_CHUNK)) {
      const rows = must(await this.db.from('games').select('id, status, finished_at, last_hlc').in('id', ids))
      games.push(...rows.map((row) => ({
        gameId: String(row.id),
        status: row.status as GameStatus,
        finishedAt: (row.finished_at as string | null) ?? null,
        lastHlc: (row.last_hlc as string | null) ?? null,
      })))
    }
    return games.sort((a, b) => (b.lastHlc ?? '').localeCompare(a.lastHlc ?? '') || a.gameId.localeCompare(b.gameId))
  }

  async claimedGuestIds(playerId: UUID): Promise<UUID[]> {
    const rows = must(await this.db.from('guests').select('id').eq('claimed_by', playerId))
    return rows.map((row) => String(row.id)).sort()
  }

  async receivedAt(opIds: readonly UUID[]): Promise<Map<UUID, number>> {
    const found = new Map<UUID, number>()
    for (const ids of chunks(opIds, IN_CHUNK)) {
      const rows = must(await this.db.from('ops').select('op_id, received_at').in('op_id', ids))
      for (const row of rows) found.set(String(row.op_id), Date.parse(String(row.received_at)))
    }
    return found
  }

  async inviteKey(gameId: UUID): Promise<string | null> {
    const row = maybe(await this.db.from('game_invite_keys').select('invite_key').eq('game_id', gameId).maybeSingle())
    return row ? String(row.invite_key) : null
  }

  async setInviteKey(gameId: UUID, key: string, registeredBy: UUID): Promise<string> {
    must(
      await this.db
        .from('game_invite_keys')
        .upsert({ game_id: gameId, invite_key: key, registered_by: registeredBy }, { onConflict: 'game_id', ignoreDuplicates: true }),
    )
    return (await this.inviteKey(gameId)) ?? key
  }

  // MARK: Finished games and ratings

  async projectFinishedGame(projection: FinishedGameProjection): Promise<void> {
    must(
      await this.db.rpc('kedro_project_finished_game', {
        p_game: {
          game_id: projection.gameId,
          finished_at_ms: projection.finishedAtMs,
          finish_reason: projection.finishReason,
          planned_rounds: projection.plannedRounds,
          rounds_played: projection.rounds.length,
          table_word: projection.tableWord,
          rounds: projection.rounds,
          is_abandoned: false,
        },
        p_seats: projection.seats.map((seat) => ({
          seat_id: seat.seatId,
          player_id: seat.playerId,
          guest_id: seat.guestId,
          display_name: seat.displayName,
          seat_order: seat.seatOrder,
          total: seat.total,
          rank: seat.rank,
          rank_shared: seat.rankShared,
          is_winner: seat.isWinner,
          rounds_played: seat.roundsPlayed,
          knocks: seat.knocks,
          knocks_landed: seat.knocksLanded,
          knocks_tied: seat.knocksTied,
          knocks_failed: seat.knocksFailed,
          lowest_hand: seat.lowestHand,
          highest_hand: seat.highestHand,
        })),
      }),
    )
  }

  async setFinishedGameAbandoned(gameId: UUID, abandoned: boolean): Promise<void> {
    must(await this.db.rpc('kedro_set_finished_game_abandoned', { p_game: gameId, p_abandoned: abandoned }))
  }

  async finishedSeatRows(): Promise<FinishedSeatRow[]> {
    return (await this.finishedSeats()).map(({ gameId, finishedAtMs, seatId, playerId, guestId, seatOrder, total }) => ({
      gameId, finishedAtMs, seatId, playerId, guestId, seatOrder, total,
    }))
  }

  async replaceRatings(ratings: readonly Rating[], changes: readonly RatingChange[]): Promise<void> {
    const refs = (subject: string) => ({
      player_id: subject.startsWith('p:') ? subject.slice(2) : null,
      guest_id: subject.startsWith('g:') ? subject.slice(2) : null,
    })
    must(
      await this.db.rpc('kedro_replace_ratings', {
        p_ratings: ratings.map((rating) => ({
          subject: rating.subject,
          ...refs(rating.subject),
          rating: rating.rating,
          games: rating.games,
          last_game_id: rating.lastGameId,
        })),
        p_changes: changes.map((change) => ({
          game_id: change.gameId,
          subject: change.subject,
          player_id: refs(change.subject).player_id,
          before: change.before,
          after: change.after,
          delta: change.delta,
          game_number: change.gameNumber,
        })),
      }),
    )
  }

  async ratings(subjects?: readonly string[]): Promise<Map<string, Rating>> {
    const rows: Row[] = []
    if (subjects) {
      for (const list of chunks(subjects, IN_CHUNK)) rows.push(...must(await this.db.from('ratings').select('*').in('subject', list)))
    } else {
      rows.push(...(await this.paged((from, to) => this.db.from('ratings').select('*').not('player_id', 'is', null).order('subject').range(from, to))))
    }
    return new Map(
      rows.map((row) => [
        String(row.subject),
        { subject: String(row.subject), rating: Number(row.rating), games: Number(row.games), lastGameId: (row.last_game_id as string | null) ?? null },
      ]),
    )
  }

  async playerStats(playerIds?: readonly UUID[]): Promise<PlayerStats[]> {
    const seats = await this.finishedSeats(playerIds ? { column: 'player_id', values: playerIds } : undefined)
    const rows: StatsRow[] = orderStatsRows(seats.filter((seat) => seat.playerId !== null))
    const wanted = playerIds ? new Set(playerIds.map((id) => `p:${id}`)) : null
    return [...aggregateStats(rows).values()].filter((entry) => !wanted || wanted.has(entry.subject))
  }

  async playedWith(playerId: UUID): Promise<PlayedWithRow[]> {
    return playedWithFrom(await this.finishedSeatsOfGamesWith(playerId), playerId)
  }

  async guestSuggestions(playerId: UUID, name: string): Promise<GuestSuggestionRow[]> {
    return guestSuggestionsFrom(await this.finishedSeatsOfGamesWith(playerId), playerId, name)
  }

  /** Seats of finished, non-abandoned games: all of them, or only those matching `filter`. */
  private async finishedSeats(filter?: { column: 'player_id' | 'game_id'; values: readonly UUID[] }): Promise<FinishedSeatDetail[]> {
    const select =
      'game_id, seat_id, player_id, guest_id, display_name, seat_order, total, is_winner, rounds_played, knocks, knocks_landed, knocks_tied, knocks_failed, finished_games!inner(finished_at_ms, is_abandoned)'
    const fetch = (values?: readonly UUID[]) =>
      this.paged((from, to) => {
        let query = this.db.from('finished_game_seats').select(select).eq('finished_games.is_abandoned', false)
        if (filter && values) query = query.in(filter.column, [...values])
        return query.order('game_id').order('seat_id').range(from, to)
      })
    const rows: Row[] = []
    if (filter) {
      for (const list of chunks(filter.values, IN_CHUNK)) rows.push(...(await fetch(list)))
    } else {
      rows.push(...(await fetch()))
    }
    return rows.map(toFinishedSeat)
  }

  private async finishedSeatsOfGamesWith(playerId: UUID): Promise<FinishedSeatDetail[]> {
    const mine = await this.finishedSeats({ column: 'player_id', values: [playerId] })
    const gameIds = [...new Set(mine.map((seat) => seat.gameId))]
    return gameIds.length === 0 ? [] : this.finishedSeats({ column: 'game_id', values: gameIds })
  }

  // MARK: Players

  async getPlayer(id: UUID): Promise<PlayerRow | null> {
    const row = maybe(await this.db.from('players').select('*').eq('id', id).maybeSingle())
    return row ? toPlayerRow(row) : null
  }

  async getPlayers(ids: readonly UUID[]): Promise<PlayerRow[]> {
    const rows: Row[] = []
    for (const list of chunks([...new Set(ids)], IN_CHUNK)) rows.push(...must(await this.db.from('players').select('*').in('id', list)))
    const byId = new Map(rows.map((row) => [String(row.id), toPlayerRow(row)]))
    return ids.flatMap((id) => {
      const row = byId.get(id)
      return row ? [row] : []
    })
  }

  async upsertPlayer(id: UUID, update: PlayerUpdate): Promise<PlayerRow> {
    const record: Row = { id, display_name: update.displayName, handle: update.handle, avatar: update.avatar }
    if (update.titleId !== undefined) record.title_id = update.titleId
    const { data, error } = await this.db.from('players').upsert(record, { onConflict: 'id' }).select('*').single()
    if (error?.code === UNIQUE_VIOLATION) throw new HandleTakenError()
    if (error) throw new Error(`players upsert: ${error.message}`)
    return toPlayerRow(data as Row)
  }

  async isHandleAvailable(handle: string, exceptPlayerId?: UUID): Promise<boolean> {
    let query = this.db.from('players').select('id').eq('handle', handle).limit(1)
    if (exceptPlayerId) query = query.neq('id', exceptPlayerId)
    return must(await query).length === 0
  }

  async searchPlayers(query: string, options: { limit: number; excludeIds: readonly UUID[]; handleOnly: boolean }): Promise<PlayerRow[]> {
    const pattern = escapeLike(query)
    const filter = options.handleOnly ? `handle.ilike.${quoteFilter(`${pattern}%`)}` : `handle.ilike.${quoteFilter(`${pattern}%`)},display_name.ilike.${quoteFilter(`%${pattern}%`)}`
    // Over-fetch so excluded players don't shrink the page, then rank: exact handle, handle prefix, name.
    const rows = must(await this.db.from('players').select('*').or(filter).order('display_name').limit(options.limit + options.excludeIds.length + 10))
    const excluded = new Set(options.excludeIds)
    const rank = (row: PlayerRow) => (row.handle === query ? 0 : row.handle.startsWith(query) ? 1 : 2)
    return rows
      .map(toPlayerRow)
      .filter((row) => !excluded.has(row.id))
      .sort((a, b) => rank(a) - rank(b) || a.displayName.toLowerCase().localeCompare(b.displayName.toLowerCase()))
      .slice(0, options.limit)
  }

  // MARK: Guests

  async registerGuests(guests: readonly GuestRegistration[]): Promise<void> {
    for (const guest of guests) {
      const base = { id: guest.id, display_name: guest.displayName, created_by: guest.createdBy }
      const first = await this.db.from('guests').upsert({ ...base, claim_token_hash: guest.claimTokenHash }, { onConflict: 'id', ignoreDuplicates: true })
      if (first.error?.code === UNIQUE_VIOLATION) {
        // Another guest already holds this token hash; keep the guest without one.
        must(await this.db.from('guests').upsert(base, { onConflict: 'id', ignoreDuplicates: true }))
      } else {
        must(first)
      }
      if (guest.claimTokenHash) {
        // The first hash recorded wins; fill it in if the guest was first seen without one.
        const fill = await this.db.from('guests').update({ claim_token_hash: guest.claimTokenHash }).eq('id', guest.id).is('claim_token_hash', null)
        if (fill.error && fill.error.code !== UNIQUE_VIOLATION) must(fill)
      }
    }
  }

  async guestClaimTokenHash(guestId: UUID): Promise<string | null | undefined> {
    const row = maybe(await this.db.from('guests').select('claim_token_hash').eq('id', guestId).maybeSingle())
    if (!row) return undefined
    return (row.claim_token_hash as string | null) ?? null
  }

  async claimGuest(claimTokenHash: string, playerId: UUID): Promise<ClaimResult> {
    const { data, error } = await this.db.rpc('kedro_claim_guest', { p_token_hash: claimTokenHash, p_player: playerId })
    if (error?.message.includes('claim_not_found')) return { ok: false, reason: 'notFound' }
    if (error?.message.includes('claim_already_claimed')) return { ok: false, reason: 'alreadyClaimed' }
    if (error) throw new Error(`kedro_claim_guest: ${error.message}`)
    const row = (Array.isArray(data) ? data[0] : data) as Row | undefined
    if (!row) return { ok: false, reason: 'notFound' }
    return { ok: true, guestId: String(row.guest_id), gamesClaimed: Number(row.games_claimed ?? 0) }
  }

  // MARK: Safety

  async addBlock(blockerId: UUID, blockedId: UUID): Promise<void> {
    must(await this.db.from('blocks').upsert({ blocker_id: blockerId, blocked_id: blockedId }, { onConflict: 'blocker_id,blocked_id', ignoreDuplicates: true }))
  }

  async removeBlock(blockerId: UUID, blockedId: UUID): Promise<void> {
    must(await this.db.from('blocks').delete().eq('blocker_id', blockerId).eq('blocked_id', blockedId))
  }

  async blockRelations(playerId: UUID): Promise<{ blocked: Set<UUID>; blockedBy: Set<UUID> }> {
    const rows = must(await this.db.from('blocks').select('blocker_id, blocked_id').or(`blocker_id.eq.${playerId},blocked_id.eq.${playerId}`))
    const blocked = new Set<UUID>()
    const blockedBy = new Set<UUID>()
    for (const row of rows) {
      if (row.blocker_id === playerId) blocked.add(String(row.blocked_id))
      if (row.blocked_id === playerId) blockedBy.add(String(row.blocker_id))
    }
    return { blocked, blockedBy }
  }

  async addReport(reporterId: UUID, report: ReportRequest): Promise<void> {
    must(
      await this.db.from('reports').insert({
        reporter_id: reporterId,
        target_type: report.targetType,
        target_id: report.targetId,
        game_id: report.gameId ?? null,
        reason: report.reason,
      }),
    )
  }

  async blocklistTerms(): Promise<string[]> {
    const rows = await this.paged((from, to) => this.db.from('taunt_blocklist').select('term').order('term').range(from, to))
    return rows.map((row) => String(row.term))
  }

  // MARK: Receipts and push

  async addReceipt(receipt: { gameId: UUID; fromPlayerId: UUID; toPlayerId: UUID; receiptKey: string }): Promise<boolean> {
    const rows = must(
      await this.db
        .from('receipts')
        .upsert(
          { game_id: receipt.gameId, from_player_id: receipt.fromPlayerId, to_player_id: receipt.toPlayerId, receipt_key: receipt.receiptKey },
          { onConflict: 'game_id,from_player_id,to_player_id', ignoreDuplicates: true },
        )
        .select('id'),
    )
    return rows.length > 0
  }

  async upsertPushToken(token: PushTokenRow): Promise<void> {
    // The unique index includes coalesce(game_id, …), which PostgREST can't target with
    // on_conflict, so look the row up first.
    let existing = this.db.from('push_tokens').select('id').eq('player_id', token.playerId).eq('kind', token.kind).eq('token', token.token).limit(1)
    existing = token.gameId ? existing.eq('game_id', token.gameId) : existing.is('game_id', null)
    const found = must(await existing)
    if (found.length > 0) {
      must(await this.db.from('push_tokens').update({ updated_at: new Date().toISOString() }).eq('id', String(found[0].id)))
      return
    }
    const { error } = await this.db.from('push_tokens').insert({ player_id: token.playerId, token: token.token, kind: token.kind, game_id: token.gameId })
    if (error && error.code !== UNIQUE_VIOLATION) throw new Error(`push_tokens insert: ${error.message}`)
  }

  async pushTokens(filter: { gameId?: UUID; playerIds?: readonly UUID[]; kind: PushTokenRow['kind'] }): Promise<PushTokenRow[]> {
    let query = this.db.from('push_tokens').select('player_id, token, kind, game_id').eq('kind', filter.kind)
    if (filter.gameId) query = query.eq('game_id', filter.gameId)
    if (filter.playerIds) query = query.in('player_id', [...filter.playerIds])
    return must(await query).map((row) => ({
      playerId: String(row.player_id),
      token: String(row.token),
      kind: row.kind as PushTokenRow['kind'],
      gameId: (row.game_id as string | null) ?? null,
    }))
  }

  // MARK: Photos

  async putPhoto(playerId: UUID, photo: { bytes: Uint8Array; contentType: string }): Promise<string> {
    const version = new Bun.CryptoHasher('sha256').update(photo.bytes).digest('hex').slice(0, 16)
    must(
      await this.db.from('player_photos').upsert(
        { player_id: playerId, photo: `\\x${Buffer.from(photo.bytes).toString('hex')}`, content_type: photo.contentType, version },
        { onConflict: 'player_id' },
      ),
    )
    return version
  }

  async getPhoto(playerId: UUID): Promise<{ bytes: Uint8Array; contentType: string; version: string } | null> {
    const row = maybe(await this.db.from('player_photos').select('photo, content_type, version').eq('player_id', playerId).maybeSingle())
    if (!row) return null
    // PostgREST returns bytea as "\x<hex>".
    const hex = String(row.photo).replace(/^\\x/, '')
    return { bytes: new Uint8Array(Buffer.from(hex, 'hex')), contentType: String(row.content_type), version: String(row.version) }
  }

  // MARK: Helpers

  private async paged(page: (from: number, to: number) => PromiseLike<Result>): Promise<Row[]> {
    const rows: Row[] = []
    for (let from = 0; ; from += PAGE) {
      const batch = must(await page(from, from + PAGE - 1))
      rows.push(...batch)
      if (batch.length < PAGE) return rows
    }
  }
}

// MARK: Mapping

type Result = { data: unknown; error: { message: string; code?: string } | null }

/** The rows of a successful query; throws on an error. */
function must(result: Result): Row[] {
  if (result.error) throw new Error(`Supabase: ${result.error.message}${result.error.code ? ` (${result.error.code})` : ''}`)
  return Array.isArray(result.data) ? (result.data as Row[]) : []
}

/** The single row of a `.maybeSingle()` query, or null; throws on an error. */
function maybe(result: Result): Row | null {
  if (result.error) throw new Error(`Supabase: ${result.error.message}${result.error.code ? ` (${result.error.code})` : ''}`)
  return (result.data as Row | null) ?? null
}

function toWireOperation(row: Row): WireOperation {
  const hlc = parseHlc(String(row.hlc))
  if (!hlc) throw new Error(`Stored op ${String(row.op_id)} has a malformed HLC`)
  return {
    opId: String(row.op_id),
    gameId: String(row.game_id),
    deviceId: String(row.device_id),
    hlc,
    actorPlayerId: (row.actor as string | null) ?? null,
    type: row.type as OperationType,
    payload: row.payload,
  }
}

function toGameRow(row: Row): GameRow {
  const text = (key: string) => (row[key] as string | null) ?? null
  return {
    id: String(row.id),
    createdBy: text('created_by'),
    status: row.status as GameStatus,
    tableWord: text('table_word'),
    plannedRounds: (row.planned_rounds as number | null) ?? null,
    scoringMode: text('scoring_mode'),
    hostSeat: text('host_seat'),
    roundsPlayed: Number(row.rounds_played ?? 0),
    startedAt: text('started_at'),
    finishedAt: text('finished_at'),
    finishReason: text('finish_reason'),
    abandonedAt: text('abandoned_at'),
    lastHlc: text('last_hlc'),
    liveActivityChannelId: text('live_activity_channel_id'),
  }
}

function toPlayerRow(row: Row): PlayerRow {
  return {
    id: String(row.id),
    displayName: String(row.display_name),
    handle: String(row.handle),
    avatar: row.avatar as Avatar,
    titleId: (row.title_id as string | null) ?? null,
    createdAt: String(row.created_at),
  }
}

function toFinishedSeat(row: Row): FinishedSeatDetail {
  const game = (Array.isArray(row.finished_games) ? row.finished_games[0] : row.finished_games) as Row | undefined
  return {
    gameId: String(row.game_id),
    finishedAtMs: Number(game?.finished_at_ms ?? 0),
    seatId: String(row.seat_id),
    playerId: (row.player_id as string | null) ?? null,
    guestId: (row.guest_id as string | null) ?? null,
    displayName: String(row.display_name),
    seatOrder: Number(row.seat_order ?? 0),
    total: Number(row.total),
    isWinner: Boolean(row.is_winner),
    roundsPlayed: Number(row.rounds_played),
    knocks: Number(row.knocks),
    knocksLanded: Number(row.knocks_landed),
    knocksTied: Number(row.knocks_tied),
    knocksFailed: Number(row.knocks_failed),
  }
}

function chunks<T>(items: readonly T[], size: number): T[][] {
  const result: T[][] = []
  for (let index = 0; index < items.length; index += size) result.push(items.slice(index, index + size))
  return result
}

/** Escapes LIKE wildcards in user input. */
function escapeLike(value: string): string {
  return value.replace(/[\\%_]/g, (char) => `\\${char}`)
}

/** Quotes a value for a PostgREST `or=(…)` filter (commas and parentheses are reserved). */
function quoteFilter(value: string): string {
  return `"${value.replace(/["\\]/g, (char) => `\\${char}`)}"`
}
