-- HYGGE — complete database migration
-- Paste this entire file into: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to re-run (all statements are idempotent).
--
-- Sections:
--   1. Food logs + workouts (per-user ownership + RLS)
--   2. Community: clubs, members, events, RSVPs, is_admin(), RLS, seed data

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. FOOD LOGS + WORKOUTS
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.food_logs add column if not exists user_id uuid default auth.uid();
alter table public.workouts  add column if not exists user_id uuid default auth.uid();

create index if not exists food_logs_user_date_idx on public.food_logs (user_id, date);
create index if not exists workouts_user_date_idx  on public.workouts  (user_id, date);

-- Drop any existing open policies on these tables
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

alter table public.food_logs enable row level security;
alter table public.workouts  enable row level security;

create policy "own rows" on public.food_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own rows" on public.workouts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);


-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. COMMUNITY
-- ═══════════════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- Owner check used inside RLS policies
create or replace function public.is_admin() returns boolean
language sql stable as $$
  select coalesce(auth.jwt() ->> 'email', '') = 'jessewallacejohnson1@icloud.com'
$$;

-- ── Clubs ──────────────────────────────────────────────────────────────────────
create table if not exists public.clubs (
  id           uuid primary key default gen_random_uuid(),
  submitted_by uuid default auth.uid() references auth.users (id) on delete set null,
  status       text not null default 'pending' check (status in ('pending','approved','rejected')),
  name         text not null,
  host         text,
  schedule     text,
  vibe         text,
  created_at   timestamptz not null default now()
);
create index if not exists clubs_status_idx on public.clubs (status);

-- One membership row per user per club
create table if not exists public.club_members (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs (id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (club_id, user_id)
);
create index if not exists club_members_club_idx on public.club_members (club_id);

-- Events run by clubs (or standalone town events)
create table if not exists public.club_events (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid references public.clubs (id) on delete cascade,
  submitted_by uuid default auth.uid() references auth.users (id) on delete set null,
  status       text not null default 'pending' check (status in ('pending','approved','rejected')),
  title        text not null,
  event_date   date not null,
  start_time   text,
  created_at   timestamptz not null default now()
);
create index if not exists club_events_status_date_idx on public.club_events (status, event_date);

create table if not exists public.event_rsvps (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.club_events (id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (event_id, user_id)
);
create index if not exists event_rsvps_event_idx on public.event_rsvps (event_id);

-- ── RLS ────────────────────────────────────────────────────────────────────────
alter table public.clubs        enable row level security;
alter table public.club_members enable row level security;
alter table public.club_events  enable row level security;
alter table public.event_rsvps  enable row level security;

-- clubs
drop policy if exists "read clubs"     on public.clubs;
drop policy if exists "submit clubs"   on public.clubs;
drop policy if exists "moderate clubs" on public.clubs;
drop policy if exists "delete clubs"   on public.clubs;

create policy "read clubs" on public.clubs for select using (
  status = 'approved' or submitted_by = auth.uid() or public.is_admin()
);
create policy "submit clubs" on public.clubs for insert with check (
  submitted_by = auth.uid() and (status = 'pending' or public.is_admin())
);
create policy "moderate clubs" on public.clubs for update using (
  public.is_admin() or (submitted_by = auth.uid() and status = 'pending')
) with check (
  public.is_admin() or (submitted_by = auth.uid() and status = 'pending')
);
create policy "delete clubs" on public.clubs for delete using (
  public.is_admin() or (submitted_by = auth.uid() and status = 'pending')
);

-- memberships
drop policy if exists "read memberships" on public.club_members;
drop policy if exists "join club"        on public.club_members;
drop policy if exists "leave club"       on public.club_members;

create policy "read memberships" on public.club_members for select using (true);
create policy "join club"        on public.club_members for insert with check (user_id = auth.uid());
create policy "leave club"       on public.club_members for delete using  (user_id = auth.uid());

-- events
drop policy if exists "read events"     on public.club_events;
drop policy if exists "submit events"   on public.club_events;
drop policy if exists "moderate events" on public.club_events;
drop policy if exists "delete events"   on public.club_events;

create policy "read events" on public.club_events for select using (
  status = 'approved' or submitted_by = auth.uid() or public.is_admin()
);
create policy "submit events" on public.club_events for insert with check (
  submitted_by = auth.uid() and (status = 'pending' or public.is_admin())
);
create policy "moderate events" on public.club_events for update using (
  public.is_admin() or (submitted_by = auth.uid() and status = 'pending')
) with check (
  public.is_admin() or (submitted_by = auth.uid() and status = 'pending')
);
create policy "delete events" on public.club_events for delete using (
  public.is_admin() or (submitted_by = auth.uid() and status = 'pending')
);

-- RSVPs
drop policy if exists "read rsvps"  on public.event_rsvps;
drop policy if exists "rsvp insert" on public.event_rsvps;
drop policy if exists "rsvp delete" on public.event_rsvps;

create policy "read rsvps"  on public.event_rsvps for select using (true);
create policy "rsvp insert" on public.event_rsvps for insert with check (user_id = auth.uid());
create policy "rsvp delete" on public.event_rsvps for delete using  (user_id = auth.uid());


-- ── Seed data ──────────────────────────────────────────────────────────────────
-- 5 approved clubs (skipped if they already exist by name)
insert into public.clubs (status, name, host, schedule, vibe)
select * from (values
  ('approved','Saturday Run Club','Marcus T.','Every Saturday, 7am','Show up. No pace required.'),
  ('approved','Yoga in the Park','Sarah K.','Tues & Thurs, 5:30pm','All levels. Bring a mat.'),
  ('approved','Trivia Night','Bad Habit Bar','Every Thursday, 7pm','Teams of 2–6. Free to play.'),
  ('approved','Book Club','Anna R.','First Sunday, 2pm','One book a month. Bring snacks, not opinions.'),
  ('approved','Cold Plunge Club','Jesse V.','Sunday mornings','60 seconds. You''ll be glad you did.')
) as v(status,name,host,schedule,vibe)
where not exists (select 1 from public.clubs c where c.name = v.name);

-- Today's events (3 events for the Today tab)
insert into public.club_events (status, club_id, title, event_date, start_time)
select 'approved',
       (select id from public.clubs where name = v.club limit 1),
       v.title, current_date, v.start_time
from (values
  ('Saturday Run Club','Run Club at Riverside','7am'),
  ('Yoga in the Park','Yoga in the Park','5pm'),
  ('Trivia Night','Trivia at Bad Habit','7pm')
) as v(club,title,start_time)
where not exists (
  select 1 from public.club_events e where e.title = v.title and e.event_date = current_date
);

-- This week's events for the week scroll
insert into public.club_events (status, club_id, title, event_date, start_time)
select 'approved',
       (select id from public.clubs where name = v.club limit 1),
       v.title, current_date + v.day_offset, v.start_time
from (values
  ('Saturday Run Club','Farmers Market', 2, '8am'),
  ('Saturday Run Club','Run Club',       2, '7am'),
  ('Trivia Night','Trivia Night',        4, '7pm'),
  ('Book Club','Book Club',              5, '2pm')
) as v(club,title,day_offset,start_time)
where not exists (
  select 1 from public.club_events e where e.title = v.title and e.event_date = current_date + v.day_offset
);
