-- Kedro v3: the 🐴 neigh is back (a `Neighed` op per tap, just for fun).
--
-- Each counted seat of a finished game keeps how many times it was neighed, for the profile's
-- neigh stats and the Most Neighs record. Neighs can arrive after a game finishes (the import of
-- the old web app's counts, or a late tap), and the API re-projects the game when they do.
--
-- Run once in the Supabase SQL editor, before deploying the API that writes it.

alter table public.finished_game_seats
  add column if not exists neighs integer not null default 0 check (neighs >= 0);
