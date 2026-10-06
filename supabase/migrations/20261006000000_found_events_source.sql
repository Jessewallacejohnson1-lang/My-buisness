-- Events Block Party finds in a town's own sources (the City's calendar feeds first) join
-- club events as one list (ADR-021 in the registry's decision records). A found event has
-- no submitter; it records the source that announced it instead. Found events are written
-- as status 'pending' and wait for the admin's review, so this changes nothing neighbours
-- see. The feed and briefing functions still require a submitter; they learn about found
-- events together with the app update that can show them.
alter table public.club_events
  add column if not exists source_name text,
  add column if not exists source_url text,
  add column if not exists source_uid text;

-- Re-reading a feed updates the events it already gave instead of adding them again. A full
-- constraint, not a partial index, so an upsert can name it; club and neighbour events
-- carry nulls here, and nulls never collide.
alter table public.club_events
  add constraint club_events_source_uid_key unique (source_name, source_uid);

comment on column public.club_events.source_name is
  'Who announced a found event, e.g. "City of St. Joseph". Null for events a club or neighbour posted.';
comment on column public.club_events.source_url is
  'Where a found event was read: the feed or page, so a reviewer can open it.';
comment on column public.club_events.source_uid is
  'The source''s own id for the event (an iCal UID), unique per source_name.';
