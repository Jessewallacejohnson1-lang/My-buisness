-- The writer marks a found event its schedule dropped as cancelled, and restores it when it
-- comes back (BP app docs/plans/watch-every-place, ticket 11; Jesse, 2026-10-15). Both
-- functions are 20261015120000_apply_judged.sql but for cancelled_at: listed_for_writer reads
-- it, apply_judged takes the two new lists (steps 5 and 6) and clears it on a re-read. Needs
-- club_events.cancelled_at (20261015200000_town_feed_cancelled.sql).

-- The events the writer checks a morning's items against: from yesterday on, with every
-- mention already counted toward the two-mention rule.
create or replace function public.listed_for_writer()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
  from (
    select e.id, e.status, e.title, e.event_date, e.start_time, e.all_day, e.location,
           e.source_name, e.source_uid, e.category, e.shows_from, e.review_reason, e.cancelled_at,
           e.club_id is null and e.submitted_by is null as found,
           coalesce((select jsonb_agg(jsonb_build_object('source_name', m.source_name,
             'source_url', m.source_url, 'source_uid', m.source_uid, 'trust', m.trust, 'sure', m.sure))
             from public.event_mentions m where m.event_id = e.id), '[]'::jsonb) as mentions
    from public.club_events e
    where e.kind = 'event' and e.event_date >= (now() at time zone 'America/Chicago')::date - 1
  ) x;
$$;

-- One morning's writes, all or nothing. Returns how many rows each step touched. Two more
-- lists than before, so the old four-list function goes and calls naming four still work.
drop function public.apply_judged(jsonb, jsonb, jsonb, jsonb);
create function public.apply_judged(p_events jsonb, p_mentions jsonb, p_upgrades jsonb, p_news jsonb,
                                    p_cancelled jsonb default '[]', p_restored jsonb default '[]')
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  n_events int; n_mentions int; n_upgrades int; n_news int; n_cancelled int; n_restored int;
begin
  -- 1. New found events, and re-reads of ones already listed (same source and uid).
  insert into public.club_events (status, kind, title, event_date, start_time, end_at, all_day,
    location, description, source_name, source_url, source_uid, category, shows_from)
  select x.status, 'event', x.title, x.event_date, x.start_time, x.end_at, x.all_day, x.location,
    x.description, x.source_name, x.source_url, x.source_uid, x.category, x.shows_from
  from jsonb_to_recordset(p_events) as x(status text, title text, event_date date,
    start_time text, end_at timestamptz, all_day boolean, location text, description text,
    source_name text, source_url text, source_uid text, category text, shows_from date)
  on conflict on constraint club_events_source_uid_key do update set
    title = excluded.title, event_date = excluded.event_date, start_time = excluded.start_time,
    end_at = excluded.end_at, all_day = excluded.all_day, location = excluded.location,
    description = excluded.description, source_url = excluded.source_url,
    category = coalesce(club_events.category, excluded.category),
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
      then 'pending' else club_events.status end;
  get diagnostics n_events = row_count;

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

  -- 4. News for the town board's store, with its publish time.
  insert into public.board_items (title, blurb, category, source_name, source_url, tier, status,
    starts_at, published_at, fetched_at)
  select x.title, x.blurb, x.category, x.source_name, x.source_url, x.tier, x.status, x.starts_at,
    case when x.status = 'published' then now() end, now()
  from jsonb_to_recordset(p_news) as x(title text, blurb text, category text, source_name text,
    source_url text, tier numeric, status text, starts_at timestamptz)
  on conflict (lower(title), source_name, coalesce(starts_at, '-infinity'::timestamptz)) do update set
    blurb = excluded.blurb, source_url = excluded.source_url, fetched_at = now(),
    status = case when board_items.status = 'staging' and excluded.status = 'published'
      then 'published' else board_items.status end,
    published_at = case when board_items.status = 'staging' and excluded.status = 'published'
      then now() else board_items.published_at end;
  get diagnostics n_news = row_count;

  -- 5. Found events their schedule dropped: kept, marked cancelled, and said in the title
  --    until the app shows a tag (Jesse, 2026-10-15). Never deleted.
  update public.club_events e set cancelled_at = now(), title = 'Cancelled: ' || e.title
  from jsonb_array_elements_text(p_cancelled) as x(id)
  where e.id = x.id::uuid and e.cancelled_at is null and e.club_id is null and e.submitted_by is null;
  get diagnostics n_cancelled = row_count;

  -- 6. Cancelled events back on their schedule (seen under another source's name; a re-read
  --    by its own source is restored in step 1).
  update public.club_events e set cancelled_at = null, title = regexp_replace(e.title, '^Cancelled: ', '')
  from jsonb_array_elements_text(p_restored) as x(id)
  where e.id = x.id::uuid and e.cancelled_at is not null;
  get diagnostics n_restored = row_count;

  return jsonb_build_object('events', n_events, 'mentions', n_mentions,
                            'published_by_mention', n_upgrades, 'news', n_news,
                            'cancelled', n_cancelled, 'restored', n_restored);
end;
$$;

revoke all on function public.listed_for_writer() from public, anon, authenticated;
revoke all on function public.apply_judged(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.listed_for_writer() to service_role;
grant execute on function public.apply_judged(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to service_role;
