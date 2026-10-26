-- Each local school's own name on its page (Jesse, 2026-10-25: "get specific school names right"):
-- "Apollo High School", as its site writes it, where the game cards keep "Apollo". 20261026000000's
-- team_page, naming the school by it.

alter table public.teams add column if not exists school_name text;

update public.teams set school_name = s.name
from (values ('apollo', 'Apollo High School'), ('tech', 'Tech High School'), ('kennedy', 'Kennedy Community School'),
             ('cathedral', 'Cathedral High School'), ('apollo-cathedral', 'Apollo-Cathedral co-op'),
             ('rocori', 'ROCORI High School'), ('sartell', 'Sartell High School'),
             ('sauk-rapids-rice', 'Sauk Rapids-Rice High School'), ('saint-benedict', 'College of Saint Benedict'),
             ('saint-johns', 'Saint John''s University')) as s(id, name)
where teams.id = s.id;

create or replace function public.team_page(p_team uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
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
