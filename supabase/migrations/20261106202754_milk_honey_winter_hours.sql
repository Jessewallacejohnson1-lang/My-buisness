-- Milk & Honey Ciders, read from its own posts on 2026-11-06 (Jesse's yes, 2026-11-06).
--
-- Winter hours, Facebook and Instagram, Nov 2: closed Monday to Wednesday, Thursday 4-9 PM,
-- Friday 12-9 PM, Saturday 10 AM-9 PM, Sunday 10 AM-6 PM. The app still had Tuesday and Wednesday
-- open 4-9 PM. Thursday to Sunday already matched.
--
-- Today only, Instagram, Nov 6: closing 2 hours early for a private event, so 7 PM. `places.hours`
-- holds a week, not a date, so Friday reads 12-7 PM until a one-time job puts it back at 5 AM
-- Saturday (11:00 UTC is 5 AM in Chicago in November). The job only touches Friday, only if it
-- still reads 12-7 PM, and removes itself.

update public.places
set hours = hours || '{"tue": [], "wed": [], "fri": [["12:00", "19:00"]]}'::jsonb
where id = '796f4577-dd1a-49f6-aac5-49d3f8632ecb';

select cron.schedule('milk-honey-friday-back', '0 11 7 11 *', $job$
  update public.places
  set hours = hours || '{"fri": [["12:00", "21:00"]]}'::jsonb
  where id = '796f4577-dd1a-49f6-aac5-49d3f8632ecb'
    and hours -> 'fri' = '[["12:00", "19:00"]]'::jsonb;
  select cron.unschedule('milk-honey-friday-back');
$job$);
