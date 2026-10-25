-- Profile remade (BP app references/profile-remake, taste/you.md 2026-10-25): a bio and a cover
-- photo on every profile, and one read for the page's counts and lists.
--
-- A friend count shows on a profile again ("24 friends · 4 groups"), which ticket 03 of the
-- friends plan had left out (20261013150000_friend_requests.sql: "no friend count anywhere"):
-- Jesse approved the counts line on 2026-10-25. Going stays per Event (friends spec, 2026-10-13:
-- "you can't track people's whole agenda"): a friend's profile lists only the Events you are
-- both Going to, and a stranger's none.

-- Nextdoor's 150-letter bio; a cover photo in the same avatars bucket, under the owner's folder.
alter table public.town_profiles add column if not exists bio text
  check (bio is null or char_length(bio) <= 150);
alter table public.town_profiles add column if not exists cover_url text;

-- Anyone sees a profile's bio and cover, so only a real account sets them, as with the photo
-- (20261009230000_anonymous_profile_photos.sql). A name stays everyone's to set.
create policy "real accounts set bio and cover" on public.town_profiles
  as restrictive for insert to authenticated
  with check ((bio is null and cover_url is null) or (select public.is_real_account()));

create policy "real accounts change bio and cover" on public.town_profiles
  as restrictive for update to authenticated
  using (true)
  with check ((bio is null and cover_url is null) or (select public.is_real_account()));

-- One profile's page beyond its name and photo: bio, cover, how many friends (counted as the
-- Friends list counts: only people you may find, and you), the groups they're in, and for a
-- friend who shows their plans, the Events not over yet that you're both Going to, soonest
-- three. Your own row too, with no Events (You has them). Nothing for anyone you may not find.
create function public.get_profile(p_user uuid)
returns table (bio text, cover_url text, friends int, group_ids uuid[], both_going uuid[])
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  if p_user is distinct from me and not private.findable(p_user) then
    return;
  end if;
  return query
    select nullif(btrim(p.bio), ''),
           -- Only a picture in their own folder of our avatars bucket, as neighbor_row's photo.
           case when p.cover_url like 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/'
                                     || p.user_id::text || '/%' then p.cover_url end,
           (select count(*)::int
            from private.friendships f
            cross join lateral (select case when f.a = p_user then f.b else f.a end as other) o
            where p_user in (f.a, f.b) and (o.other = me or private.findable(o.other))),
           array(select m.club_id from public.club_members m where m.user_id = p_user order by m.created_at),
           case when p_user <> me and p.plans_to_friends and private.relation(me, p_user) = 'friends' then
             array(select e.id
                   from public.club_events e
                   join public.event_rsvps a on a.event_id = e.id and a.user_id = me
                   join public.event_rsvps b on b.event_id = e.id and b.user_id = p_user
                   where e.status = 'approved' and e.kind = 'event' and e.cancelled_at is null
                     and coalesce(e.end_at, (e.event_date + 1)::timestamp at time zone 'America/Chicago') > now()
                   order by e.event_date, e.start_time, e.id
                   limit 3)
           else '{}'::uuid[] end
    from public.town_profiles p
    where p.user_id = p_user;
end;
$$;

revoke execute on function public.get_profile(uuid) from public, anon;
grant execute on function public.get_profile(uuid) to authenticated;
