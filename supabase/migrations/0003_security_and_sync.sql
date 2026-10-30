-- Kedro v3, part 2: write paths, table invites, photos.
--
-- 1. `GameConfigured` (the lobby's table word / scoring mode / house voice op) was missing from
--    the ops.type CHECK, so any chunk containing one failed to insert and the game never synced.
-- 2. Every write goes through the API (service role), which validates ops, applies the
--    admission rules, the taunt filter and limits, the block safeguard and the App Clip limits,
--    and reprojects. Direct PostgREST inserts into `ops` and `receipts` skipped all of that, and
--    Realtime then pushed the rows to every phone, so the insert grants and policies go.
-- 3. `game_invite_keys`: the HMAC key each table makes its rotating invite codes with (derived
--    from the table secret on the phones), so the API can check codes before seating someone who
--    holds only the public game ID, or starting an App Clip session.
-- 4. `player_photos`: uploaded profile pictures, served publicly by the API at /photos/:playerId.

-- MARK: 1. ops.type

alter table public.ops drop constraint if exists ops_type_check;
alter table public.ops add constraint ops_type_check check (type in (
  'GameCreated', 'GameStarted', 'GameConfigured', 'PlayerSeated', 'SeatRemoved', 'ScorekeeperChanged',
  'RoundRecorded', 'RoundEdited', 'RoundUndone', 'KnockMarked', 'KnockerProposed',
  'KnockerResolved', 'HandReported', 'RoundsChanged', 'DealerChanged', 'TauntSent',
  'TauntRetracted', 'ReactionAdded', 'ReceiptSent', 'TableSpeakerClaimed', 'GameFinished',
  'GameAbandoned', 'GameRestored'
));

-- MARK: 2. Writes only through the API

drop policy if exists "Seated players append their own ops" on public.ops;
revoke insert on public.ops from anon, authenticated;

drop policy if exists "Send a receipt" on public.receipts;
revoke insert, update, delete on public.receipts from anon, authenticated;

-- MARK: 3. Table invite keys (service role only)

create table public.game_invite_keys (
  game_id       uuid primary key references public.games (id) on delete cascade,
  -- 32 bytes, base64url (43 characters). Never the table secret itself.
  invite_key    text not null check (invite_key ~ '^[A-Za-z0-9_-]{43}$'),
  registered_by uuid references public.players (id) on delete set null,
  created_at    timestamptz not null default now()
);

alter table public.game_invite_keys enable row level security;
revoke all on public.game_invite_keys from anon, authenticated;

-- MARK: 4. Profile photos (service role only; the API serves them)

create table public.player_photos (
  player_id    uuid primary key references public.players (id) on delete cascade,
  photo        bytea not null check (octet_length(photo) <= 524288),
  content_type text not null check (content_type in ('image/jpeg', 'image/png')),
  -- A content hash prefix, used in the URL for cache-busting.
  version      text not null,
  updated_at   timestamptz not null default now()
);

create trigger player_photos_updated_at
  before update on public.player_photos
  for each row execute function public.kedro_set_updated_at();

alter table public.player_photos enable row level security;
revoke all on public.player_photos from anon, authenticated;
