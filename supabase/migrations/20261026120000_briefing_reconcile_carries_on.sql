-- ============================================================================
-- The briefing routine carries on past a failed write.
--
-- run_briefing_reconcile() makes up to three writes: compose today, publish
-- today, draft tomorrow. Before this, any one of them raising aborted the whole
-- run — a bad draft for TOMORROW could stop TODAY being published, and the only
-- trace was a bare error in cron.job_run_details.
--
-- Now each write runs in its own block. A failure rolls back that step alone
-- (a plpgsql exception block is a savepoint, so a half-composed day never
-- lands), adds ONE line to the report's `failures` array, and the run moves on
-- to the next step. The hourly schedule retries the failed step next hour.
--
-- One dependency is kept on purpose: if composing today fails there is no row
-- to publish, so publishing today is skipped rather than failing a second time.
-- That is still one line in the report, not two.
--
-- Offline proof: node supabase/tests/briefing_reconcile.test.mjs
-- ============================================================================

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
    v_failures jsonb := '[]'::jsonb;
begin
    -- Town-anchored, never the server's UTC date: after ~7pm local, UTC has
    -- already rolled over and "today" would skip a day.
    v_today    := (now() at time zone 'America/Chicago')::date;
    v_tomorrow := v_today + 1;

    -- TODAY must be published.
    select status into v_status from public.daily_briefings where briefing_date = v_today;

    if v_status is null then
        -- Nothing composed at all — a cold start, or several missed runs.
        begin
            perform public.compose_briefing(v_today, public.town_almanac_line(v_today));
            v_actions := v_actions || jsonb_build_array(
                jsonb_build_object('action', 'composed_today', 'date', v_today));
            v_status := 'draft';
        exception when others then
            v_failures := v_failures || to_jsonb(
                format('composed_today %s failed: %s (%s)', v_today, sqlerrm, sqlstate));
        end;
    end if;

    -- Still null here means composing today just failed: nothing to publish.
    if v_status is not null and v_status <> 'published' then
        begin
            v_actions := v_actions || jsonb_build_array(
                jsonb_build_object('action', 'published_today',
                                   'result', public.publish_briefing(v_today)));
        exception when others then
            v_failures := v_failures || to_jsonb(
                format('published_today %s failed: %s (%s)', v_today, sqlerrm, sqlstate));
        end;
    end if;

    -- TOMORROW gets drafted, not published.
    if not exists (select 1 from public.daily_briefings where briefing_date = v_tomorrow) then
        begin
            v_actions := v_actions || jsonb_build_array(
                jsonb_build_object('action', 'drafted_tomorrow',
                                   'result', public.compose_briefing(
                                       v_tomorrow, public.town_almanac_line(v_tomorrow))));
        exception when others then
            v_failures := v_failures || to_jsonb(
                format('drafted_tomorrow %s failed: %s (%s)', v_tomorrow, sqlerrm, sqlstate));
        end;
    end if;

    return jsonb_build_object(
        'ran_at', now(),
        'town_date', v_today,
        'actions', v_actions,
        -- One line per failed write. Empty on a healthy run.
        'failures', v_failures,
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
