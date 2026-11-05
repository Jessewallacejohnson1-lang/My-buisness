-- A doubled Event: Cathedral's Knowledge Bowl meet on Nov 10 at 4 PM shows three times in the Town feed: one
-- host's three Bound listings under three names. Cathedral's calendar lists only the one kept (read 2026-11-05).
-- Kept: e2e9905a "Cathedral Knowledge Bowl Meet", the copy with the About.
update public.club_events set status = 'rejected', review_reason = 'other'
 where id in ('643d8899-53ff-4a47-a34d-42a0525f2d81',  -- "Cathedral Knowledge Bowl", Nov 10
              '6f0a3740-985f-489f-ad34-520a9b60dec3'); -- "St. Cloud Cathedral Knowledge Bowl Meet", Nov 10
