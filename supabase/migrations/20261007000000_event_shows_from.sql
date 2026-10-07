-- When an event starts showing in the Town feed (Jesse, 2026-10-07).
-- Null means the app's default, two weeks before the event. A skill is to set a
-- bigger event's day earlier, so that needs no app update.
alter table public.club_events add column if not exists shows_from date;

comment on column public.club_events.shows_from is
  'Day the event starts showing in the Town feed; null = two weeks before event_date.';
