-- The order of Search's places and of the places at the end of the Town feed is saved by the cloud's job, and places
-- of one turn change places with each other (BP app docs/plans/community-value, ticket 05; Jesse, 2026-11-24: "rotate
-- the popular ones randomly . and on search do the same but for the ones that recetly posted"). Why a place stands
-- where it does is not here, and nothing here is read by the app but the order it makes.
--
--   private.place_lines        each place's spot, and its turn on Search (`wall`) and at the feed's end (`feed`). Places
--                              of one turn trade places; a null turn keeps its spot, after every turn.
--   public.save_place_lines    the whole list, saved by the cloud's job (watch) or the service key; deals the wall.
--   private.deal_places        writes each place's search_logo.rank: by turn, what put out an Event or News in the last
--                              7 days first, in a new order each Town day; then the rest by spot.
--   public.get_town_more       20261101190237's, but: the 21 kinds left out are back in, a closed place is out, and
--                              round 0 goes by turn, shuffled at each read, then by spot.
--
-- Roll back: select cron.unschedule('deal-places'); drop function public.save_place_lines(jsonb), private.deal_places(timestamptz);
-- drop table private.place_lines; create get_town_more again from 20261101190237_town_more_repeats_from_the_list.sql.

create table private.place_lines (
  place_id uuid primary key references public.places (id) on delete cascade,
  spot int not null,
  wall smallint,
  feed smallint
);
alter table private.place_lines enable row level security;
revoke all on private.place_lines from public, anon, authenticated, watch;

create function private.deal_places(p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  dealt int;
begin
  with day as (select (p_now at time zone 'America/Chicago')::date::text as d),
  lined as (
    select p.id, l.wall, l.spot, p.search_logo,
           l.wall is not null and (
             exists (select 1 from public.club_events e where e.place_entry_id = p.entry_id and e.status = 'approved'
                       and e.cancelled_at is null and e.created_at > p_now - interval '7 days' and e.created_at <= p_now)
             or exists (select 1 from public.board_items b where b.place_entry_id = p.entry_id and b.status = 'published'
                       and b.published_at > p_now - interval '7 days' and b.published_at <= p_now)) as fresh
    from public.places p left join private.place_lines l on l.place_id = p.id
    where p.closed_at is null and p.search_logo->>'url' is not null
  ),
  ranked as (
    select x.id, row_number() over (order by x.wall nulls last, not x.fresh,
             case when x.fresh then md5(day.d || x.id::text) end, x.spot nulls last, x.id) - 1 as n
    from lined x, day
  )
  update public.places p set search_logo = p.search_logo || jsonb_build_object('rank', r.n)
  from ranked r
  where p.id = r.id and (p.search_logo->>'rank') is distinct from r.n::text;
  get diagnostics dealt = row_count;
  return dealt;
end
$$;
revoke all on function private.deal_places(timestamptz) from public, anon, authenticated, watch;

create function public.save_place_lines(p_lines jsonb)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  saved int;
begin
  if jsonb_array_length(p_lines) < 100 then
    raise exception 'a list of % places is not the whole Town', jsonb_array_length(p_lines);
  end if;
  delete from private.place_lines where true;  -- Supabase refuses a delete with no where from the API
  insert into private.place_lines (place_id, spot, wall, feed)
  select p.id, (x ->> 'spot')::int, (x ->> 'wall')::smallint, (x ->> 'feed')::smallint
  from jsonb_array_elements(p_lines) x
  join public.places p on p.id = (x ->> 'id')::uuid and p.closed_at is null;
  get diagnostics saved = row_count;
  perform private.deal_places();
  return saved;
end
$$;
revoke all on function public.save_place_lines(jsonb) from public, anon, authenticated;
grant execute on function public.save_place_lines(jsonb) to watch, service_role;

create or replace function public.get_town_more(p_round int default 0, p_opened uuid[] default '{}',
                                                p_shown uuid[] default '{}', p_now timestamptz default now())
returns table (kind text, id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select coalesce(auth.uid()::text, '') as uid
  ),
  to_try as (
    select p.id, l.feed, l.spot,
           exists (select 1 from public.town_follows f
                   where f.follower_id = auth.uid() and f.target_type = 'place' and f.target_id = p.id) as mine,
           (select count(*) from public.town_follows f where f.target_type = 'place' and f.target_id = p.id) as follows,
           p.id = any(coalesce(p_opened, '{}')) as opened
    from public.places p left join private.place_lines l on l.place_id = p.id
    where p.search_logo->>'url' is not null and p.closed_at is null
      and not exists (select 1 from public.feed_mutes m where m.user_id = auth.uid() and m.host = p.name)
  ),
  placed as (
    select 'place'::text as kind, p.id,
           row_number() over (order by
             case when p_round = 0 then not p.mine else p.opened end,
             case when p_round = 0 then p.feed end nulls last,
             case when p_round = 0 and p.feed is not null then md5(p_now::text || me.uid || p.id::text) end,
             case when p_round = 0 then p.spot end nulls last,
             case when p_round = 0 then -p.follows end,
             md5(p_round::text || me.uid || p.id::text)) as n
    from to_try p, me
  ),
  -- Repeats: in a later round only, as many as there are groups of 3 places, and only of what the phone's
  -- list shows (p_shown), so each one can be drawn.
  recent as (
    select e.id from public.club_events e
    where p_round > 0 and e.id = any(coalesce(p_shown, '{}'))
      and e.status = 'approved' and e.kind = 'event' and e.cancelled_at is null
      and e.created_at > p_now - interval '7 days'
    union all
    select b.id from public.board_items b
    where p_round > 0 and b.id = any(coalesce(p_shown, '{}')) and b.status = 'published'
      and b.published_at > p_now - interval '7 days' and b.published_at <= p_now
  ),
  again as (
    select 'again'::text as kind, r.id, row_number() over (order by md5(p_round::text || r.id::text)) as n
    from recent r
  )
  select x.kind, x.id from (
    -- Places fill three of every four spots, a repeat the fourth.
    select p.kind, p.id, (p.n - 1) / 3 * 4 + (p.n - 1) % 3 as spot from placed p
    union all
    select a.kind, a.id, (a.n - 1) * 4 + 3 from again a
    where a.n <= (select (count(*) + 2) / 3 from placed)
  ) x
  order by x.spot;
$$;

-- 4:30 AM Chicago in summer, 3:30 in winter, before the morning watch.
select cron.schedule('deal-places', '30 9 * * *', $$select private.deal_places()$$);
