-- "CSB sweeps MIAC weekly honors" came from The House's Instagram, a sponsor's post about CSB's
-- athletes; it is CSB Athletics' news, so it shows their logo (Jesse, 2026-11-10).
update public.board_items
   set source_name = 'CSB Athletic Activities', place_entry_id = 'activities-athletic-csb'
 where id = '378fe1c3-1c61-4ce6-abd8-ddd249b1a38d';
