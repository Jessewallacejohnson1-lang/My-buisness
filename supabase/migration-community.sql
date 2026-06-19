-- Korina / Hygge community migration
-- Run in: Supabase Dashboard → SQL Editor → New query → paste → Run
--
-- The community tier: local clubs you can join, and the events those clubs run.
-- Approved rows are public; pending rows await owner review. Members manage
-- only their own membership/RSVP; the owner (is_admin) moderates everything.

create extension if not exists pgcrypto;

-- ── Owner check, evaluated inside RLS ──────────────────────────────────────
create or replace function public.is_admin() returns boolean
language sql stable as $$
  select coalesce(auth.jwt() ->> 'email', '') = 'jessewallacejohnson1@icloud.com'
$$;

-- ── Clubs ──────────────────────────────────────────────────────────────────
create table if not exists public.clubs (
  id           uuid primary key default gen_random_uuid(),
  submitted_by uuid default auth.uid() references auth.users (id) on delete set null,
  status       text not null default 'pending' check (status in ('pending','approved','rejected')),
  name         text not null,
  host         text,                 -- "Marcus T." or "Bad Habit Bar"
  schedule     text,                 -- "Every Saturday, 7am"
  vibe         text,                 -- italic one-liner
  created_at   timestamptz not null default now()
);
create index if not exists clubs_status_idx on public.clubs (status);

-- One membership row per user per club.
create table if not exists public.club_members (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs (id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (club_id, user_id)
);
create index if not exists club_members_club_idx on public.club_members (club_id);

-- ── Club events (the Today / This Week timeline) ───────────────────────────
create table if not exists public.club_events (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid references public.clubs (id) on delete cascade,  -- nullable: town events w/o a club
  submitted_by uuid default auth.uid() references auth.users (id) on delete set null,
  status       text not null default 'pending' check (status in ('pending','approved','rejected')),
  title        text not null,
  event_date   date not null,
  start_time   text,                 -- display string, e.g. '7am'
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

-- ── RLS ────────────────────────────────────────────────────────────────────
alter table public.clubs         enable row level security;
alter table public.club_members  enable row level security;
alter table public.club_events   enable row level security;
alter table public.event_rsvps   enable row level security;

-- clubs: approved are public; submitters see their own; admin sees all
drop policy if exists "read clubs" on public.clubs;
create policy "read clubs" on public.clubs for select using (
  status = 'approved' or submitted_by = auth.uid() or public.is_admin()
);
drop policy if exists "submit clubs" on public.clubs;
create policy "submit clubs" on public.clubs for insert with check (
  submitted_by = auth.uid() and (status = 'pending' or public.is_admin())
);
drop policy if exists "moderate clubs" on public.clubs;
create policy "moderate clubs" on public.clubs for update using (
  public.is_admin() or (submitted_by = auth.uid() and status = 'pending')
) with check (
  public.is_admin() or (submitted_by = auth.uid() and status = 'pending')
);
drop policy if exists "delete clubs" on public.clubs;
create policy "delete clubs" on public.clubs for delete using (
  public.is_admin() or (submitted_by = auth.uid() and status = 'pending')
);

-- memberships: readable by all (for counts); each user manages only their own
drop policy if exists "read memberships" on public.club_members;
create policy "read memberships" on public.club_members for select using (true);
drop policy if exists "join club" on public.club_members;
create policy "join club" on public.club_members for insert with check (user_id = auth.uid());
drop policy if exists "leave club" on public.club_members;
create policy "leave club" on public.club_members for delete using (user_id = auth.uid());

-- events: same shape as clubs
drop policy if exists "read events" on public.club_events;
create policy "read events" on public.club_events for select using (
  status = 'approved' or submitted_by = auth.uid() or public.is_admin()
);
drop policy if exists "submit events" on public.club_events;
create policy "submit events" on public.club_events for insert with check (
  submitted_by = auth.uid() and (status = 'pending' or public.is_admin())
);
drop policy if exists "moderate events" on public.club_events;
create policy "moderate events" on public.club_events for update using (
  public.is_admin() or (submitted_by = auth.uid() and status = 'pending')
) with check (
  public.is_admin() or (submitted_by = auth.uid() and status = 'pending')
);
drop policy if exists "delete events" on public.club_events;
create policy "delete events" on public.club_events for delete using (
  public.is_admin() or (submitted_by = auth.uid() and status = 'pending')
);

-- rsvps: readable by all (for "going" counts); each user manages only their own
drop policy if exists "read rsvps" on public.event_rsvps;
create policy "read rsvps" on public.event_rsvps for select using (true);
drop policy if exists "rsvp insert" on public.event_rsvps;
create policy "rsvp insert" on public.event_rsvps for insert with check (user_id = auth.uid());
drop policy if exists "rsvp delete" on public.event_rsvps;
create policy "rsvp delete" on public.event_rsvps for delete using (user_id = auth.uid());

-- ── Seed: a handful of approved clubs + today's / this week's events ─────────
-- (Run once. Safe to re-run: guarded by NOT EXISTS on name.)
insert into public.clubs (status, name, host, schedule, vibe)
select * from (values
  ('approved','Saturday Run Club','Marcus T.','Every Saturday, 7am','Show up. No pace required.'),
  ('approved','Yoga in the Park','Sarah K.','Tues & Thurs, 5:30pm','All levels. Bring a mat.'),
  ('approved','Trivia Night','Bad Habit Bar','Every Thursday, 7pm','Teams of 2–6. Free to play.'),
  ('approved','Book Club','Anna R.','First Sunday, 2pm','One book a month. Bring snacks, not opinions.'),
  ('approved','Cold Plunge Club','Jesse V.','Sunday mornings','60 seconds. You''ll be glad you did.')
) as v(status,name,host,schedule,vibe)
where not exists (select 1 from public.clubs c where c.name = v.name);

-- Today's timeline (attach to the run club + yoga where it fits).
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

-- This week (next few days) for the WeekScroll.
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
