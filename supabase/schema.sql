-- Kedro score tracker — Supabase schema
-- Run this in your Supabase project: SQL Editor → New query → paste & run

-- Key-value store used by the app
create table if not exists kedro_kv (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz default now()
);

-- Auto-update updated_at on every write
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace trigger kedro_kv_updated_at
  before update on kedro_kv
  for each row execute procedure set_updated_at();

-- Row-level security (open access via anon key — suitable for local/trusted use)
alter table kedro_kv enable row level security;

create policy "Allow all" on kedro_kv
  for all
  using (true)
  with check (true);

-- Enable real-time so all clients get live updates
alter publication supabase_realtime add table kedro_kv;
