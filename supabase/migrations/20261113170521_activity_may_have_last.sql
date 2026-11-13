-- activity_has_event asks activity_may_have last, not first (BP app docs/plans/school-search, ticket 06; Jesse,
-- 2026-11-13: "yes i agree"). First, it cost every pair of the same team four more name lookups, and most pairs are no
-- match: on 8,700 Town-feed-like pairs the function's own work went from 93 ms to 137-162 ms. Last, it runs only for a
-- pair everything else already said yes to, where it is true by construction, and still turns down a match a new name
-- rule would make without it.

-- 20261113143629_faster_school_page.sql's activity_has_event but for where activity_may_have sits.
create or replace function public.activity_has_event(a public.team_activities, e public.club_events)
returns boolean
language sql stable set search_path = '' as $$
  select x.n is not null
    and coalesce(a.fielded_by, a.team_id) = any(array_append(coalesce(e.team_ids, '{}'), e.activity_team))
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
