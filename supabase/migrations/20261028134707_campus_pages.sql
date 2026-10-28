-- The campus calendars' pages (BP app docs/plans/follows, tickets 07 and 08; Jesse, 2026-10-27): each
-- calendar the CSB and SJU events portal fills the Town feed with is its own page, followed by the name
-- its cards show, like Joetown's (`town_pages`, 20261027143913_city_pages.sql). A page lists the Events
-- carrying its name (`town_page`), its Event pages name it with Follow (`event_host`), and a follow lifts
-- its Events in the Town feed (town-feed 27). The photo is the one Block Party keeps for the registry
-- entry `csbsju-events` (place-photos). CSB and SJU Athletics stay out: following Saint Ben's or Saint
-- John's on the school pages already covers their games.

insert into public.town_pages (town, slug, name, kind, source_name, picture, picture_kind)
select 'st-joseph-mn', p.slug, p.name, 'College', p.name,
       'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/csbsju-events/photo-774a7306de.webp',
       'photo'
from (values ('csbsju-campus-events', 'CSB SJU Campus Events'),
             ('csbsju-libraries', 'CSB SJU Libraries'),
             ('csbsju-outdoor-u', 'CSB SJU Outdoor U'),
             ('sju-school-of-theology', 'Saint John''s School of Theology'),
             ('csbsju', 'CSB SJU')) p (slug, name)
on conflict (town, slug) do update set name = excluded.name, kind = excluded.kind,
  source_name = excluded.source_name, picture = excluded.picture, picture_kind = excluded.picture_kind;
