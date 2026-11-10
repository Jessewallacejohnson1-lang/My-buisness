-- Morning report 2026-11-10: take out a double and a misleading title.

-- 'Market at the Meadow' (website) is the same market as 'Market at the Meadow Day'
-- (86881695, Instagram), which keeps the fuller About and the Bloom Room place.
update public.club_events set status = 'rejected', review_reason = 'other'
where id = 'c70f2c45-f8df-4134-915f-edda05166c4d';

-- 'Bemidji Wrestling Tournament' (MSHSL) is ROCORI's home meet with Bemidji, St. Cloud and
-- Sauk Rapids-Rice at ROCORI; the title reads as a tournament in Bemidji. ROCORI's own
-- listings (fd20f342, 9ad64b86, ed1c5864) stay.
update public.club_events set status = 'rejected', review_reason = 'wrong_title'
where id = '8e2a21c4-01ca-4649-a5cd-cf6fbf74a368';
