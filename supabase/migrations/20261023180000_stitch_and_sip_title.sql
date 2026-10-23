-- Milk & Honey's Stitch and Sip read two ways in the feed; one title for all of them (Jesse, 2026-10-23).
update public.club_events
set title = 'Stitch & Sip'
where source_name = 'Milk & Honey Ciders' and title = 'Stitch and Sip';
