-- Take-out, 2026-11-22: "Young Alum Social" (Saint John's Preparatory School, Dec 21 9 AM, the RSVP form's link, read by
-- Saturday's social check) is St. John's Prep's own "Young Alumni Social" at The House Food & Tap, the copy kept when
-- the same listing was taken out on Nov 19. Keeps 2cb85493 (the Prep's own events page, the longer About).
update public.club_events set status = 'rejected', review_reason = 'other'
where id = '0eead154-489e-48ac-9615-47d5568e0eab';
