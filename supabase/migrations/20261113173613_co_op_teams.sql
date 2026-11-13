-- A co-op team's games land on every member school's activity (BP app docs/plans/school-search, ticket 08; Jesse,
-- 2026-11-13: "yes to all"). Several winter teams are co-ops of two or more schools. Their games come from the host
-- school's Bound feed tagged with the co-op team ("St. Cloud Girls Hockey" names st-cloud and Apollo), so they landed
-- only on the host's row: Tech's Girls Hockey, Boys Hockey and Adapted Hockey, Cathedral's Girls Hockey, Gymnastics and
-- Boys Swim & Dive, ROCORI's Boys Swim and Sauk Rapids-Rice's Gymnastics had no games while the co-op played weekly.
--
-- `fielded_by` can't carry it: it replaces the row's own school, so Apollo's Wrestling would lose the 10 tournaments its
-- feed lists under Apollo alone. `coop` is a second team whose games the row also takes, beside its own (or its
-- fielder's). The gender rule still reads the school's own rows, so a co-op's ungendered "Wrestling" meet is the
-- school's Wrestling, never its Girls Wrestling.

alter table public.team_activities add column if not exists coop text references public.teams (id);
comment on column public.team_activities.coop is
  'A co-op team whose games this activity also takes, beside its own school''s (or fielded_by''s): MSHSL''s cooperative '
  'sponsorship, members as its team pages list them (BP app school-search 08).';
create index if not exists team_activities_coop_idx on public.team_activities (coop);

-- The co-op teams as the schedules write them (live already; a fresh database gets them here).
insert into public.teams (id, name, short_name, local) values
  ('st-cloud', 'St. Cloud', 'St. Cloud', false),
  ('st-cloud-srr', 'St. Cloud-SRR', 'St. Cloud-SRR', false),
  ('st-cloud-rocori', 'St. Cloud-ROCORI', 'St. Cloud-ROCORI', false),
  ('sartell-sauk-rapids', 'Sartell-Sauk Rapids', 'Sartell-SR', false),
  ('river-lakes', 'River Lakes', 'River Lakes', false)
on conflict (id) do nothing;

-- Members from MSHSL's 2026-27 team pages ("Schools:"), local schools only. Nordic has no co-op team in the feeds: the
-- host's own games carry it (Apollo hosts Tech's and ROCORI's, Cathedral hosts Sartell's). Girls wrestling, Cathedral
-- bowling and alpine stay out: MSHSL lists no girls co-op, bowling isn't MSHSL's, and no alpine meet is in any feed.
do $$
declare n int;
begin
  update public.team_activities a set coop = m.coop
  from (values
    ('apollo', 'Boys Hockey', 'st-cloud'), ('tech', 'Boys Hockey', 'st-cloud'),
    ('apollo', 'Girls Hockey', 'st-cloud'), ('tech', 'Girls Hockey', 'st-cloud'), ('cathedral', 'Girls Hockey', 'st-cloud'),
    ('apollo', 'Wrestling', 'st-cloud'), ('tech', 'Wrestling', 'st-cloud'), ('cathedral', 'Wrestling', 'st-cloud'),
    ('kennedy', 'Wrestling 7-12', 'st-cloud'),
    ('apollo', 'Girls Basketball', 'st-cloud'), ('tech', 'Girls Basketball', 'st-cloud'),
    ('apollo', 'Adapted Hockey (Adapted Floor Hockey)', 'st-cloud'), ('tech', 'Adapted Hockey', 'st-cloud'),
    ('sartell', 'Adapted Floor Hockey', 'st-cloud'), ('sauk-rapids-rice', 'Adapted Sports: Floor Hockey', 'st-cloud'),
    ('kennedy', 'Boys/Girls Adapted Floor Hockey', 'st-cloud'),
    ('apollo', 'Girls Gymnastics', 'st-cloud-srr'), ('tech', 'Girls Gymnastics', 'st-cloud-srr'),
    ('cathedral', 'Gymnastics', 'st-cloud-srr'), ('sauk-rapids-rice', 'Gymnastics', 'st-cloud-srr'),
    ('apollo', 'Boys Swim & Dive', 'st-cloud-rocori'), ('tech', 'Boys Swim & Dive', 'st-cloud-rocori'),
    ('cathedral', 'Boys Swim & Dive', 'st-cloud-rocori'), ('rocori', 'Swimming & Diving - Boys', 'st-cloud-rocori'),
    ('kennedy', 'Boys Swimming 7-12', 'st-cloud-rocori'),
    ('sartell', 'Hockey - Girls', 'sartell-sauk-rapids'), ('sauk-rapids-rice', 'Hockey - Girls', 'sartell-sauk-rapids'),
    ('rocori', 'Hockey - Boys', 'river-lakes'), ('rocori', 'Hockey - Girls', 'river-lakes'),
    ('tech', 'Boys Nordic Skiing', 'apollo'), ('tech', 'Girls Nordic Skiing', 'apollo'),
    ('rocori', 'Nordic Ski Racing - Boys', 'apollo'), ('rocori', 'Nordic Ski Racing - Girls', 'apollo'),
    ('sartell', 'Nordic Ski (boys)', 'cathedral'), ('sartell', 'Nordic Ski (girls)', 'cathedral')
  ) as m(team_id, name, coop)
  where a.team_id = m.team_id and a.name = m.name;
  get diagnostics n = row_count;
  if n <> 35 then
    raise exception 'co-op rows: % updated, 35 expected; a school renamed an activity', n;
  end if;
end $$;

-- 20261113170521_activity_may_have_last.sql's activity_has_event, taking the co-op's games too.
create or replace function public.activity_has_event(a public.team_activities, e public.club_events)
returns boolean
language sql stable set search_path = '' as $$
  select x.n is not null
    and (coalesce(a.fielded_by, a.team_id) = any(array_append(coalesce(e.team_ids, '{}'), e.activity_team))
         or a.coop = any(array_append(coalesce(e.team_ids, '{}'), e.activity_team)))
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
    and private.activity_may_have(private.sport_base(a.name), private.sport_gender(a.name), x.n,
                                  private.sport_base(x.n), private.sport_gender(x.n), e.sport is null)
  from (select coalesce(e.sport, e.activity_name) as n) x
$$;

-- 20261113143629_faster_school_page.sql's team_page and activities_next: the co-op's games join the quick pairing.
create or replace function public.team_page(p_team uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with t as (select * from public.teams where uuid = p_team and local),
  acts as materialized (
    select a, a.id, a.sort, coalesce(a.fielded_by, a.team_id) as fielder, a.coop,
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
      and k.team in (select fielder from acts union select coop from acts)),
  -- Materialized so activity_has_event sees only these: left to the planner, it ran first, being the cheaper call.
  pairs as materialized (
    select a.id as activity, a.sort, a.a, v.e
    from acts a join evs v on v.team = a.fielder or v.team = a.coop
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
    select a, a.id, coalesce(a.fielded_by, a.team_id) as fielder, a.coop,
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
      and k.team in (select fielder from acts union select coop from acts)),
  pairs as materialized (
    select a.id, a.a, v.e, (v.e).event_date, (v.e).start_time
    from acts a join evs v on v.team = a.fielder or v.team = a.coop
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
