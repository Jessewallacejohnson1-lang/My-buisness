-- A school's club meetings, assemblies and PTO meetings reach only those following the school (Jesse, 2026-11-05).
-- The readers now mark new ones the same way. Kennedy's own calendar named no school to follow, so these name it.
update public.club_events set followers_only = true
 where source_name = 'Cathedral High School' and title = 'Art Club';

update public.club_events set followers_only = true, activity_team = 'kennedy'
 where source_name = 'Kennedy Community School'
   and title in ('Character Trait Assembly', 'Veterans Day Assembly', 'PTO Meeting at Kennedy');
