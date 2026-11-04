-- The schools' Bound calendars join a school and its room, and the two often repeat: "ROCORI High School
-- High School Gym". read_events.py now writes them once. Stored rows get the same words here, first:
-- private.same_place doesn't see the two forms as one place, so the next morning's re-read would mark about
-- 115 upcoming Events as moved and tell whoever saved them. Nothing moved, so the trigger stays out of it.
-- A campus listing's bare address gets its place's name the same way (title-and-place, The place line).
do $$
begin
  alter table public.club_events disable trigger club_events_moved;
  update public.club_events
     set location = regexp_replace(location, '\m(Foley High School|High School|Middle School|Field House|Gym) \1\M', '\1', 'g')
   where source_uid like 'bound:%'
     and location ~ '\m(Foley High School|High School|Middle School|Field House|Gym) \1\M';
  update public.club_events
     set location = 'Episcopal House of Prayer, Collegeville'
   where location like '14215 Fruit Farm Road%';
  alter table public.club_events enable trigger club_events_moved;
end $$;

-- A game's About names the same place. The writer keeps the longer text, so the corrected one would never land.
update public.club_events
   set description = regexp_replace(description, '\m(Foley High School|High School|Middle School|Field House|Gym) \1\M', '\1', 'g')
 where source_uid like 'bound:%'
   and description ~ '\m(Foley High School|High School|Middle School|Field House|Gym) \1\M';

-- Hidden this morning for titles that named nothing (20261104165238). The reader now names them, so they
-- come back under those names rather than wait in Review.
update public.club_events set title = 'Winter Show', status = 'approved', review_reason = null
 where id in ('7ab86d8f-71fa-4a60-a000-16bab6b85144', 'ab6ae222-d1d4-4b28-b2e4-160b440b3cc5');  -- Cathedral's Theatre listing, Nov 19 and 20
update public.club_events set title = 'Sartell Boys Wrestling Meet · MS', status = 'approved', review_reason = null
 where id in ('22b67930-56b1-46b2-bb22-cb6d9cef19f7', '43bc4eed-f632-4756-bb86-fec4df2a4287');  -- Dec 7 and Jan 11
