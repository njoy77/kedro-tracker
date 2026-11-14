-- Kedro v3: finish wiring up the 🐴 neigh (migration 0005).
--
-- 1. ops.type is checked against the list of op types (0003); 0005 added the seats' neigh count but
--    not the op type, so a Neighed op was refused on insert.
-- 2. kedro_project_finished_game (0002) lists the seat columns it writes, so the API's per-seat
--    neigh count never reached finished_game_seats.neighs. Replacing it keeps its grants.
-- apps/api/test/schema.test.ts now checks both against the code.
--
-- Run once in the Supabase SQL editor. Safe to run again.

alter table public.ops drop constraint if exists ops_type_check;
alter table public.ops add constraint ops_type_check check (type in (
  'GameCreated', 'GameStarted', 'GameConfigured', 'PlayerSeated', 'SeatRemoved', 'ScorekeeperChanged',
  'RoundRecorded', 'RoundEdited', 'RoundUndone', 'KnockMarked', 'KnockerProposed',
  'KnockerResolved', 'HandReported', 'RoundsChanged', 'DealerChanged', 'TauntSent',
  'TauntRetracted', 'ReactionAdded', 'ReceiptSent', 'TableSpeakerClaimed', 'GameFinished',
  'GameAbandoned', 'GameRestored', 'Neighed'
));

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
    rounds_played, knocks, knocks_landed, knocks_tied, knocks_failed, lowest_hand, highest_hand, neighs
  )
  select
    target, s.seat_id, coalesce(s.player_id, g.claimed_by), s.guest_id, s.display_name, s.seat_order, s.total,
    s.rank, s.rank_shared, s.is_winner, s.rounds_played, s.knocks, s.knocks_landed, s.knocks_tied,
    s.knocks_failed, s.lowest_hand, s.highest_hand, coalesce(s.neighs, 0)
  from jsonb_to_recordset(p_seats) as s(
    seat_id text, player_id uuid, guest_id uuid, display_name text, seat_order integer, total integer,
    rank integer, rank_shared boolean, is_winner boolean, rounds_played integer, knocks integer,
    knocks_landed integer, knocks_tied integer, knocks_failed integer, lowest_hand integer, highest_hand integer, neighs integer
  )
  left join public.guests g on g.id = s.guest_id;
end;
$$;
