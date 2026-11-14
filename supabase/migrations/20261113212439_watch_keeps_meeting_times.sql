-- The Sunday step keeps school clubs' meeting times current (BP app docs/plans/nothing-scheduled, ticket 05). The
-- morning job, as `watch`, reads each school's club page (the registry's `clubs_page`; sources/scripts/meeting_times.py)
-- and compares each club's time with `team_activities.meets` (20261113202211_club_meeting_times.sql): a time that moved
-- replaces the stored one, and a time the page dropped goes back to null ("No events yet" on its row). Only that column:
-- an activity's name, kind and order stay the migrations'.
grant select (meets), update (meets) on public.team_activities to watch;
create policy "watch keeps meeting times" on public.team_activities for update to watch using (true) with check (true);
