-- The Ptanyétu Powwow (Nov 7, 1 PM) showed twice in the Town feed: Saint Ben's and Saint John's own
-- calendar lists it (efbe0cf2), and the St. Cloud school district's Facebook post put a second copy at
-- Kennedy Community School, where it isn't (it is in Clemens Fieldhouse at CSB). The Facebook copy is
-- hidden; a re-read keeps an admin's reject. Jesse's standing rule: a wrong or doubled Event comes out.
update public.club_events set status = 'rejected',
       review_reason = 'wrong_place'
 where id = '941220e1-734b-48df-9a78-80b50432ea71';
