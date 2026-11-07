-- One thing listed twice. Each line names the copy kept.
-- Ptanyetu Powwow, today 1 PM at Clemens Fieldhouse, from CSB SJU Campus Events with no place line, is Kennedy
-- Community School's Ptanyétu Powwow at the same hour. Kept: 941220e1, the copy with the place.
update public.club_events set status = 'rejected', review_reason = 'other'
  where id = 'efbe0cf2-9264-476d-92da-a33b613998b2';
