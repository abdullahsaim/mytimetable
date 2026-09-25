-- Semaine v6 update: remembers which events came from an imported calendar.
-- Run once in Supabase: SQL Editor > New query > paste > Run
alter table public.events add column if not exists source text not null default '';
alter table public.events add column if not exists ext_id text not null default '';
