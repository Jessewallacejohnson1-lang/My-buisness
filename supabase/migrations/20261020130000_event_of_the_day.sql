-- Event of the day (BP app docs/plans/daily-tab, ticket 14). Each morning the morning job's
-- last step shortlists the Town's standout Events for the day (sources/models/standouts.md) into
-- daily_standouts, rank 1 the Town's top pick. get_event_of_the_day gives each person theirs: for
-- each part of the day with a standout (morning before noon, afternoon to 5 PM, evening after), the
-- one sharing the most of their interests, else that part's top-ranked one, so up to three (Jesse,
-- 2026-10-08, Town feed ticket 14). A day the job wrote nothing gets the Town feed's own top Event
-- of the day (SPEC.md, Agent jobs). Its rows are get_town_feed's, so the app reads them with the
-- Town feed's decoder.

create table public.daily_standouts (
  town text not null,
  day date not null,
  event_id uuid not null references public.club_events (id) on delete cascade,
  rank smallint not null check (rank > 0),
  why text not null check (btrim(why) <> ''),
  picked_at timestamptz not null default now(),
  primary key (town, day, event_id),
  unique (town, day, rank)
);

comment on table public.daily_standouts is
  'The morning job''s standout Events for one Town and day, rank 1 its top pick, each with the model''s reason (daily-tab 14). Only the service key writes.';

alter table public.daily_standouts enable row level security;
create policy "Anyone reads the standouts" on public.daily_standouts
  for select to anon, authenticated using (true);

create function public.get_event_of_the_day(p_now timestamptz default now())
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
           -- The hour it starts, read as the feed reads "7 PM", "7:30 pm", "noon", "19:00".
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
  -- The job wrote nothing today: the feed's top Event, never routine business (draw 1) or a
  -- standing thing that repeats (weekly trivia; standing things never go here). One you're Going
  -- to comes first, since the feed lowers an Event you acted on and Going would otherwise hand
  -- its spot to the next.
  fallback as (
    select p.* from parts p
    where p.draw > 1 and p.recurrence is null and not exists (select 1 from written)
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
