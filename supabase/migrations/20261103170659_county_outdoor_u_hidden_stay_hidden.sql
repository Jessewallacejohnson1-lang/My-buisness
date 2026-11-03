-- The county reader now places Outdoor U's programs at "Outdoor U, SJU" (read_events.py OUTDOOR_U).
-- The eight county copies hidden on Nov 3 (20261103153703) were written at "2850 Abbey Plaza"; a hidden
-- copy whose source re-reads it at a new place goes back to pending (apply_judged), so they take the new
-- place line now and stay hidden. Apply before the reader change reaches main.
update public.club_events set location = 'Outdoor U, SJU', place_entry_id = 'sju'
 where source_name = 'Stearns County' and status = 'rejected' and location = '2850 Abbey Plaza'
   and id in (
   '0437dd8a-0bc7-4622-972c-c2e078b3ad49',  -- Animal Tracking, Jan 9
   '47f6f6cb-4e7e-4cc9-a7da-6ba8a16b5659',  -- Banff Mountain Film Festival, Dec 4
   'edc733ad-2e32-4001-a28d-5090bc6e7ee5',  -- The Owl Hoot, Jan 23
   'b03ea030-55d1-4889-b810-1dd1a38b03da',  -- Print Making Workshop, Nov 20
   'e187b6da-e4fe-4480-a4c4-956acbdefdf8',  -- Christmas Wreath Making Workshop, Nov 30 4:30
   'dc010930-924e-42e0-b8a4-b86cf4a9f917',  -- Christmas Wreath Making Workshop, Dec 1 12:30
   '69cbce4d-b5e2-478d-83f8-cd17eeb466e7',  -- Christmas Wreath Making Workshop, Dec 2 12:30
   '5c2954b1-9e04-4e21-8f22-543c517b9a79'   -- Christmas Wreath Making Workshop, Dec 2 4:30
 );
