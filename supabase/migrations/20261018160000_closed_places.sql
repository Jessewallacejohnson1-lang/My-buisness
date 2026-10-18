-- Five app places that closed, out of Search (BP app docs/plans/place-photos, ticket 04; Jesse's yes,
-- 2026-10-18). Google Maps lists Tacoholic, Joseph's Spa and Salon and Medelberg Family Chiropractic
-- as permanently closed; M & T Off Sale Liquor and Jan's Barbershop are on no listing any more (Jan's
-- address is Two Bits Mens Grooming now). All five were seeded by hand in July 2026 and nothing
-- re-adds them. Data only; spotlights point at none of them.
delete from public.places where id in (
  '3eb6bc6a-0a46-4c42-b7fe-1a6179d07a59',  -- Tacoholic
  '0a0698ad-ffd4-4c7c-af9a-bcf20d264fba',  -- Joseph's Spa and Salon
  'adc8dc90-6582-4b84-ab02-60045af02894',  -- Medelberg Family Chiropractic
  '05bfe9d4-4da2-4e4b-bd8b-ba62ef8ca0c8',  -- M & T Off Sale Liquor
  'c8b85b16-7751-4328-b8b1-9f5faf27dbd6'   -- Jan's Barbershop
);
