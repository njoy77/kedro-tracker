-- Kedro v3 schema (iOS flagship, PRD §6.4).
--
-- Games are an append-only operation log (`ops`); everything else about a game (`games`,
-- `seats`, `finished_games`, `finished_game_seats`, `ratings`) is a projection the API rebuilds
-- from that log with packages/shared (foldGame, projectFinishedGame, replayRatings).
--
-- The API writes with the service role (which bypasses RLS). RLS below is for anyone reading or
-- writing with a user JWT (the apps through PostgREST and Realtime):
--   - public profile data (players, ranked stats, ratings) is readable by any signed-in user;
--   - a game, its seats and its ops are readable only by people seated in it (or its creator);
--   - players can insert their own ops into games they're in, and nobody can update or delete ops.
--
-- The legacy `kedro_kv` table used by the web app (supabase/schema.sql) is left untouched.

create extension if not exists pg_trgm with schema extensions;

-- MARK: Helpers

create or replace function public.kedro_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- MARK: People

create table public.players (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  handle       text not null check (handle ~ '^[a-z0-9._]{3,20}$'),
  -- {"kind":"photo","url":…} | {"kind":"emoji","emoji":…,"colorIndex":0-11} | {"kind":"curated","id":…}
  avatar       jsonb not null check (jsonb_typeof(avatar) = 'object' and avatar ? 'kind'),
  title_id     text check (title_id ~ '^TI-[0-9]{2}$'),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create unique index players_handle_key on public.players (handle);
create index players_display_name_trgm on public.players using gin (lower(display_name) extensions.gin_trgm_ops);
create index players_handle_trgm on public.players using gin (handle extensions.gin_trgm_ops);

create trigger players_updated_at
  before update on public.players
  for each row execute function public.kedro_set_updated_at();

-- A name at a table with no account (PRD §3.2). Claimable once, by whoever holds the claim
-- token; only its SHA-256 is stored.
create table public.guests (
  id               uuid primary key,
  display_name     text not null check (char_length(display_name) between 1 and 40),
  created_by       uuid references public.players (id) on delete set null,
  claim_token_hash text unique check (claim_token_hash ~ '^[0-9a-f]{64}$'),
  claimed_by       uuid references public.players (id) on delete set null,
  claimed_at       timestamptz,
  created_at       timestamptz not null default now(),
  check ((claimed_by is null) = (claimed_at is null))
);

create index guests_claimed_by on public.guests (claimed_by) where claimed_by is not null;

-- MARK: Games

create table public.games (
  id                       uuid primary key,
  created_by               uuid references public.players (id) on delete set null,
  status                   text not null default 'lobby' check (status in ('lobby', 'active', 'finished', 'abandoned')),
  table_word               text,
  planned_rounds           integer check (planned_rounds between 1 and 50),
  scoring_mode             text check (scoring_mode in ('scorekeeper', 'selfReport')),
  host_seat                text,
  rounds_played            integer not null default 0,
  created_at               timestamptz not null default now(),
  started_at               timestamptz,
  finished_at              timestamptz,
  finish_reason            text check (finish_reason in ('completed', 'endedEarly', 'autoFinished')),
  abandoned_at             timestamptz,
  -- The newest op's HLC string (what a client passes as ?after= to catch up).
  last_hlc                 text,
  -- APNs broadcast channel for the game's Live Activity (design §13.2), once created.
  live_activity_channel_id text,
  updated_at               timestamptz not null default now()
);

create index games_created_by on public.games (created_by);
create index games_status on public.games (status) where status in ('lobby', 'active');

create trigger games_updated_at
  before update on public.games
  for each row execute function public.kedro_set_updated_at();

-- Who is seated where (projection of PlayerSeated / SeatRemoved / GameStarted). No foreign keys
-- to players or guests: the op log is the source of truth and may name people before they sync.
create table public.seats (
  game_id      uuid not null references public.games (id) on delete cascade,
  seat_id      text not null check (seat_id ~ '^[pg]:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
  player_id    uuid,
  guest_id     uuid,
  display_name text not null,
  seat_order   integer not null,
  device_id    uuid,
  primary key (game_id, seat_id),
  check ((player_id is null) <> (guest_id is null))
);

create index seats_player on public.seats (player_id) where player_id is not null;
create index seats_guest on public.seats (guest_id) where guest_id is not null;

-- The append-only operation log (ARCHITECTURE.md §4.2). Idempotent by op_id.
create table public.ops (
  op_id       uuid primary key,
  game_id     uuid not null references public.games (id) on delete restrict,
  -- "<wallMs, 15 digits>-<counter, 5 digits>-<node>": string order is HLC order.
  hlc         text not null check (hlc ~ '^[0-9]{15}-[0-9]{5}-.+$'),
  device_id   uuid not null,
  -- actorPlayerId: null for guest-mode phones and system actions.
  actor       uuid,
  type        text not null check (type in (
    'GameCreated', 'GameStarted', 'PlayerSeated', 'SeatRemoved', 'ScorekeeperChanged',
    'RoundRecorded', 'RoundEdited', 'RoundUndone', 'KnockMarked', 'KnockerProposed',
    'KnockerResolved', 'HandReported', 'RoundsChanged', 'DealerChanged', 'TauntSent',
    'TauntRetracted', 'ReactionAdded', 'ReceiptSent', 'TableSpeakerClaimed', 'GameFinished',
    'GameAbandoned', 'GameRestored'
  )),
  payload     jsonb not null,
  -- The signed-in player whose phone uploaded it (often a relay for other phones at the table).
  received_by uuid,
  received_at timestamptz not null default now()
);

create index ops_game_order on public.ops (game_id, hlc, device_id, op_id);

create or replace function public.kedro_ops_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'ops are append-only: % is not allowed', tg_op
    using errcode = 'insufficient_privilege';
end;
$$;

create trigger ops_no_update_or_delete
  before update or delete on public.ops
  for each row execute function public.kedro_ops_append_only();

create trigger ops_no_truncate
  before truncate on public.ops
  for each statement execute function public.kedro_ops_append_only();

-- MARK: Finished-game projections (stats input, PRD §5)

create table public.finished_games (
  game_id        uuid primary key references public.games (id) on delete cascade,
  finished_at    timestamptz not null,
  finished_at_ms bigint not null,
  finish_reason  text not null check (finish_reason in ('completed', 'endedEarly', 'autoFinished')),
  planned_rounds integer not null,
  rounds_played  integer not null,
  table_word     text not null,
  -- The authoritative rounds ([Round] JSON, the finisher's finalRounds).
  rounds         jsonb not null,
  -- An abandon within 15 minutes of finishing voids the game for stats.
  is_abandoned   boolean not null default false,
  projected_at   timestamptz not null default now()
);

create index finished_games_order on public.finished_games (finished_at_ms, game_id) where not is_abandoned;

create table public.finished_game_seats (
  game_id       uuid not null references public.finished_games (game_id) on delete cascade,
  seat_id       text not null,
  -- The seat's player, or the player who claimed this guest.
  player_id     uuid,
  guest_id      uuid,
  display_name  text not null,
  seat_order    integer not null,
  total         integer not null,
  rank          integer not null,
  rank_shared   boolean not null,
  is_winner     boolean not null,
  rounds_played integer not null,
  knocks        integer not null,
  knocks_landed integer not null,
  knocks_tied   integer not null,
  knocks_failed integer not null,
  lowest_hand   integer,
  highest_hand  integer,
  primary key (game_id, seat_id),
  check (player_id is not null or guest_id is not null)
);

create index finished_game_seats_player on public.finished_game_seats (player_id) where player_id is not null;
create index finished_game_seats_guest on public.finished_game_seats (guest_id) where guest_id is not null;

-- Lifetime stats per player from finished, non-abandoned games (one row per game, preferring the
-- player's own seat over a claimed guest seat in the same game). Mirrors aggregateStats().
create view public.player_stats
with (security_invoker = true)
as
with per_game as (
  select distinct on (s.player_id, s.game_id) s.*
  from public.finished_game_seats s
  join public.finished_games g on g.game_id = s.game_id
  where s.player_id is not null and not g.is_abandoned
  order by s.player_id, s.game_id, (s.guest_id is null) desc
)
select
  player_id,
  count(*)::integer                              as games_played,
  (count(*) filter (where is_winner))::integer   as wins,
  sum(total)::integer                            as total_score,
  sum(rounds_played)::integer                    as rounds_played,
  sum(knocks)::integer                           as knocks,
  sum(knocks_landed)::integer                    as knocks_landed,
  sum(knocks_tied)::integer                      as knocks_tied,
  sum(knocks_failed)::integer                    as knocks_failed,
  min(total)                                     as best_game,
  max(total)                                     as worst_game
from per_game
group by player_id;

-- Ratings are a cache: the API replays every finished game (replayRatings) and replaces both
-- tables in one transaction (kedro_replace_ratings). Never update them incrementally.
create table public.ratings (
  subject      text primary key, -- "p:<playerId>" or "g:<guestId>" (unclaimed)
  player_id    uuid,
  guest_id     uuid,
  rating       double precision not null,
  games        integer not null,
  last_game_id uuid,
  replayed_at  timestamptz not null default now()
);

create index ratings_player on public.ratings (player_id) where player_id is not null;

create table public.rating_changes (
  game_id     uuid not null references public.finished_games (game_id) on delete cascade,
  subject     text not null,
  player_id   uuid,
  before      double precision not null,
  after       double precision not null,
  delta       double precision not null,
  game_number integer not null,
  primary key (game_id, subject)
);

create index rating_changes_player on public.rating_changes (player_id) where player_id is not null;

-- MARK: Safety (design §8.3)

create table public.blocks (
  blocker_id uuid not null references public.players (id) on delete cascade,
  blocked_id uuid not null references public.players (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index blocks_blocked on public.blocks (blocked_id);

create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.players (id) on delete cascade,
  target_type text not null check (target_type in ('taunt', 'player', 'photo')),
  target_id   text not null,
  game_id     uuid references public.games (id) on delete set null,
  reason      text not null check (char_length(reason) between 1 and 500),
  status      text not null default 'open' check (status in ('open', 'reviewed', 'actioned', 'dismissed')),
  created_at  timestamptz not null default now()
);

create index reports_open on public.reports (created_at) where status = 'open';

-- The custom-taunt filter's terms (slurs and identity-based abuse; profanity is allowed).
-- PLACEHOLDER: ships empty. The list and its review process need an owner (design §18 item 5).
create table public.taunt_blocklist (
  term       text primary key check (char_length(term) between 1 and 100),
  note       text,
  created_at timestamptz not null default now()
);

-- MARK: Receipts and push

create table public.receipts (
  id             uuid primary key default gen_random_uuid(),
  game_id        uuid not null references public.games (id) on delete cascade,
  from_player_id uuid not null references public.players (id) on delete cascade,
  to_player_id   uuid not null references public.players (id) on delete cascade,
  receipt_key    text not null check (receipt_key ~ '^RC-[0-9]{2}$'),
  created_at     timestamptz not null default now(),
  -- One receipt per rival per game (design §8.5).
  unique (game_id, from_player_id, to_player_id),
  check (from_player_id <> to_player_id)
);

create index receipts_to on public.receipts (to_player_id, created_at desc);

create table public.push_tokens (
  id         uuid primary key default gen_random_uuid(),
  player_id  uuid not null references public.players (id) on delete cascade,
  token      text not null check (token ~ '^[0-9a-f]{32,512}$'),
  kind       text not null check (kind in ('apns', 'liveactivity')),
  -- Live Activity push-to-start / update tokens are per game.
  game_id    uuid references public.games (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index push_tokens_unique on public.push_tokens (player_id, kind, token, coalesce(game_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index push_tokens_game on public.push_tokens (game_id) where game_id is not null;

create trigger push_tokens_updated_at
  before update on public.push_tokens
  for each row execute function public.kedro_set_updated_at();

-- MARK: Row-level security

-- True when the signed-in user is seated in the game (as a player, or as a guest they claimed)
-- or created it. Security definer so policies can call it without recursive RLS checks.
create or replace function public.kedro_is_seated(target_game uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.seats s
    where s.game_id = target_game
      and (
        s.player_id = auth.uid()
        or s.guest_id in (select g.id from public.guests g where g.claimed_by = auth.uid())
      )
  ) or exists (
    select 1 from public.games g where g.id = target_game and g.created_by = auth.uid()
  );
$$;

revoke all on function public.kedro_is_seated(uuid) from public, anon;
grant execute on function public.kedro_is_seated(uuid) to authenticated, service_role;

alter table public.players             enable row level security;
alter table public.guests              enable row level security;
alter table public.games               enable row level security;
alter table public.seats               enable row level security;
alter table public.ops                 enable row level security;
alter table public.finished_games      enable row level security;
alter table public.finished_game_seats enable row level security;
alter table public.ratings             enable row level security;
alter table public.rating_changes      enable row level security;
alter table public.blocks              enable row level security;
alter table public.reports             enable row level security;
alter table public.taunt_blocklist     enable row level security;
alter table public.receipts            enable row level security;
alter table public.push_tokens         enable row level security;

-- Nothing is readable without signing in.
revoke all on
  public.players, public.guests, public.games, public.seats, public.ops, public.finished_games,
  public.finished_game_seats, public.ratings, public.rating_changes, public.blocks, public.reports,
  public.taunt_blocklist, public.receipts, public.push_tokens, public.player_stats
from anon;

-- Players: public profiles; you write only your own.
create policy "Profiles are public" on public.players
  for select to authenticated using (true);
create policy "Create your own profile" on public.players
  for insert to authenticated with check (id = (select auth.uid()));
create policy "Update your own profile" on public.players
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Guests: visible only in the context of their games; the claim token hash is never exposed.
revoke all on public.guests from authenticated;
grant select (id, display_name, created_by, claimed_by, claimed_at, created_at) on public.guests to authenticated;
create policy "Guests are visible to their tables" on public.guests
  for select to authenticated using (
    created_by = (select auth.uid())
    or claimed_by = (select auth.uid())
    or exists (select 1 from public.seats s where s.guest_id = guests.id and public.kedro_is_seated(s.game_id))
  );

-- Games and seats: only for people at the table.
create policy "Seated players read the game" on public.games
  for select to authenticated using (public.kedro_is_seated(id));
create policy "Seated players read the seats" on public.seats
  for select to authenticated using (public.kedro_is_seated(game_id));

-- Ops: read if seated; insert your own; never update or delete (also enforced by trigger).
revoke update, delete, truncate on public.ops from authenticated;
create policy "Seated players read the log" on public.ops
  for select to authenticated using (public.kedro_is_seated(game_id));
create policy "Seated players append their own ops" on public.ops
  for insert to authenticated with check (
    actor = (select auth.uid())
    and (received_by is null or received_by = (select auth.uid()))
    and public.kedro_is_seated(game_id)
    and exists (select 1 from public.games g where g.id = ops.game_id and g.status in ('lobby', 'active'))
  );

-- Finished games are public game history (PRD §3.3); unclaimed guests' rows only to their tables.
create policy "Finished games are public" on public.finished_games
  for select to authenticated using (true);
create policy "Player results are public; guest results stay at the table" on public.finished_game_seats
  for select to authenticated using (player_id is not null or public.kedro_is_seated(game_id));

create policy "Ratings are public for players" on public.ratings
  for select to authenticated using (player_id is not null);
create policy "Rating history is public for players" on public.rating_changes
  for select to authenticated using (player_id is not null);

-- Blocks, reports, receipts, push tokens: your own.
create policy "Read your blocks" on public.blocks
  for select to authenticated using (blocker_id = (select auth.uid()));
create policy "Block someone" on public.blocks
  for insert to authenticated with check (blocker_id = (select auth.uid()));
create policy "Unblock someone" on public.blocks
  for delete to authenticated using (blocker_id = (select auth.uid()));

create policy "File a report" on public.reports
  for insert to authenticated with check (reporter_id = (select auth.uid()));
create policy "Read your reports" on public.reports
  for select to authenticated using (reporter_id = (select auth.uid()));

create policy "Read receipts you sent or got" on public.receipts
  for select to authenticated using (from_player_id = (select auth.uid()) or to_player_id = (select auth.uid()));
create policy "Send a receipt" on public.receipts
  for insert to authenticated with check (from_player_id = (select auth.uid()));

create policy "Manage your push tokens" on public.push_tokens
  for all to authenticated using (player_id = (select auth.uid())) with check (player_id = (select auth.uid()));

-- taunt_blocklist: no policies (service role only).
revoke all on public.taunt_blocklist from authenticated;

-- MARK: API functions (service role only; each runs in one transaction)

-- Replaces a game's live projection (games row + seats) after the API re-folds its log.
create or replace function public.kedro_sync_game(p_game jsonb, p_seats jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  target uuid := (p_game ->> 'id')::uuid;
begin
  update public.games set
    status         = p_game ->> 'status',
    table_word     = p_game ->> 'table_word',
    planned_rounds = (p_game ->> 'planned_rounds')::integer,
    scoring_mode   = p_game ->> 'scoring_mode',
    host_seat      = p_game ->> 'host_seat',
    rounds_played  = (p_game ->> 'rounds_played')::integer,
    started_at     = (p_game ->> 'started_at')::timestamptz,
    finished_at    = (p_game ->> 'finished_at')::timestamptz,
    finish_reason  = p_game ->> 'finish_reason',
    abandoned_at   = (p_game ->> 'abandoned_at')::timestamptz,
    last_hlc       = p_game ->> 'last_hlc'
  where id = target;

  delete from public.seats where game_id = target;
  insert into public.seats (game_id, seat_id, player_id, guest_id, display_name, seat_order, device_id)
  select target, s.seat_id, s.player_id, s.guest_id, s.display_name, s.seat_order, s.device_id
  from jsonb_to_recordset(p_seats) as s(
    seat_id text, player_id uuid, guest_id uuid, display_name text, seat_order integer, device_id uuid
  );
end;
$$;

-- Writes (or rewrites) a finished game's projection. Guest seats already claimed by a player are
-- attributed to that player.
create or replace function public.kedro_project_finished_game(p_game jsonb, p_seats jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  target uuid := (p_game ->> 'game_id')::uuid;
begin
  insert into public.finished_games (
    game_id, finished_at, finished_at_ms, finish_reason, planned_rounds, rounds_played, table_word, rounds, is_abandoned
  ) values (
    target,
    to_timestamp((p_game ->> 'finished_at_ms')::bigint / 1000.0),
    (p_game ->> 'finished_at_ms')::bigint,
    p_game ->> 'finish_reason',
    (p_game ->> 'planned_rounds')::integer,
    (p_game ->> 'rounds_played')::integer,
    p_game ->> 'table_word',
    p_game -> 'rounds',
    coalesce((p_game ->> 'is_abandoned')::boolean, false)
  )
  on conflict (game_id) do update set
    finished_at = excluded.finished_at,
    finished_at_ms = excluded.finished_at_ms,
    finish_reason = excluded.finish_reason,
    planned_rounds = excluded.planned_rounds,
    rounds_played = excluded.rounds_played,
    table_word = excluded.table_word,
    rounds = excluded.rounds,
    is_abandoned = excluded.is_abandoned,
    projected_at = now();

  delete from public.finished_game_seats where game_id = target;
  insert into public.finished_game_seats (
    game_id, seat_id, player_id, guest_id, display_name, seat_order, total, rank, rank_shared, is_winner,
    rounds_played, knocks, knocks_landed, knocks_tied, knocks_failed, lowest_hand, highest_hand
  )
  select
    target, s.seat_id, coalesce(s.player_id, g.claimed_by), s.guest_id, s.display_name, s.seat_order, s.total,
    s.rank, s.rank_shared, s.is_winner, s.rounds_played, s.knocks, s.knocks_landed, s.knocks_tied,
    s.knocks_failed, s.lowest_hand, s.highest_hand
  from jsonb_to_recordset(p_seats) as s(
    seat_id text, player_id uuid, guest_id uuid, display_name text, seat_order integer, total integer,
    rank integer, rank_shared boolean, is_winner boolean, rounds_played integer, knocks integer,
    knocks_landed integer, knocks_tied integer, knocks_failed integer, lowest_hand integer, highest_hand integer
  )
  left join public.guests g on g.id = s.guest_id;
end;
$$;

-- Marks a finished game's projection abandoned (or restored) without touching its results.
create or replace function public.kedro_set_finished_game_abandoned(p_game uuid, p_abandoned boolean)
returns void
language sql
set search_path = ''
as $$
  update public.finished_games set is_abandoned = p_abandoned, projected_at = now() where game_id = p_game;
$$;

-- Replaces every rating with a fresh replay (replayRatings in packages/shared).
create or replace function public.kedro_replace_ratings(p_ratings jsonb, p_changes jsonb)
returns void
language plpgsql
set search_path = ''
as $$
begin
  delete from public.rating_changes where true;
  delete from public.ratings where true;
  insert into public.ratings (subject, player_id, guest_id, rating, games, last_game_id)
  select r.subject, r.player_id, r.guest_id, r.rating, r.games, r.last_game_id
  from jsonb_to_recordset(p_ratings) as r(
    subject text, player_id uuid, guest_id uuid, rating double precision, games integer, last_game_id uuid
  );
  insert into public.rating_changes (game_id, subject, player_id, before, after, delta, game_number)
  select c.game_id, c.subject, c.player_id, c.before, c.after, c.delta, c.game_number
  from jsonb_to_recordset(p_changes) as c(
    game_id uuid, subject text, player_id uuid, before double precision, after double precision,
    delta double precision, game_number integer
  );
end;
$$;

-- Claims a guest identity for a player (PRD §3.2): one claim per guest, ever. Returns the guest
-- and how many finished, non-abandoned games moved to the player, or raises:
--   'claim_not_found' (no guest with that token hash) / 'claim_already_claimed'.
create or replace function public.kedro_claim_guest(p_token_hash text, p_player uuid)
returns table (guest_id uuid, games_claimed integer)
language plpgsql
set search_path = ''
as $$
declare
  claimed public.guests%rowtype;
begin
  select * into claimed from public.guests g where g.claim_token_hash = p_token_hash for update;
  if not found then
    raise exception 'claim_not_found' using errcode = 'no_data_found';
  end if;
  if claimed.claimed_by is not null then
    raise exception 'claim_already_claimed' using errcode = 'unique_violation';
  end if;

  update public.guests set claimed_by = p_player, claimed_at = now() where id = claimed.id;
  update public.finished_game_seats set player_id = p_player where finished_game_seats.guest_id = claimed.id;

  return query
    select claimed.id, count(distinct s.game_id)::integer
    from public.finished_game_seats s
    join public.finished_games f on f.game_id = s.game_id
    where s.guest_id = claimed.id and not f.is_abandoned;
end;
$$;

revoke all on function public.kedro_sync_game(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.kedro_project_finished_game(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.kedro_set_finished_game_abandoned(uuid, boolean) from public, anon, authenticated;
revoke all on function public.kedro_replace_ratings(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.kedro_claim_guest(text, uuid) from public, anon, authenticated;
grant execute on function public.kedro_sync_game(jsonb, jsonb) to service_role;
grant execute on function public.kedro_project_finished_game(jsonb, jsonb) to service_role;
grant execute on function public.kedro_set_finished_game_abandoned(uuid, boolean) to service_role;
grant execute on function public.kedro_replace_ratings(jsonb, jsonb) to service_role;
grant execute on function public.kedro_claim_guest(text, uuid) to service_role;

-- MARK: Realtime

-- Seated phones subscribe to their game's new ops (RLS applies to Realtime's postgres_changes).
alter publication supabase_realtime add table public.ops;
