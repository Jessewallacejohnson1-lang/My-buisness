-- Add location and description to club_events
alter table public.club_events
  add column if not exists location    text,
  add column if not exists description text;

-- Allow all authenticated users to submit events as approved (no moderation queue)
drop policy if exists "submit events" on public.club_events;
create policy "submit events" on public.club_events for insert with check (
  submitted_by = auth.uid()
);
-- Note: the app inserts events with status='approved' (no moderation queue), so they
-- appear in everyone's timeline immediately. This insert policy only verifies the
-- submitter is the authed user; the existing read policy surfaces approved rows to all.

-- daily_quests: one per day, set by admin
create table if not exists public.daily_quests (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text,
  date        date not null unique,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

alter table public.daily_quests enable row level security;

drop policy if exists "read quests" on public.daily_quests;
create policy "read quests" on public.daily_quests
  for select using (true);

drop policy if exists "write quests" on public.daily_quests;
create policy "write quests" on public.daily_quests
  for all using (public.is_admin()) with check (public.is_admin());

-- quest_completions: one row per user per quest
create table if not exists public.quest_completions (
  id           uuid primary key default gen_random_uuid(),
  quest_id     uuid not null references public.daily_quests (id) on delete cascade,
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  completed_at timestamptz not null default now(),
  unique (quest_id, user_id)
);

alter table public.quest_completions enable row level security;

drop policy if exists "read completions" on public.quest_completions;
create policy "read completions" on public.quest_completions
  for select using (true);

drop policy if exists "insert completion" on public.quest_completions;
create policy "insert completion" on public.quest_completions
  for insert with check (user_id = auth.uid());

create index if not exists quest_completions_quest_idx on public.quest_completions (quest_id);
