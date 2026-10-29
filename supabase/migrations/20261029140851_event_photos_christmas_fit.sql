-- Event photos (BP app docs/plans/event-photos 07, round 2): a Christmas photo goes on a holiday event
-- from November 1, and on any event from December 1 to January 6 (2026-10-28: a November faculty recital
-- showed Saint John's Christmas choir). Before, every November event at a place with one took it.

create or replace function private.christmas_fit(p_title text, p_date date)
returns boolean
language sql
immutable
as $$
  select (extract(month from p_date) = 11
          and lower(coalesce(p_title, '')) ~ 'christmas|holiday|advent|santa|twinkle|carol|nativity|noel|black friday|days of giving|gift|wreath')
      or extract(month from p_date) = 12 or (extract(month from p_date) = 1 and extract(day from p_date) <= 6)
$$;

-- public.event_picture, as 20261028162731_event_photos_gender.sql made it, with the holiday test.
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
             or ('christmas' = any (s.seasons) and private.christmas_fit(e.title, e.event_date)))
        and not ('girls' = any (s.subjects) and coalesce(private.event_gender(e.title, e.sport), '') = 'boys')
        and not ('boys' = any (s.subjects) and coalesce(private.event_gender(e.title, e.sport), '') = 'girls')
      order by s.seasons = '{}', md5(e.id::text || s.id::text)
      limit 1),
    (select public.place_picture(e.place_entry_id) from public.club_events e where e.id = p_event))
$$;
