-- The Town's two public pages, Joetown and the City, and the City's boards as follow targets (BP app
-- docs/plans/follows, ticket 04). Opened from the Town bar's wordmark and Daily's Joetown logo.
--
-- A page is one `town_pages` row: the Town's own (Joetown) and its City's. Each lists its coming
-- Events: those its own source wrote (`club_events.source_name`, the registry entry's name). The
-- City's page also lists its boards (`city_boards`, 20261019150000_city_boards.sql), each with its
-- next meeting. A neighbour follows a page or a board like a Place: `follow_target('page' | 'board',
-- id)`, a real account only, the real count from `follow_card`, listed in `my_follows`. A City
-- meeting's Event page names its board, or the City when it has none (`event_host`).

create table if not exists public.town_pages (
  id           uuid primary key default gen_random_uuid(),
  town         text not null,              -- sources.town
  slug         text not null,              -- 'town' (the Town's own page) or 'city'
  name         text not null,              -- as it calls itself
  kind         text not null,              -- the kind line: "City government"
  source_name  text not null,              -- club_events.source_name of its Events
  picture      text,                       -- a photo or logo address; none draws its initial
  picture_kind text,                       -- 'photo', 'logo', or 'town': the app's own Town logo
  unique (town, slug)
);

alter table public.town_pages enable row level security;
drop policy if exists "read town pages" on public.town_pages;
create policy "read town pages" on public.town_pages for select to anon, authenticated using (true);
grant select on public.town_pages to anon, authenticated;

insert into public.town_pages (town, slug, name, kind, source_name, picture_kind) values
  ('st-joseph-mn', 'town', 'Joetown', 'St. Joseph''s events', 'JoeTown', 'town'),
  ('st-joseph-mn', 'city', 'City of St. Joseph', 'City government', 'City of St. Joseph', null)
on conflict (town, slug) do update set name = excluded.name, kind = excluded.kind,
  source_name = excluded.source_name, picture_kind = excluded.picture_kind;

alter table public.town_follows drop constraint if exists town_follows_target_type_check;
alter table public.town_follows add constraint town_follows_target_type_check
  check (target_type in ('club', 'profile', 'place', 'team', 'activity', 'page', 'board'));

-- 20261026000000_activity_follows.sql's followable, with a page and a board.
create or replace function private.followable(p_type text, p_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case p_type
    when 'profile' then private.findable(p_id)
    when 'place' then exists (select 1 from public.places pl where pl.id = p_id)
    when 'team' then exists (select 1 from public.teams t where t.uuid = p_id and t.local)
    when 'activity' then exists (select 1 from public.team_activities a join public.teams t on t.id = a.team_id
                                 where a.id = p_id and t.local)
    when 'page' then exists (select 1 from public.town_pages p where p.id = p_id)
    when 'board' then exists (select 1 from public.city_boards b where b.id = p_id)
    else false
  end
$$;

-- One page: who it is, its coming Events (up to 10, soonest first) and, for a City, its boards A to
-- Z, each with its next meeting (null: none set) and whether you follow it (false signed out).
create or replace function public.town_page(p_town text, p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id, 'name', p.name, 'kind', p.kind, 'picture', p.picture, 'picture_kind', p.picture_kind,
    'events', coalesce((
      select jsonb_agg(x order by x ->> 'date', x ->> 'time')
      from (
        select jsonb_build_object('id', e.id, 'title', e.title, 'date', e.event_date, 'time', e.start_time,
                                  'location', e.location) as x
        from public.club_events e
        where lower(e.source_name) = lower(p.source_name) and e.status = 'approved' and e.cancelled_at is null
          and not e.followers_only and e.event_date >= (now() at time zone 'America/Chicago')::date
        order by e.event_date, e.start_time
        limit 10
      ) y), '[]'::jsonb),
    'boards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'name', b.name,
        'following', exists (select 1 from public.town_follows f where f.follower_id = auth.uid()
                             and f.target_type = 'board' and f.target_id = b.id),
        'next', (select jsonb_build_object('date', e.event_date, 'time', e.start_time)
                 from public.club_events e
                 where e.source_name = b.city_name and e.draw = 1 and e.status = 'approved'
                   and e.cancelled_at is null and e.event_date >= (now() at time zone 'America/Chicago')::date
                   and public.meeting_board(e) = b.id
                 order by e.event_date, e.start_time
                 limit 1)) order by b.name)
      from public.city_boards b
      where b.town = p.town and b.city_name = p.source_name), '[]'::jsonb))
  from public.town_pages p
  where p.town = p_town and p.slug = p_slug
$$;
revoke execute on function public.town_page(text, text) from public;
grant execute on function public.town_page(text, text) to anon, authenticated;

-- One board's coming meetings, for its row: up to 20, soonest first.
create or replace function public.board_meetings(p_board uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x order by x ->> 'date', x ->> 'time'), '[]'::jsonb)
  from (
    select jsonb_build_object('id', e.id, 'title', e.title, 'date', e.event_date, 'time', e.start_time,
                              'location', e.location) as x
    from public.city_boards b
    join public.club_events e on e.source_name = b.city_name and e.draw = 1
    where b.id = p_board and e.status = 'approved' and e.cancelled_at is null
      and e.event_date >= (now() at time zone 'America/Chicago')::date
      and public.meeting_board(e) = b.id
    order by e.event_date, e.start_time
    limit 20
  ) y
$$;
revoke execute on function public.board_meetings(uuid) from public;
grant execute on function public.board_meetings(uuid) to anon, authenticated;

-- 20261026020000_my_follows_own_photos.sql's my_follows, with pages and boards. A board's `kind` is
-- its City's name, as its row says it ("Planning Commission", "City of St. Joseph").
create or replace function public.my_follows()
returns table (target_type text, target_id uuid, name text, kind text, picture text, picture_kind text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  return query
    select x.* from (
      select 'profile'::text, t.target_id, p.display_name, null::text,
             case when p.avatar_url like 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/'
                                         || p.user_id::text || '/%' then p.avatar_url end,
             'photo'::text
      from public.town_follows t
      join public.town_profiles p on p.user_id = t.target_id
      where t.follower_id = me and t.target_type = 'profile' and private.findable(t.target_id)
      union all
      select 'place'::text, t.target_id, pl.name, pl.primary_type, pic ->> 'url', pic ->> 'kind'
      from public.town_follows t
      join public.places pl on pl.id = t.target_id
      cross join lateral (select public.place_picture(pl.entry_id) as pic) pp
      where t.follower_id = me and t.target_type = 'place'
      union all
      select 'team'::text, t.target_id, tm.short_name, 'team'::text, tm.logo_url, 'logo'::text
      from public.town_follows t
      join public.teams tm on tm.uuid = t.target_id
      where t.follower_id = me and t.target_type = 'team'
      union all
      select 'page'::text, t.target_id, pg.name, pg.kind, pg.picture, pg.picture_kind
      from public.town_follows t
      join public.town_pages pg on pg.id = t.target_id
      where t.follower_id = me and t.target_type = 'page'
      union all
      select 'board'::text, t.target_id, b.name, b.city_name, null::text, null::text
      from public.town_follows t
      join public.city_boards b on b.id = t.target_id
      where t.follower_id = me and t.target_type = 'board'
    ) x (target_type, target_id, name, kind, picture, picture_kind)
    order by lower(x.name), x.target_id;
end;
$$;

-- 20261022170000_follow_places_and_people.sql's event_host, with a page's Events first: a City
-- meeting's board ("Planning Commission", its kind the City's name), else the page that wrote it
-- (the City, Joetown). Then the neighbour who posted it, then its Place, as before.
create or replace function public.event_host(p_event uuid)
returns table (target_type text, target_id uuid, name text, kind text, picture text, picture_kind text,
               friend boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select h.target_type, h.target_id, h.name, h.kind, h.picture, h.picture_kind,
         h.target_type = 'profile' and auth.uid() is not null
           and private.relation(auth.uid(), h.target_id) = 'friends'
  from public.club_events e
  cross join lateral (
    select 'board'::text, b.id, b.name, b.city_name, null::text, null::text, 0
    from public.city_boards b
    where b.id = public.meeting_board(e)
    union all
    select 'page'::text, pg.id, pg.name, pg.kind, pg.picture, pg.picture_kind, 1
    from public.town_pages pg
    where lower(pg.source_name) = lower(e.source_name)
    union all
    select 'profile'::text, p.user_id, p.display_name, null::text, p.avatar_url, 'photo'::text, 2
    from public.town_profiles p
    where p.user_id = e.submitted_by and private.findable(e.submitted_by)
    union all
    select 'place'::text, pl.id, pl.name, pl.primary_type, pic ->> 'url', pic ->> 'kind', 3
    from public.places pl
    cross join lateral (select public.place_picture(pl.entry_id) as pic) pp
    where pl.entry_id = e.place_entry_id
    order by 7, 3
    limit 1
  ) h (target_type, target_id, name, kind, picture, picture_kind, rank)
  where e.id = p_event and e.club_id is null and e.status = 'approved'
$$;
