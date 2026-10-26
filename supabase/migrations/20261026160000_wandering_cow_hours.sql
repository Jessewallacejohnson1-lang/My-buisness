-- The Wandering Cow's hours from its own site (wanderingcowmn.com/contact, read 2026-10-26):
-- Google kept its summer hours into fall (Jesse, 2026-10-26: the place's own site wins when it is
-- newer). Its registry entry says `hours_from: website`, so the monthly Google check leaves them.

update public.places set hours = '{"sun": [["14:00", "20:00"]], "mon": [["16:00", "21:00"]], "tue": [["16:00", "21:00"]], "wed": [["16:00", "21:00"]], "thu": [["16:00", "21:00"]], "fri": [["16:00", "21:00"]], "sat": [["14:00", "21:00"]]}' where id = '01ed0060-197a-4ce3-bfb4-a15ba1777285'; -- The Wandering Cow Ice Cream
