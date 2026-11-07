-- An Event that happens at no one place: Online, a bare town, or several places (BP app inside-cards 20).
-- The morning's map spots step sets it (sources/scripts/spots.py), and the Event page then leaves out its
-- Map button, where an Event with no spot yet opens Apple Maps instead (Jesse, 2026-11-06, inside-cards 06).
-- The morning watch's role already updates club_events, so it needs no new grant.
alter table public.club_events add column no_place boolean not null default false;

comment on column public.club_events.no_place is
  'Happens at no one place (Online, a bare town, several places): no Map button. Set by the morning''s spots step.';
