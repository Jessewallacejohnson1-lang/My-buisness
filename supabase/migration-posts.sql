-- migration-posts.sql — multi-kind posts on club_events + photo storage.
-- Run AFTER migration-community.sql and migration-quests.sql.

-- 1. Kind + photo + kind-specific columns on the reused posts table.
alter table public.club_events
  add column if not exists kind       text not null default 'event',
  add column if not exists image_url  text,
  add column if not exists cadence    text,   -- Club: e.g. "Thursdays 6pm"
  add column if not exists length     text,   -- Trail: e.g. "2.4 mi"
  add column if not exists difficulty text;   -- Trail: e.g. "Easy"

-- Constrain kind to the four supported values.
alter table public.club_events
  drop constraint if exists club_events_kind_check;
alter table public.club_events
  add constraint club_events_kind_check
  check (kind in ('event', 'club', 'trail', 'notice'));

-- 2. Only Events require a date/time; other kinds are undated.
alter table public.club_events alter column event_date drop not null;
alter table public.club_events alter column start_time drop not null;

-- 3. Photo storage: public bucket, signed-in users upload under their own uid.
insert into storage.buckets (id, name, public)
values ('post-images', 'post-images', true)
on conflict (id) do nothing;

drop policy if exists "post-images public read" on storage.objects;
create policy "post-images public read" on storage.objects
  for select using (bucket_id = 'post-images');

drop policy if exists "post-images owner insert" on storage.objects;
create policy "post-images owner insert" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
