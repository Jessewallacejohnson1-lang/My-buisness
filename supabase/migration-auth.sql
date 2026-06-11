-- Grove auth migration
-- Run in: Supabase Dashboard → SQL Editor → New query → paste → Run
--
-- Adds per-user ownership to food_logs and workouts and replaces the open
-- RLS policies with per-user ones. Existing rows (logged before auth) have
-- no owner and will no longer be visible — they were shared test data.

-- 1. Ownership columns. New inserts pick up the signed-in user automatically.
alter table public.food_logs add column if not exists user_id uuid default auth.uid();
alter table public.workouts  add column if not exists user_id uuid default auth.uid();

create index if not exists food_logs_user_date_idx on public.food_logs (user_id, date);
create index if not exists workouts_user_date_idx  on public.workouts  (user_id, date);

-- 2. Drop every existing policy on both tables (the open "for now" ones).
do $$
declare pol record;
begin
  for pol in
    select policyname, tablename from pg_policies
    where schemaname = 'public' and tablename in ('food_logs', 'workouts')
  loop
    execute format('drop policy %I on public.%I', pol.policyname, pol.tablename);
  end loop;
end $$;

-- 3. Per-user policies: you can only see and touch your own rows.
alter table public.food_logs enable row level security;
alter table public.workouts  enable row level security;

create policy "own rows" on public.food_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own rows" on public.workouts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
