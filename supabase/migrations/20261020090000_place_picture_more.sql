-- A place's other photos come with its picture, so a Town card swipes through them and its Event page shows
-- the same ones (BP app docs/plans/event-card, ticket 02; Jesse, 2026-10-20). public.place_picture's photo
-- object gains `more`: the place's other live photos in position order, each with its credit, site and size;
-- `[]` when it has one. The cover is the lowest position, ties broken by id, and leaves `more` by its id.
-- As 20261019230000_place_photo_size.sql otherwise.

create or replace function public.place_picture(p_entry_id text)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object('url', p.url, 'kind', 'photo', 'credit', p.credit, 'site', p.source_url,
                               'w', p.width, 'h', p.height,
                               'more', coalesce((select jsonb_agg(jsonb_build_object('url', o.url, 'kind', 'photo',
                                                          'credit', o.credit, 'site', o.source_url,
                                                          'w', o.width, 'h', o.height)
                                                        order by o.position, o.id)
                                                   from public.place_photos o
                                                  where o.entry_id = p.entry_id and o.status = 'live'
                                                    and o.kind = 'photo' and o.id <> p.id), '[]'::jsonb))
       from public.place_photos p
      where p.entry_id = p_entry_id and p.status = 'live' and p.kind = 'photo'
      order by p.position, p.id limit 1),
    (select jsonb_build_object('url', p.url, 'kind', 'logo', 'hue', p.hue)
       from public.place_photos p
      where p.entry_id = p_entry_id and p.status = 'live' and p.kind = 'logo'
      order by p.position limit 1),
    (select jsonb_build_object('url', pl.search_logo->>'url', 'kind', 'logo',
              'hue', case when coalesce((pl.search_logo->>'chroma')::boolean, true)
                          then (pl.search_logo->>'hue')::numeric end)
       from public.places pl
      where pl.entry_id = p_entry_id and pl.search_logo->>'url' is not null
      order by pl.name limit 1))
$$;

grant execute on function public.place_picture(text) to anon, authenticated;
