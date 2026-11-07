-- The daily dig (BP app docs/plans/dig-deeper 22): after the morning's photo step, each new Event still with no
-- photo or flyer of its own looks further on the free rungs (the person it is about, by name; its place's own site;
-- local news), and a photo found there is saved as its own, like the morning's (sources/scripts/event_photos.py).
-- club_events.photo_dug_at: when the dig finished with an Event, found or not, so each is dug once. An Event the dig
-- didn't reach (no finder answered, or its pictures weren't judged) stays null and is dug the next morning.

alter table public.club_events add column if not exists photo_dug_at timestamptz;
