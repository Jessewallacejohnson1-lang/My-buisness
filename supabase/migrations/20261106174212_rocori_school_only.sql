-- ROCORI's Grad Party Parent Meeting and Kindergarten Signing Days reach only those following the school, as a PTO meeting
-- does (Jesse's yes, 2026-11-06). Both came from Instagram posts, which name no school to follow, so these name it.
update public.club_events set followers_only = true, activity_team = 'rocori'
 where id in (
   '4d4af446-3045-4d81-976a-a24a254e7ac2',  -- Grad Party Parent Meeting, 2026-11-16
   '1a6830bc-cb18-4d8d-96d5-7c22e5be3a93',  -- Kindergarten Signing Day, 2026-11-17
   'e99cea16-7f43-45ab-91f6-bfd36712abb3',  -- Kindergarten Signing Day, 2027-02-09
   '8e490ab0-cd36-4a7d-a0dd-d7f83522de3f'   -- Kindergarten Signing Day, 2027-04-06
 );
