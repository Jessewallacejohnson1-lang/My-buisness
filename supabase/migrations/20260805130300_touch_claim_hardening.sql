-- ============================================================================
-- Harden the touch claim and move compose_briefing onto it.
--
-- Two defects found running the Phase 2 gate:
--
-- 1. pick_touch() was called inside the claiming UPDATE's WHERE clause. Declared
--    VOLATILE, it was re-evaluated per candidate row, so several rows satisfied
--    `id = pick_touch(...)` at once and the UPDATE tried to stamp the same
--    used_on onto all of them -- a 23505 against the unique index that aborted
--    the whole compose. It only ever succeeded for a season with exactly one
--    remaining poll, which is why 'fall' worked and 'summer' did not.
--    Fixes: pick_touch is now STABLE, and the chosen id is resolved once into a
--    variable before the UPDATE runs.
--
-- 2. Re-running compose for a date that already had a touch could still race on
--    the unique index. claim_touch() is now idempotent: it returns the existing
--    touch for the date, and treats a unique violation as "someone else claimed
--    it" rather than an error.
--
-- Also switches the bank counter to count only touches usable in the date's
-- season, so `bank_low` warns when the season you are actually in runs dry
-- rather than when the whole bank does.
-- ============================================================================

create or replace function public.pick_touch(p_date date)
returns uuid
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
    select id from public.daily_touches
    where used_on is null
      and kind = 'poll'
      and season in ('any', public.season_of(p_date))
    order by (season = 'any'), created_at, id
    limit 1;
$$;

create or replace function public.claim_touch(p_date date)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_id uuid; v_pick uuid;
begin
    select id into v_id from public.daily_touches where used_on = p_date;
    if v_id is not null then return v_id; end if;

    v_pick := public.pick_touch(p_date);
    if v_pick is null then return null; end if;

    update public.daily_touches set used_on = p_date
    where id = v_pick
    returning id into v_id;

    return v_id;
exception when unique_violation then
    select id into v_id from public.daily_touches where used_on = p_date;
    return v_id;
end;
$$;

create or replace function public.compose_briefing(
    p_date date, p_almanac_md text, p_weather jsonb default null,
    p_fallback_title text default null, p_fallback_body text default null,
    p_fallback_deeplink text default null
) returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $$
declare
    c_near_days constant int := 14; c_bank_floor constant int := 10;
    v_yesterday_lead uuid; v_featured int := 0; v_mode text; v_touch_id uuid;
    v_spotlight_id uuid; v_bank int; v_title text; v_body text; v_deeplink text;
begin
    if p_almanac_md is null or btrim(p_almanac_md) = '' then
        raise exception 'compose_briefing: p_almanac_md is required';
    end if;

    insert into public.daily_briefings (briefing_date, almanac_md, weather, status)
    values (p_date, p_almanac_md, p_weather, 'draft')
    on conflict (briefing_date) do update
        set almanac_md = excluded.almanac_md,
            weather = coalesce(excluded.weather, public.daily_briefings.weather);

    select event_id into v_yesterday_lead from public.briefing_featured
    where briefing_date = p_date - 1 and rank = 1;

    delete from public.briefing_featured where briefing_date = p_date;

    with candidates as (
        select e.id, e.event_date,
               (select count(*) from public.event_rsvps r where r.event_id = e.id) as rsvps
        from public.club_events e
        where e.status='approved' and e.submitted_by is not null
          and coalesce(e.kind,'event')='event' and e.event_date is not null
          and e.event_date >= p_date
    ),
    ranked as (
        select id, row_number() over (
            order by (id is not distinct from v_yesterday_lead), event_date asc, rsvps desc, id) as rnk
        from candidates where event_date <= p_date + c_near_days
    )
    insert into public.briefing_featured (briefing_date, event_id, rank)
    select p_date, id, rnk from ranked where rnk <= 3;

    get diagnostics v_featured = row_count;
    v_mode := 'near';

    if v_featured = 0 then
        insert into public.briefing_featured (briefing_date, event_id, rank)
        select p_date, e.id, 1 from public.club_events e
        where e.status='approved' and e.submitted_by is not null
          and coalesce(e.kind,'event')='event' and e.event_date is not null
          and e.event_date >= p_date
        order by e.event_date asc, e.id limit 1;
        get diagnostics v_featured = row_count;
        v_mode := case when v_featured > 0 then 'next_up' else 'evergreen' end;
    end if;

    if v_featured = 0 then
        v_title := coalesce(p_fallback_title, 'The Lake Wobegon Trail is open');
        v_body := coalesce(p_fallback_body, 'Nothing on the calendar today. The trailhead is a few blocks from here.');
        v_deeplink := coalesce(p_fallback_deeplink, 'activities');
    end if;

    v_touch_id := public.claim_touch(p_date);

    select count(*) into v_bank from public.daily_touches
    where used_on is null and kind='poll' and season in ('any', public.season_of(p_date));

    select spotlight_id into v_spotlight_id from public.daily_briefings where briefing_date = p_date;
    if v_spotlight_id is null then
        update public.spotlights set last_shown = p_date
        where id = (select id from public.spotlights where active
                    order by last_shown asc nulls first, slug limit 1)
        returning id into v_spotlight_id;
    end if;

    update public.daily_briefings
    set spotlight_id = v_spotlight_id, fallback_title = v_title,
        fallback_body = v_body, fallback_deeplink = v_deeplink
    where briefing_date = p_date;

    return jsonb_build_object(
        'briefing_date', to_char(p_date,'YYYY-MM-DD'), 'featured_mode', v_mode,
        'featured_count', v_featured, 'touch_id', v_touch_id,
        'touch_season', (select season from public.daily_touches where id = v_touch_id),
        'spotlight_id', v_spotlight_id, 'bank_remaining_in_season', v_bank,
        'bank_low', v_bank < c_bank_floor, 'status', 'draft');
end;
$$;

revoke all on function public.pick_touch(date) from public, anon, authenticated;
revoke all on function public.claim_touch(date) from public, anon, authenticated;
revoke all on function public.compose_briefing(date, text, jsonb, text, text, text) from public, anon, authenticated;

grant execute on function public.pick_touch(date) to service_role;
grant execute on function public.claim_touch(date) to service_role;
grant execute on function public.compose_briefing(date, text, jsonb, text, text, text) to service_role;
