-- Seasonal places (BP app business-hours, Jesse 2026-10-26): out of season the business page says
-- "Closed till May 8". `places.hours` gains "season": [first day, last day], month-day, each year
-- until the place posts new dates; the monthly Google check keeps it (accounts.py new_hours).
-- Farmers' Market: Fridays 3-6 PM, May 8 to Oct 16 (stjosephfarmersmarket.com, 2026 season).
-- Thomsen's Garden Center: April 1 "until Halloween" (thomsensgardencenter.com).
-- Sunny Mary Meadow: the farm store opens Thu and Fri late April through October
-- (sunnymarymeadow.com/faq); late April taken as April 23, the fourth Thursday.

update public.places set hours = '{"sun": [], "mon": [], "tue": [], "wed": [], "thu": [], "fri": [["15:00", "18:00"]], "sat": [], "season": ["05-08", "10-16"]}' where id = '4a213aca-4735-40dd-9ac4-2b58696a0427'; -- St. Joseph Farmers' Market
update public.places set hours = hours || '{"season": ["04-01", "10-31"]}'::jsonb where id = 'f97e06d6-8cf9-4a75-9acd-b891ba516509'; -- Thomsen's Garden Center
update public.places set hours = hours || '{"season": ["04-23", "10-31"]}'::jsonb where id = '448b008c-6c70-4591-b3e6-f094d6e41899'; -- Sunny Mary Meadow
