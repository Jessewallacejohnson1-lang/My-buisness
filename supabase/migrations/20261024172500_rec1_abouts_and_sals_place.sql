-- The rec1 reader's first morning (2026-10-25) brought the City's programs with only a price as
-- their About, and the morning's search found nothing more. Two have fuller words in the City's
-- own earlier posts (the rows they replaced): written here. Sal's band night lost its place when
-- the morning re-read its page without one: put back, as Sal's own event page gives it.
update public.club_events set description = $about$St. Joseph Parks and Rec hosts a morning of Halloween crafts for kids ages 2 to 14. It costs $5 per child; sign up on the City's registration site. Costumes are welcome.$about$
  where source_uid like 'rec1:%' and title = 'Fall Craft Day' and event_date = '2026-10-31';
update public.club_events set description = $about$St. Joseph Parks and Rec runs Thursday night youth dodgeball in the Kennedy Community School gym through Dec. 10, right after youth volleyball. It is for ages 6 to 14 and costs $20; sign up on the City's registration site.$about$
  where source_uid like 'rec1:%' and title = 'Youth dodgeball';
update public.club_events set location = 'Sal''s Bar and Grill' where id = '138ebd2a-881a-4daf-a5d8-cc3950669b0c';
