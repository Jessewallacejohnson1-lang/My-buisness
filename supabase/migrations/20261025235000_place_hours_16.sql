-- Hours for the places Google hadn't been checked against (BP app business-hours ticket 01,
-- Jesse's yes 2026-10-25). The 16 places with a Search logo and no Google id were looked up on
-- Google Maps by name and address (Apify's Google Maps crawler); a result counts only when its
-- street number and first street word match the place's. Google wins over the website. Four
-- places gain hours, two change; six already matched. Joetown Burgers (Google returned The House,
-- same address), The Newsleaders (other address), Sheryl Matters Massage (no address) and the
-- Farmers' Market (seasonal, address written differently) keep no hours.

update public.places set hours = '{"sun": [], "mon": [["08:00", "16:00"]], "tue": [["08:00", "16:00"]], "wed": [["08:00", "16:00"]], "thu": [["08:00", "16:00"]], "fri": [["08:00", "12:00"]], "sat": []}' where id = '5be29c95-5f5d-45aa-83b0-0f591916b4ee'; -- AMS Tax & Accounting Solutions, PA
update public.places set hours = '{"sun": [["12:00", "01:00"]], "mon": [["12:00", "01:00"]], "tue": [["12:00", "01:00"]], "wed": [["12:00", "01:00"]], "thu": [["12:00", "01:00"]], "fri": [["12:00", "01:00"]], "sat": [["12:00", "01:00"]]}' where id = 'b8088f9f-a0b8-44ee-a63c-6242e10fe4d8'; -- John Kuebelbeck American Legion Post 328
update public.places set hours = '{"sun": [], "mon": [["08:00", "16:30"]], "tue": [["08:00", "16:30"]], "wed": [["08:00", "16:30"]], "thu": [["08:00", "16:30"]], "fri": [["08:00", "12:00"]], "sat": []}' where id = '5acceae4-ff09-40c7-9c46-e05d2857f018'; -- Hansen & Company Woodworks
update public.places set hours = '{"sun": [], "mon": [["09:00", "17:00"]], "tue": [["09:00", "17:00"]], "wed": [["09:00", "17:00"]], "thu": [["09:00", "17:00"]], "fri": [["09:00", "15:00"]], "sat": []}' where id = 'cf3c7388-f4ab-4522-ae1d-3d2a018c69a5'; -- Amy Hedtke - State Farm
update public.places set hours = '{"sun": [["07:00", "22:00"]], "mon": [["07:00", "22:00"]], "tue": [["07:00", "22:00"]], "wed": [["07:00", "22:00"]], "thu": [["07:00", "22:00"]], "fri": [["07:00", "22:00"]], "sat": [["07:00", "22:00"]]}' where id = 'b367e8ab-b872-4142-b814-ecdd4e318d5d'; -- Wildwood Ranch Maple Syrup
update public.places set hours = '{"sun": [], "mon": [["09:00", "19:00"]], "tue": [["09:00", "19:00"]], "wed": [["09:00", "17:00"]], "thu": [["09:00", "17:00"]], "fri": [["09:00", "17:00"]], "sat": [["10:00", "14:00"]]}' where id = 'f974053c-c39a-4bb3-a6ef-bf163d232b7f'; -- Floor to Ceiling
