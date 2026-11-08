-- Casey's General Store is not in St. Joseph (Jesse, 2026-11-08: "there's no Casey's in town").
-- OpenStreetMap and Overture list one at 421 4th Ave NE, and place_rows.py made it a page today
-- from that. Its row goes; the registry entry is retired, so the sync won't make it again.
delete from public.places where entry_id = 'caseys-general-store' and source = 'registry';
