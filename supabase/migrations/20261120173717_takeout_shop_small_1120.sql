-- Take-out, 2026-11-20: the Shop Small Crawl read again from the City's Facebook, with no post link and one line of About.

update public.club_events set status = 'rejected', review_reason = 'other' where id in (
  '04032606-16fc-4f03-a735-37fccc9b152b'  -- "Shop Small Crawl", Nov 28 (City of St. Joseph, link is facebook.com only). Kept 5308e5a7 "Shop Small Saturday in Joetown" (JoeTown, its Facebook event).
);
