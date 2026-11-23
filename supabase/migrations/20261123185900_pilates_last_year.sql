-- "Pilates Class", Mondays 10 AM at City Hall, is last fall's: the City's catalog still lists Oct 6 to Dec 29 with no year,
-- its sign-ups opened 09/22/2025, and both days are Mondays in 2025 and Tuesdays in 2026. Nobody was Going. The reader takes
-- the year from the sign-up day now, so it doesn't come back (Jesse's yes, 2026-11-23; BP app watch-every-place 48).
update public.club_events set status = 'rejected', review_reason = 'wrong_when'
where id = 'afc45dd0-43aa-4160-965c-10858a9146ca' and source_uid = 'rec1:3920573';
