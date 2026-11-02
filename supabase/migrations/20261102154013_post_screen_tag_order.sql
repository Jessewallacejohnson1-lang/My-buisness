-- Tagged friends keep the order they were tagged in (town-feed 29, BP app references/post-screen): the card
-- names the first ("Jesse is with Sam and 2 others"), and claim_submit had sorted them by id (the review,
-- 2026-11-02). claim_submit from 20261102005550_post_screen_posts.sql, line for line but for that.
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
        tagged = (select array_agg(x.id order by x.n)
                  from (select u.id, min(u.n) as n from unnest(e.tagged) with ordinality as u(id, n) group by u.id) x
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
