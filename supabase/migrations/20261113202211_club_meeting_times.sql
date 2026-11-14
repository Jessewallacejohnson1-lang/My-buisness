-- A club's meeting time on its row of the school's page (BP app docs/plans/nothing-scheduled, ticket 03; the look Jesse
-- approved: references/club-meeting-times/mock.html, beside Apple Sports' "Off Season" line). School clubs publish a
-- weekly meeting time, not dates (dig-deeper 26), so a club with no Event coming said "No events yet" all year. Now its
-- row says the pattern, "Fridays · 8 AM", never a computed date: a school's pattern doesn't know its days off.
--
-- `meets` is a Group's meeting rule (`clubs.meets`, rsvp-and-groups 05): days, a time, the weeks of the month. Two
-- additions the schools' words need: "every": 2 (every other week) and a time given only in words ("After school").
-- group_meetings never reads these rows; the app says a rule in words (`MeetingRule.words`).

-- A list or nothing, so the app's read of a page never meets a stray object; a mistyped rule inside it costs only itself
-- (the app reads a field of the wrong kind as missing).
alter table public.team_activities add column if not exists meets jsonb
  check (meets is null or jsonb_typeof(meets) = 'array');
comment on column public.team_activities.meets is
  'When the activity meets, as its school''s page says it: a Group''s meeting rules (clubs.meets) [{days, time, weeks, '
  'every}], shown on its row while no Event is coming (BP app nothing-scheduled 03). Null: the school gives no time.';

-- Sartell's activities page (isd748.org/sabres, read once on 2026-11-13; the copy is BP app
-- docs/plans/nothing-scheduled/assets/03-sartell-sabres.html, read by sources/scripts/meeting_times.py): 12 of its 31
-- clubs give a time. The other schools' pages give an advisor or "All year". Ticket 05's weekly step keeps them current.
do $$
declare n int;
begin
  update public.team_activities a set meets = m.meets::jsonb
  from (values
    ('Bible Study', '[{"days": ["fri"], "time": "08:00"}]'),
    ('Birding Club', '[{"days": ["tue"], "time": "08:00"}]'),
    ('Crochet & Knitting Club', '[{"days": ["thu"], "time": "07:45"}]'),
    ('Fellowship of Christian Athletes', '[{"days": ["thu"], "time": "07:15"}]'),
    ('F.E.M. Club', '[{"days": ["tue"], "time": "08:00"}]'),
    ('Honor Society', '[{"days": ["tue"], "weeks": [2]}]'),
    ('Letters of Love', '[{"days": ["fri"], "weeks": [2]}]'),
    ('Path to Healthcare Club', '[{"days": ["fri"], "every": 2, "time": "07:45"}]'),
    ('Sartell K-Pop Dance Cover Club', '[{"days": ["wed"], "time": "After school"}]'),
    ('S.A.F.E. Club', '[{"days": ["mon"], "weeks": [1, 3], "time": "08:00"}]'),
    ('Student Council', '[{"days": ["fri"], "time": "07:45"}]'),
    ('Table Top Gaming Club', '[{"days": ["wed"], "time": "08:00"}]')
  ) as m(name, meets)
  where a.team_id = 'sartell' and a.name = m.name;
  get diagnostics n = row_count;
  if n <> 12 then
    raise exception 'Sartell meeting times: % updated, 12 expected; the school renamed a club', n;
  end if;
end $$;

-- 20261113173613_co_op_teams.sql's team_page, each activity carrying its meeting rules.
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
    from acts a cross join lateral unnest(array[a.fielder, a.coop]) f(team) join evs v on v.team = f.team
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
        'id', a.id, 'name', (a.a).name, 'note', (a.a).note, 'kind', (a.a).kind, 'meets', (a.a).meets,
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
