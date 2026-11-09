-- Onboarding ticket 31 (BP app docs/plans/onboarding/issues/31-gender.md): the gender a neighbour may
-- pick on the Birthday step, Female or Male. Optional: no answer stays null.
--
-- Private like the birthday: town_profiles is read only by its own account and the read-only ops role
-- (schema.sql's town_profiles_select_own and bizops_ro_read). get_profile and every other function that
-- reads someone else's row names its columns, so none returns this one. Nothing reads it yet; what it
-- changes in the Town feed is BP app town-feed 52.

alter table public.town_profiles add column if not exists gender text
  check (gender in ('female', 'male'));
