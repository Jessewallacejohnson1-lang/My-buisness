-- Korina progress migration
-- Run in: Supabase Dashboard → SQL Editor → New query → paste → Run
--
-- Body-weight log: one optional entry per user per day. Powers the weight
-- curve on /progress and the "latest weight" card on the dashboard.

create table if not exists public.weight_logs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date        date not null default current_date,
  weight_kg   numeric not null,
  created_at  timestamptz not null default now(),
  unique (user_id, date)
);

create index if not exists weight_logs_user_date_idx
  on public.weight_logs (user_id, date desc);

alter table public.weight_logs enable row level security;

drop policy if exists "own weight logs" on public.weight_logs;
create policy "own weight logs" on public.weight_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
