-- BP app feed-learns 04: Importance (1 to 5) replaced the draw (1 to 3) on 2026-11-25 (20261125195811), and the first
-- morning on it passed on 2026-11-26. Nothing reads the draw any more (no function, view, index, app or script), so it
-- goes, with its check (club_events_draw_check). Jesse's yes, 2026-11-26.
alter table public.club_events drop column draw;
