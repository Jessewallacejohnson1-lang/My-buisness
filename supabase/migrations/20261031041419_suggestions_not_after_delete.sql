-- Friend suggestions leave out anyone whose request you deleted (BP app docs/plans/town-feed,
-- ticket 28). `private.relation` reads a deleted request as nothing between you, so the sender came
-- back on the list of the person who said no. Same function as 20261022150000_people_you_may_know
-- (live body checked 2026-10-30), with that one exclusion added; grants stay as they were.

create or replace function public.get_people_you_may_know()
returns table (user_id uuid, display_name text, avatar_url text, since timestamptz,
               relation text, mutual_friends int, friends_since timestamptz, shared_group text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  return query
    with mine as (
      select case when f.a = me then f.b else f.a end as friend
      from private.friendships f
      where me in (f.a, f.b)
    ), via_friends as (
      -- A friend who blocked you, or is banned, isn't counted: "2 mutual friends" never points
      -- at someone you can't see.
      select case when f.a = m.friend then f.b else f.a end as person, count(*)::int as mutual
      from mine m
      join private.friendships f on m.friend in (f.a, f.b)
      where private.findable(m.friend)
      group by 1
    ), via_groups as (
      select theirs.user_id as person, min(c.name) as club
      from public.club_members mine_c
      join public.clubs c on c.id = mine_c.club_id and c.status = 'approved'
      join public.club_members theirs on theirs.club_id = mine_c.club_id
      where mine_c.user_id = me
      group by 1
    ), followers as (
      select t.follower_id as person
      from public.town_follows t
      where t.target_type = 'profile' and t.target_id = me
    ), candidates as (
      select c.person, sum(c.mutual)::int as mutual, max(c.club) as club, bool_or(c.follows) as follows
      from (select v.person, v.mutual, null::text as club, false as follows from via_friends v
            union all
            select g.person, 0, g.club, false from via_groups g
            union all
            select fo.person, 0, null, true from followers fo) c
      group by c.person
    ), kept as (
      select c.person, c.mutual, c.club,
             row_number() over (order by c.mutual desc, (c.club is not null) desc, c.follows desc,
                                         lower(btrim(p.display_name)), c.person) as n
      from candidates c
      join public.town_profiles p on p.user_id = c.person and p.suggest_me
      where c.person <> me
        and private.findable(c.person)
        and private.relation(me, c.person) = 'none'
        and not exists (select 1 from private.suggestion_hides h
                        where h.user_id = me and h.hidden_id = c.person)
        -- A request you deleted still waits on their side (it never expires, friends spec), so
        -- they aren't suggested back to you; one they took back no longer counts.
        and not exists (select 1 from private.friend_requests r
                        where r.from_id = c.person and r.to_id = me and r.cancelled_at is null)
      order by n
      limit 20
    )
    select r.user_id, r.display_name, r.avatar_url, r.since, r.relation, k.mutual, r.friends_since, k.club
    from kept k
    cross join lateral private.neighbor_row(me, k.person) r
    order by k.n;
end;
$$;
