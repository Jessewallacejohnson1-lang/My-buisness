-- Jesse, 2026-10-24:
-- Laser Dentistry is gone from St. Joseph: its own site says Dr. Contardo retired and the practice
-- runs from Becker. Its app place comes out (no spotlights; its one photo is already retired).
delete from public.places where id = 'c14fa998-6e8e-4a83-935e-6b288045bfe4';
-- Fall Craft Day (Oct 31): the City's registration catalog puts it at the Fire Hall, its earlier
-- post at the Centennial Park shelter. The catalog wins; the post's copy is hidden, and the
-- morning's rec1 reader lists the catalog's.
update public.club_events set status = 'rejected' where id = 'e48c28ad-c4c3-463b-af74-a40717e2829e';
