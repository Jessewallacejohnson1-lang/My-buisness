-- Places that are gone or were never places, off Search and the map, as American Burger Bar (20261116142612).
-- None has an Apple Maps id, so the morning's Apple check never read them. Two separate checks agreed on each:
-- Google Maps (SerpAPI) and an agent's web research that never saw Google's answer. Jesse's yes, 2026-11-16.
-- Proof per place: BP app docs/plans/watch-every-place/assets/32-closed-places/sweep.json. Registry entries retired.
-- Undo one: set its closed_at back to null (they have no apple_place_id, so the morning won't hide them again).

-- Birdie’s Pizza & Garden Bar: closed; Brick Oven Pizza at The House now (Jan 2026)
update public.places set closed_at = now() where id = '9a643552-39cb-47b9-9d21-50fb855b7f7f' and closed_at is null;
-- One Hour Heating & Air Conditioning: not here: now Opie's Gold Heat n' Air, St. Cloud
update public.places set closed_at = now() where id = '5d6e7680-19b9-46c7-a984-2e00e710221e' and closed_at is null;
-- Malibu Tan: not here: only in St. Cloud; 708 Elm St E for lease
update public.places set closed_at = now() where id = '9e25759d-92dc-4b30-b1a3-7cc786686c14' and closed_at is null;
-- Millstream Communications: not a place: made from Millstream Park's disc golf page
update public.places set closed_at = now() where id = '8a757cf2-e513-4268-9663-006d4f39bcdb' and closed_at is null;
-- The Oasis Bar and Pit: not a place: a family home, sold 2022
update public.places set closed_at = now() where id = '916f97f5-d309-4ff6-9802-d4b1571ad676' and closed_at is null;
-- V-Twin Tavern: not a place: no sign it existed; a street of houses
update public.places set closed_at = now() where id = 'd9cdb2ab-8778-422d-9012-c9a6eabac1ab' and closed_at is null;
-- Tastefully Simple Independent Consultant Lori Tiffany: not a place: a home seller, no storefront
update public.places set closed_at = now() where id = '68224218-70f6-4af5-a392-e9e8cfb190ca' and closed_at is null;
-- Paul Eisenschenk-LakePlace.com: not a place: one agent at a home address
update public.places set closed_at = now() where id = '4af5c137-0357-41f8-99a6-df0229f8180b' and closed_at is null;
-- Beumer Outdoors: a double of Collegeville Orchards (its owners)
update public.places set closed_at = now() where id = '9f3b5315-bd3f-4c3c-96ff-81a3ac7da5e0' and closed_at is null;
-- Collegeville Communities Llc: not a place: a company record; Krewe is at the address
update public.places set closed_at = now() where id = 'd041ee33-c807-4412-9ce6-7baee7eccc1e' and closed_at is null;
-- Lane Marie Hair: a double: a chair inside Blush Salon
update public.places set closed_at = now() where id = 'f003989a-d0e0-42a2-9bc1-a418afd4cad6' and closed_at is null;
-- Joetown Burgers: a double: the kitchen inside The House Food and Tap
update public.places set closed_at = now() where id = 'd2737fe2-749c-4473-8346-35b2c5c774b0' and closed_at is null;

-- Young Alum Social (Dec 21) is at The House, 13 2nd Ave NW: it keeps its place there instead of Birdie's.
update public.club_events set place_entry_id = 'food-house-tap'
where id = '2edb0ef0-60c5-4264-a8d5-fe3cdce9ee2e' and place_entry_id = 'birdies-pizza-garden-bar';
