-- An Event's price as words, its own field (BP app docs/plans/inside-cards/issues/14-about-says-what-to-expect.md).
-- Jesse, 2026-11-06: an About says only what the Event is and what to expect; the price, time, date and place get
-- their own lines on the Event page. The date, time and place had fields; the price had nowhere to go.
--
-- 1. public.club_events.price: free text as a source says it ("Free", "$22, $20 seniors, $15 students"), null when
--    unknown, and the page shows nothing then (never a placeholder). The morning's About writers fill it
--    (sources/models/describe.md); the one-off cleaning of today's Abouts is sources/scripts/clean_abouts.py, run
--    after Jesse's yes. The watch role's table-wide update on club_events (20261031040831_watch_key.sql) covers it.
-- 2. private.event_cards (20261108033320_heart_replaces_save.sql's, copied whole) sends `price` on every card, so
--    the Event page shows it from every door.
-- 3. public.club_events.about_written_at: when the morning's describe step or the cleaning wrote the About. Not
--    described_at, which the describe step sets on every Event it researched, found or not: a thin About nobody
--    wrote stays the source's own (review of the run, 2026-11-08).
-- 4. public.apply_judged (20261106194443_closings_wait_a_week.sql's, copied whole): a judged item's `price` lands, a
--    re-read with none keeps it, and a re-read's longer words no longer write over an About we wrote
--    (about_written_at), which is shorter on purpose; a fuller listing still fills one only researched. Before this,
--    the next morning's read of a calendar put the cleaned About back (b7e4e59c's note on the ticket).
--
-- Roll back: re-run 20261108033320's event_cards and 20261106194443's apply_judged, then
-- `alter table public.club_events drop column price, drop column about_written_at`.

-- 1. and 3. The fields.
alter table public.club_events add column price text;
comment on column public.club_events.price is
  'What it costs, as words from a source ("Free", "$10 at the door"); null when no source says (inside-cards 14).';
alter table public.club_events add column about_written_at timestamptz;
comment on column public.club_events.about_written_at is
  'When the morning''s describe step or the About cleaning wrote this About: a re-read never writes over it (inside-cards 14).';

-- 2. The card.
create or replace function private.event_cards(p_events uuid[])
returns table (id uuid, card jsonb)
language sql
stable
security invoker
set search_path = ''
as $$
  -- The group that posted it, else, for a found Event, the group it was found for: worked out once per
  -- Event (kept, as the Town feed's `shown` is), never once per group the join tries.
  with ev as materialized (
    select e.*,
           coalesce(e.club_id, case when e.submitted_by is null and e.source_name is not null
                                    then private.event_group(e.source_name, e.place_entry_id, e.title) end) as group_id
    from public.club_events e
    where e.id = any (p_events)
  ),
  -- Each host's picture once, and all of them before any Event's picture. The host picture is read as
  -- its owner and the Event picture as the caller, so asking for both on every row makes Postgres 18 plan
  -- their shared place_picture again each time: 124 ms against 46 for 200 Events (PGlite, 2026-11-02).
  hosts as materialized (
    select jsonb_object_agg(k.host, private.host_picture(k.source_name, k.own_entry_id)) as pictures
    from (select distinct jsonb_build_array(e.source_name, c.own_entry_id)::text as host, e.source_name, c.own_entry_id
          from ev e
          left join public.clubs c on c.id = e.group_id) k
  )
  select e.id,
         jsonb_build_object(
           'id', e.id,
           'title', e.title,
           'event_date', e.event_date,
           'start_time', e.start_time,
           'location', e.location,
           'image_url', e.image_url,
           'category', e.category,
           'club_name', c.name,
           'source_name', e.source_name,
           'end_at', e.end_at,
           'all_day', e.all_day,
           'created_at', e.created_at,
           'going_count', private.going_count(e.id),
           'going', exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid()),
           'cancelled', e.cancelled_at is not null,
           -- The Heart, which is a save now (inside-cards 16): every account's, and whether the caller gave one. Every
           -- door to the Event page knows it, so a heart shows the same from the feed, the bell, Going and Liked.
           'heart_count', private.heart_count(e.id),
           'hearted', exists (select 1 from public.event_likes l where l.event_id = e.id and l.user_id = auth.uid()),
           -- A photo of what it is, else its place's picture (event-photos 07).
           'place_picture', public.event_picture(e.id),
           -- Who puts it on, its logo first (Jesse, 2026-10-23).
           'host_picture', h.pictures -> jsonb_build_array(e.source_name, c.own_entry_id)::text,
           'description', e.description,
           -- What it costs, as words (inside-cards 14): the Event page's price line, absent when unknown.
           'price', e.price,
           -- What it is, in one to three words (event-card 05).
           'what', e.what,
           -- Whether it's a real happening, the one meaning of live and "Now" (town-feed 41).
           'live_kind', private.is_live_kind(e.what, e.title, e.draw, e.all_day, e.start_time, e.event_date, e.end_at,
                                             e.sport is not null and e.team_ids is not null),
           -- The newest of those friends' Going, which brings a seen card back (town-feed 41).
           'friends_going_at', fg.last_at,
           -- The page it was found on, the Event page's link under About (Jesse, 2026-10-27).
           'source_url', e.source_url,
           -- A game between two teams (game-card 01): its teams, host first, its final, live score and plays.
           'game', private.event_game(e.sport, e.team_ids, e.occasion)
                     || jsonb_build_object('final', e.final_score, 'live', e.live_score, 'plays', e.scoring_plays),
           -- Up to three friends Going, newest Going first (town-feed 28).
           'friends_going', coalesce(fg.people, '[]'::jsonb),
           -- How its series repeats ("Every Sunday"), the Event page's day row from every door (inside-cards 23).
           'recurrence', sr.recurrence)
  from ev e
  left join public.clubs c on c.id = e.group_id
  left join private.friends_going(p_events) fg on fg.event_id = e.id
  left join private.series_repeats(p_events) sr on sr.id = e.id
  cross join hosts h
$$;

revoke execute on function private.event_cards(uuid[]) from public;
grant execute on function private.event_cards(uuid[]) to anon, authenticated;

-- 4. The writer.
create or replace function public.apply_judged(p_events jsonb, p_mentions jsonb, p_upgrades jsonb, p_news jsonb,
                                    p_cancelled jsonb default '[]', p_restored jsonb default '[]')
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  n_events int; n_mentions int; n_upgrades int; n_news int; n_cancelled int; n_restored int;
  events_added jsonb; news_added jsonb;
begin
  -- 0. Every team a game names (game-card 01), so its card has both before a logo is found.
  insert into public.teams (id, name, short_name)
  select distinct t.id, t.name, coalesce(t.short, t.name)
  from jsonb_to_recordset(p_events) as x(team_ids text[], team_names text[], team_shorts text[])
  cross join lateral unnest(x.team_ids, x.team_names, x.team_shorts) as t(id, name, short)
  where t.id is not null and t.name is not null
  on conflict (id) do nothing;

  -- 1. New found events, and re-reads of ones already listed (same source and uid). Added are the ones
  --    not there before: the statement reads the table as it was before its own insert.
  with given as (
    select a.n, x.*
    from jsonb_array_elements(p_events) with ordinality as a(item, n)
    cross join lateral jsonb_to_record(a.item) as x(status text, title text, event_date date,
      start_time text, end_at timestamptz, all_day boolean, location text, description text,
      source_name text, source_url text, source_uid text, category text, shows_from date,
      place_entry_id text, sport text, team_ids text[], occasion text,
      followers_only boolean, activity_team text, activity_name text, price text)
  ), written as (
    insert into public.club_events (status, kind, title, event_date, start_time, end_at, all_day,
      location, description, source_name, source_url, source_uid, category, shows_from, place_entry_id,
      sport, team_ids, occasion, followers_only, activity_team, activity_name, price)
    select x.status, 'event', x.title, x.event_date, x.start_time, x.end_at, x.all_day, x.location,
      x.description, x.source_name, x.source_url, x.source_uid, x.category, x.shows_from, x.place_entry_id,
      x.sport, x.team_ids, x.occasion, coalesce(x.followers_only, false), x.activity_team, x.activity_name,
      nullif(x.price, '')
    from given as x
    on conflict on constraint club_events_source_uid_key do update set
      title = excluded.title, event_date = excluded.event_date, start_time = excluded.start_time,
      end_at = excluded.end_at, all_day = excluded.all_day,
      location = coalesce(nullif(excluded.location, ''), club_events.location),
      -- A fuller listing fills a thin About, but never one the describe step or the cleaning wrote (about_written_at):
      -- that one says only what it is and what to expect, so it is shorter on purpose (inside-cards 14).
      description = case when club_events.about_written_at is null
          and length(coalesce(excluded.description, '')) >= length(coalesce(club_events.description, ''))
        then excluded.description else club_events.description end,
      -- What it costs, as words: a re-read with none keeps the one it had (inside-cards 14).
      price = coalesce(nullif(excluded.price, ''), club_events.price),
      source_url = excluded.source_url,
      -- coalesce: a writer from before place_entry_id (the cloud routine until this is pushed)
      -- must not wipe a place already set.
      place_entry_id = coalesce(excluded.place_entry_id, club_events.place_entry_id),
      category = coalesce(club_events.category, excluded.category),
      -- Written as read, so a game read wrong once is right the next morning.
      sport = excluded.sport, team_ids = excluded.team_ids, occasion = excluded.occasion,
      -- Once a public page lists it, it stays everyone's; a re-read naming no activity keeps the one it had.
      followers_only = club_events.followers_only and excluded.followers_only,
      activity_team = coalesce(excluded.activity_team, club_events.activity_team),
      activity_name = coalesce(excluded.activity_name, club_events.activity_name),
      -- On its source's list again: not called off.
      cancelled_at = null,
      shows_from = case when club_events.event_date is distinct from excluded.event_date
          or club_events.shows_from is null then excluded.shows_from else club_events.shows_from end,
      -- An admin's approve or decline stands; only a found event the writer left pending is
      -- published by its source. A decline for a misread goes back to Review when the source
      -- changes it (the same rule as read_events.py had).
      status = case when club_events.status = 'pending' and club_events.review_reason is null
          and excluded.status = 'approved' then 'approved'
        when club_events.status = 'rejected'
          and club_events.review_reason is distinct from 'not_event' and club_events.review_reason is not null
          and (club_events.title, club_events.event_date, club_events.start_time, club_events.all_day, club_events.location)
              is distinct from (excluded.title, excluded.event_date, excluded.start_time, excluded.all_day, excluded.location)
        then 'pending' else club_events.status end
    returning 1
  )
  select (select count(*) from written),
    coalesce(jsonb_agg(g.n - 1 order by g.n) filter (where not exists (select 1 from public.club_events e
      where e.source_name = g.source_name and e.source_uid = g.source_uid)), '[]')
  into n_events, events_added
  from given g;

  -- 2. Every mention (ADR-021), counted toward the two-mention rule next time.
  insert into public.event_mentions (event_id, source_name, source_url, source_uid, trust, sure)
  select e.id, x.source_name, x.source_url, x.source_uid, x.trust, x.sure
  from jsonb_to_recordset(p_mentions) as x(event_id uuid, event_source_name text,
    event_source_uid text, source_name text, source_url text, source_uid text, trust text, sure boolean)
  join public.club_events e on e.id = x.event_id
    or (x.event_id is null and e.source_name = x.event_source_name and e.source_uid = x.event_source_uid)
  on conflict (event_id, source_name, source_url) do update set source_uid = excluded.source_uid,
    trust = excluded.trust, sure = excluded.sure, last_seen = now();
  get diagnostics n_mentions = row_count;

  -- 3. Listed events a new mention publishes: pending -> approved, never an admin's call.
  update public.club_events e set status = 'approved'
  from jsonb_array_elements_text(p_upgrades) as x(id)
  where e.id = x.id::uuid and e.status = 'pending' and e.review_reason is null
    and e.club_id is null and e.submitted_by is null;
  get diagnostics n_upgrades = row_count;

  -- 4. News for the town board's store, with its publish time, its interests and the place that
  --    posted it (town-feed 35). The plan left repeats out (write_judged.repeat_of); each is added, or
  --    re-read into the one already there under the same title.
  with given as (
    select a.n, x.*
    from jsonb_array_elements(p_news) with ordinality as a(item, n)
    cross join lateral jsonb_to_record(a.item) as x(title text, blurb text, category text, source_name text,
      source_url text, tier numeric, status text, starts_at timestamptz, ends_on date, shows_from timestamptz, interests text[], place_entry_id text)
  ), judged as (
    select g.*,
      exists (select 1 from public.board_items b where lower(b.title) = lower(g.title) and b.source_name = g.source_name
              and coalesce(b.starts_at, '-infinity'::timestamptz) = coalesce(g.starts_at, '-infinity'::timestamptz)) as listed
    from given g
  ), written as (
    insert into public.board_items (title, blurb, category, source_name, source_url, tier, status,
      starts_at, ends_on, published_at, fetched_at, interests, place_entry_id)
    select x.title, x.blurb, x.category, x.source_name, x.source_url, x.tier, x.status, x.starts_at, x.ends_on,
      case when x.status = 'published' then greatest(now(), x.shows_from) end, now(), x.interests, x.place_entry_id
    from judged as x
    on conflict (lower(title), source_name, coalesce(starts_at, '-infinity'::timestamptz)) do update set
      blurb = excluded.blurb, source_url = excluded.source_url, fetched_at = now(),
      ends_on = coalesce(excluded.ends_on, board_items.ends_on),
      -- The first read's interests stand, as an Event's category does; a writer from before them
      -- (the cloud routine until this is pushed) leaves both as they were.
      interests = coalesce(board_items.interests, excluded.interests),
      place_entry_id = coalesce(excluded.place_entry_id, board_items.place_entry_id),
      status = case when board_items.status = 'staging' and excluded.status = 'published'
        then 'published' else board_items.status end,
      published_at = case when board_items.status = 'staging' and excluded.status = 'published'
        then excluded.published_at else board_items.published_at end
    returning 1
  )
  select (select count(*) from written),
    coalesce(jsonb_agg(n - 1 order by n) filter (where not listed), '[]')
  into n_news, news_added
  from judged;

  -- 5. Found events their schedule dropped: kept and marked cancelled, never deleted; the app
  --    shows the Canceled tag (Jesse, 2026-10-15), so the title stays as written.
  update public.club_events e set cancelled_at = now()
  from jsonb_array_elements_text(p_cancelled) as x(id)
  where e.id = x.id::uuid and e.cancelled_at is null and e.club_id is null and e.submitted_by is null;
  get diagnostics n_cancelled = row_count;

  -- 6. Cancelled events back on their schedule (seen under another source's name; a re-read
  --    by its own source is restored in step 1).
  update public.club_events e set cancelled_at = null
  from jsonb_array_elements_text(p_restored) as x(id)
  where e.id = x.id::uuid and e.cancelled_at is not null;
  get diagnostics n_restored = row_count;

  return jsonb_build_object('events', n_events, 'mentions', n_mentions,
                            'published_by_mention', n_upgrades, 'news', n_news,
                            'cancelled', n_cancelled, 'restored', n_restored,
                            'added', jsonb_build_object('events', events_added, 'news', news_added));
end;
$$;

revoke all on function public.apply_judged(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.apply_judged(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to service_role;
