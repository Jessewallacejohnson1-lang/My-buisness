-- Event of the day leaves out standing things that repeat (weekly trivia), the morning's standouts
-- included: "Standing things never go here" (BP app daily-tab 14). 20261020130000_event_of_the_day.sql
-- left them out of the fallback only. Line for line that file's function but for the recurrence
-- filter, moved from the fallback into `feed`, and the start-time note.

create or replace function public.get_event_of_the_day(p_now timestamptz default now())
returns table (
  id uuid,
  title text,
  event_date date,
  start_time text,
  location text,
  image_url text,
  category text,
  club_name text,
  source_name text,
  end_at timestamptz,
  all_day boolean,
  created_at timestamptz,
  going_count int,
  rsvpd boolean,
  recurrence text,
  leaves_at timestamptz,
  reason text,
  reason_name text,
  score jsonb,
  heart_count int,
  hearted boolean,
  saved boolean,
  cancelled boolean,
  friends_going jsonb,
  place_picture jsonb,
  description text,
  club_id uuid,
  in_club boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  with town as (
    select 'st-joseph-mn'::text as town, (p_now at time zone 'America/Chicago')::date as today
  ),
  -- Today's Events as the caller's Town feed has them, in its order: on now or still to come
  -- (the feed lets one go at its leaves_at), not called off.
  feed as (
    select f.*,
           -- Its interests as the feed matches them: the tagger's, else its writer's one.
           case when e.interests_tagged_at is not null then e.interests else array[e.category] end as tags,
           coalesce(e.draw, 2) as draw,
           -- The hour it starts, read as the feed reads "7 PM", "7:30 pm", "noon", "19:00": the
           -- same patterns as get_town_feed's start_minutes (20261019180000_group_join_on_cards.sql);
           -- change both together.
           case
             when f.all_day then null
             when lower(btrim(f.start_time)) = 'noon' then 12
             when m12 is not null and m12[1]::int between 1 and 12 then m12[1]::int % 12 + case when m12[3] = 'p' then 12 else 0 end
             when m24 is not null and m24[1]::int < 24 then m24[1]::int
           end as hour
    from public.get_town_feed(p_now) with ordinality f
    join public.club_events e on e.id = f.id
    cross join town
    cross join lateral (select
      regexp_match(lower(btrim(f.start_time)), '^(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?$') as m12,
      regexp_match(btrim(f.start_time), '^(\d{1,2}):(\d{2})(?::\d{2})?$') as m24) t
    where f.event_date = town.today and not f.cancelled
      -- Standing things that repeat (weekly trivia) never go here, picked or not (daily-tab 14).
      and f.recurrence is null
  ),
  parts as (
    -- Morning before noon (all day or untimed counts as morning), afternoon to 5 PM, evening.
    select f.*, case when f.hour is null or f.hour < 12 then 1 when f.hour < 17 then 2 else 3 end as part
    from feed f
  ),
  me as (
    select coalesce((select p.interests from public.town_profiles p where p.user_id = auth.uid()),
                    '{}'::text[]) as interests
  ),
  written as (
    select s.event_id, s.rank from public.daily_standouts s, town
    where s.town = town.town and s.day = town.today
  ),
  standouts as (
    select p.*, w.rank,
           cardinality(array(select unnest(p.tags) intersect select unnest(me.interests))) as fit
    from parts p
    join written w on w.event_id = p.id
    cross join me
  ),
  -- Each part's standout sharing the most of your interests, else its top-ranked one. Going
  -- doesn't move it: the pick reads interests and rank only.
  mine as (
    select distinct on (s.part) s.* from standouts s order by s.part, s.fit desc, s.rank
  ),
  -- The job wrote nothing today: the feed's top Event, never routine business (draw 1). One
  -- you're Going to comes first, since the feed lowers an Event you acted on and Going would
  -- otherwise hand its spot to the next.
  fallback as (
    select p.* from parts p
    where p.draw > 1 and not exists (select 1 from written)
    order by p.rsvpd desc, p.ordinality
    limit 1
  ),
  picked as (
    select m.id, m.part, m.ordinality from mine m
    union all
    select f.id, f.part, f.ordinality from fallback f
  )
  select f.id, f.title, f.event_date, f.start_time, f.location, f.image_url, f.category, f.club_name,
         f.source_name, f.end_at, f.all_day, f.created_at, f.going_count, f.rsvpd, f.recurrence,
         f.leaves_at, f.reason, f.reason_name, f.score, f.heart_count, f.hearted, f.saved, f.cancelled,
         f.friends_going, f.place_picture, f.description, f.club_id, f.in_club
  from picked k
  join feed f on f.id = k.id
  order by k.part, k.ordinality;
$$;

grant execute on function public.get_event_of_the_day(timestamptz) to anon, authenticated;
