-- Kedro v3: let the ops table store `Neighed` ops (the 🐴 neigh, migration 0005).
--
-- ops.type is checked against the list of op types (0003); 0005 added the seats' neigh count but
-- not the op type, so a Neighed op was refused on insert. apps/api/test/schema.test.ts now checks
-- that this list matches packages/shared's OPERATION_TYPES.
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
