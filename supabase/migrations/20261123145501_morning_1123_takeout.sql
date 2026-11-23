-- Morning report 2026-11-23 take-out.

-- "Advent Reconciliation Service" (Church of Saint Joseph's calendar, Dec 12 1 PM): today's re-read moved it to the
-- Church of St. Joseph. The calendar page (churchcenter.com/calendar/event/239707592, read 2026-11-23) is titled
-- "Advent Reconciliation Service/St. John the Baptist": it is at St. John the Baptist, where the Event was until today.
-- No other copy. Nobody is Going, saved or liked it.
update public.club_events set status = 'rejected', review_reason = 'wrong_place'
where id = 'e92df612-059e-4ecb-b3d1-22173bd20425';

-- News "District 742 weather closing plan" says "Decision by 9 PM the night before". The district's page
-- (isd742.org weather-announcements, read 2026-11-23) says by 9 PM only when they can decide that evening; otherwise
-- families hear between 5:15 and 6 AM. A parent who hears nothing by 9 would take it that school is on.
update public.board_items set status = 'archived' where id = 'bf15ae3b-9ddc-4a2b-8b7a-58aec5cf37a0';
