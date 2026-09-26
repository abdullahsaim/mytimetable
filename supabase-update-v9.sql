-- Cadence v9 update: push notifications (even when the app is closed) + data retention
-- Run once in Supabase: SQL Editor > New query > paste > Run
-- BEFORE running: replace CHANGE-ME-CRON-SECRET below with the same random text you
-- save as the CRON_SECRET secret for the send-push function (see setup steps).

-- 1) Devices that asked for notifications (one row per browser/phone)
create table if not exists public.push_subscriptions (
  endpoint   text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  p256dh     text not null,
  auth       text not null,
  tz         text not null default 'Europe/Paris',
  created_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user on public.push_subscriptions (user_id);
alter table public.push_subscriptions enable row level security;

drop policy if exists "own push subscriptions" on public.push_subscriptions;
create policy "own push subscriptions" on public.push_subscriptions
  for select to authenticated using ((select auth.uid()) = user_id);

-- Register / unregister this device. A browser that was signed in to another
-- account before is moved to the current account.
create or replace function public.register_push(p_endpoint text, p_p256dh text, p_auth text, p_tz text)
returns void language sql security definer set search_path = public as $$
  insert into public.push_subscriptions (endpoint, user_id, p256dh, auth, tz)
  values (p_endpoint, auth.uid(), p_p256dh, p_auth, coalesce(nullif(p_tz, ''), 'Europe/Paris'))
  on conflict (endpoint) do update
    set user_id = auth.uid(), p256dh = excluded.p256dh, auth = excluded.auth, tz = excluded.tz, created_at = now();
$$;
create or replace function public.unregister_push(p_endpoint text)
returns void language sql security definer set search_path = public as $$
  delete from public.push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
$$;
revoke all on function public.register_push(text, text, text, text) from public, anon;
revoke all on function public.unregister_push(text) from public, anon;
grant execute on function public.register_push(text, text, text, text) to authenticated;
grant execute on function public.unregister_push(text) to authenticated;

-- 2) What was already sent, so nothing is sent twice. Server-only (no client policies).
create table if not exists public.push_log (
  user_id uuid not null references auth.users(id) on delete cascade,
  key     text not null,
  sent_at timestamptz not null default now(),
  primary key (user_id, key)
);
alter table public.push_log enable row level security;

-- 3) Run send-push every 5 minutes, and clean old send records daily (GDPR: keep only what's needed)
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule(jobid) from cron.job where jobname in ('cadence-push', 'cadence-cleanup');

select cron.schedule('cadence-push', '*/5 * * * *', $$
  select net.http_post(
    url     := 'https://uoevqzzhxghwmupnitsi.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVvZXZxenpoeGdod211cG5pdHNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAzNjg3MTksImV4cCI6MjEwNTk0NDcxOX0.cpugKGCuhc3p1PIEfUMzjPju5DyElvYP2dxG9mDR9B8',
      'x-cron-secret', 'a7158963a37465598b16c2b89d41c0af300e35d72532e664'
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 20000
  );
$$);

select cron.schedule('cadence-cleanup', '17 3 * * *', $$
  delete from public.push_log where sent_at < now() - interval '30 days';
  delete from cron.job_run_details where end_time < now() - interval '7 days';
$$);
