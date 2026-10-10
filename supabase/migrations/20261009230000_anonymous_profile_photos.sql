-- Anonymous accounts, second step (review of ticket 01, 2026-10-09). A profile's photo is
-- a link anyone's going faces show (get_today_briefing sends the avatars of the people
-- going), so an anonymous account could point its own at any outside image. The storage
-- rule only covered uploads; this covers the link. A name stays theirs to set.

create policy "real accounts set profile photos" on public.town_profiles
  as restrictive for insert to authenticated
  with check (avatar_url is null or (select public.is_real_account()));

create policy "real accounts change profile photos" on public.town_profiles
  as restrictive for update to authenticated
  using (true)
  with check (avatar_url is null or (select public.is_real_account()));
