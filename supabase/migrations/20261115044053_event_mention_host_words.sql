-- The host's own words with a social mention of an Event (BP app docs/plans/event-schedule, ticket 01). When the social
-- read writes or reads again an Event, or a mention of one, from a Facebook event or post or an Instagram post, it keeps
-- the host's words (the event's About, the post's text) on that mention, newest words win (morning.py save_host_words).
-- The morning job's time-slot step (sources/scripts/event_parts.py) reads them in place of the social page it never
-- fetches, so WinterWalk's schedule on its Facebook event reaches its page with no new Apify read.
-- event_mentions stays admin-key only: no policy for anon or authenticated, the app never reads it. The Watch key's
-- role already may select and update the table's every column (20261031040831_watch_key.sql).
--
-- The parts table's comment drops "running 12 hours or longer": every Event's parts are read now. get_event_parts is
-- unchanged (its live rule, a real happening under 12 hours, stays).
--
-- Roll back: alter table public.event_mentions drop column host_words; and re-run the table comment in
-- 20261110193831_event_parts.sql.

alter table public.event_mentions add column if not exists host_words text;
comment on column public.event_mentions.host_words is
  'The host''s own words from this social mention (a Facebook event''s About, a post''s text), newest read wins. Admin key only.';

comment on table public.event_parts is
  'Parts at a stated time of an Event (happening-now 03, event-schedule 01). ends_at empty = 1 hour. Only the morning job writes.';
