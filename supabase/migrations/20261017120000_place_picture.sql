-- Every event's picture comes from the photos Block Party keeps itself, not from a Google
-- lookup on every phone each time the app opens (BP app docs/plans/place-photos, step 3;
-- Jesse, 2026-10-16, iOS MEMORY.md). public.place_picture(entry) picks one for the place an
-- event happens at (club_events.place_entry_id): its live photo with the lowest position,
-- else its live logo, else the logo Search shows for it (places.search_logo, the cut-out; never
-- the map pin's, a logo on a white square that looked like a blank card); null when there is
-- none. The three reads that build event cards (the Town
-- feed, your Going, your saves) send it as a new last column, `place_picture`
-- (20261017120100_town_feed_place_picture.sql, 20261017120200_my_going_place_picture.sql).
--
-- place_photos.hue: a logo's backdrop hue, as Search's (places.search_logo.hue); null for a
-- black, white or grey logo, which gets a nearly neutral backdrop.

alter table public.place_photos add column if not exists hue smallint;

create or replace function public.place_picture(p_entry_id text)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object('url', p.url, 'kind', 'photo', 'credit', p.credit, 'site', p.source_url)
       from public.place_photos p
      where p.entry_id = p_entry_id and p.status = 'live' and p.kind = 'photo'
      order by p.position limit 1),
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
