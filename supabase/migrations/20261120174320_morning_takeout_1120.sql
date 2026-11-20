-- Take-out, 2026-11-20 morning report: two copies of one thing, seven times.

update public.club_events set status = 'rejected', review_reason = 'other' where id in (
  'e06345bd-ecd3-4e85-8024-855beb17b13a', -- "Mamma Mia!", Nov 20, 7 PM (District 742's Facebook post, no place). Kept 96af73b4 (Tech High School, its Performing Arts Center).
  '9a1f951c-ee5d-49f9-8646-d0c8a6255a2c', -- "Mamma Mia!", Nov 21, 2 PM (the same post). Kept 78bf6f08 (Tech High School).
  '28ab3068-e3a0-483f-8346-d24de26f1d63', -- "Mamma Mia!", Nov 21, 7 PM (the same post). Kept 0c570026 (Tech High School).
  '489ba578-0121-424f-bf6f-1384e9545030', -- "Mamma Mia!", Nov 22, 2 PM (the same post). Kept b36a49e0 (Tech High School).
  'c3320e6c-06a9-436d-b8d5-f0f09dad1e95', -- "Black Friday at White Peony", Nov 27, 7 AM (Instagram). Kept 238ea1de "Black Friday" (the shop's own events page, 5 AM).
  '90ad35ec-763f-46e4-8426-25feefab1a1e', -- "Red Dirt Road at La Playette", Dec 5 (the band's Facebook event). Kept 7212266b "Red Dirt Road Band" (The La Playette's own list).
  '83c98d19-c6ae-473b-853b-d364e44d8833'  -- "Mooney Family Fundraiser", Dec 6 (JoeTown's Instagram). Kept 7b87d535 "Mooney Strong Fundraiser" (The La Playette's own list, has its About).
);
