-- After the best's repeats come from the phone's own list (BP app docs/plans/town-feed, ticket 23). A later
-- round's repeats were any Event put out in the last 7 days, and on 2026-11-01 none of the 16 a round sent
-- were in the 169-card list a signed-out phone showed: most new Events wait past their show-from day. The
-- phone draws a repeat only from its list, so it now sends that list's ids (p_shown) and repeats come from
-- them. get_town_more is 20261101182035_after_the_best.sql's but for p_shown, so it is made again.

drop function if exists public.get_town_more(int, uuid[], timestamptz);

create function public.get_town_more(p_round int default 0, p_opened uuid[] default '{}',
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
    select p.id,
           exists (select 1 from public.town_follows f
                   where f.follower_id = auth.uid() and f.target_type = 'place' and f.target_id = p.id) as mine,
           (select count(*) from public.town_follows f where f.target_type = 'place' and f.target_id = p.id) as follows,
           p.id = any(coalesce(p_opened, '{}')) as opened
    from public.places p
    where p.search_logo->>'url' is not null
      and coalesce(p.primary_type, '') <> all (array[
        'accounting', 'insurance_agency', 'car_repair', 'moving_company', 'doctor', 'real_estate_agency',
        'chiropractor', 'pharmacy', 'general_contractor', 'bank', 'finance', 'dentist', 'veterinary_care',
        'post_office', 'point_of_interest', 'day_care_center', 'church', 'lodging', 'hardware_store',
        'grocery_store', 'liquor_store'])
      and not exists (select 1 from public.feed_mutes m where m.user_id = auth.uid() and m.host = p.name)
  ),
  placed as (
    select 'place'::text as kind, p.id,
           row_number() over (order by
             case when p_round = 0 then not p.mine else p.opened end,
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

revoke execute on function public.get_town_more(int, uuid[], uuid[], timestamptz) from public;
grant execute on function public.get_town_more(int, uuid[], uuid[], timestamptz) to anon, authenticated;
