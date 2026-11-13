-- A school's page opens signed out, its events card shows Yesterday, and Search says an activity's next day
-- (BP app docs/plans/school-search, ticket 06; Jesse, 2026-11-13: "i agree").
-- team_page asked activity_has_event about every activity and every upcoming event in town, about 3 s for Kennedy and
-- 7 s for Sartell, past the 3 s a signed-out read gets: 7 of 9 schools failed on every signed-out call (2026-11-13).
-- Now each name goes through sport_base once, a cheap test that reads no table drops the pairs that can't match, and
-- activity_has_event judges only the rest: 0.1-0.5 s, the same activities and the same next events.

-- The parts of a slash name's sport ("Band/Choir/Orchestra"), each through sport_base.
create or replace function private.slash_bases(p text) returns text[]
language sql immutable set search_path = '' as $$
  select array(select private.sport_base(x) from unnest(string_to_array(p, '/')) x)
$$;

-- The tests of activity_has_event that read no table, on names already through sport_base and sport_gender: true for
-- every pair it says yes to, and for some it then turns down. activity_has_event asks it first, so a new way for a name
-- to match goes in here too or never matches; team_page and activities_next ask only this of every pair, and
-- activity_has_event of the pairs it lets through. No search_path of its own, unlike the rest, so a query takes its
-- words in rather than calling it once a pair (Sartell's page has 23,000 pairs); every name in it is schema-qualified.
create or replace function private.activity_may_have(a_base text, a_gender text, n text, n_base text, n_gender text,
                                                     no_sport boolean)
returns boolean language sql immutable as $$
  select (n_base = a_base
          or (no_sport and n_base <> '' and ' ' || a_base || ' ' like '% ' || n_base || ' %')
          or (no_sport and n like '%/%' and a_base = any(private.slash_bases(n))))
     and (n_gender is null or coalesce(a_gender, n_gender) = n_gender)
$$;

-- 20261113141150_kennedy_activity_events.sql's activity_has_event, asking activity_may_have first.
create or replace function public.activity_has_event(a public.team_activities, e public.club_events)
returns boolean
language sql stable set search_path = '' as $$
  select x.n is not null
    and coalesce(a.fielded_by, a.team_id) = any(array_append(coalesce(e.team_ids, '{}'), e.activity_team))
    and private.activity_may_have(private.sport_base(a.name), private.sport_gender(a.name), x.n,
                                  private.sport_base(x.n), private.sport_gender(x.n), e.sport is null)
    and (private.sport_base(x.n) = private.sport_base(a.name)
         or (e.sport is null and private.sport_base(x.n) <> ''
             and ' ' || private.sport_base(a.name) || ' ' like '% ' || private.sport_base(x.n) || ' %'
             and not exists (select 1 from public.team_activities r
                             where r.team_id = a.team_id and private.sport_base(r.name) = private.sport_base(x.n)))
         or (e.sport is null and x.n like '%/%'
             and private.sport_base(a.name) in (select private.sport_base(p) from unnest(string_to_array(x.n, '/')) p)))
    and case
      when private.sport_gender(x.n) is not null
        then coalesce(private.sport_gender(a.name), private.sport_gender(x.n)) = private.sport_gender(x.n)
      else private.sport_gender(a.name) is not distinct from (
        select private.sport_gender(r.name) from public.team_activities r
        where r.team_id = coalesce(a.fielded_by, a.team_id) and r.fielded_by is null
          and private.sport_base(r.name) = private.sport_base(x.n)
        order by private.sport_gender(r.name) is not null,
                 lower(r.name) not like private.sport_base(x.n) || '%', r.sort
        limit 1)
    end
  from (select coalesce(e.sport, e.activity_name) as n) x
$$;

-- 20261026132204_activity_follow_lift.sql's team_page, faster, and with the school's events from the Town's yesterday
-- on (`events`, each once, with the first of its activities in the school's order), so the page's events card is
-- this one read rather than activity_events once an activity. `games` is as it was.
create or replace function public.team_page(p_team uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with t as (select * from public.teams where uuid = p_team and local),
  acts as materialized (
    select a, a.id, a.sort, coalesce(a.fielded_by, a.team_id) as fielder,
           private.sport_base(a.name) as base, private.sport_gender(a.name) as gender
    from t join public.team_activities a on a.team_id = t.id),
  -- Each event once a team it names, so it meets each activity by its team with an equal join.
  evs as materialized (
    select e, k.team, x.n, private.sport_base(x.n) as base, private.sport_gender(x.n) as gender
    from public.club_events e,
         lateral (select coalesce(e.sport, e.activity_name) as n) x,
         lateral (select distinct unnest(array_append(coalesce(e.team_ids, '{}'), e.activity_team)) as team) k
    where e.status = 'approved' and e.cancelled_at is null
      and e.event_date >= (now() at time zone 'America/Chicago')::date - 1
      and k.team in (select fielder from acts)),
  -- Materialized so activity_has_event sees only these: left to the planner, it ran first, being the cheaper call.
  pairs as materialized (
    select a.id as activity, a.sort, a.a, v.e
    from acts a join evs v on v.team = a.fielder
    where private.activity_may_have(a.base, a.gender, v.n, v.base, v.gender, (v.e).sport is null)),
  hits as materialized (
    select p.activity, p.sort, (p.e).id, (p.e).title, (p.e).event_date, (p.e).start_time, (p.e).location
    from pairs p
    where public.activity_has_event(p.a, p.e))
  select jsonb_build_object(
    'id', t.uuid, 'name', coalesce(t.school_name, t.name), 'short', t.short_name, 'logo', t.logo_url,
    'colors', t.colors,
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
          and not e.followers_only
          and e.event_date >= (now() at time zone 'America/Chicago')::date
        order by e.event_date, e.start_time
        limit 5
      ) x), '[]'::jsonb),
    'activities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'name', (a.a).name, 'note', (a.a).note, 'kind', (a.a).kind,
        'following', exists (select 1 from public.town_follows f where f.follower_id = auth.uid()
                             and f.target_type = 'activity' and f.target_id = a.id),
        'next', (select jsonb_build_object('id', h.id, 'title', h.title, 'date', h.event_date, 'time', h.start_time)
                 from hits h
                 where h.activity = a.id and h.event_date >= (now() at time zone 'America/Chicago')::date
                 order by h.event_date, h.start_time
                 limit 1)) order by a.sort)
      from acts a), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object('id', h.id, 'title', h.title, 'date', h.event_date, 'time', h.start_time,
                                          'location', h.location, 'activity', h.activity)
                       order by h.event_date, h.start_time, h.sort)
      from (select distinct on (id) * from hits order by id, sort) h), '[]'::jsonb))
  from t
$$;

revoke execute on function public.team_page(uuid) from public;
grant execute on function public.team_page(uuid) to anon, authenticated;

-- Each activity's next event from the Town's today, for the given local schools: Search's day under a typed activity
-- ("Kennedy · Tomorrow"). `[{id, date, time}]`, only the activities with one.
create or replace function public.activities_next(p_teams text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with acts as materialized (
    select a, a.id, coalesce(a.fielded_by, a.team_id) as fielder,
           private.sport_base(a.name) as base, private.sport_gender(a.name) as gender
    from public.team_activities a
    join public.teams t on t.id = a.team_id and t.local
    where a.team_id = any(p_teams)),
  evs as materialized (
    select e, k.team, x.n, private.sport_base(x.n) as base, private.sport_gender(x.n) as gender
    from public.club_events e,
         lateral (select coalesce(e.sport, e.activity_name) as n) x,
         lateral (select distinct unnest(array_append(coalesce(e.team_ids, '{}'), e.activity_team)) as team) k
    where e.status = 'approved' and e.cancelled_at is null
      and e.event_date >= (now() at time zone 'America/Chicago')::date
      and k.team in (select fielder from acts)),
  pairs as materialized (
    select a.id, a.a, v.e, (v.e).event_date, (v.e).start_time
    from acts a join evs v on v.team = a.fielder
    where private.activity_may_have(a.base, a.gender, v.n, v.base, v.gender, (v.e).sport is null))
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'date', n.event_date, 'time', n.start_time)), '[]'::jsonb)
  from (select distinct on (id) id, a from pairs order by id) a
  -- An activity's pairs soonest first, asked in turn until one is its: the inner order and `offset 0` keep the
  -- planner from asking every pair before sorting.
  cross join lateral (
    select c.event_date, c.start_time
    from (select p.e, p.event_date, p.start_time from pairs p where p.id = a.id
          order by p.event_date, p.start_time offset 0) c
    where public.activity_has_event(a.a, c.e)
    order by c.event_date, c.start_time
    limit 1) n
$$;

revoke execute on function public.activities_next(text[]) from public;
grant execute on function public.activities_next(text[]) to anon, authenticated;
