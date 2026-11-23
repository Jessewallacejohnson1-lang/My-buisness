-- Every tap on a card is recorded (BP app docs/plans/feed-learns, ticket 02; Jesse's yes at Check-in 1, 2026-11-22).
-- The Feed learning from taps (ticket 06) needs weeks of them, so they are saved from now on. Four new kinds: a photo
-- swiped to the next (photo), the place or host tapped (place), a map opened (map) and the link to where the item was
-- found (link). Going, Hearts and comments are read from their own tables.
--
--   feed_actions   takes the four kinds, for Events and posts (a post is a club_events row).
--   news_actions   News's opens and taps. feed_actions' item is an Event, so a News id can't go there. Insert-only, as
--                  feed_actions is: who and when are set here, and nobody reads a row through the API.
--   once a day     one row per person, item, kind and Town day in both. A row whose item has gone is skipped, so one
--                  deleted post no longer makes the server refuse the app's whole batch, its views included.
--
-- Roll back: the app first (it would lose every batch with a new kind), then the action check of
-- 20261030202350_feed_actions_once_a_day.sql, the trigger of 20261105211111_fresh_every_open.sql, and
-- drop table public.news_actions.

alter table public.feed_actions drop constraint feed_actions_action_check;
alter table public.feed_actions add constraint feed_actions_action_check
  check (action in ('view', 'open', 'not_interested', 'reported', 'share', 'photo', 'place', 'map', 'link'));

-- As 20261105211111_fresh_every_open.sql, but a row whose Event or post has gone is skipped.
create or replace function private.feed_actions_once_a_day()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.club_events e where e.id = new.item_id) then
    return null;
  end if;
  update public.feed_actions a
     set times = a.times + 1, last_at = new.at
   where new.action = 'view'
     and a.item_id = new.item_id and a.user_id = new.user_id and a.action = new.action
     and (a.at at time zone 'America/Chicago')::date = (new.at at time zone 'America/Chicago')::date
     and new.at >= coalesce(a.last_at, a.at) + interval '10 minutes';
  if exists (select 1 from public.feed_actions a
             where a.item_id = new.item_id and a.user_id = new.user_id and a.action = new.action
               and (a.at at time zone 'America/Chicago')::date = (new.at at time zone 'America/Chicago')::date) then
    return null;
  end if;
  return new;
end
$$;

create table public.news_actions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  item_id uuid not null references public.board_items (id) on delete cascade,
  action text not null check (action in ('open', 'photo', 'place', 'link')),
  at timestamptz not null default now()
);
-- The repeat check, and an account's or a story's deletion, look rows up by these.
create index news_actions_user_id_idx on public.news_actions (user_id);
create index news_actions_item_user_idx on public.news_actions (item_id, user_id);

alter table public.news_actions enable row level security;
revoke all on public.news_actions from anon, authenticated;
grant insert (item_id, action) on public.news_actions to authenticated;
create policy "insert own news actions" on public.news_actions
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- Security definer: nobody reads this table through the API, the caller included.
create function private.news_actions_once_a_day()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.board_items b where b.id = new.item_id)
     or exists (select 1 from public.news_actions a
                where a.item_id = new.item_id and a.user_id = new.user_id and a.action = new.action
                  and (a.at at time zone 'America/Chicago')::date = (new.at at time zone 'America/Chicago')::date) then
    return null;
  end if;
  return new;
end
$$;
revoke execute on function private.news_actions_once_a_day() from public, anon, authenticated;

create trigger news_actions_once_a_day
  before insert on public.news_actions
  for each row execute function private.news_actions_once_a_day();
