-- How many people follow a profile, and who follows you (BP app backlog 34, references/followers-count):
-- the counts under a Profile's name become friends, following, followers (Jesse, 2026-11-17), and on
-- your own Profile the followers number opens the list of people following you. Nobody else's list
-- is ever read: my_followers answers only for the reader.
--
-- Both count only people the reader may find (not blocked either way, a real named account), as the
-- friends and following counts beside them do, so the number and the list agree.
--
-- The return type changes, so get_profile is dropped and made again: 20261114174015_profile_following.sql's
-- body, with `followers` added.
drop function public.get_profile(uuid);

-- One profile's page beyond its name and photo: bio, cover, how many friends (counted as the
-- Friends list counts: only people you may find, and you), the groups they're in, for a friend who
-- shows their plans the Events not over yet that you're both Going to, soonest three, how many
-- they follow, and how many follow them. Your own row too, with no Events (You has them). Nothing for anyone you may not find.
create function public.get_profile(p_user uuid)
returns table (bio text, cover_url text, friends int, group_ids uuid[], both_going uuid[], following int, followers int)
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
           else '{}'::uuid[] end,
           -- my_follows' rows for p_user, as the reader may see them.
           (select count(*)::int
            from public.town_follows t
            where t.follower_id = p_user
              and case t.target_type
                    when 'profile' then exists (select 1 from public.town_profiles x where x.user_id = t.target_id)
                                        and (t.target_id = me or private.findable(t.target_id))
                    when 'place' then exists (select 1 from public.places pl where pl.id = t.target_id)
                    when 'team' then exists (select 1 from public.teams tm where tm.uuid = t.target_id)
                    when 'page' then exists (select 1 from public.town_pages pg where pg.id = t.target_id)
                    when 'board' then exists (select 1 from public.city_boards b where b.id = t.target_id)
                    else false
                  end),
           -- People following p_user, counted as my_followers lists them: only people the reader may
           -- find, the reader included.
           (select count(*)::int
            from public.town_follows t
            join public.town_profiles x on x.user_id = t.follower_id
            where t.target_type = 'profile' and t.target_id = p_user
              and (t.follower_id = me or private.findable(t.follower_id)))
    from public.town_profiles p
    where p.user_id = p_user;
end;
$$;

revoke execute on function public.get_profile(uuid) from public, anon;
grant execute on function public.get_profile(uuid) to authenticated;

-- The people following you, newest first, as search answers a neighbour (name, photo, how you stand,
-- mutual friends). Yours only: there is no parameter for anyone else's.
create function public.my_followers()
returns table (user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int, friends_since timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  return query
    select r.*
    from public.town_follows t
    cross join lateral private.neighbor_row(me, t.follower_id) r
    where t.target_type = 'profile' and t.target_id = me
      and t.follower_id <> me and private.findable(t.follower_id)
    order by t.created_at desc, t.follower_id;
end;
$$;

revoke execute on function public.my_followers() from public, anon;
grant execute on function public.my_followers() to authenticated;
