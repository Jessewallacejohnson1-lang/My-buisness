-- The save says what it did with each item (BP app smooth-mornings 05). The morning report counted what
-- the writer sent: on Oct 28 it said "26 new" News and the database got 1 new row, the other 25 only a new
-- fetched_at. apply_judged now answers, in the order given, "added" or "merged" (a re-read of one already
-- listed) for each Event and "added" or "repeat" for each News; morning.py write counts and lists the new
-- ones from that answer. Those two lists replace the counts of Events and News written.
--
-- One News is one link: an item with a link of its own (own_link: a post's address, a feed item's link, as
-- write_judged.own_link decides) whose source already has that link, or an earlier item in the same call
-- has, is a repeat whatever its title says, and is left as it is. White Peony's boo baskets were written
-- three times on Oct 26 and 27 under three wordings of one Instagram post. An item without one (its
-- source's home page, a page the registry reads, or a writer from before this) keeps the title rule.
--
-- 20261026135926_apply_judged_keeps_public.sql's apply_judged line for line but for steps 1 and 4 and what
-- it returns.

create or replace function public.apply_judged(p_events jsonb, p_mentions jsonb, p_upgrades jsonb, p_news jsonb,
                                    p_cancelled jsonb default '[]', p_restored jsonb default '[]')
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  events_done jsonb; news_done jsonb; n_mentions int; n_upgrades int; n_cancelled int; n_restored int;
begin
  -- 0. Every team a game names (game-card 01), so its card has both before a logo is found.
  insert into public.teams (id, name, short_name)
  select distinct t.id, t.name, t.name
  from jsonb_to_recordset(p_events) as x(team_ids text[], team_names text[])
  cross join lateral unnest(x.team_ids, x.team_names) as t(id, name)
  where t.id is not null and t.name is not null
  on conflict (id) do nothing;

  -- 1. New found events, and re-reads of ones already listed (same source and uid). Each says which it
  --    was: the statement reads the table as it was before its own insert.
  with given as (
    select a.n, x.*
    from jsonb_array_elements(p_events) with ordinality as a(item, n)
    cross join lateral jsonb_to_record(a.item) as x(status text, title text, event_date date,
      start_time text, end_at timestamptz, all_day boolean, location text, description text,
      source_name text, source_url text, source_uid text, category text, shows_from date,
      place_entry_id text, sport text, team_ids text[], occasion text,
      followers_only boolean, activity_team text, activity_name text)
  ), written as (
    insert into public.club_events (status, kind, title, event_date, start_time, end_at, all_day,
      location, description, source_name, source_url, source_uid, category, shows_from, place_entry_id,
      sport, team_ids, occasion, followers_only, activity_team, activity_name)
    select x.status, 'event', x.title, x.event_date, x.start_time, x.end_at, x.all_day, x.location,
      x.description, x.source_name, x.source_url, x.source_uid, x.category, x.shows_from, x.place_entry_id,
      x.sport, x.team_ids, x.occasion, coalesce(x.followers_only, false), x.activity_team, x.activity_name
    from given as x
    on conflict on constraint club_events_source_uid_key do update set
      title = excluded.title, event_date = excluded.event_date, start_time = excluded.start_time,
      end_at = excluded.end_at, all_day = excluded.all_day,
      location = coalesce(nullif(excluded.location, ''), club_events.location),
      description = case when length(coalesce(excluded.description, '')) >= length(coalesce(club_events.description, ''))
        then excluded.description else club_events.description end,
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
  )
  select coalesce(jsonb_agg(case when exists (select 1 from public.club_events e
                                              where e.source_name = g.source_name and e.source_uid = g.source_uid)
                                 then 'merged' else 'added' end order by g.n), '[]')
  into events_done
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
  --    posted it (town-feed 35). One News is one link: an item with a link of its own that its source
  --    already has, or an earlier item here has, is a repeat and left as it is. The rest are added, or
  --    re-read into the one already there under the same title (a repeat too).
  with given as (
    select a.n, x.*
    from jsonb_array_elements(p_news) with ordinality as a(item, n)
    cross join lateral jsonb_to_record(a.item) as x(title text, blurb text, category text, source_name text,
      source_url text, tier numeric, status text, starts_at timestamptz, interests text[], place_entry_id text,
      own_link boolean)
  ), judged as (
    select g.*,
      g.own_link is true and (
        exists (select 1 from public.board_items b where b.source_name = g.source_name and b.source_url = g.source_url)
        or exists (select 1 from given e where e.n < g.n and e.own_link is true
                   and e.source_name = g.source_name and e.source_url = g.source_url)) as linked,
      exists (select 1 from public.board_items b where lower(b.title) = lower(g.title) and b.source_name = g.source_name
              and coalesce(b.starts_at, '-infinity'::timestamptz) = coalesce(g.starts_at, '-infinity'::timestamptz)) as listed
    from given g
  ), written as (
    insert into public.board_items (title, blurb, category, source_name, source_url, tier, status,
      starts_at, published_at, fetched_at, interests, place_entry_id)
    select x.title, x.blurb, x.category, x.source_name, x.source_url, x.tier, x.status, x.starts_at,
      case when x.status = 'published' then now() end, now(), x.interests, x.place_entry_id
    from judged as x
    where not x.linked
    on conflict (lower(title), source_name, coalesce(starts_at, '-infinity'::timestamptz)) do update set
      blurb = excluded.blurb, source_url = excluded.source_url, fetched_at = now(),
      -- The first read's interests stand, as an Event's category does; a writer from before them
      -- (the cloud routine until this is pushed) leaves both as they were.
      interests = coalesce(board_items.interests, excluded.interests),
      place_entry_id = coalesce(excluded.place_entry_id, board_items.place_entry_id),
      status = case when board_items.status = 'staging' and excluded.status = 'published'
        then 'published' else board_items.status end,
      published_at = case when board_items.status = 'staging' and excluded.status = 'published'
        then now() else board_items.published_at end
  )
  select coalesce(jsonb_agg(case when linked or listed then 'repeat' else 'added' end order by n), '[]')
  into news_done
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

  return jsonb_build_object('events', events_done, 'mentions', n_mentions,
                            'published_by_mention', n_upgrades, 'news', news_done,
                            'cancelled', n_cancelled, 'restored', n_restored);
end;
$$;

revoke all on function public.apply_judged(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.apply_judged(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to service_role;
