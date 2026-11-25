-- The feed judge's first pass over what Apify brought (BP app watch-every-place 52), on Jesse's yes to the list
-- ("I agree to all", 2026-11-25). Each was read against its own post.

-- Taken out, both judges: each names the copy kept or the day it was over.
update public.board_items set status = 'archived' where status = 'published' and id in (
  'c80e0c31-687d-49d7-b89e-b54ee12b0d0d',  -- "Hours through November": "Open weekends through November 29" is the newer copy, kept
  'dfa7eda0-8090-4761-8e97-98814715250c',  -- "Holla for a Dolla at KPower Yoga": a teaser; "KPower Yoga Black Friday deals" is the offer, kept
  'eb5871ce-8081-4c8d-844b-f35426f7c852',  -- "Give to the Max Day at MPR": its "today" was Nov 19
  'f1505aca-45af-409c-a589-81866c829a81'   -- "American Education Week at SRR": Nov 16 to 20
);

-- The bakery's flyer: Tue and Wed 7 AM to 3 PM, Thu 7 to 9 AM, Fri closed, Sat 7 AM to 3 PM, Sun closed.
update public.board_items
set blurb = 'Thanksgiving 7 to 9 AM; Wed and Sat 7 AM to 3 PM; closed Fri 11/27 and Sun 11/29.'
where id = '040e8d80-4a69-469e-89af-f7b15b9a4e48' and blurb = 'Open Tue-Sat; closed Fri 11/27 and Sun 11/29.';

-- The post: "Johnnie football is headed to the NCAA Division III playoffs".
update public.board_items
set title = 'Johnnie football to NCAA playoffs; Cole Stencel to cross country nationals'
where id = 'c9bcaef9-e6df-4bec-814c-382b2604feb9' and title = 'CSB football to NCAA playoffs; Cole Stencel to cross country nationals';

-- The post: "named the MIAC Defensive Player of the Week".
update public.board_items
set title = 'Weckström MIAC Defensive Player of Week'
where id = 'd5b7b205-4548-46f7-aa18-2235f4c47948' and title = 'Weckström MIAC Goalie of Week';

do $$
begin
  -- A correction is no move: no card says it moved and nobody is told.
  alter table public.club_events disable trigger club_events_moved;

  -- "Kindergarten Signing Day" (Apr 6, 2027): the post says 5:00 to 6:30 p.m.; the winter clock was kept past March.
  update public.club_events
  set start_time = '5 PM', end_at = '2027-04-06 18:30:00 America/Chicago'
  where id = '8e490ab0-cd36-4a7d-a0dd-d7f83522de3f' and start_time = '6 PM';

  alter table public.club_events enable trigger club_events_moved;
end $$;

-- Moved marks where only the place's name changed: Art & Heritage Place's own longer name, Golden Hour Wellness and its
-- street address, and the church's lawn.
update public.club_events set moved_at = null, moved_from = null where id in (
  'b9e55833-4abb-46ed-ba6a-c374d8d3a47b', '0a8d958b-00cb-4e2b-867b-2507e211e55c',
  'b17b9218-4923-45bf-afef-642d5e052dc6', 'c59e0b2f-6bbf-4059-81c5-6a39a2ee04aa',
  '100b741c-bf2e-43d9-8923-7d59725c3393'
);
