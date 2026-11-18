-- BP app place-pages 06: Jesse's yes (2026-11-17) to hide places Apple Maps agrees are gone.
-- Speedway (27 W Birch St): Apple Maps has no Speedway in St. Joseph; GasBuddy reviews say closed,
--   and the building is listed for sublease as a "former convenience store".
-- Insurance Advisors (26 E Birch St): Apple Maps has none in St. Joseph; BBB's address for it,
--   235 Cedar St E Ste 103, is Mainstay, already in the app.
-- Neither has upcoming Events. Undo: empty closed_at (and apple_place_id) in a migration.
update public.places set closed_at = now()
 where entry_id in ('speedway', 'insurance-advisors-st-joseph') and closed_at is null;

-- Scheels Athletic Complex stays: it is a venue on purpose (Sartell hockey games, 25 upcoming).
-- Apple Maps puts 1109 First St S in Sartell, so its address says Sartell now, and its About,
-- which both checks passed, goes live (it was held only for the town doubt).
update public.places
   set address = '1109 1st St S, Sartell, MN 56377',
       about = 'SCHEELS Athletic Complex is a multi-sport and event center at Pinecone Regional Park in Sartell, owned and run by the nonprofit Sartell Youth Recreation Center. It opened as Bernick''s Arena in November 2003, and a 2021 expansion added the RDR Arena, with one rink keeping ice all year and the other switching between ice and turf. Youth and high school teams, St. John''s University hockey and SCSU hockey use it for hockey, skating, lacrosse, soccer and football.'
 where entry_id = 'scheels-athletic-complex';
