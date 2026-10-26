-- Follow one of a school's activities (BP app docs/plans/school-activities, ticket 02; Jesse, 2026-10-25:
-- "parents search for a specific activity and subscribe or follow it"). A star on the school's page
-- follows one `team_activities` row; the page lists them with each one's next event and whether you
-- follow it. Kennedy Community School gets the logo the app already has for it, and its colours read
-- from that logo (references/team-follow/team_colors.py: silver #CDCECF, green #1C532F, navy #1B2859),
-- navy first so its page is navy fading down and a starred star green.

alter table public.town_follows drop constraint if exists town_follows_target_type_check;
alter table public.town_follows add constraint town_follows_target_type_check
  check (target_type in ('club', 'profile', 'place', 'team', 'activity'));

-- 20261023120000_team_follows.sql's followable, with an activity of a local school.
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
    else false
  end
$$;

update public.teams
set logo_url = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/kennedy-community-school/logo-14e0e9e7e8.webp',
    colors = array['#1B2859', '#1C532F', '#CDCECF']
where id = 'kennedy';

-- 20261023120000_team_follows.sql's team_page, plus `activities`: each in the school's own order,
-- with its note ("St. Cloud Crush co-op"), kind, next game (null: "No events yet") and whether you
-- follow it (false signed out).
create or replace function public.team_page(p_team uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.uuid, 'name', t.name, 'short', t.short_name, 'logo', t.logo_url, 'colors', t.colors,
    'games', coalesce((
      select jsonb_agg(g order by g ->> 'date', g ->> 'time')
      from (
        select jsonb_build_object('id', e.id, 'sport', e.sport, 'date', e.event_date,
                                  'time', e.start_time, 'location', e.location,
                                  'other', coalesce(o.short_name, o.name,
                                                    e.team_ids[case when e.team_ids[1] = t.id then 2 else 1 end])) as g
        from public.club_events e
        left join public.teams o on o.id = e.team_ids[case when e.team_ids[1] = t.id then 2 else 1 end]
        where t.id = any(e.team_ids) and e.status = 'approved' and e.cancelled_at is null
          and e.event_date >= (now() at time zone 'America/Chicago')::date
        order by e.event_date, e.start_time
        limit 5
      ) x), '[]'::jsonb),
    'activities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'name', a.name, 'note', a.note, 'kind', a.kind,
        'following', exists (select 1 from public.town_follows f where f.follower_id = auth.uid()
                             and f.target_type = 'activity' and f.target_id = a.id),
        'next', (select jsonb_build_object('id', e.id, 'title', e.title, 'date', e.event_date, 'time', e.start_time)
                 from public.club_events e
                 where e.status = 'approved' and e.cancelled_at is null and e.sport is not null
                   and e.event_date >= (now() at time zone 'America/Chicago')::date
                   and public.activity_has_event(a, e)
                 order by e.event_date, e.start_time
                 limit 1)) order by a.sort)
      from public.team_activities a
      where a.team_id = t.id), '[]'::jsonb))
  from public.teams t
  where t.uuid = p_team and t.local
$$;
revoke execute on function public.team_page(uuid) from public;
grant execute on function public.team_page(uuid) to anon, authenticated;

-- One activity's coming events, for its row's arrow: up to 20, soonest first.
create or replace function public.activity_events(p_activity uuid)
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
    from public.team_activities a
    join public.club_events e on e.sport is not null and public.activity_has_event(a, e)
    where a.id = p_activity and e.status = 'approved' and e.cancelled_at is null
      and e.event_date >= (now() at time zone 'America/Chicago')::date
    order by e.event_date, e.start_time
    limit 20
  ) y
$$;
revoke execute on function public.activity_events(uuid) from public;
grant execute on function public.activity_events(uuid) to anon, authenticated;
