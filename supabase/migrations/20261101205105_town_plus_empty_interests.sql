-- New event's claim (20261101203718_town_plus_posting.sql), with one fix: a new Event's interests
-- default to an empty list, not null, so "no interests set" is an empty list or none. Live, the
-- first proof Event was never claimed for it (BP app references/town-plus, 2026-11-01).

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
