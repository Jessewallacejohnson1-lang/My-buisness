-- Place photos we keep ourselves (Jesse, 2026-10-16), so a venue picture no longer costs a
-- Google Places lookup on every phone, every time the app opens. One to two real photos per
-- place, keyed by the registry's permanent entry id (sources/<town>-mn.md), so a place that
-- isn't in public.places yet, a campus building or a school, can have one too.
--
-- The file itself lives in the public `places` bucket at <town>/<entry_id>/photo-<hash>.webp.
-- source_url is the page it came from: the app credits it ("Photo: krewemn.com") and the
-- monthly refresh checks whether it is still there.
--
-- A refresh never swaps a photo on its own (Jesse, 2026-10-16): it adds a 'proposed' row, and
-- only his yes turns it 'live' and the old one 'retired'.

create table if not exists public.place_photos (
  id          bigint generated always as identity primary key,
  entry_id    text not null,
  town        text not null default 'st-joseph',
  url         text not null,
  source_url  text not null,
  position    smallint not null default 0,      -- 0 is the cover
  status      text not null default 'live' check (status in ('live', 'proposed', 'retired')),
  added_at    timestamptz not null default now()
);

-- One live and one proposed photo per slot; retired ones pile up as history.
create unique index if not exists place_photos_one_per_slot
  on public.place_photos (entry_id, status, position) where status <> 'retired';

alter table public.place_photos enable row level security;

-- The app reads live photos; only the service role writes (no insert/update policies).
drop policy if exists "read live place photos" on public.place_photos;
create policy "read live place photos" on public.place_photos
  for select using (status = 'live');
