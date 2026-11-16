-- A school's own Event names its school on the Event page (BP app inside-cards 33, Jesse 2026-11-15: yes to the
-- ticket). About 200 upcoming Events posted by a high school (Sartell, Apollo, Cathedral, ROCORI, Sauk Rapids-Rice,
-- Tech) showed the school's logo on their Town card but no host row on the page, and a tap on the card's mark opened
-- the Event itself: the poster has no `town_pages` page and no `places` row. Each of these schools has a page of its
-- own (a local team, `TeamPage`), so `event_host` now names it: the local team whose school, or one of its other
-- names, is who posted the Event, with the card's picture (`private.host_picture`), else the team's logo. It comes
-- after the poster's own page or place and before the venue, which moves from 5 to 6.
--
-- "CSB Athletics" and "SJU Athletics" post the colleges' games and events; they become names of Saint Benedict and
-- Saint John's, so their Events name the college too (and Search finds the college by them).
--
-- Body copied from 20261115200354_page_names_card_host.sql, the newest that makes it; only the team row and the
-- venue's rank change.
update public.teams set aliases = array_append(aliases, 'CSB Athletics')
where id = 'saint-benedict' and not ('CSB Athletics' = any (aliases));
update public.teams set aliases = array_append(aliases, 'SJU Athletics')
where id = 'saint-johns' and not ('SJU Athletics' = any (aliases));

create or replace function public.event_host(p_event uuid)
returns table (target_type text, target_id uuid, name text, kind text, picture text, picture_kind text,
               friend boolean)
language sql
stable
security definer
set search_path = ''
as $$
  -- Each target once, the host's row first: a list that names its host again adds no second row.
  select y.target_type, y.target_id, y.name, y.kind, y.picture, y.picture_kind, y.friend
  from (
  select distinct on (x.target_id) x.*
  from (
    select h.target_type, h.target_id, h.name, h.kind, h.picture, h.picture_kind,
           h.target_type = 'profile' and auth.uid() is not null
             and private.relation(auth.uid(), h.target_id) = 'friends' as friend,
           0::bigint as ord
    from public.club_events e
    cross join lateral (
      select 'board'::text, b.id, b.name, b.city_name, null::text, null::text, 0
      from public.city_boards b
      where b.id = public.meeting_board(e)
      union all
      -- The City's own meetings name the City; every other page of the Event's source comes before its venue.
      select 'page'::text, pg.id, pg.name, pg.kind, coalesce(pic ->> 'url', pg.picture),
             case when pic is null then pg.picture_kind else pic ->> 'kind' end, case pg.slug when 'city' then 1 else 3 end
      from public.town_pages pg
      cross join lateral (select private.host_picture(pg.source_name, null) as pic) pp
      where lower(pg.source_name) = lower(e.source_name)
      union all
      select 'profile'::text, p.user_id, p.display_name, null::text, p.avatar_url, 'photo'::text, 2
      from public.town_profiles p
      where p.user_id = e.submitted_by and private.findable(e.submitted_by)
      union all
      -- The place the card's mark is, found by the source's name as `private.host_picture` finds it, then the venue.
      select 'place'::text, pl.id, pl.name, pl.primary_type, pic ->> 'url', pic ->> 'kind', 4
      from public.places pl
      cross join lateral (select private.entry_picture(pl.entry_id) as pic) pp
      where pl.entry_id = coalesce((select h.entry_id from public.host_entries h where h.name = e.source_name),
                                   (select s.entry_id from public.sources s where s.name = e.source_name
                                     order by s.entry_id limit 1))
      union all
      -- A school's own Event: the school's page, with the card's picture (inside-cards 33).
      select 'team'::text, t.uuid, coalesce(t.school_name, t.name), null::text, coalesce(pic ->> 'url', t.logo_url),
             case when pic ->> 'url' is not null then pic ->> 'kind' when t.logo_url is not null then 'logo' end, 5
      from public.teams t
      cross join lateral (select private.host_picture(e.source_name, null) as pic) pp
      where t.local and lower(e.source_name) in (select lower(n) from unnest(t.school_name || t.aliases) n)
      union all
      select 'place'::text, pl.id, pl.name, pl.primary_type, pic ->> 'url', pic ->> 'kind', 6
      from public.places pl
      cross join lateral (select private.entry_picture(pl.entry_id) as pic) pp
      where pl.entry_id = e.place_entry_id
      order by 7, 3
      limit 1
    ) h (target_type, target_id, name, kind, picture, picture_kind, rank)
    where e.id = p_event and e.club_id is null and e.status = 'approved'
    union all
    -- The places it was made with (town-feed 58), after the host.
    select 'place'::text, pl.id, pl.name, pl.primary_type, pic ->> 'url', pic ->> 'kind', false, k.n
    from public.club_events e
    cross join lateral unnest(e.collab_entry_ids) with ordinality k(entry, n)
    join public.places pl on pl.entry_id = k.entry
    cross join lateral (select public.place_picture(pl.entry_id) as pic) pp
    where e.id = p_event and e.club_id is null and e.status = 'approved'
  ) x
  order by x.target_id, x.ord
  ) y
  order by y.ord
$$;
