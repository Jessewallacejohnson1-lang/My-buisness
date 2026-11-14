-- Kennedy's calendar Events get their place (BP app docs/plans/school-search/issues/09-kennedys-calendar-places.md).
-- District 742's calendar pages write their label in double quotes since November 2026, and read_events.py read only
-- single ones, so 13 of Kennedy's calendar rows had no place line. The reader reads both now, and leaves a title that
-- says it is held elsewhere ("Knowledge Bowl at Saint John's Prep 6-8 grades") without the school's place.
--
-- 1. public.apply_judged (20261111152016_one_event_for_a_show.sql's, copied whole): a declined Event goes back to
--    Review when its source changes it, but a read with no place changes nothing, since the location line keeps the
--    stored place. Without this, Kennedy's Prep Knowledge Bowl (Nov 19, declined as a double of Bound's 0e55ea20)
--    went back to Review on the next morning's read: its calendar line gives no place, its row says Saint John's Prep.
-- 2. The rows the morning reads no more (past days) and the ones it reads get the place line the reader writes, first,
--    so the next read changes nothing. Filling a blank line is no move (private.is_move), and neither is dropping a
--    street; the trigger stays out of it anyway, as 20261104174524 did.
-- 3. The Nov 12 "6th Grade Orchestra Informance" is a copy: the calendar moved it to Nov 11 under a new occurrence id.
--
-- Roll back: re-run 20261111152016_one_event_for_a_show.sql's apply_judged; set the location of the rows below back to null
-- (f9f03033 to 'Kennedy Community School, 1300 Jade Rd') and deb05d15 back to 'approved' with no review_reason.

-- 1.
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
      followers_only boolean, activity_team text, activity_name text, price text, ages text, gender text, collab_entry_ids text[])
  ), written as (
    insert into public.club_events (status, kind, title, event_date, start_time, end_at, all_day,
      location, description, source_name, source_url, source_uid, category, shows_from, place_entry_id,
      sport, team_ids, occasion, followers_only, activity_team, activity_name, price, ages, for_gender, collab_entry_ids)
    select x.status, 'event', x.title, x.event_date, x.start_time, x.end_at, x.all_day, x.location,
      x.description, x.source_name, x.source_url, x.source_uid, x.category, x.shows_from, x.place_entry_id,
      x.sport, x.team_ids, x.occasion, coalesce(x.followers_only, false), x.activity_team, x.activity_name,
      nullif(x.price, ''), nullif(x.ages, ''), nullif(x.gender, ''), coalesce(x.collab_entry_ids, '{}')
    from given as x
    on conflict on constraint club_events_source_uid_key do update set
      title = excluded.title,
      -- A show keeps its first day: the calendar lists only its days to come (town-feed 62).
      event_date = case when excluded.source_uid like 'run:%'
                        then least(club_events.event_date, excluded.event_date) else excluded.event_date end,
      start_time = excluded.start_time,
      end_at = excluded.end_at, all_day = excluded.all_day,
      location = coalesce(nullif(excluded.location, ''), club_events.location),
      -- A fuller listing fills a thin About, but never one the describe step or the cleaning wrote (about_written_at):
      -- that one says only what it is and what to expect, so it is shorter on purpose (inside-cards 14).
      description = case when club_events.about_written_at is null
          and length(coalesce(excluded.description, '')) >= length(coalesce(club_events.description, ''))
        then excluded.description else club_events.description end,
      -- What it costs, as words: a re-read with none keeps the one it had (inside-cards 14).
      price = coalesce(nullif(excluded.price, ''), club_events.price),
      -- Who it's for by age: the same, a re-read that doesn't say keeps it (inside-cards 30).
      ages = coalesce(nullif(excluded.ages, ''), club_events.ages),
      -- Who it's for by gender: the same, a re-read that doesn't say keeps it (town-feed 52).
      for_gender = coalesce(excluded.for_gender, club_events.for_gender),
      -- The businesses it was made with (town-feed 58): a re-read that names none keeps them.
      collab_entry_ids = case when cardinality(excluded.collab_entry_ids) > 0 then excluded.collab_entry_ids
                              else club_events.collab_entry_ids end,
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
      shows_from = case when (club_events.event_date is distinct from excluded.event_date and excluded.source_uid not like 'run:%')
          or club_events.shows_from is null then excluded.shows_from else club_events.shows_from end,
      -- (A show's re-read always reads a later first day; that is no move, town-feed 62.)
      -- An admin's approve or decline stands; only a found event the writer left pending is
      -- published by its source. A decline for a misread goes back to Review when the source
      -- changes it (the same rule as read_events.py had). A read with no place keeps the stored one (the
      -- location line above), so it is no change (school-search 09).
      status = case when club_events.status = 'pending' and club_events.review_reason is null
          and excluded.status = 'approved' then 'approved'
        when club_events.status = 'rejected'
          and club_events.review_reason is distinct from 'not_event' and club_events.review_reason is not null
          and (club_events.title, club_events.event_date, club_events.start_time, club_events.all_day, club_events.location)
              is distinct from (excluded.title, case when excluded.source_uid like 'run:%' then club_events.event_date
                  else excluded.event_date end, excluded.start_time, excluded.all_day,
                  coalesce(nullif(excluded.location, ''), club_events.location))
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

-- 2. Fall Picture Retakes is an all-day run: its colour names the Kennedy Calendar, as the reader now reads it.
do $$
begin
  alter table public.club_events disable trigger club_events_moved;
  update public.club_events set location = 'Kennedy Community School'
   where source_name = 'Kennedy Community School'
     and id in ('05c12039-eba9-43a6-8ec7-e697c345c77d',   -- Oct 27  Fall Picture Retakes
                'd9a40c94-490d-4d3a-a32c-45b2d976418d',   -- Nov 6   Character Trait Assembly
                '15a3652a-6252-4f0b-bd05-ad4c1673eb59',   -- Nov 6   JH Knowledge Bowl
                '06b7f40b-20be-4aaa-804a-b701dfea86d0',   -- Nov 10  PTO Meeting at Kennedy
                '93013c10-4772-4700-9305-251c2297de62',   -- Nov 11  6th Grade Orchestra Informance
                'c3ee31cd-b66f-4c05-8b6d-59e4891fecad',   -- Dec 2   3rd Grade Concert
                '84b9f30e-cd6f-4f44-aade-ea2ba6a474ad',   -- Dec 2   1st 2nd Grade Concert
                '6d0b4ce6-199b-47c2-982a-70fece75f3f2',   -- Dec 3   Knowledge Bowl
                'b1ae2ed8-56fb-4bf2-829b-9050d71e9dea',   -- Dec 3   Spelling Bee
                '8f92d063-e3d9-4835-8494-6ce696a93699',   -- Dec 10  Knowledge Bowl
                'ab0ec721-b733-45f7-8fc7-260bcad11887',   -- Dec 17  Knowledge Bowl
                'f9f03033-e819-4c63-b477-037dd38c5377')   -- Dec 10  Band Choir Orchestra Concert (was "…, 1300 Jade Rd")
     and (location is null or location = 'Kennedy Community School, 1300 Jade Rd');
  alter table public.club_events enable trigger club_events_moved;
end $$;

-- 3. Kept 93013c10, Nov 11.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id = 'deb05d15-2810-438a-b118-486e038310e9' and status = 'approved';

-- The Prep Knowledge Bowl, in case a morning before this one sent it back to Review (kept 0e55ea20, Bound's).
update public.club_events set status = 'rejected', review_reason = 'other'
 where id = 'fdd32f02-56af-4513-b9b5-7e9f15a35d90' and status = 'pending';
