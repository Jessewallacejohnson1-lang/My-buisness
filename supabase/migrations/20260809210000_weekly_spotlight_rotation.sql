-- ============================================================================
-- Weekly spotlight rotation.
--
-- One append-only assignment row owns each ISO week (Monday through Sunday).
-- compose_briefing() reuses that row for every town date in the week, while
-- daily_briefings keeps the per-edition foreign key used by the existing read
-- RPC. This migration is authored for human review and is not applied here.
-- ============================================================================

alter table public.spotlights
    add column if not exists subject_type text not null default 'place'
        check (subject_type in ('place', 'business'));

create table if not exists public.spotlight_weeks (
    week_start   date primary key,
    week_key     text unique not null,
    spotlight_id uuid not null references public.spotlights (id) on delete restrict,
    created_at   timestamptz not null default now(),
    check (week_start = date_trunc('week', week_start::timestamp)::date)
);

create index if not exists spotlight_weeks_spotlight_id_idx
    on public.spotlight_weeks (spotlight_id, week_start desc);

alter table public.spotlight_weeks enable row level security;

drop policy if exists "spotlight archive select" on public.spotlight_weeks;
create policy "spotlight archive select" on public.spotlight_weeks
    for select to authenticated
    using (true);

grant select on public.spotlight_weeks to authenticated;

-- Preserve the most recently composed subject for every historical ISO week.
-- Picking the latest day keeps the current live edition from changing when this
-- migration is first applied; future weeks are assigned exactly once below.
insert into public.spotlight_weeks (week_start, week_key, spotlight_id)
select history.week_start, history.week_key, history.spotlight_id
from (
    select distinct on (date_trunc('week', db.briefing_date::timestamp)::date)
           date_trunc('week', db.briefing_date::timestamp)::date as week_start,
           to_char(db.briefing_date, 'IYYY-"W"IW') as week_key,
           db.spotlight_id
    from public.daily_briefings db
    where db.spotlight_id is not null
    order by date_trunc('week', db.briefing_date::timestamp)::date,
             db.briefing_date desc
) history
on conflict (week_start) do nothing;

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
    c_near_days      constant int := 14;
    c_bank_floor     constant int := 10;

    v_yesterday_lead uuid;
    v_featured       int := 0;
    v_mode           text;
    v_touch_id       uuid;
    v_spotlight_id   uuid;
    v_week_start     date;
    v_week_key       text;
    v_bank           int;
    v_title          text;
    v_body           text;
    v_deeplink       text;
begin
    if p_almanac_md is null or btrim(p_almanac_md) = '' then
        raise exception 'compose_briefing: p_almanac_md is required';
    end if;

    -- p_date is already the caller's town-local date. ISO week math happens on
    -- that date value, never on a UTC timestamp.
    v_week_start := date_trunc('week', p_date::timestamp)::date;
    v_week_key := to_char(p_date, 'IYYY-"W"IW');

    -- 1. The briefing row. Always composed as a draft; publishing is separate.
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
          and e.submitted_by is not null
          and coalesce(e.kind, 'event') = 'event'
          and e.event_date is not null
          and e.event_date >= p_date
    ),
    ranked as (
        select id,
               row_number() over (
                   order by
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

    -- 3. Fallback copy when there is genuinely nothing to feature.
    if v_featured = 0 then
        v_title    := coalesce(p_fallback_title, 'The Lake Wobegon Trail is open');
        v_body     := coalesce(p_fallback_body, 'Nothing on the calendar today. The trailhead is a few blocks from here.');
        v_deeplink := coalesce(p_fallback_deeplink, 'activities');
    end if;

    -- 4. Keep the hardened, seasonal, race-safe touch claim introduced by
    -- 20260805130300_touch_claim_hardening.sql.
    v_touch_id := public.claim_touch(p_date);

    select count(*) into v_bank
    from public.daily_touches
    where used_on is null
      and kind = 'poll'
      and season in ('any', public.season_of(p_date));

    -- 5. Weekly spotlight. The archive row is first-write-wins, so concurrent
    -- composers and every later day in the week resolve to the same subject.
    select sw.spotlight_id into v_spotlight_id
    from public.spotlight_weeks sw
    where sw.week_start = v_week_start;

    if v_spotlight_id is null then
        select s.id into v_spotlight_id
        from public.spotlights s
        where s.active
          and s.subject_type in ('place', 'business')
        order by s.last_shown asc nulls first, s.slug
        limit 1;

        if v_spotlight_id is not null then
            insert into public.spotlight_weeks (week_start, week_key, spotlight_id)
            values (v_week_start, v_week_key, v_spotlight_id)
            on conflict (week_start) do nothing;

            -- A racing composer may have won with a different candidate.
            select sw.spotlight_id into v_spotlight_id
            from public.spotlight_weeks sw
            where sw.week_start = v_week_start;

            update public.spotlights
            set last_shown = v_week_start
            where id = v_spotlight_id
              and last_shown is distinct from v_week_start;
        end if;
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
        'touch_season',    (select season from public.daily_touches where id = v_touch_id),
        'spotlight_id',    v_spotlight_id,
        'spotlight_week',  v_week_key,
        'bank_remaining_in_season', v_bank,
        'bank_low',        v_bank < c_bank_floor,
        'status',          'draft'
    );
end;
$$;

revoke all on function public.compose_briefing(date, text, jsonb, text, text, text)
    from public, anon, authenticated;
grant execute on function public.compose_briefing(date, text, jsonb, text, text, text)
    to service_role;
