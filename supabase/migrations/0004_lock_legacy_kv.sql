-- Kedro v3, part 3: retire the legacy web storage.
--
-- The web app now keeps score through the API like the iOS app, and the web history was copied
-- into the v3 tables once (scripts/import-legacy.ts). `kedro_kv` stays as a read-only record of
-- that history: nothing writes to it again, so a browser still running the old web app can't
-- change or wipe it (the old policy let anyone with the public key do both).
--
-- Run once, after the final import and after the new web app is deployed.

drop policy if exists "Allow all" on public.kedro_kv;
revoke insert, update, delete, truncate on public.kedro_kv from anon, authenticated;
create policy "Legacy history is read-only" on public.kedro_kv for select using (true);
