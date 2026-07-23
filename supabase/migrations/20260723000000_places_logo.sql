-- Brand logos for map POIs.
--
-- `logo_url` holds the public URL of a curated square brand mark sourced from
-- the business's OWN website/socials (nominative use — standard map-app
-- practice). It is NEVER a Google Places photo: those may not be persisted
-- (ToS), and the curation pipeline (scripts/fetch_place_logos.py) only touches
-- Google for the transient websiteUri lookup. Null = the app falls back to the
-- category glyph, which is the designed end state for logo-less places.
--
-- Storage: logos live in the public `place-logos` bucket, one 256x256 PNG per
-- place row uuid. Reads are public (the map loads them anonymously); writes are
-- admin-gated as defense-in-depth — the offline pipeline uploads with the
-- service-role key, which bypasses RLS anyway.

alter table public.places add column if not exists logo_url text;

comment on column public.places.logo_url is
    'Public URL of the curated square brand logo in the place-logos bucket; null = glyph fallback.';

insert into storage.buckets (id, name, public)
values ('place-logos', 'place-logos', true)
on conflict (id) do nothing;

drop policy if exists "place-logos public read" on storage.objects;
create policy "place-logos public read" on storage.objects
    for select using (bucket_id = 'place-logos');

drop policy if exists "place-logos admin insert" on storage.objects;
create policy "place-logos admin insert" on storage.objects
    for insert with check (bucket_id = 'place-logos' and public.is_admin());

drop policy if exists "place-logos admin update" on storage.objects;
create policy "place-logos admin update" on storage.objects
    for update using (bucket_id = 'place-logos' and public.is_admin());

drop policy if exists "place-logos admin delete" on storage.objects;
create policy "place-logos admin delete" on storage.objects
    for delete using (bucket_id = 'place-logos' and public.is_admin());
