-- Control Room · the read path — bizops_ro.
--
-- The bizops roadmap's non-negotiable Phase-2 prerequisite: the dashboard
-- reads Block Party data through a READ-ONLY Postgres role, never a
-- write-capable key. Defense in depth, four layers:
--   1. role default_transaction_read_only = on
--   2. SELECT-only grants, on an enumerated table list (no blanket grant)
--   3. RLS stays enabled everywhere; bizops_ro gets explicit SELECT policies
--   4. statement_timeout so a bad dashboard query cannot camp on the db
--
-- The wellness app's tables (food_logs, workouts, profiles) are deliberately
-- NOT granted — the control room has no business reading them.
--
-- LOGIN + the password are set out-of-band (never committed). To rotate:
--   alter role bizops_ro with login password '<new>';

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'bizops_ro') then
    create role bizops_ro nologin;
  end if;
end $$;

alter role bizops_ro set default_transaction_read_only = on;
alter role bizops_ro set statement_timeout = '10s';
alter role bizops_ro connection limit 5;

grant usage on schema public to bizops_ro;

do $$
declare
  t text;
begin
  foreach t in array array[
    'content_decisions', 'content_candidates', 'agent_events',
    'board_items', 'evergreen_pool', 'almanac_daily', 'town_almanac',
    'daily_briefings', 'briefing_featured', 'daily_touches', 'touch_votes',
    'spotlights', 'spotlight_weeks', 'places', 'club_events', 'event_rsvps',
    'clubs', 'club_members', 'daily_quests', 'quest_completions',
    'app_events', 'board_sweeps', 'posting_dismissals', 'town_status',
    'event_saves', 'event_likes', 'event_comments', 'town_follows',
    'user_utility_prefs', 'town_profiles'
  ] loop
    execute format('grant select on table public.%I to bizops_ro', t);
    -- RLS applies to bizops_ro (no bypassrls on Supabase), so each granted
    -- table needs an explicit allow-read policy. Policies are additive and
    -- scoped `to bizops_ro`, so app-role access is untouched.
    execute format(
      'create policy bizops_ro_read on public.%I for select to bizops_ro using (true)', t
    );
  end loop;
end $$;
