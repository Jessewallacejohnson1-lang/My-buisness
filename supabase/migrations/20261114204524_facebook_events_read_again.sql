-- Facebook Events read again (BP app docs/plans/watch-every-place/issues/24-facebook-events-read-again.md; Jesse,
-- 2026-11-14: "make sure that they check for updates on events and changes in discription or new images", and on a
-- re-read's About, "whichever is the newest").
--
-- 1. club_events.source_words: what the host's own listing said, "words.cover" fingerprints (sources/scripts/social.py
--    listing). Only a Facebook event's read fills it for now.
-- 2. public.apply_judged (20261114044956_kennedy_calendar_places.sql's, copied whole) writes it, and on a re-read: new
--    words give the newest About, a new cover clears photo_checked_at so the photo picker looks again. A null
--    fingerprint (every Event before this) only takes the first one.
-- 3. The upcoming Events a host listed alone at a Facebook event are keyed by its number ('fb:<n>'), as the writer now
--    keys them, so the next read of a moved date or time updates the Event instead of adding a second one. One event
--    page listing several dates keeps its 'page:' ids. The row's own event_mentions keep theirs: the writer reads both.
--
-- 4. public.retire_own_event_photos: the photo step swaps its own earlier pick for a better one (sources/scripts/
--    event_photos.py keep), retiring that row first, since an Event has one live photo of each kind. The Watch key still
--    may not take a photo down (watch_saves.test.mjs): this retires only rows the step itself picked ('event photos').
--
-- Roll back: re-run 20261114044956_kennedy_calendar_places.sql's apply_judged; set source_uid back with the select in
-- this file's 3. read from the log (or leave it: an fb: id only matters to the new writer); drop column source_words; drop function public.retire_own_event_photos(bigint[]).

-- 1.
alter table public.club_events add column if not exists source_words text;
comment on column public.club_events.source_words is
  'What the host''s own listing said, as "words.cover" fingerprints (social.listing): a change gives the newest About or a new photo look.';

-- 2.
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
      followers_only boolean, activity_team text, activity_name text, price text, ages text, gender text, collab_entry_ids text[],
      source_words text)
  ), written as (
    insert into public.club_events (status, kind, title, event_date, start_time, end_at, all_day,
      location, description, source_name, source_url, source_uid, category, shows_from, place_entry_id,
      sport, team_ids, occasion, followers_only, activity_team, activity_name, price, ages, for_gender, collab_entry_ids,
      source_words)
    select x.status, 'event', x.title, x.event_date, x.start_time, x.end_at, x.all_day, x.location,
      x.description, x.source_name, x.source_url, x.source_uid, x.category, x.shows_from, x.place_entry_id,
      x.sport, x.team_ids, x.occasion, coalesce(x.followers_only, false), x.activity_team, x.activity_name,
      nullif(x.price, ''), nullif(x.ages, ''), nullif(x.gender, ''), coalesce(x.collab_entry_ids, '{}'),
      nullif(x.source_words, '')
    from given as x
    on conflict on constraint club_events_source_uid_key do update set
      title = excluded.title,
      -- A show keeps its first day: the calendar lists only its days to come (town-feed 62).
      event_date = case when excluded.source_uid like 'run:%'
                        then least(club_events.event_date, excluded.event_date) else excluded.event_date end,
      start_time = excluded.start_time,
      end_at = excluded.end_at, all_day = excluded.all_day,
      location = coalesce(nullif(excluded.location, ''), club_events.location),
      -- The host changed its own words (source_words' first half): the newest About, whatever its length and whoever
      -- wrote the last (Jesse, 2026-11-14: "whichever is the newest"; watch-every-place 24). Else a fuller listing fills
      -- a thin About, but never one the describe step or the cleaning wrote (about_written_at): that one says only what
      -- it is and what to expect, so it is shorter on purpose (inside-cards 14). A first fingerprint only says what
      -- the host says now.
      description = case
        when split_part(club_events.source_words, '.', 1) <> split_part(excluded.source_words, '.', 1)
          and nullif(excluded.description, '') is not null then excluded.description
        when club_events.about_written_at is null
          and length(coalesce(excluded.description, '')) >= length(coalesce(club_events.description, ''))
        then excluded.description else club_events.description end,
      about_written_at = case
        when split_part(club_events.source_words, '.', 1) <> split_part(excluded.source_words, '.', 1)
          and nullif(excluded.description, '') is not null then null else club_events.about_written_at end,
      -- A new cover (its second half): the photo picker looks again (event_photos.py todo), and keeps its own pick or
      -- runs a better one; a person's photo stays.
      photo_checked_at = case
        when split_part(club_events.source_words, '.', 2) <> split_part(excluded.source_words, '.', 2)
          and split_part(excluded.source_words, '.', 2) <> '' then null else club_events.photo_checked_at end,
      source_words = coalesce(excluded.source_words, club_events.source_words),
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

-- 3.
update public.club_events e
   set source_uid = 'fb:' || substring(e.source_url from 'facebook\.com/events/([0-9]+)')
 where e.kind = 'event'
   and e.event_date >= (now() at time zone 'America/Chicago')::date
   and e.source_uid like 'page:%'
   and e.source_url ~ 'facebook\.com/events/[0-9]+'
   and not exists (
     select 1 from public.club_events o
      where o.id <> e.id and o.source_name = e.source_name
        and o.event_date >= (now() at time zone 'America/Chicago')::date - 1
        and substring(o.source_url from 'facebook\.com/events/([0-9]+)')
          = substring(e.source_url from 'facebook\.com/events/([0-9]+)'));

-- 4.
create or replace function public.retire_own_event_photos(p_ids bigint[])
returns int
language sql
security definer
set search_path = ''
as $$
  with retired as (
    update public.place_photos set status = 'retired'
     where id = any(p_ids) and proposed_by = 'event photos' and status = 'live' and event_id is not null
    returning 1)
  select count(*)::int from retired;
$$;
revoke all on function public.retire_own_event_photos(bigint[]) from public, anon, authenticated;
grant execute on function public.retire_own_event_photos(bigint[]) to watch, service_role;
