-- A search_logo the app can't read would fail the whole places list (the map and Search decode
-- every row at once), so the database refuses one: null, or an object with a text url, a
-- numeric hue and a boolean chroma.
alter table public.places add constraint places_search_logo_shape check (
  search_logo is null or (
    jsonb_typeof(search_logo) = 'object'
    and jsonb_typeof(search_logo -> 'url') = 'string'
    and jsonb_typeof(search_logo -> 'hue') = 'number'
    and jsonb_typeof(search_logo -> 'chroma') = 'boolean'
  )
);

-- Only logo3d.py publish writes the places bucket, as the service role, which skips policies:
-- the admin write policies have no caller.
drop policy if exists "places admin insert" on storage.objects;
drop policy if exists "places admin update" on storage.objects;
drop policy if exists "places admin delete" on storage.objects;

-- The 256 px favicon bucket is retired (its files are deleted through the Storage API, which
-- also removes the bucket); its policies go with it.
drop policy if exists "place-logos admin delete" on storage.objects;
drop policy if exists "place-logos admin insert" on storage.objects;
drop policy if exists "place-logos admin update" on storage.objects;
drop policy if exists "place-logos public read" on storage.objects;
