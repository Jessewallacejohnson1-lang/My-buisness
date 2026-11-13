-- "Faculty Recital: Gyehyun Jung" is one recital listed on two days (BP app nothing-scheduled 01): the campus calendar
-- (my.csbsju.edu event 4100036) says Thursday Nov 19, 1 PM; the music department's season page, now read by
-- `csbsju-music`, says Tuesday Dec 8, 7:30 PM, Stephen B. Humphrey Auditorium. The department's page is the newer word:
-- edited Nov 9, with the recital's block moved to sit between Dec 6 and Dec 9, while its photo keeps June's name
-- "11_19" and the portal's entry is unchanged since Oct 14. The page's Dec 8 copy becomes the Event; the portal's
-- Nov 19 copy comes out as a wrong date (nobody had saved, hearted or joined it, 2026-11-13). A decline stays through
-- the portal's re-reads until the portal changes the recital's date, time or place (write_judged's Re-read rule).
-- Only while it still says Nov 19: once the portal moves it, it is the same recital as the page's and merges.
update public.club_events
set status = 'rejected', review_reason = 'wrong_when'
where source_name = 'CSB SJU Campus Events' and source_uid = '4100036' and event_date = '2026-11-19';
