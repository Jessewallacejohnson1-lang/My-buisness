-- Each open Place's rating, kept where no one in the app can read it (BP app docs/plans/community-value, ticket 03;
-- Jesse, 2026-11-24). How a Place is rated is BP app's, which is private; no migration holds a rating.
--
--   private.place_ratings      one row each time a Place is rated, with both judges' levels and their proof.
--   private.place_levels       the newest for each open Place, so a Place that closes drops out at once.
--   private.place_love         how many different people followed a Place, or hearted, saved, shared, commented on or
--                              are Going to something of its, in the last 30 days. One person counts once, an account
--                              without a sign-in counts for nothing, and neither does who posted it. No Place has a
--                              linked Owner yet: whatever links one must be left out here.
--   public.place_facts         what the app knows about each open Place, for the judges. No rating in it.
--   public.place_ratings_now   each open Place's newest rating from before today.
--   public.save_place_ratings  saves a round; a Place rated twice in one Town day keeps the second.
--
-- Only the cloud routines (watch) and the service key may call the three public functions.
--
-- Roll back: drop function public.save_place_ratings(jsonb), public.place_ratings_now(), public.place_facts(),
-- private.place_love(uuid); drop view private.place_levels; drop table private.place_ratings.

create table private.place_ratings (
  id bigint generated always as identity primary key,
  place_id uuid not null references public.places (id) on delete cascade,
  rated_at timestamptz not null default now(),
  a jsonb not null,
  b jsonb not null,
  judged smallint not null check (judged between 1 and 5),
  sure boolean not null,
  love int not null,
  level smallint not null check (level between 1 and 5),
  note text,
  check (btrim(coalesce(a ->> 'proof', '')) <> '' and btrim(coalesce(b ->> 'proof', '')) <> ''),
  check (sure or (judged between 2 and 4 and level between 2 and 4))
);
create index place_ratings_newest_idx on private.place_ratings (place_id, rated_at desc, id desc);
alter table private.place_ratings enable row level security;
revoke all on private.place_ratings from public, anon, authenticated, watch;

create view private.place_levels with (security_invoker = true) as
  select distinct on (r.place_id) r.place_id, r.level, r.judged, r.sure, r.love, r.rated_at
  from private.place_ratings r
  join public.places p on p.id = r.place_id and p.closed_at is null
  order by r.place_id, r.rated_at desc, r.id desc;
revoke all on private.place_levels from public, anon, authenticated, watch;

create function private.place_love(p_place uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  with place as (select p.id, p.entry_id from public.places p where p.id = p_place),
  since as (select now() - interval '30 days' as at),
  events as (select e.id, e.submitted_by from public.club_events e, place where e.place_entry_id = place.entry_id),
  news as (select b.id from public.board_items b, place where b.place_entry_id = place.entry_id),
  loved as (
    select f.follower_id as person from public.town_follows f, place, since
     where f.target_type = 'place' and f.target_id = place.id and f.created_at >= since.at
    union
    select l.user_id from public.event_likes l join events e on e.id = l.event_id, since
     where l.created_at >= since.at and l.user_id is distinct from e.submitted_by
    union
    select g.user_id from public.event_rsvps g join events e on e.id = g.event_id, since
     where g.created_at >= since.at and g.user_id is distinct from e.submitted_by
    union
    select s.user_id from public.event_saves s join events e on e.id = s.event_id, since
     where s.created_at >= since.at and s.user_id is distinct from e.submitted_by
    union
    select c.user_id from public.event_comments c join events e on e.id = c.event_id, since
     where c.created_at >= since.at and c.status = 'shown' and c.user_id is distinct from e.submitted_by
    union
    select a.user_id from public.feed_actions a join events e on e.id = a.item_id, since
     where a.action = 'share' and a.at >= since.at and a.user_id is distinct from e.submitted_by
    union
    select n.user_id from public.news_likes n join news on news.id = n.item_id, since
     where n.created_at >= since.at
  )
  select count(*)::int from loved join auth.users u on u.id = loved.person where not coalesce(u.is_anonymous, false);
$$;
revoke all on function private.place_love(uuid) from public, anon, authenticated, watch;

create function public.place_facts()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with today as (select (now() at time zone 'America/Chicago')::date as d),
  titles as (
    select e.place_entry_id, case when e.team_ids is not null then 'Games' else e.title end as title,
           count(*) as dates, max(coalesce(e.draw, 0)) as draw, bool_or(e.event_date >= today.d) as upcoming
    from public.club_events e, today
    where e.status = 'approved' and e.cancelled_at is null and e.event_date > today.d - 365
    group by 1, 2),
  events as (
    select place_entry_id, jsonb_agg(jsonb_build_object('title', title, 'dates', dates, 'draw', draw, 'upcoming', upcoming)
                                     order by draw desc, dates desc, title) as list
    from titles group by 1),
  news as (
    select place_entry_id, jsonb_agg(jsonb_build_object('day', created_at::date, 'title', title) order by created_at desc) as list
    from public.board_items where created_at > now() - interval '90 days' group by 1),
  follows as (
    select target_id, count(distinct follower_id) as n from public.town_follows where target_type = 'place' group by 1)
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'entry_id', p.entry_id, 'place_id', p.place_id, 'google_place_id', p.google_place_id, 'name', p.name,
    'address', p.address, 'family', p.family, 'kind', coalesce(p.category, p.primary_type), 'adults_only', p.adults_only,
    'about', p.about, 'links', p.links, 'events', coalesce(e.list, '[]'), 'news', coalesce(n.list, '[]'),
    'follows', coalesce(f.n, 0), 'love', private.place_love(p.id)) order by p.name), '[]')
  from public.places p
  left join events e on e.place_entry_id = p.entry_id
  left join news n on n.place_entry_id = p.entry_id
  left join follows f on f.target_id = p.id
  where p.closed_at is null;
$$;
revoke all on function public.place_facts() from public, anon, authenticated;
grant execute on function public.place_facts() to watch, service_role;

create function public.place_ratings_now()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with newest as (
    select distinct on (r.place_id) r.place_id, r.level, r.judged, r.sure, r.rated_at
    from private.place_ratings r
    join public.places p on p.id = r.place_id and p.closed_at is null
    where (r.rated_at at time zone 'America/Chicago')::date < (now() at time zone 'America/Chicago')::date
    order by r.place_id, r.rated_at desc, r.id desc)
  select coalesce(jsonb_object_agg(place_id, jsonb_build_object('level', level, 'judged', judged, 'sure', sure,
    'rated', (rated_at at time zone 'America/Chicago')::date)), '{}') from newest;
$$;
revoke all on function public.place_ratings_now() from public, anon, authenticated;
grant execute on function public.place_ratings_now() to watch, service_role;

create function public.save_place_ratings(p_ratings jsonb)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  saved int;
begin
  delete from private.place_ratings r
   using jsonb_array_elements(p_ratings) x
   where r.place_id = (x ->> 'id')::uuid
     and (r.rated_at at time zone 'America/Chicago')::date = (now() at time zone 'America/Chicago')::date;
  insert into private.place_ratings (place_id, a, b, judged, sure, love, level, note)
  select p.id, x -> 'a', x -> 'b', (x ->> 'judged')::smallint, (x ->> 'sure')::boolean, (x ->> 'love')::int,
         (x ->> 'level')::smallint, x ->> 'note'
  from jsonb_array_elements(p_ratings) x
  join public.places p on p.id = (x ->> 'id')::uuid and p.closed_at is null;
  get diagnostics saved = row_count;
  return saved;
end
$$;
revoke all on function public.save_place_ratings(jsonb) from public, anon, authenticated;
grant execute on function public.save_place_ratings(jsonb) to watch, service_role;
