-- A neighbour's Event at several places (BP app docs/plans/town-feed/issues/54-an-event-at-several-places.md).
-- Jesse, 2026-11-09: "they can also add multiple places. Like a plus sign after the place", then "yes" to the
-- Check-in 1 page (references/event-several-places): up to 5 places, the first stays `location`.
--
-- public.club_events.more_places: the places after the first, in the order picked; null is one place. The first
-- stays `location`, so every card, map pin and calendar entry still reads one place. The app keeps each to 120
-- letters (NewEventDraft.placeLimit). A poster can't change it once the instant check has claimed the Event
-- ("moderate events", 20261101203718_town_plus_posting.sql), and the check reads it (moderate-post).
--
-- Roll back: `alter table public.club_events drop column more_places`.

alter table public.club_events add column more_places text[]
  constraint club_events_more_places check (more_places is null or cardinality(more_places) between 1 and 4);
comment on column public.club_events.more_places is
  'A neighbour''s Event''s places after the first (`location`), in order; null is one place (town-feed 54).';
