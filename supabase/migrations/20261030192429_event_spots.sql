-- Where each Event really is, for the map's bubbles (BP app references/map-reset/plan.md): the venue its
-- location names, or its Place's own spot when the location is empty or names that Place, from the
-- hand-checked coordinates in the source registry. Empty when nothing real matched; the map leaves those
-- Events off. Only the morning job (service_role) writes them; everyone who can read the Event reads them.
alter table public.club_events add column if not exists lat double precision;
alter table public.club_events add column if not exists lng double precision;
