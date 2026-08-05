-- ============================================================================
-- Close anonymous read access to the social graph + pin is_admin()'s search_path
-- ============================================================================
-- NOT YET APPLIED — review, then run in the Supabase SQL editor or via
-- `supabase db push`. This changes live authorization on a project with real
-- users, so it is deliberately committed unapplied.
--
-- ── 1. Anonymous social-graph read ──────────────────────────────────────────
-- `event_rsvps`, `club_members` and `quest_completions` each carry a policy of
-- `using (true)` granted to `public`, which includes the unauthenticated `anon`
-- role. Because the anon key ships inside the app binary (and is committed to
-- this public repo, which is normal and fine for an anon key), anyone can read
-- those tables without signing in.
--
-- Verified against production on 2026-08-05:
--     GET /rest/v1/event_rsvps  ->  200, rows containing user_id + event_id
-- Today that is 2 rows. At launch it is a public "who is going to what" graph,
-- plus club membership and quest activity per user_id.
--
-- `club_members` and `quest_completions` return nothing right now only because
-- they are empty — the same policy is on them, so they leak the moment they fill.
--
-- THE FIX IS THE ROLE, NOT THE PREDICATE. Every read of these tables in the app
-- passes an access token (BlockParty/Backend/CommunityAPI.swift lines 79, 145,
-- 155, 182, 217, 317, 325, 354, 383 and SocialAPI.swift 279, 344 — all
-- `accessToken: t`), so no anonymous read path exists to break. But the app does
-- read OTHER users' rows: rsvpCounts() counts every RSVP on an event, and club
-- member_count counts every membership. So `using (true)` must stay — narrowing
-- these to own-rows-only would zero out every count in the UI.
--
-- Net effect: signed-in users see exactly what they see today; signed-out
-- callers get an empty set instead of the social graph.

drop policy if exists "read rsvps" on public.event_rsvps;
create policy "read rsvps" on public.event_rsvps
    as permissive for select to authenticated
    using (true);

drop policy if exists "read memberships" on public.club_members;
create policy "read memberships" on public.club_members
    as permissive for select to authenticated
    using (true);

drop policy if exists "read completions" on public.quest_completions;
create policy "read completions" on public.quest_completions
    as permissive for select to authenticated
    using (true);


-- ── 2. is_admin() has a mutable search_path ─────────────────────────────────
-- Flagged by the Supabase security linter (0011_function_search_path_mutable).
-- This function is the entire admin gate: it decides who can moderate clubs and
-- events and who can write `places`. A function without a pinned search_path
-- resolves unqualified names against the caller's search_path.
--
-- `auth.jwt()` is already schema-qualified, so pinning search_path to empty does
-- not change behaviour — it only removes the resolution ambiguity.
--
-- AFTER APPLYING, verify admin still works (sign in as the admin account and
-- confirm the map "+" button and club moderation still appear). If it regresses,
-- the rollback is this same function without the `set search_path` line.

create or replace function public.is_admin()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'email', '') = 'jessewallacejohnson1@icloud.com'
$$;

-- NOTE, unchanged here on purpose: admin is still a single hardcoded address, so
-- it cannot be granted or revoked without a schema change. Moving it to an
-- `admins` table or a custom JWT claim is the real fix and is a separate change.
