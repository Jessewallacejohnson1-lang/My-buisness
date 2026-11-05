-- Every friend Going comes with an Event, not the first three (BP app five-tabs 08). A bubble says "+3" and a card
-- "Sarah and 4 friends are going", and with only three names five friends read as "Sarah and 2 friends". Newest first
-- still; the app draws as many faces as it has room for.

create or replace function private.friends_going(p_events uuid[])
returns table (event_id uuid, friends int, people jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  with mine as (
    select case when f.a = auth.uid() then f.b else f.a end as friend
    from private.friendships f
    where auth.uid() in (f.a, f.b)
  ),
  going as (
    select r.event_id, r.user_id, r.created_at,
           -- The first word that starts with a letter: "🎉 Anna Lee" is Anna.
           (regexp_match(p.display_name, '[[:alpha:]][^[:space:]]*'))[1] as name,
           -- Only a photo in their own folder of our avatars bucket (friends ticket 02).
           case when p.avatar_url like 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/avatars/'
                                       || p.user_id::text || '/%' then p.avatar_url end as photo
    from mine m
    join public.event_rsvps r on r.user_id = m.friend and r.event_id = any (p_events)
    join public.club_events e on e.id = r.event_id
    join public.town_profiles p on p.user_id = m.friend
    where p.plans_to_friends
      and private.findable(m.friend)
      and coalesce(e.end_at, (e.event_date + 1)::timestamp at time zone 'America/Chicago') > now()
  ),
  ranked as (
    select g.*, row_number() over (partition by g.event_id order by g.created_at desc, g.user_id) as n
    from going g
  )
  select r.event_id, count(*)::int,
         jsonb_agg(jsonb_build_object('name', r.name, 'photo', r.photo) order by r.n)
  from ranked r
  group by r.event_id
$$;
