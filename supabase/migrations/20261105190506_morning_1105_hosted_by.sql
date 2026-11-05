-- Two Abouts said the school whose calendar lists a meet hosted it. Each school is only taking part.
update public.club_events
   set description = 'A high school wrestling invitational at Litchfield High School, with Tech High School on the schedule and the first session starting at 4:45 PM. Check the school''s Bound page for the schools entered and the schedule.'
 where id = '7a41d119-c2d3-423b-b509-c5d33a443729';  -- Wrestling Invitational, Dec 4

update public.club_events
   set description = 'A girls wrestling meet at East Ridge High School, with ROCORI High School on the schedule, starting at 8 AM. Check the school''s Bound page for the teams entered and the schedule.'
 where id = '0af83b77-f324-465e-8972-a33112d6e8b1';  -- ROCORI Girls Wrestling Meet, Jan 16
