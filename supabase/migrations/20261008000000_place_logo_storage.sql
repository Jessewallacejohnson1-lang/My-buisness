-- Each business's logo files live in one Storage folder per place, named by place_id:
-- places/<town>/<place_id>/logo-<hash>.webp (Search's cut-out or 3D render) and
-- pin-<hash>.png (the same logo on a white square, for map pins). A new version gets a new
-- file name; the row points at the current one and the old file is deleted. The working
-- files behind each logo (the business's original, every 3D try, the detail list) sit in
-- the private place-sources bucket under the same <town>/<place_id>/ folder. Both are
-- written by `logo3d.py publish` (BP app's logo-3d skill). Replaces the flat place-logos
-- bucket of 256 px favicons (Jesse, 2026-10-08).
insert into storage.buckets (id, name, public) values ('places', 'places', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('place-sources', 'place-sources', false) on conflict (id) do nothing;

create policy "places public read" on storage.objects
  for select to public
  using ((bucket_id = 'places'::text));

create policy "places admin insert" on storage.objects
  for insert to public
  with check (((bucket_id = 'places'::text) AND is_admin()));

create policy "places admin update" on storage.objects
  for update to public
  using (((bucket_id = 'places'::text) AND is_admin()));

create policy "places admin delete" on storage.objects
  for delete to public
  using (((bucket_id = 'places'::text) AND is_admin()));

-- place-sources: no policies, so only the service role reads or writes it.

alter table public.places add column if not exists search_logo jsonb;

comment on column public.places.search_logo is
  'Search''s logo for this place: {url, hue, chroma, d3, rank, wall}. url is the logo-<hash>.webp in the places bucket; hue and chroma set its backdrop; d3 marks a 3D render; rank is its place in the wall''s order; wall false keeps a logo another place shows off the wall. Null = no logo in Search. Written by logo3d.py publish.';
comment on column public.places.logo_url is
  'Public URL of the place''s map-pin logo (places bucket, <town>/<place_id>/pin-<hash>.png: the Search logo on a white square); null = glyph fallback. Written by logo3d.py publish.';
