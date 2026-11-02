-- Neighbours post again, not only Events (BP app references/post-screen, town-feed 29; Jesse, 2026-11-01:
-- draft 1, Facebook's New post, "I agree to all", then "yes to all and start" and "A yes" at Check-in 1).
-- The Town bar's + opens New post: a neighbour's own words, maybe one photo, a Place and friends they're
-- with, for the whole Town or only their Friends. It is a club_events row of kind 'post' and goes through
-- town-plus's instant check (claim_submit, moderate-post's submit path), its photo rule and its 10 a day.
-- Turning on Event in New post makes a plain Event as town-plus does; nothing changes for those.
-- Applied live only with Jesse's yes.

-- 1. The kind, who may see it, and who it's with.
alter table public.club_events drop constraint if exists club_events_kind_check;
alter table public.club_events add constraint club_events_kind_check
  check (kind in ('event', 'trail', 'post'));
alter table public.club_events add column if not exists friends_only boolean not null default false;
alter table public.club_events add column if not exists tagged uuid[];

-- 2. Friends only, kept in the read rule itself, so neither a plain read nor the Town feed's live
-- updates hand a Friends-only post to anyone but the poster and their friends.
create or replace function private.sees_post(p_poster uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_poster = auth.uid()
      or exists (select 1 from private.friendships f
                 where f.a = least(auth.uid(), p_poster) and f.b = greatest(auth.uid(), p_poster))
$$;
revoke execute on function private.sees_post(uuid) from public;
grant execute on function private.sees_post(uuid) to anon, authenticated;

alter policy "read events" on public.club_events to anon, authenticated
  using ((status = 'approved' and (not friends_only or private.sees_post(submitted_by)))
         or submitted_by = (select auth.uid()) or public.is_admin());

-- 3. The poster deletes their own post, live or not; its photo goes with it (their own folder only).
-- Hearts, saves and reports go with the row (their foreign keys cascade).
alter policy "delete events" on public.club_events
  using (public.is_admin() or (submitted_by = (select auth.uid()) and (status = 'pending' or kind = 'post')));
create policy "event images own folder delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'event-images' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- 4. The instant check's claim (town-plus's, line for line) now also takes a post: no day, time or end,
-- words or a photo, and the tagged ids it keeps are only the poster's friends (anyone else is dropped,
-- not refused, so an unfriend never leaves a post stuck). An Event stays the Town's: never Friends-only,
-- never tagged.
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
    update public.club_events e
    set checked_at = now(),
        tagged = (select array_agg(x.id order by x.id) from (select distinct u.id from unnest(e.tagged) as u(id)) x
                  where exists (select 1 from private.friendships f
                                where f.a = least(p_user, x.id) and f.b = greatest(p_user, x.id)))
    where e.id = p_event and e.submitted_by = p_user and e.status = 'pending' and e.checked_at is null
      and (
        (e.kind = 'event' and not e.friends_only and e.tagged is null)
        or (e.kind = 'post' and e.event_date is null and e.start_time is null and e.end_at is null
            and not e.all_day and (btrim(e.title) <> '' or e.image_url is not null)
            and char_length(e.title) <= 2000 and coalesce(cardinality(e.tagged), 0) <= 20)
      )
      and coalesce(e.category, 'other') = 'other'
      and (e.image_url is null or e.image_url ~ v_photo)
      and e.club_id is null and e.source_name is null and e.source_uid is null and e.source_url is null
      and e.place_entry_id is null and e.team_ids is null and e.activity_team is null
      and e.activity_name is null and e.sport is null and e.occasion is null and e.what is null
      and e.draw is null and e.shows_from is null and coalesce(cardinality(e.interests), 0) = 0 and e.interests_tagged_at is null
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
