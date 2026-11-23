-- Take-out, 2026-11-22: two doubles found while measuring BP app watch-every-place 42.

-- "Shop Small Saturday" (JoeTown's Instagram post, Nov 28 10 AM, Downtown) is JoeTown's own "Shop Small Saturday in
-- Joetown". Keeps 5308e5a7 (the longer About). The Sisters' "Joetown Shop Small Crawl" (e6d655c7) stays: it is the
-- Art and Heritage Place's own stop on the crawl, a tour and a sale there.
update public.club_events set status = 'rejected', review_reason = 'other'
where id = 'ccdcb1bd-ff2b-4a9d-9c9b-a9fad145ef8c';

-- "Christmas with Ben's & John's" (the ticket site, Dec 5 8 PM, The Great Hall) is the same performance as the music
-- department's Facebook event at 8 PM, which the department's own events page puts at the Church of Saint Michael,
-- St. Michael (read 2026-11-22). Keeps 7447b820 (the right place) and gives it the fuller About.
update public.club_events set description = (
  select description from public.club_events where id = 'db4e3856-21e5-4633-bdc2-3af18c69b484')
where id = '7447b820-147d-4c1d-b48b-4575c82972f6';
update public.club_events set status = 'rejected', review_reason = 'wrong_place'
where id = 'db4e3856-21e5-4633-bdc2-3af18c69b484';
