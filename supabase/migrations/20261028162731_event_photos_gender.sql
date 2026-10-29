-- Event photos (BP app docs/plans/event-photos 07, round 2): a girls' game never shows a boys' photo,
-- nor the other way (2026-10-28: Sartell, Kennedy and Sauk Rapids-Rice girls' basketball showed boys).
-- A scene showing one side carries 'girls' or 'boys' among its subjects; an untagged one (the fans, the
-- empty rink) fits either, and so does an event that names neither (SJU's and CSB's games).

create or replace function private.event_gender(p_title text, p_sport text)
returns text
language sql
immutable
as $$
  select case
    when x ~ '\y(girls|women|womens|women''s|lady|ladies)\y' then 'girls'
    when x ~ '\y(boys|men|mens|men''s)\y' then 'boys'
  end
  from (select lower(coalesce(p_sport, '') || ' ' || coalesce(p_title, '')) as x) t
$$;

-- public.event_picture, as 20261028155018_event_photos_christmas.sql made it, with the girls' and boys' test.
create or replace function public.event_picture(p_event uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object('url', s.url, 'kind', 'photo', 'credit', s.credit, 'site', s.source_url,
                               'w', s.width, 'h', s.height,
                               'more', coalesce((select jsonb_agg(jsonb_build_object('url', o.url, 'kind', 'photo',
                                                          'credit', o.credit, 'site', o.source_url,
                                                          'w', o.width, 'h', o.height)
                                                        order by o.position, o.id)
                                                   from public.place_photos o
                                                  where o.entry_id = s.entry_id and o.status = 'live'
                                                    and o.kind = 'photo'), '[]'::jsonb))
       from public.club_events e
       join public.place_photos s on s.entry_id = e.place_entry_id and s.status = 'live' and s.kind = 'scene'
      where e.id = p_event
        and private.event_subject(e.title, e.sport, e.category) = any (s.subjects)
        and (s.seasons = '{}' or private.season_of(e.event_date) = any (s.seasons)
             or ('christmas' = any (s.seasons) and private.christmas_time(e.event_date)))
        and not ('girls' = any (s.subjects) and coalesce(private.event_gender(e.title, e.sport), '') = 'boys')
        and not ('boys' = any (s.subjects) and coalesce(private.event_gender(e.title, e.sport), '') = 'girls')
      order by s.seasons = '{}', md5(e.id::text || s.id::text)
      limit 1),
    (select public.place_picture(e.place_entry_id) from public.club_events e where e.id = p_event))
$$;
