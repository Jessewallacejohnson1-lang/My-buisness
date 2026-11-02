-- Closed places take themselves off the app (Jesse, 2026-11-01: "use Apple Maps, Apple Maps is
-- correct"). Bello Cucina said goodbye on its own Facebook on Oct 24; a week later Apple Maps had it
-- Permanently Closed and Google still listed its hours. Each app place keeps its Apple Maps place id;
-- the morning finish (sources/scripts/apple_maps.py) reads its Apple Maps page as the Watch key and,
-- when Apple says closed for good, sets closed_at and cancels its upcoming Events. The app's public
-- read shows only open places, so this needs no app update. Undo: empty closed_at and apple_place_id.
alter table public.places
  add column apple_place_id text,
  add column closed_at timestamptz;
comment on column public.places.apple_place_id is
  'Apple Maps place id (MapKit MKMapItem.Identifier); its page at maps.apple.com/place?place-id= says whether the place closed for good.';
comment on column public.places.closed_at is
  'When Apple Maps (or Jesse) said this place closed for good. Set: the app no longer shows it.';

drop policy if exists "read places" on public.places;
create policy "read places" on public.places for select to anon, authenticated using (closed_at is null);

-- The morning finish hides a closed place; it still may not rename or move one, nor change its Apple id.
grant update (closed_at) on public.places to watch;

-- Each place's Apple Maps place, matched with MapKit by its name near its pin
-- (sources/scripts/apple_match.swift, 2026-11-01).
update public.places set apple_place_id = 'IAE1C4789868EBBDF' where id = 'ab44fdd8-302b-4523-abca-d087d89874f1';  -- All Occasion Floral & Gifts = All Occasions Floral and Gifts (84 m)
update public.places set apple_place_id = 'I3A137D3D13266DFC' where id = '5be29c95-5f5d-45aa-83b0-0f591916b4ee';  -- AMS Tax & Accounting Solutions, PA = AMS Tax & Accounting Solutions (108 m)
update public.places set apple_place_id = 'I540261D802D1299' where id = 'cf3c7388-f4ab-4522-ae1d-3d2a018c69a5';  -- Amy Hedtke - State Farm = Amy Hedtke - State Farm Insurance Agent (146 m)
update public.places set apple_place_id = 'I680A73E2FBE2058C' where id = '3f3c5259-67f9-491e-9af5-5c4b21a80b58';  -- Bad Habit Brewing Company = Bad Habit Brewing Company (6 m)
update public.places set apple_place_id = 'I742F53B0B959ED11' where id = '2b90146d-3652-4a02-b1a5-a5d132c62522';  -- Blush Salon = Blush Salon and Suites (11 m)
update public.places set apple_place_id = 'I6A242AE454871FD5' where id = 'dcc05e93-f05b-4143-b05c-d2a665bf72f2';  -- Bo Diddley's Deli = Bo Diddley's Deli (5 m)
update public.places set apple_place_id = 'I772B54BF19BECA43' where id = '443332c9-0465-49f3-9afc-f5f103eb3bad';  -- Bruno Press = Bruno Press (57 m)
update public.places set apple_place_id = 'I586B5FC4B145A174' where id = 'ffc8cb61-7783-4676-9e3d-ba8bc813b718';  -- Cedar Street Salon & Spa = Cedar Street Salon And Spa (160 m)
update public.places set apple_place_id = 'I409EFACA098C2C6A' where id = 'c70fd279-04d4-46b0-b605-878a85bdb2fa';  -- CentraCare - St. Joseph Clinic = CentraCare - St. Joseph Clinic (310 m)
update public.places set apple_place_id = 'I401BD469E9025244' where id = 'fa4b334d-2a48-4f99-94eb-1ac8ea764367';  -- China One = China One (8 m)
update public.places set apple_place_id = 'I1D5C34F347CEE941' where id = 'c29f89a1-5caa-423a-9424-b08373328871';  -- Chiropractic Connection, PC = Chiropractic Connection (6 m)
update public.places set apple_place_id = 'I92D13B409E364741' where id = '20b5fabb-0c41-438d-840a-ce8da5d6d6e4';  -- CMS Autobody = CMS Auto Body (5 m)
update public.places set apple_place_id = 'ID2E74ACB9238CB6E' where id = '0ad2d330-9895-4735-9ff1-44c8b1d43b31';  -- Coborn's Pharmacy = Coborn's Pharmacy (18 m)
update public.places set apple_place_id = 'IC772D915398AADF1' where id = '23dd1b61-a5ae-4fb3-bb1e-af98c921ae55';  -- Daisy A Day Floral & Gift = Daisy A Day Floral & Gift (30 m)
update public.places set apple_place_id = 'I96438D6F1881E041' where id = '012f809a-029a-426e-8440-4f55ed50d41e';  -- Exponential Chiropractic Healing Center = Exponential Chiropractic Healing Center (14 m)
update public.places set apple_place_id = 'IEF7B3FCC9F4EA6D7' where id = 'f974053c-c39a-4bb3-a6ef-bf163d232b7f';  -- Floor to Ceiling = Floor To Ceiling (96 m)
update public.places set apple_place_id = 'ICBB6FEA39CB7B43C' where id = 'c10adb95-4e83-4b9a-95c5-f96178dad197';  -- Floral Arts Inc. = Floral Arts (41 m)
update public.places set apple_place_id = 'I6EE8EFC3F8E301E3' where id = 'fed769b6-ec34-4cc6-bb05-8e7016e79aec';  -- Flour & Flower = Flour & Flower (3 m)
update public.places set apple_place_id = 'IEA315333985BB99E' where id = '971d058c-e779-44e5-a133-bd4fc2d08b8b';  -- Gary's Pizza = Gary's Pizza (2 m)
update public.places set apple_place_id = 'IE4DA6C285F7300' where id = '21e97746-5906-433f-8322-76fdb267b86a';  -- Golden Hour Wellness = Golden Hour Wellness (38 m)
update public.places set apple_place_id = 'I87175AB58CB94F38' where id = '432e41ab-313d-4d88-b891-08e42ab95b69';  -- Granite City Gymnastics = Granite City Gymnastics (48 m)
update public.places set apple_place_id = 'I4206B80C144509EF' where id = '13db727c-f385-43ab-a67d-8cb534833563';  -- Groundsman LLC = Groundsman LLC (263 m)
update public.places set apple_place_id = 'I15A5BAAAB20982A4' where id = '8e61e7d8-f5aa-426e-9325-bebb2875cae9';  -- Hair By Hanna = Hair by Hanna (44 m)
update public.places set apple_place_id = 'I7A30A879BEA61185' where id = '5acceae4-ff09-40c7-9c46-e05d2857f018';  -- Hansen & Company Woodworks = Hansen & Company Woodworks (61 m)
update public.places set apple_place_id = 'I8EE12F6F4B83D614' where id = '4600a722-e962-4182-ad2a-035c04de3b74';  -- Her Hair Studio = Her Hair Studio (24 m)
update public.places set apple_place_id = 'I9BDE2C7A2AD1E9B4' where id = '63fd93ff-7254-461c-9e64-b7c9169a56ae';  -- Jupiter Moon Ice Cream - St. Joseph = Jupiter Moon Ice Cream (5 m)
update public.places set apple_place_id = 'I8B60BB9D3BB533C4' where id = 'c109060a-ab8c-4197-bfc6-0d6cda06c964';  -- Kay's Kitchen = Kay's Kitchen (4 m)
update public.places set apple_place_id = 'IEF850F6D4BE03EAF' where id = 'b21d44d8-e28f-4b4e-8a7d-65eed035eb31';  -- Kensington Bank = Kensington Bank - Loan and Deposit Production Office (11 m)
update public.places set apple_place_id = 'I1B45EEE0ECCF686D' where id = 'e70d7fad-c801-48f5-b874-2191defaf9b5';  -- KPower Yoga = KPower Yoga (3 m)
update public.places set apple_place_id = 'I3FE79D56EDDDB3D' where id = '02280501-5d7d-4c2b-8a6b-2ec671ce9c7c';  -- Krewe Restaurant = Krewe Restaurant (6 m)
update public.places set apple_place_id = 'IE526AC89A4B29525' where id = '1f6263f8-77cb-4e9a-a767-c8326723e9c3';  -- La Playette Bar = La Playette Bar (10 m)
update public.places set apple_place_id = 'IFBAC037045EC88A2' where id = 'a5cd14e5-24b9-4d32-b57f-accb06cfdf1c';  -- Lee's Ace Hardware = Lee's Ace Hardware (6 m)
update public.places set apple_place_id = 'IEB016B368838757E' where id = 'd66e9cbf-d9d8-48e1-8fdf-412c8cf8202d';  -- Little Saints Academy = Little St Academy (109 m)
update public.places set apple_place_id = 'IF76D6DD377270269' where id = '805fce4e-79c4-428b-bbb2-ec2799fcaf82';  -- Magnifi Financial = Magnifi Financial (3 m)
update public.places set apple_place_id = 'I9CDEBDC35F9DAE8A' where id = '796f4577-dd1a-49f6-aac5-49d3f8632ecb';  -- Milk & Honey Ciders = Milk & Honey Ciders (6 m)
update public.places set apple_place_id = 'IB6F25ADDF3E68143' where id = '3a51b1c2-eb45-4de4-8e38-5b48ca6ef44f';  -- Neighbors Route 75 = Neighbors Route 75 Bar and Grill (10 m)
update public.places set apple_place_id = 'I1C8788D9B525D3F0' where id = '00041f04-ca31-4c78-83d2-0c99dc78cb8b';  -- Obbink Distilling = Obbink Distilling (63 m)
update public.places set apple_place_id = 'I5B11D4F86A0E1935' where id = '48258ad2-2c0c-4d87-ab65-950e7ab083e4';  -- Powerhouse Outdoor Equipment = Powerhouse Outdoor Equipment (0 m)
update public.places set apple_place_id = 'IC6AED011DB5AEA3' where id = 'b370e75b-0fcc-41be-91df-0b26b41e76a2';  -- RJ's Auto Repair = RJ's Auto Repair (519 m)
update public.places set apple_place_id = 'IFE4208DF19D48A89' where id = 'eb9183fc-e63c-426c-9321-a0128375c7d9';  -- Saint Benedict's Monastery = Saint Benedict's Monastery (90 m)
update public.places set apple_place_id = 'IF15BA190320BEC11' where id = '6b0f79a9-fff6-4e60-af98-a6a45ce51223';  -- Sal's Bar & Grill = Sal's Bar & Grill (7 m)
update public.places set apple_place_id = 'IFC4ED1AC8F8B424A' where id = 'fea5593e-15d0-446e-85b0-4bbc42dbda0c';  -- Sentry Bank = Sentry Bank (10 m)
update public.places set apple_place_id = 'I3EB3D6274FD5D5C1' where id = '2b59f99a-f6da-4c3a-86c3-a5b10b1ca8e3';  -- Solar Nails of St Joseph = Solar Nails (18 m)
update public.places set apple_place_id = 'I3E3D9B2C8CCC5F3F' where id = '8d32d5e6-2c7b-47d4-8b58-86afc63e6442';  -- St Joseph Meat Market Inc = St. Joseph Meat Market (9 m)
update public.places set apple_place_id = 'IFA0F72EC5D5693BF' where id = 'f2f87782-f065-4a9b-b812-45f1bd27757e';  -- St. Joseph Health & Wellness, LLC = St Joseph Health and Wellness (16 m)
update public.places set apple_place_id = 'I99395C79C70390DF' where id = 'c9038816-1498-4bf2-8724-d726040b608c';  -- St. Joseph Veterinary Clinic = St Joseph Veterinary Clinic (59 m)
update public.places set apple_place_id = 'I2194FDA6B46B197D' where id = '448b008c-6c70-4591-b3e6-f094d6e41899';  -- Sunny Mary Meadow = Sunny Mary Meadow (178 m)
update public.places set apple_place_id = 'IC01D82F0A38CEC4A' where id = 'afb922c5-2d75-4704-8179-5c6043323627';  -- The Estates Bed & Breakfast = The Estates Bed and Breakfast (5 m)
update public.places set apple_place_id = 'I9547CE8B9F254BF5' where id = '7a27d0a0-126d-412c-871d-20a531a8ba72';  -- The House Food and Tap = The House Food and Tap (3 m)
update public.places set apple_place_id = 'IB89CF8E6456ACE79' where id = 'ed7a8833-6520-42b5-8eda-b11694731209';  -- The Local Blend = The Local Blend (19 m)
update public.places set apple_place_id = 'I679CB67530832AFF' where id = 'ef33e2f0-a5e6-47da-b91f-23f2142adcd3';  -- The Middy = The Middy (5 m)
update public.places set apple_place_id = 'I5D8DD6080AF06EAB' where id = '8cd01a3f-1441-4c1d-9aef-81419a6a75f0';  -- The Perfect Fit, LLC = The Perfect Fit (36 m)
update public.places set apple_place_id = 'IFA784867DF0BB2DD' where id = '01ed0060-197a-4ce3-bfb4-a15ba1777285';  -- The Wandering Cow Ice Cream = The Wandering Cow Hand Dipped Ice Cream and Shaved Ice (4 m)
update public.places set apple_place_id = 'I39FB4C3C26EFD0D' where id = 'f97e06d6-8cf9-4a75-9acd-b891ba516509';  -- Thomsen's Garden Center = Thomsens Garden Center (122 m)
update public.places set apple_place_id = 'I23FC14FE5DC59E43' where id = '10d6b505-b952-4b17-a1ba-64b7affe7338';  -- TireMaxx Service Centers = Tiremaxx Service Centers (314 m)
update public.places set apple_place_id = 'ICA8F4B38176EE135' where id = '75afbf0c-cb83-462b-8d38-5890d9cd0f06';  -- Trobec's Bus Service, Inc. = Trobec's Bus Service - Headquarters  (145 m)
update public.places set apple_place_id = 'I98A76BD3A1A22DF3' where id = 'bfcfe784-444a-44b5-835f-f3518032899c';  -- Two Bits Men's Grooming Salon = Two Bits Men’s Grooming Salon (20 m)
update public.places set apple_place_id = 'I28D60998CAC7F9AF' where id = '43d7228e-1fe5-487a-a30a-f53065818e22';  -- United States Postal Service = United States Postal Service (0 m)
update public.places set apple_place_id = 'ID878F0009A582A55' where id = 'e945c8d1-4575-4151-a415-db3403b0c54b';  -- Unwind: Collaborative Healing Center = Unwind: Collaborative Healing Center (31 m)
update public.places set apple_place_id = 'I1B1831D644B2853A' where id = '32654a5c-2f31-460d-b750-fe559b7f3d4c';  -- Uptown Styles by Arbor = Uptown Styles (26 m)
update public.places set apple_place_id = 'I5A8F4A068AC99F06' where id = '16b7e598-78b2-4b10-a95b-e03958879fe0';  -- WELL & Company St. Joseph = WELL & Company (15 m)
update public.places set apple_place_id = 'I34553AAA99C7DD6A' where id = '606a751d-98e2-4f3a-8926-a1d3966592e0';  -- White Peony Boutique = White Peony Boutique (42 m)
update public.places set apple_place_id = 'IA62CC769DBFBA744' where id = '1b601b20-6069-41bb-81dc-07ce8f3c65e1';  -- Woodcrest of Country Manor = Woodcrest of Country Manor (27 m)
update public.places set apple_place_id = 'IA795B6409227DC6C' where id = '132e001b-e5b6-45fa-8db8-18ec28eb0c85';  -- W|R Home Co. = W | R Home Company (42 m)
-- No Apple Maps place near its pin carries its name (Google's monthly closed list still covers them):
--   Autobody 2000 Inc (2f68442e-0399-4ac5-b60d-cc3237fa7746)
--   Brenny Transportation, Inc. (2e89bbb6-8728-4ae6-8b8b-53c1629ba395)
--   Central MN Realty (3a9a0946-ad17-4d83-9883-6f245a032569)
--   Coborn's Grocery Store (cbd3dec1-e1ed-4aa7-b32d-a02f7ae4ff8d)
--   CSB Benedicta Arts Center Galleries (Gorecki Gallery) (cc5cf7ef-2f3a-477f-a1e2-f26c4fd4178e)
--   Heim-kins Rescued Treasures (0afa5fe5-4429-482c-9a66-1babcadb17ab)
--   Home Town Title (71571e13-d608-48c8-8755-f3e78bb391a8)
--   Hudson & Company (339de4f9-8cdb-4e9c-8a4d-5a21ea96f86a)
--   Insurance Advisors (eec1f213-8624-4b14-9b00-2a5285e306df)
--   Joetown Burgers (d2737fe2-749c-4473-8346-35b2c5c774b0)
--   John Kuebelbeck American Legion Post 328 (b8088f9f-a0b8-44ee-a63c-6242e10fe4d8)
--   Milbert Johnson Family Dentistry (1b35c7a9-713b-4da7-906e-4f74b0c2cb80)
--   Minnesota Street Market, Food & Art Co-op (7566738c-0349-4b9e-837b-f0c5ad5ed64e)
--   Omann Insurance Agency, LLC (a6e854dd-632e-4e84-a6e5-2ce40c753af5)
--   Pierce Insurance Agency (b4af59d7-0006-4fb7-8ff9-b79bb2e380c4)
--   Saint Joseph Off Sale Liquor (Hollander's St. Joseph Liquor Shoppe) (8f895259-9d33-412e-bfcb-9adc2605935b)
--   Sheryl Matters Massage (e47c4da2-b44f-44d2-af68-adb8181634b1)
--   St. Joseph Farmers' Market (4a213aca-4735-40dd-9ac4-2b58696a0427)
--   The Newsleaders (b69f0ecb-e938-45a8-861b-87ce92a01710)
--   Whitby Gift Shop & Gallery (bc27d1cb-ec01-4a70-a084-9948376f8a2a)
--   Wildwood Ranch Maple Syrup (b367e8ab-b872-4142-b814-ecdd4e318d5d)
