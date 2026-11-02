-- Neighbours post Events again (BP app references/town-plus; Jesse, 2026-11-01: "i agree w all",
-- then "i agree to all yes"). The Town bar's + opens New event: the photo goes to the poster's own
-- folder of event-images, the Event goes in pending, and moderate-post's `submit` path runs the
-- instant check: approved, or rejected with its reason. Applied live only with Jesse's yes.

-- When the check claimed the Event, once: a retry or a second call never pays the model again.
alter table public.club_events add column if not exists checked_at timestamptz;
create index if not exists club_events_checked_by on public.club_events (submitted_by, checked_at)
  where checked_at is not null;

-- A no from the instant check is a decline with its own reason (report.sql's list, plus one).
alter table public.club_events drop constraint if exists club_events_review_reason_check;
alter table public.club_events add constraint club_events_review_reason_check
  check (review_reason is null or review_reason in
         ('not_event', 'wrong_when', 'wrong_place', 'wrong_title', 'other', 'reported', 'declined'));

-- The poster can change their pending Event only until the check claims it, so what the check
-- read is what goes live.
alter policy "moderate events" on public.club_events
  using (public.is_admin()
         or (submitted_by = (select auth.uid()) and status = 'pending' and checked_at is null))
  with check (public.is_admin()
              or (submitted_by = (select auth.uid()) and status = 'pending' and checked_at is null));

-- Photos: a real account (the restrictive "real accounts upload photos" rule still applies) puts
-- them in its own folder only, images only, 10 MB at most, as the avatars bucket allows.
create policy "event images own folder upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'event-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
update storage.buckets
set file_size_limit = 10485760,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
where id = 'event-images';

-- The instant check's claim: true once for a plain pending Event of the caller's, under 10 a day.
-- Plain means the poster set only what the check reads (name, place, words, photo) and the day
-- and time; every column that would make it look like a found Event, a Group's, a team's, a
-- business's or a bigger draw is empty, and the photo is the poster's own upload. The lock on the
-- caller makes two calls at once count one after the other. Only moderate-post calls it, with the
-- caller it has already checked.
create or replace function public.claim_submit(p_event uuid, p_user uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_photo text := '^https://lxdgwhvqjqmqliobwjpi\.supabase\.co/storage/v1/object/public/event-images/'
                  || p_user::text || '/[0-9a-f-]+\.jpg$';
  v_claimed boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('claim_submit:' || p_user::text, 0));
  if (select count(*) from public.club_events
      where submitted_by = p_user and checked_at > now() - interval '24 hours') >= 10 then
    return false;
  end if;
  with c as (
    update public.club_events e set checked_at = now()
    where e.id = p_event and e.submitted_by = p_user and e.status = 'pending' and e.checked_at is null
      and e.kind = 'event' and coalesce(e.category, 'other') = 'other'
      and (e.image_url is null or e.image_url ~ v_photo)
      and e.club_id is null and e.source_name is null and e.source_uid is null and e.source_url is null
      and e.place_entry_id is null and e.team_ids is null and e.activity_team is null
      and e.activity_name is null and e.sport is null and e.occasion is null and e.what is null
      and e.draw is null and e.shows_from is null and e.interests is null and e.interests_tagged_at is null
      and e.lat is null and e.lng is null and coalesce(e.followers_only, false) = false
      and e.cancelled_at is null and e.moved_at is null and e.moved_from is null
      and e.live_score is null and e.final_score is null and e.scoring_plays is null
      and e.review_reason is null and e.rechecked_at is null
    returning 1
  )
  select exists (select 1 from c) into v_claimed;
  return v_claimed;
end
$$;
revoke execute on function public.claim_submit(uuid, uuid) from public, anon, authenticated;
grant execute on function public.claim_submit(uuid, uuid) to service_role;
