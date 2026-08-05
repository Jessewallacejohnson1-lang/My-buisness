-- ============================================================================
-- Phase 2: the content engine.
--
-- compose_briefing() is the whole deterministic half of the 6 AM routine -- the
-- featured picker, the touch picker and the spotlight rotation -- so that
-- whatever ends up invoking it (a scheduled agent today, pg_cron later) stays a
-- thin caller that only supplies the two things SQL cannot produce: the almanac
-- copy and an Open-Meteo weather snapshot.
--
-- Both functions are service-role only. They are security definer and execute
-- is revoked from anon and authenticated, because they write content.
-- ============================================================================

-- The composed spotlight is recorded explicitly rather than re-derived.
-- spotlights.last_shown drives the ROTATION, but it cannot identify the choice:
-- compose stamps last_shown = p_date, after which "oldest last_shown first"
-- points at a different row than the one that was chosen. The read model must
-- return what was composed, so the choice is stored.
alter table public.daily_briefings
    add column if not exists spotlight_id uuid references public.spotlights (id) on delete set null;

create or replace function public.compose_briefing(
    p_date               date,
    p_almanac_md         text,
    p_weather            jsonb default null,
    p_fallback_title     text  default null,
    p_fallback_body      text  default null,
    p_fallback_deeplink  text  default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
    -- "Happening soon" means soon. Past this, an event is not news.
    c_near_days      constant int := 14;
    -- Below this many unused touches, the routine asks for more to be written.
    c_bank_floor     constant int := 10;

    v_yesterday_lead uuid;
    v_featured       int := 0;
    v_mode           text;
    v_touch_id       uuid;
    v_spotlight_id   uuid;
    v_bank           int;
    v_title          text;
    v_body           text;
    v_deeplink       text;
begin
    if p_almanac_md is null or btrim(p_almanac_md) = '' then
        raise exception 'compose_briefing: p_almanac_md is required';
    end if;

    -- 1. The briefing row. Always composed as a draft; publishing is a separate
    --    step so a day can be reviewed in the dashboard before it goes live.
    --    Re-running for the same date refreshes the copy and keeps the picks.
    insert into public.daily_briefings (briefing_date, almanac_md, weather, status)
    values (p_date, p_almanac_md, p_weather, 'draft')
    on conflict (briefing_date) do update
        set almanac_md = excluded.almanac_md,
            weather    = coalesce(excluded.weather, public.daily_briefings.weather);

    -- 2. Featured events.
    select event_id into v_yesterday_lead
    from public.briefing_featured
    where briefing_date = p_date - 1 and rank = 1;

    delete from public.briefing_featured where briefing_date = p_date;

    with candidates as (
        select e.id,
               e.event_date,
               (select count(*) from public.event_rsvps r where r.event_id = e.id) as rsvps
        from public.club_events e
        where e.status = 'approved'
          -- Hard invariant, shared with every event display query in the app:
          -- a null submitter is seed/fabricated content and must never surface.
          and e.submitted_by is not null
          -- Trails live in club_events too, but a trail is not "happening soon".
          and coalesce(e.kind, 'event') = 'event'
          and e.event_date is not null
          and e.event_date >= p_date
    ),
    ranked as (
        select id,
               row_number() over (
                   order by
                       -- Yesterday's lead sorts last, so with a thin calendar the
                       -- two events swap places daily instead of the same one
                       -- leading every morning. It still appears -- being demoted
                       -- beats an empty slot.
                       (id is not distinct from v_yesterday_lead),
                       event_date asc,
                       rsvps desc,
                       id
               ) as rnk
        from candidates
        where event_date <= p_date + c_near_days
    )
    insert into public.briefing_featured (briefing_date, event_id, rank)
    select p_date, id, rnk from ranked where rnk <= 3;

    get diagnostics v_featured = row_count;
    v_mode := 'near';

    -- Nothing inside the window: show the single next real event, however far
    -- out. An honest "here is what is actually next" beats evergreen filler.
    if v_featured = 0 then
        insert into public.briefing_featured (briefing_date, event_id, rank)
        select p_date, e.id, 1
        from public.club_events e
        where e.status = 'approved'
          and e.submitted_by is not null
          and coalesce(e.kind, 'event') = 'event'
          and e.event_date is not null
          and e.event_date >= p_date
        order by e.event_date asc, e.id
        limit 1;

        get diagnostics v_featured = row_count;
        v_mode := case when v_featured > 0 then 'next_up' else 'evergreen' end;
    end if;

    -- 3. Fallback copy, written only when there is genuinely nothing to feature.
    --    Defaulted rather than left null: a null here is the one failure the
    --    briefing format cannot absorb, an empty module with no explanation.
    if v_featured = 0 then
        v_title    := coalesce(p_fallback_title, 'The Lake Wobegon Trail is open');
        v_body     := coalesce(p_fallback_body, 'Nothing on the calendar today. The trailhead is a few blocks from here.');
        v_deeplink := coalesce(p_fallback_deeplink, 'activities');
    end if;

    -- 4. Daily touch: oldest unused poll, claimed for this date. Idempotent --
    --    a date that already has a touch keeps it.
    select id into v_touch_id from public.daily_touches where used_on = p_date;
    if v_touch_id is null then
        update public.daily_touches
        set used_on = p_date
        where id = (
            select id from public.daily_touches
            where used_on is null and kind = 'poll'
            order by created_at, id
            limit 1
        )
        returning id into v_touch_id;
    end if;

    select count(*) into v_bank
    from public.daily_touches where used_on is null and kind = 'poll';

    -- 5. Spotlight: least recently shown active row.
    select spotlight_id into v_spotlight_id
    from public.daily_briefings where briefing_date = p_date;

    if v_spotlight_id is null then
        update public.spotlights
        set last_shown = p_date
        where id = (
            select id from public.spotlights
            where active
            order by last_shown asc nulls first, slug
            limit 1
        )
        returning id into v_spotlight_id;
    end if;

    update public.daily_briefings
    set spotlight_id       = v_spotlight_id,
        fallback_title     = v_title,
        fallback_body      = v_body,
        fallback_deeplink  = v_deeplink
    where briefing_date = p_date;

    return jsonb_build_object(
        'briefing_date',   to_char(p_date, 'YYYY-MM-DD'),
        'featured_mode',   v_mode,
        'featured_count',  v_featured,
        'touch_id',        v_touch_id,
        'touch_assigned',  v_touch_id is not null,
        'spotlight_id',    v_spotlight_id,
        'bank_remaining',  v_bank,
        -- The routine surfaces this; it does not decide what to do about it.
        'bank_low',        v_bank < c_bank_floor,
        'status',          'draft'
    );
end;
$$;

create or replace function public.publish_briefing(p_date date)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_touch uuid; v_featured int;
begin
    select id into v_touch from public.daily_touches where used_on = p_date;
    select count(*) into v_featured from public.briefing_featured where briefing_date = p_date;

    -- Refuse to publish a day with no touch AND no featured content. Better a
    -- status:'none' payload, which the client already renders calmly, than a
    -- published briefing that is visibly empty.
    if v_touch is null and v_featured = 0 then
        return jsonb_build_object('published', false,
                                  'reason', 'nothing to publish: no touch and no featured events');
    end if;

    update public.daily_briefings
    set status = 'published', published_at = coalesce(published_at, now())
    where briefing_date = p_date;

    if not found then
        return jsonb_build_object('published', false, 'reason', 'no briefing row for that date');
    end if;

    return jsonb_build_object('published', true, 'briefing_date', to_char(p_date, 'YYYY-MM-DD'));
end;
$$;

-- Which dates still need composing. The routine reads this first, so a missed
-- 6 AM run self-heals on the next one instead of leaving a permanent hole.
create or replace function public.briefings_pending(p_from date, p_days int default 2)
returns table (briefing_date date, state text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
    select d::date,
           coalesce((select db.status from public.daily_briefings db where db.briefing_date = d::date),
                    'missing')
    from generate_series(p_from, p_from + (p_days - 1), interval '1 day') as d
    where coalesce((select db.status from public.daily_briefings db where db.briefing_date = d::date),
                   'missing') <> 'published'
    order by 1;
$$;

revoke all on function public.compose_briefing(date, text, jsonb, text, text, text) from public, anon, authenticated;
revoke all on function public.publish_briefing(date) from public, anon, authenticated;
revoke all on function public.briefings_pending(date, int) from public, anon, authenticated;

grant execute on function public.compose_briefing(date, text, jsonb, text, text, text) to service_role;
grant execute on function public.publish_briefing(date) to service_role;
grant execute on function public.briefings_pending(date, int) to service_role;
