-- Cadence database setup
-- Run once in Supabase: SQL Editor > New query > paste > Run

create table if not exists public.events (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  id         text not null,
  title      text not null,
  type       text not null check (type in ('class','shift','personal')),
  date       date not null,
  start_min  int  not null check (start_min between 0 and 1440),
  end_min    int  not null check (end_min between 0 and 1440),
  location   text not null default '',
  source     text not null default '',
  ext_id     text not null default '',
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);
create index if not exists events_user_date on public.events (user_id, date);

create table if not exists public.settings (
  user_id    uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Row Level Security: each user can only see and change their own rows
alter table public.events   enable row level security;
alter table public.settings enable row level security;

drop policy if exists "own events" on public.events;
create policy "own events" on public.events
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "own settings" on public.settings;
create policy "own settings" on public.settings
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Live sync between devices
alter table public.events replica identity full;
alter publication supabase_realtime add table public.events;
