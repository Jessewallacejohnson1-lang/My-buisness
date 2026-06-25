-- Event photos. Run once in the Supabase SQL editor.
-- Adds an optional image to events + a public storage bucket for the uploads.
-- Events still post fine without this — addEvent() retries without the image,
-- and uploadEventImage() returns null if the bucket is missing.

-- 1. Column on the events table
alter table public.club_events
  add column if not exists image_url text;

-- 2. Public bucket for the uploaded photos
insert into storage.buckets (id, name, public)
values ('event-images', 'event-images', true)
on conflict (id) do nothing;

-- 3. Anyone can view; signed-in neighbors can upload
drop policy if exists "event images public read" on storage.objects;
create policy "event images public read"
  on storage.objects for select
  using (bucket_id = 'event-images');

drop policy if exists "event images authenticated upload" on storage.objects;
create policy "event images authenticated upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'event-images');
