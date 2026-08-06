-- ============================================================================
-- The briefing routine, running inside the database.
--
-- Chosen after the scheduled-agent path turned out to be unreachable: cloud
-- agents cannot read local env vars, there is no Supabase MCP connector, and
-- compose_briefing/publish_briefing are service_role only — so any external
-- runner needs a full-access service-role key stored somewhere. pg_cron needs
-- none of that: it runs as the job owner inside Postgres.
--
-- HOURLY AND IDEMPOTENT, not a single 6 AM fire. Three reasons:
--   · DST-proof. "6 AM Central" is 11:00 UTC in summer and 12:00 in winter; an
--     hourly reconcile never has to know.
--   · Self-healing. A missed hour costs an hour, not a whole day with no
--     briefing and nothing to recover it.
--   · Cheap. The work is two index lookups when there is nothing to do, which
--     is 23 hours out of 24.
--
-- What it guarantees: today is PUBLISHED, tomorrow is DRAFTED. Tomorrow staying
-- a draft is deliberate — it leaves the dashboard edit window, and it means the
-- day is re-composed against a fresher calendar on the morning it goes live.
-- ============================================================================

create extension if not exists pg_cron;

-- --------------------------------------------------------------------------
-- Town copy, with no AI call and no outbound request.
--
-- evergreen_pool already holds 15 written, true, town-voice facts (it is the
-- almanac generator's fallback bank). Rotating it deterministically by date
-- gives every day a real town line for free.
--
-- Note this is `daily_briefings.almanac_md`, the TOWN-WIDE line. The line each
-- neighbour actually reads is their personalized one from `almanac_daily`,
-- generated per user by the daily-almanac edge function — unchanged by this.
-- --------------------------------------------------------------------------
create or replace function public.town_almanac_line(p_date date)
returns text
language sql
stable
set search_path to 'public', 'pg_temp'
as $$
    select coalesce(
        (select line from public.evergreen_pool
         where active
         -- Deterministic per date, so re-running a day yields the same line.
         order by md5(id::text || p_date::text)
         limit 1),
        'A quiet day in St. Joseph.'
    );
$$;

-- --------------------------------------------------------------------------
-- The job itself.
-- --------------------------------------------------------------------------
create or replace function public.run_briefing_reconcile()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
    v_today    date;
    v_tomorrow date;
    v_status   text;
    v_actions  jsonb := '[]'::jsonb;
begin
    -- Town-anchored, never the server's UTC date: after ~7pm local, UTC has
    -- already rolled over and "today" would skip a day.
    v_today    := (now() at time zone 'America/Chicago')::date;
    v_tomorrow := v_today + 1;

    -- TODAY must be published.
    select status into v_status from public.daily_briefings where briefing_date = v_today;

    if v_status is null then
        -- Nothing composed at all — a cold start, or several missed runs.
        perform public.compose_briefing(v_today, public.town_almanac_line(v_today));
        v_actions := v_actions || jsonb_build_array(
            jsonb_build_object('action', 'composed_today', 'date', v_today));
        v_status := 'draft';
    end if;

    if v_status <> 'published' then
        v_actions := v_actions || jsonb_build_array(
            jsonb_build_object('action', 'published_today',
                               'result', public.publish_briefing(v_today)));
    end if;

    -- TOMORROW gets drafted, not published.
    if not exists (select 1 from public.daily_briefings where briefing_date = v_tomorrow) then
        v_actions := v_actions || jsonb_build_array(
            jsonb_build_object('action', 'drafted_tomorrow',
                               'result', public.compose_briefing(
                                   v_tomorrow, public.town_almanac_line(v_tomorrow))));
    end if;

    return jsonb_build_object(
        'ran_at', now(),
        'town_date', v_today,
        'actions', v_actions,
        -- Surfaced so a low bank is visible in cron.job_run_details rather than
        -- only discovered when the routine runs out of polls.
        'bank_remaining_in_season', (
            select count(*) from public.daily_touches
            where used_on is null and kind = 'poll'
              and season in ('any', public.season_of(v_today))
        )
    );
end;
$$;

revoke all on function public.run_briefing_reconcile() from public, anon, authenticated;
revoke all on function public.town_almanac_line(date) from public, anon, authenticated;

-- Every hour, on the hour. pg_cron records each run in cron.job_run_details,
-- which is the observability surface — no extra logging table needed.
select cron.schedule(
    'briefing-reconcile',
    '0 * * * *',
    $job$select public.run_briefing_reconcile()$job$
);
