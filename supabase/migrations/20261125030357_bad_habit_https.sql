-- Bad Habit Brewing's website refused https when it was listed; it answers now with a valid certificate (Let's Encrypt,
-- checked 2026-11-24). Its business page's link, on Jesse's yes the same day.
update public.places
set links = replace(links::text, '"http://www.badhabitbeer.com/"', '"https://www.badhabitbeer.com/"')::jsonb
where id = '3f3c5259-67f9-491e-9af5-5c4b21a80b58';

-- The morning watch's row goes with the registry's address, so its fingerprint stays and the next read still sees a change.
update public.sources set url = 'https://www.badhabitbeer.com/events'
where entry_id = 'bad-habit-brewing' and url = 'http://www.badhabitbeer.com/events';
