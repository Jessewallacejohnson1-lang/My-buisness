-- Tonight's social watch wrote "FARMacy" (all day Nov 3, Sunny Mary Meadow's Facebook post about
-- eucalyptus and spruce bundles and meeting the other vendors). That's the first day of the farm's
-- Tuesday indoor Holiday Market, already listed for Nov 3 at 3 PM (a1fa3f40, kept). Hidden; a re-read
-- keeps an admin's reject.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id = '23d45b36-5d02-4c6b-84bf-3484ee48482e';
