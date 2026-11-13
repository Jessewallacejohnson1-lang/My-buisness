-- Search's Event calendar (BP app five-tabs 10): a year of the Town's public Events, one row per Event, as
-- Event cards, from the first of this month to the end of the 11th month after it. Public, as Jesse asked
-- ("only show public events no news no groups", 2026-11-13): no News, no posts, nothing posted in a Group,
-- nothing only followers or friends see. Unlike the Town feed, every date of a repeating Event is its own
-- row, and an Event shows months before its show-from day.
--
-- The rest is the Town feed's own reach for the caller (supabase/town_feed.sql, `real_events` and `shown`):
-- College, City meetings, Not interested, Mute, 18+ and middle school. Change one there, change it here.
create function public.get_town_calendar(p_now timestamptz default now())
returns table (card jsonb)
language sql
stable
security invoker
set search_path = public
as $$
  with town as (
    select (p_now at time zone 'America/Chicago')::date as today,
           date_trunc('month', (p_now at time zone 'America/Chicago')::date)::date as first_day
  ),
  me as (
    -- Under 18 from the caller's birthday; signed out or no birthday counts as grown.
    select coalesce(p.interests, '{}'::text[]) as interests,
           p.birthday is null or p.birthday <= (p_now at time zone 'America/Chicago')::date - interval '18 years'
             as adult
    from (select 1) one
    left join public.town_profiles p on p.user_id = auth.uid()
  ),
  muted as (
    select m.host from public.feed_mutes m where m.user_id = auth.uid()
  ),
  -- Not interested keeps out the Event and every date of its series.
  hidden as (
    select lower(btrim(e.title)) || '|' || coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') as series
    from private.my_not_interested() n
    join public.club_events e on e.id = n.item_id
  ),
  cities as (
    select lower(pg.source_name) as source from public.town_pages pg where pg.slug = 'city'
  ),
  my_pages as (
    select lower(pg.source_name) as source
    from public.town_follows f
    join public.town_pages pg on pg.id = f.target_id
    where f.follower_id = auth.uid() and f.target_type = 'page'
  ),
  my_boards as (
    select b.id
    from public.town_follows f
    join public.city_boards b on b.id = f.target_id
    where f.follower_id = auth.uid() and f.target_type = 'board'
  ),
  picked as (
    select e.id, e.event_date, e.title
    from public.club_events e
    cross join town
    cross join me
    cross join lateral (select coalesce(e.club_id::text, e.source_name, e.submitted_by::text, '') as host,
                               case when e.interests_tagged_at is not null then e.interests
                                    else array[e.category] end as tags,
                               exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
                                 or exists (select 1 from public.event_likes l where l.event_id = e.id and l.user_id = auth.uid())
                                 as mine) x
    where e.status = 'approved'
      and e.kind = 'event'
      and e.event_date is not null
      and (e.submitted_by is not null or e.source_name is not null)
      -- Public only: no Group's post, nothing for followers or friends alone.
      and e.club_id is null
      and not coalesce(e.followers_only, false)
      and not coalesce(e.friends_only, false)
      and e.cancelled_at is null
      and e.event_date >= town.first_day
      and e.event_date < (town.first_day + interval '12 months')::date
      -- Over is gone: an earlier day of this month keeps only what still runs.
      and (e.event_date >= town.today or e.end_at > p_now)
      -- For college students: only for those who picked College, or are Going or Hearted it.
      and (not ('college' = any(e.interests) and e.interests_tagged_at is not null)
           or 'college' = any(me.interests) or x.mine)
      -- A City meeting: only for those who follow the City or its board, picked Town meetings, or are Going
      -- or Hearted it.
      and (not (coalesce(e.draw = 1, false) and exists (select 1 from cities c where c.source = lower(e.source_name)))
           or ('town_meetings' = any(e.interests) and 'town_meetings' = any(me.interests))
           or exists (select 1 from my_pages p where p.source = lower(e.source_name))
           or exists (select 1 from my_boards b where b.id = public.meeting_board(e))
           or x.mine)
      -- Middle school sports and Knowledge Bowl: only for those who picked Middle school, or are Going or Hearted it.
      and (not ('middle_school' = any(x.tags) and e.interests_tagged_at is not null
                and ('watch_sports' = any(x.tags) or coalesce(e.what, e.title) ~* 'knowledge bowl'))
           or 'middle_school' = any(me.interests) or x.mine)
      and not exists (select 1 from muted m where m.host = x.host)
      and not exists (select 1 from muted m join public.places pl on pl.name = m.host
                      where pl.entry_id = any(e.collab_entry_ids))
      and not exists (select 1 from hidden h where h.series = lower(btrim(e.title)) || '|' || x.host)
      -- Under 18 never sees what its place keeps to 18+ or 21+, nor an age mark from 18 up.
      and (me.adult or not private.adults_only(e.place_entry_id, e.club_id, e.title || ' ' || coalesce(e.description, '')))
      and (me.adult or coalesce((regexp_match(e.ages, '^(?:Ages )?(\d+)(?:\+|–)'))[1]::int, 0) < 18)
  )
  -- The Event card, asked once for all of the rows.
  select ec.card
  from picked p
  join private.event_cards(array(select x.id from picked x)) ec on ec.id = p.id
  order by p.event_date, p.title, p.id
$$;

revoke execute on function public.get_town_calendar(timestamptz) from public;
grant execute on function public.get_town_calendar(timestamptz) to anon, authenticated;
