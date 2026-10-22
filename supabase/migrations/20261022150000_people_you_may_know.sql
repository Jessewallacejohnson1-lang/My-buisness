-- People you may know (BP app docs/plans/daily-tab, ticket 22; rules from town-feed ticket 15).
--
-- Who is on your list, strongest first: people your friends are friends with (the more you
-- share, the higher), people in an approved group you're in, people who follow you. Phone
-- contacts come with friends ticket 06. Never a Going, a save, a Heart or a view.
--
-- Never on it: you, your friends, anyone you asked or who asked you, anyone blocked either way
-- (`private.findable`), anyone you hid with the X, and anyone who turned off "Suggest me to people
-- I may know". The reason line only says what both could already see: the friends you share
-- (counted only among friends you may find), or a group that's approved. Nobody is ever told.

-- On by default (town-feed 15). Each neighbour writes their own row, as `plans_to_friends`.
alter table public.town_profiles add column if not exists suggest_me boolean not null default true;

-- The X: that person never comes back on your list. They're never told.
create table private.suggestion_hides (
  user_id uuid not null references auth.users (id) on delete cascade,
  hidden_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, hidden_id),
  check (user_id <> hidden_id)
);
revoke all on private.suggestion_hides from public, anon, authenticated;

-- At most 20, strongest first. The candidates are counted and cut to 20 before each is made into
-- a row, as `search_neighbors` does, so the work stays small in a big Town.
create function public.get_people_you_may_know()
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
      order by n
      limit 20
    )
    select r.user_id, r.display_name, r.avatar_url, r.since, r.relation, k.mutual, r.friends_since, k.club
    from kept k
    cross join lateral private.neighbor_row(me, k.person) r
    order by k.n;
end;
$$;

-- The X. Hiding twice is fine.
create function public.hide_suggestion(p_user uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  if p_user is null or p_user = me then
    raise exception 'nobody to hide' using errcode = '22023';
  end if;
  insert into private.suggestion_hides (user_id, hidden_id) values (me, p_user)
  on conflict do nothing;
end;
$$;

revoke execute on function public.get_people_you_may_know(), public.hide_suggestion(uuid) from public, anon;
grant execute on function public.get_people_you_may_know(), public.hide_suggestion(uuid) to authenticated;
