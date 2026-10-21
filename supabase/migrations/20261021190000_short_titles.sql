-- Found events' titles over 40 characters, shortened by the title-and-place skill: the source's
-- own words a neighbour would recognise, never cut mid-word (Jesse, 2026-10-21: three lines don't
-- fit the Town's Event of the day poster). Only upcoming found events; a game's two team names
-- stay whole. From now on the morning job shortens new ones (`morning.py titles`) and the writer
-- keeps a listed short title when its source sends the long one again (write_judged.py).
update public.club_events e set title = s.short
from (values
  ('Coffee and Conversations With Superintendent Putnam', 'Coffee With Superintendent Putnam'),
  ('Free Art Prints from The Saint John''s Bible', 'Free Saint John''s Bible Art Prints'),
  ('"What is the price of liberty?" by the Humanities Institute', 'What is the price of liberty?'),
  ('Sacred Heart Chapel Dedication Anniversary', 'Sacred Heart Chapel Anniversary'),
  ('Anniversary of the Dedication of Sacred Heart Chapel', 'Sacred Heart Chapel Anniversary'),
  ('The Great Pumpkin Returns to Saint John’s Abbey!', 'The Great Pumpkin Returns'),
  ('Pilgrimage for All Saints and All Souls Days', 'All Saints and All Souls Pilgrimage'),
  ('Grounding Our Emotions During Tough Times', 'Grounding Our Emotions'),
  ('Therapy Dogs at Clemens and Alcuin Library', 'Therapy Dogs'),
  ('Therapy Dogs at Clemens and Alcuin Libraries', 'Therapy Dogs'),
  ('SJU Cross Country vs Saint John''s Fall Finale', 'SJU Cross Country: Fall Finale'),
  ('Christmas Craft Sale at Saint Scholastica Convent', 'Christmas Craft Sale'),
  ('What it Means to Be a Two-Spirit Influencer', 'Two-Spirit Influencer'),
  ('Koch Chair in Catholic Thought and Teaching Presents the Reverend Daniel G. Groody',
   'Rev. Daniel Groody: Koch Chair Lecture'),
  ('Magic the Gathering co-sponsored with Tabletop Gaming', 'Magic the Gathering'),
  ('Magic the Gathering co-sponsored by Tabletop Gaming', 'Magic the Gathering'),
  ('Festival of Cultures Student Showcase and Fashion Show', 'Festival of Cultures Fashion Show'),
  ('Christmas with Saint Ben''s and Saint John''s', 'Christmas with CSB SJU'),
  ('Christmas with Saint Ben''s & Saint John''s', 'Christmas with CSB SJU'),
  ('Encountering Mary Through the Vision of Sister Thomas Carey', 'Encountering Mary: Sister Thomas Carey'),
  ('Certificate in Benedictine Spirituality Webinar', 'Benedictine Spirituality Certificate')
) as s(long, short)
where e.title = s.long and e.club_id is null and e.submitted_by is null
  and e.event_date >= date '2026-10-21';
