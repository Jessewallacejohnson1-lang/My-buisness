-- The campus calendars' pages (BP app docs/plans/follows, tickets 07 and 08; Jesse, 2026-10-27): each
-- calendar the CSB and SJU events portal fills the Town feed with is its own page, followed by the name
-- its cards show, like Joetown's (`town_pages`, 20261027143913_city_pages.sql). A page lists the Events
-- carrying its name (`town_page`), its Event pages name it with Follow (`event_host`), and a follow lifts
-- its Events in the Town feed (town-feed 27). The photo is the one Block Party keeps for the registry
-- entry `csbsju-events` (place-photos). CSB and SJU Athletics stay out: following Saint Ben's or Saint
-- John's on the school pages already covers their games.

-- A photo from the web says whose it is, as a Place's does (place-photos): the site it came from.
alter table public.town_pages add column if not exists picture_credit text;

insert into public.town_pages (town, slug, name, kind, source_name, picture, picture_kind, picture_credit)
select 'st-joseph-mn', p.slug, p.name, 'College', p.name,
       'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/csbsju-events/photo-774a7306de.webp',
       'photo', 'csbsju.edu'
from (values ('csbsju-campus-events', 'CSB SJU Campus Events'),
             ('csbsju-libraries', 'CSB SJU Libraries'),
             ('csbsju-outdoor-u', 'CSB SJU Outdoor U'),
             ('sju-school-of-theology', 'Saint John''s School of Theology'),
             ('csbsju', 'CSB SJU')) p (slug, name)
on conflict (town, slug) do update set name = excluded.name, kind = excluded.kind,
  source_name = excluded.source_name, picture = excluded.picture, picture_kind = excluded.picture_kind,
  picture_credit = excluded.picture_credit;

-- One page (20261027143913_city_pages.sql's, plus its photo's credit): who it is, its coming Events (up to 10, soonest first) and, for a City, its boards A to
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
    'picture_credit', p.picture_credit,
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

-- A page by its id, as a host's tap knows it (`event_host`, `my_follows`): the same read.
create or replace function public.town_page_by_id(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select public.town_page(p.town, p.slug) from public.town_pages p where p.id = p_id
$$;
revoke execute on function public.town_page_by_id(uuid) from public;
grant execute on function public.town_page_by_id(uuid) to anon, authenticated;
