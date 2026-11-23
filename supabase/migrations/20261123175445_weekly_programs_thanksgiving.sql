-- Youth volleyball and dodgeball showed on Thanksgiving: our reader worked out the Thursday, and Kennedy has no school that
-- day. Their next one is Dec 3 (Jesse's yes, 2026-11-23; BP app watch-every-place 46). Nobody was Going, and a correction
-- is no move, so no card says it moved.
do $$
begin
  alter table public.club_events disable trigger club_events_moved;
  update public.club_events
  set event_date = '2026-12-03', end_at = end_at + interval '7 days', shows_from = '2026-11-19', moved_at = null, moved_from = null
  where source_uid in ('rec1:4429084', 'rec1:4429103') and event_date = '2026-11-26';
  alter table public.club_events enable trigger club_events_moved;
end $$;
