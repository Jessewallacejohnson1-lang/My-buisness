-- Every place's logo made in the cloud, in the new look, with no Mac step (BP app logo-cutouts 06; Jesse, 2026-11-20:
-- "automate this ... for literally every business ... in the cloud and not on my computer").
--
-- The morning job (as `watch`, 20261031040831_watch_key.sql) runs sources/scripts/place_logos.py: a place with a
-- website and no logo gets the file its two helpers both pick, made by the logo module, and on Sundays a Search logo an
-- older logo module made is made again from its file. So the job may now set a place's two logo columns, mark the day
-- it looked, and keep each logo's file and notes in the private place-sources bucket, where BP app's logo publish
-- already keeps them, and read them back. A place's name and everything else stay the migrations' and Jesse's.

-- The day the morning last looked for a place's logo: it looks again after 30 days (place_logos.LOOK_AGAIN).
alter table public.places add column if not exists logo_looked date;

-- A wrong logo comes down with a migration that empties search_logo and logo_url and adds its file's address here, so
-- the morning never picks it again: the report's take-down line writes both. Only a migration writes it.
alter table public.places add column if not exists logo_refused text[] not null default '{}';

grant update (search_logo, logo_url, logo_looked) on public.places to watch;

create policy "watch keeps logo sources" on storage.objects for insert to watch
  with check (bucket_id = 'place-sources');
create policy "watch reads logo sources" on storage.objects for select to watch
  using (bucket_id = 'place-sources');

-- Every Search logo BP app's publish made, in its place's own folder, is what today's logo module makes: made again
-- from its file in place-sources on 2026-11-20, each came out byte for byte the live logo and pin. So each takes this
-- module's version (sources/scripts/logo.py's hash, logo.VERSION), and the Sunday check leaves it until logo.py
-- changes. 3D logos, and a logo set another way (from another folder: Saint Benedict's Monastery's), take none.
update public.places
set search_logo = search_logo || jsonb_build_object('made', 'd958de38')
where search_logo is not null
  and closed_at is null and not coalesce((search_logo->>'d3')::boolean, false)
  and search_logo->>'url' like '%/object/public/places/st-joseph/' || coalesce(place_id, entry_id) || '/%';
