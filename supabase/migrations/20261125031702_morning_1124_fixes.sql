-- The morning report of 2026-11-24, its three questions on Jesse's yes ("yes to all", 2026-11-24; BP app backlog 42).
-- The fourth, the Bad Habit News's link, was put right by 5179d2d3.
do $$
begin
  -- A correction is no move: no card says it moved and nobody is told.
  alter table public.club_events disable trigger club_events_moved;

  -- "RIS Grade 5 Band, Choir & Orchestra" (Dec 8) back in, at its own school: the district's calendar
  -- (isd748.org/calendars, read 2026-11-24) lists "RIS 5th Grade Band Concert" 6 to 7 PM and "RIS 5th Grade Choir and
  -- Orchestra" 7 to 8 PM under "RIS - Riverview Intermediate School". Its map spot is looked up by the next run.
  update public.club_events
  set location = 'Riverview Intermediate School, Sartell', end_at = '2026-12-08 20:00:00 America/Chicago',
      status = 'approved', review_reason = null, spot_looked_at = null
  where id = '678565e7-5801-4a93-a79f-a2c0f27170c9' and location = 'Rock Ridge Intermediate, Sartell';

  -- "Groovy Shoes at WinterWalk" (Dec 4) had the About, and a "moved" mark, from the harp ensemble its listing was first
  -- made for. WinterWalk's page: "Groovy Shoes, 6–9 pm in the Bad Habit Tap Room". The harp is in WinterWalk's own parts.
  update public.club_events
  set description = 'Live music from Groovy Shoes in the Bad Habit Tap Room, part of the JoeTown WinterWalk Festival.',
      moved_at = null, moved_from = null
  where id = 'f0d31941-8eda-4c36-a57e-b1729921b450'
    and description = 'A harp ensemble performs at Heritage Hall as part of the JoeTown WinterWalk Festival.';

  alter table public.club_events enable trigger club_events_moved;
end $$;

-- "Winter Break Countdown Dress Up" (Tech High School, Dec 4 to 18): 11 school days for its own students, nothing a
-- neighbour can go to. Nobody was Going to, saved, liked or commented on one.
update public.club_events set status = 'rejected', review_reason = 'not_event'
where title = 'Winter Break Countdown Dress Up' and source_name = 'Tech High School'
  and event_date between '2026-12-04' and '2026-12-18' and status = 'approved';
