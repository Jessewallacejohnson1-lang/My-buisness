-- The St. Joseph Lions Club's own page is its Facebook page (BP app docs/plans/nothing-scheduled, ticket 08).
-- Its registry entry `st-joseph-lions-club` (sources/st-joseph-mn.md) names that page; the morning sync writes it to
-- public.sources under the entry's name, and the social watch writes each Event it reads there with the same name.
-- private.event_group then matches that Event to the Group, as it does the Rod and Gun Club's site, so its card
-- names the Lions Club with Join and members see it lifted.
update public.clubs set own_entry_id = 'st-joseph-lions-club' where entry_id = 'group-st-joseph-lions-club';
