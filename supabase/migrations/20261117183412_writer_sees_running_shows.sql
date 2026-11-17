-- The writer sees Events still running, with their last day (BP app loopholes 21). It saw only Events whose first day
-- was yesterday or later, so a show open since Nov 3 was out of sight: the College's page read "Bréagán Art Exhibition"
-- under a new id each morning, wrote it again beside the campus calendar's "Bréagán", and a take-out didn't hold.
-- write_judged.same_show joins such a read to the show as a Mention. Copied from 20261015200100_apply_judged_cancelled.sql.
create or replace function public.listed_for_writer()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
  from (
    select e.id, e.status, e.title, e.event_date, e.start_time, e.end_at, e.all_day, e.location,
           e.source_name, e.source_uid, e.category, e.shows_from, e.review_reason, e.cancelled_at,
           e.club_id is null and e.submitted_by is null as found,
           coalesce((select jsonb_agg(jsonb_build_object('source_name', m.source_name,
             'source_url', m.source_url, 'source_uid', m.source_uid, 'trust', m.trust, 'sure', m.sure))
             from public.event_mentions m where m.event_id = e.id), '[]'::jsonb) as mentions
    from public.club_events e
    where e.kind = 'event' and (e.event_date >= (now() at time zone 'America/Chicago')::date - 1
      or (e.end_at at time zone 'America/Chicago')::date >= (now() at time zone 'America/Chicago')::date)
  ) x;
$$;
