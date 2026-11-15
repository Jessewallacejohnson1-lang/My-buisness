-- An Event page's host shows the picture its Town card shows (BP app inside-cards 31, Jesse 2026-11-15: "why does
-- the event card pfp on the home page look different than the one inside the card", "the logo changes example the
-- midterm election event"). The card's mark is `private.host_picture`, logo first; `event_host` handed the page the
-- place's photo first (`place_picture`) and a page's stored photo (`town_pages.picture`), so 1,468 of 1,470 upcoming
-- Events showed one picture on the card and another on the page. Now the host's row takes the card's logo-first
-- pick: a place its own (`private.entry_picture`), a page the one its source name finds as the card's does, else
-- its stored picture. The businesses an Event was made with keep `place_picture`, as their card marks do.
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
      -- The City's own meetings name the City; a Joetown Event still names its Place first.
      select 'page'::text, pg.id, pg.name, pg.kind, coalesce(pic ->> 'url', pg.picture),
             case when pic is null then pg.picture_kind else pic ->> 'kind' end, case pg.slug when 'city' then 1 else 4 end
      from public.town_pages pg
      cross join lateral (select private.host_picture(pg.source_name, null) as pic) pp
      where lower(pg.source_name) = lower(e.source_name)
      union all
      select 'profile'::text, p.user_id, p.display_name, null::text, p.avatar_url, 'photo'::text, 2
      from public.town_profiles p
      where p.user_id = e.submitted_by and private.findable(e.submitted_by)
      union all
      select 'place'::text, pl.id, pl.name, pl.primary_type, pic ->> 'url', pic ->> 'kind', 3
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
