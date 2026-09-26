-- Remove the almanac completely (Jesse, 2026-09-25).
--
-- The almanac card was deleted from the app on 2026-09-18, but its whole back end
-- was left running: two tables, a column, a helper, a section of the briefing RPC,
-- and a deployed edge function. Nothing had rendered it since September and the
-- personalised writer had not run since 2026-08-06. This removes the rest.
--
-- The town facts this produced are archived in docs/ST-JOSEPH-ALMANAC-ARCHIVE.md;
-- they are not recoverable from the database after this migration.
--
-- Order matters: every function that names an almanac object is replaced BEFORE
-- that object is dropped, so nothing is ever left pointing at something missing.
-- evergreen_pool is deliberately NOT touched - town_almanac_line read from it, but
-- it is the feed's own fallback pool and outlives the almanac.

-- 1. The briefing RPC stops returning an almanac section.
create or replace function public.get_today_briefing(p_date date default null::date, p_tz text default 'America/Chicago'::text)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
    with request_context as (
        select coalesce(p_date, (now() at time zone p_tz)::date) as v_date
    ),
    briefing as (
        select db.* from public.daily_briefings db
        cross join request_context rc
        where db.briefing_date = rc.v_date and db.status = 'published'
        limit 1
    ),
    featured_rows as (
        select bf.rank,
               jsonb_build_object(
                   'rank', row_number() over (order by bf.rank),
                   'id', e.id, 'title', e.title,
                   'event_date', to_char(e.event_date, 'YYYY-MM-DD'),
                   'start_time', e.start_time, 'location', e.location,
                   'image_url', e.image_url, 'club_name', c.name,
                   'category', coalesce(e.category, 'other'),
                   'going_count', coalesce(going.n, 0)::int,
                   'going_avatars', coalesce(avatars.items, '[]'::jsonb),
                   'like_count', coalesce(likes.n, 0)::int,
                   'comment_count', coalesce(comments.n, 0)::int,
                   'rsvpd', exists (select 1 from public.event_rsvps r
                                    where r.event_id = e.id and r.user_id = (select auth.uid())),
                   'saved', exists (select 1 from public.event_saves s
                                    where s.event_id = e.id and s.user_id = (select auth.uid())),
                   'liked', exists (select 1 from public.event_likes l
                                    where l.event_id = e.id and l.user_id = (select auth.uid()))
               ) as item
        from public.briefing_featured bf
        join briefing b on b.briefing_date = bf.briefing_date
        join public.club_events e on e.id = bf.event_id
        left join public.clubs c on c.id = e.club_id
        left join lateral (select count(*) as n from public.event_rsvps er where er.event_id = e.id) going on true
        left join lateral (
            select coalesce(jsonb_agg(p.avatar_url order by p.user_id), '[]'::jsonb) as items
            from (select er.user_id, tp.avatar_url
                  from public.event_rsvps er
                  join public.town_profiles tp on tp.user_id = er.user_id
                  where er.event_id = e.id and tp.avatar_url is not null
                  order by er.user_id limit 3) p
        ) avatars on true
        left join lateral (select count(*) as n from public.event_likes el where el.event_id = e.id) likes on true
        left join lateral (select count(*) as n from public.event_comments ec where ec.event_id = e.id) comments on true
        where e.status = 'approved' and e.submitted_by is not null
    ),
    featured_module as (
        select coalesce(jsonb_agg(fr.item order by fr.rank), '[]'::jsonb) as items from featured_rows fr
    ),
    touch_module as (
        select jsonb_build_object(
                   'id', dt.id, 'kind', dt.kind, 'prompt', dt.prompt,
                   'options', dt.options, 'body', dt.body,
                   'vote_counts', case when dt.kind = 'poll'
                                       then coalesce(tally.j -> 'vote_counts', '[]'::jsonb)
                                       else '[]'::jsonb end,
                   'total_votes', case when dt.kind = 'poll'
                                       then coalesce((tally.j ->> 'total_votes')::int, 0)
                                       else 0 end,
                   'my_vote', (
                       select tv.option_idx from public.touch_votes tv
                       where tv.touch_id = dt.id
                         and tv.user_id = (select auth.uid())
                         and jsonb_typeof(dt.options) = 'array'
                         and tv.option_idx < jsonb_array_length(dt.options)
                       limit 1
                   )
               ) as item
        from public.daily_touches dt
        cross join request_context rc
        cross join briefing b
        left join lateral (select public.touch_tally(dt.id) as j) tally on true
        where dt.used_on = rc.v_date
          and dt.kind in ('poll', 'history')
        limit 1
    ),
    spotlight_module as (
        select jsonb_build_object(
                   'id', s.id, 'slug', s.slug, 'title', s.title,
                   'blurb', s.blurb, 'image_url', s.image_url, 'place_id', s.place_id
               ) as item
        from public.spotlights s
        join briefing b on b.spotlight_id = s.id
        where s.active
        limit 1
    )
    select jsonb_build_object(
               'briefing_date', to_char(rc.v_date, 'YYYY-MM-DD'),
               'tz', p_tz,
               'status', case when b.briefing_date is null then 'none' else 'published' end,
               'published_at', b.published_at,
               'weather', b.weather,
               'featured', fm.items,
               'featured_fallback', case when jsonb_array_length(fm.items) = 0 and b.fallback_body is not null
                                         then jsonb_build_object('kind','evergreen','title',b.fallback_title,
                                                                 'body',b.fallback_body,'deeplink',b.fallback_deeplink)
                                         else null end,
               'touch', tm.item,
               'spotlight', sm.item,
               'caught_up', jsonb_build_object(
                   'next_briefing_at', ((rc.v_date + 1) + time '06:00') at time zone p_tz,
                   'label', 'New briefing at 6 AM')
           )
    from request_context rc
    cross join featured_module fm
    left join briefing b on true
    left join touch_module tm on true
    left join spotlight_module sm on true;
$fn$;

-- 2. compose_briefing no longer takes an almanac line. New signature, so the old
--    six-argument version is dropped after the replacement exists.
create or replace function public.compose_briefing(p_date date, p_weather jsonb default null::jsonb, p_fallback_title text default null::text, p_fallback_body text default null::text, p_fallback_deeplink text default null::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
    c_near_days constant int := 14; c_bank_floor constant int := 10;
    v_yesterday_lead uuid; v_featured int := 0; v_mode text; v_touch_id uuid;
    v_spotlight_id uuid; v_bank int; v_title text; v_body text; v_deeplink text;
begin
    insert into public.daily_briefings (briefing_date, weather, status)
    values (p_date, p_weather, 'draft')
    on conflict (briefing_date) do update
        set weather = coalesce(excluded.weather, public.daily_briefings.weather);

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
$fn$;

-- 3. The hourly reconcile stops sourcing an almanac line.
create or replace function public.run_briefing_reconcile()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
    v_today    date;
    v_tomorrow date;
    v_status   text;
    v_actions  jsonb := '[]'::jsonb;
begin
    v_today    := (now() at time zone 'America/Chicago')::date;
    v_tomorrow := v_today + 1;

    select status into v_status from public.daily_briefings where briefing_date = v_today;

    if v_status is null then
        perform public.compose_briefing(v_today);
        v_actions := v_actions || jsonb_build_array(
            jsonb_build_object('action', 'composed_today', 'date', v_today));
        v_status := 'draft';
    end if;

    if v_status <> 'published' then
        v_actions := v_actions || jsonb_build_array(
            jsonb_build_object('action', 'published_today',
                               'result', public.publish_briefing(v_today)));
    end if;

    if not exists (select 1 from public.daily_briefings where briefing_date = v_tomorrow) then
        v_actions := v_actions || jsonb_build_array(
            jsonb_build_object('action', 'drafted_tomorrow',
                               'result', public.compose_briefing(v_tomorrow)));
    end if;

    return jsonb_build_object(
        'ran_at', now(),
        'town_date', v_today,
        'actions', v_actions,
        'bank_remaining_in_season', (
            select count(*) from public.daily_touches
            where used_on is null and kind = 'poll'
              and season in ('any', public.season_of(v_today))
        )
    );
end;
$fn$;

-- 4. Now nothing references the almanac. Drop it.
drop function if exists public.compose_briefing(date, text, jsonb, text, text, text);
drop function if exists public.town_almanac_line(date);
alter table public.daily_briefings drop column if exists almanac_md;
drop table if exists public.almanac_daily;
drop table if exists public.town_almanac;
