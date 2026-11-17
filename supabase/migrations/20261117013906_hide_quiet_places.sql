-- Places with no sign of life, off Search and the map (Jesse's yes, 2026-11-16: hide all 11, less Heim-kins, which
-- posted a Facebook event for Nov 6). Not on Apple Maps or Google Maps, and an agent's web research found nothing
-- current. One check only, so this is Jesse's call, not the two-check rule. Proof: BP app
-- docs/plans/watch-every-place/assets/32-closed-places/sweep.json. Registry entries retired. No Events at any of them.
-- Undo one: set its closed_at back to null (no apple_place_id, so the morning won't hide it again).

-- 7 Hills Staurolites
update public.places set closed_at = now() where id = 'ca9e920c-3d82-4e2f-aa1d-cdee9860b915' and closed_at is null;
-- Rocky Acre Gardens
update public.places set closed_at = now() where id = '884bcb4d-fba0-461e-9dcc-be2ea6e72e04' and closed_at is null;
-- The Master Engraving Shoppe
update public.places set closed_at = now() where id = 'f4739351-dda2-4a98-8374-9453078f4a03' and closed_at is null;
-- Fifth Gear Repair
update public.places set closed_at = now() where id = '97725c16-b0f4-48c5-aa28-e1342797bee2' and closed_at is null;
-- Outlet Bait & Tackle
update public.places set closed_at = now() where id = 'f4c9cb3c-c830-4811-92b7-54930c6e7c9a' and closed_at is null;
-- Sam's Outdoor & More
update public.places set closed_at = now() where id = '8cf9cef4-8228-4f7f-b0a2-2e8ca35d2be8' and closed_at is null;
-- The Barn
update public.places set closed_at = now() where id = 'f44fde55-dba1-4ed5-90cc-2fb59a78d754' and closed_at is null;
-- Sheryl Matters Massage
update public.places set closed_at = now() where id = 'e47c4da2-b44f-44d2-af68-adb8181634b1' and closed_at is null;
-- John Mondloch Remodeling
update public.places set closed_at = now() where id = 'f33591a2-1bce-4770-9ca5-ca43a1eec039' and closed_at is null;
-- Cost Cutters
update public.places set closed_at = now() where id = '33af3119-8b13-4ce7-a8c8-e0d6bf4a5532' and closed_at is null;
