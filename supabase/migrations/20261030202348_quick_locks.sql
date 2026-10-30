-- Quick locks (BP app docs/plans/loopholes, ticket 04), numbered as the ticket numbers them. Lock 3
-- is moderate-post's own code; lock 4, one view record per person per card per day, is
-- 20261030202350_feed_actions_once_a_day.sql. Uses pg_cron, so the PGlite stories never load it.
-- Applied live only with Jesse's yes.

-- 1. The old Today job: it rebuilt a briefing every hour that nothing reads any more.
select cron.unschedule('briefing-reconcile');

-- 2. Uploads. Nothing has written to event-images since the composers went (iOS 910e05e1) and it
-- holds no files, so its upload rule goes: any signed-in account could put any file of any size in
-- a public bucket. Profile photos stay open to their owner, images only and under 10 MB.
drop policy "event images authenticated upload" on storage.objects;
update storage.buckets
set file_size_limit = 10485760,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
where id = 'avatars';

-- 5a. Row rules read the caller once per query, not once per row: auth.uid() becomes
-- (select auth.uid()), each rule otherwise as it is live.
alter policy "own saves insert" on public.event_saves with check ((select auth.uid()) = user_id);
alter policy "own saves delete" on public.event_saves using ((select auth.uid()) = user_id);
alter policy "own likes insert" on public.event_likes with check ((select auth.uid()) = user_id);
alter policy "own likes delete" on public.event_likes using ((select auth.uid()) = user_id);
alter policy "own comments insert" on public.event_comments with check ((select auth.uid()) = user_id);
alter policy "own comments delete" on public.event_comments using ((select auth.uid()) = user_id);
alter policy "own completions are readable" on public.event_completions using ((select auth.uid()) = user_id);
alter policy "own completions are insertable" on public.event_completions with check ((select auth.uid()) = user_id);
alter policy "own completions are deletable" on public.event_completions using ((select auth.uid()) = user_id);
alter policy town_profiles_insert_own on public.town_profiles with check ((select auth.uid()) = user_id);
alter policy town_profiles_update_own on public.town_profiles
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
alter policy "submit clubs" on public.clubs
  with check (submitted_by = (select auth.uid()) and (status = 'pending' or public.is_admin()));
alter policy "moderate clubs" on public.clubs
  using (public.is_admin() or (submitted_by = (select auth.uid()) and status = 'pending'))
  with check (public.is_admin() or (submitted_by = (select auth.uid()) and status = 'pending'));
alter policy "delete clubs" on public.clubs
  using (public.is_admin() or (submitted_by = (select auth.uid()) and status = 'pending'));
alter policy "join club" on public.club_members with check (user_id = (select auth.uid()));
alter policy "leave club" on public.club_members using (user_id = (select auth.uid()));
alter policy "submit events" on public.club_events
  with check (submitted_by = (select auth.uid()) and (status = 'pending' or public.is_admin()));
alter policy "moderate events" on public.club_events
  using (public.is_admin() or (submitted_by = (select auth.uid()) and status = 'pending'))
  with check (public.is_admin() or (submitted_by = (select auth.uid()) and status = 'pending'));
alter policy "delete events" on public.club_events
  using (public.is_admin() or (submitted_by = (select auth.uid()) and status = 'pending'));
alter policy "rsvp insert" on public.event_rsvps with check (user_id = (select auth.uid()));
alter policy "rsvp delete" on public.event_rsvps using (user_id = (select auth.uid()));
alter policy "insert completion" on public.quest_completions with check (user_id = (select auth.uid()));
alter policy "own posting dismissals select" on public.posting_dismissals using ((select auth.uid()) = user_id);
alter policy "own posting dismissals insert" on public.posting_dismissals with check ((select auth.uid()) = user_id);
alter policy "own posting dismissals delete" on public.posting_dismissals using ((select auth.uid()) = user_id);

-- 5b. One read rule per role: these were written for every role, so bizops_ro (the read-only login,
-- which has its own read-everything rule) ran both. Now they are the app's and the website's only.
alter policy "read published items" on public.board_items to anon, authenticated;
alter policy "read events" on public.club_events to anon, authenticated
  using (status = 'approved' or submitted_by = (select auth.uid()) or public.is_admin());
alter policy "read clubs" on public.clubs to anon, authenticated
  using (status = 'approved' or submitted_by = (select auth.uid()) or public.is_admin());
alter policy "own comments select" on public.event_comments to anon, authenticated
  using ((select auth.uid()) = user_id);
alter policy "own likes select" on public.event_likes to anon, authenticated
  using ((select auth.uid()) = user_id);
alter policy "own rsvps select" on public.event_rsvps to anon, authenticated;
alter policy "own saves select" on public.event_saves to anon, authenticated;
alter policy "read evergreen" on public.evergreen_pool to anon, authenticated;
alter policy "read places" on public.places to anon, authenticated;
alter policy "own follows select" on public.town_follows to anon, authenticated
  using ((select auth.uid()) = follower_id);
alter policy town_profiles_select_own on public.town_profiles to anon, authenticated
  using ((select auth.uid()) = user_id);
-- Quests are the old app's (no rows, nothing reads or writes them): the admin-only write rule
-- doubled every read.
drop policy "write quests" on public.daily_quests;
alter policy "read quests" on public.daily_quests to anon, authenticated;

-- 5c. An index under each foreign key, so deleting an account or an Event doesn't scan the table.
-- feed_actions' is in the once-a-day migration, which looks rows up by it.
create index friendships_requested_by_idx on private.friendships (requested_by);
create index suggestion_hides_hidden_id_idx on private.suggestion_hides (hidden_id);
create index daily_standouts_event_id_idx on public.daily_standouts (event_id);
create index event_completions_event_id_idx on public.event_completions (event_id);
create index news_hides_item_id_idx on public.news_hides (item_id);
create index posting_dismissals_user_id_idx on public.posting_dismissals (user_id);
create index spotlights_place_id_idx on public.spotlights (place_id);
create index team_activities_fielded_by_idx on public.team_activities (fielded_by);
create index touch_votes_user_id_idx on public.touch_votes (user_id);

-- 6. Signed out, the app and the website call only what a page shows anyone (team, town, board,
-- activity and host pages, follow counts, the waitlist counts). A followed team's finals need an
-- account, and the rule that turns on row security for new tables is the database's own.
revoke execute on function public.my_team_finals(timestamptz) from public, anon;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
