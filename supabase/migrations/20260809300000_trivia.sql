-- ============================================================================
-- Daily St. Joseph trivia.
--
-- Polls/history remain the regular briefing touch. Trivia is claimed separately,
-- so a published town day can carry one of each without weakening the existing
-- vote or RLS boundaries.
-- ============================================================================

alter table public.daily_touches
    add column if not exists correct_idx smallint;

-- The original inline constraints received PostgreSQL's generated names.
alter table public.daily_touches
    drop constraint if exists daily_touches_kind_check,
    drop constraint if exists daily_touches_check,
    drop constraint if exists daily_touches_content_check,
    drop constraint if exists daily_touches_trivia_answer_check;

alter table public.daily_touches
    add constraint daily_touches_kind_check
        check (kind in ('poll', 'history', 'trivia')),
    add constraint daily_touches_content_check
        check (
            (kind = 'poll'
                and jsonb_typeof(options) = 'array'
                and jsonb_array_length(options) > 0)
            or (kind = 'history' and body is not null)
            or (kind = 'trivia'
                and jsonb_typeof(options) = 'array'
                and jsonb_array_length(options) = 4)
        ),
    add constraint daily_touches_trivia_answer_check
        check (
            (kind = 'trivia'
                and correct_idx is not null
                and correct_idx >= 0
                and correct_idx < jsonb_array_length(options))
            or (kind in ('poll', 'history') and correct_idx is null)
        );

-- `used_on` used to be globally unique. Keep one regular touch and one trivia
-- touch per date, with each lane independently idempotent.
alter table public.daily_touches
    drop constraint if exists daily_touches_used_on_key;

create unique index if not exists daily_touches_regular_used_on_unique_idx
    on public.daily_touches (used_on)
    where used_on is not null and kind in ('poll', 'history');

create unique index if not exists daily_touches_trivia_used_on_unique_idx
    on public.daily_touches (used_on)
    where used_on is not null and kind = 'trivia';

create index if not exists daily_touches_unused_trivia_idx
    on public.daily_touches (created_at, id)
    where used_on is null and kind = 'trivia';

-- The regular briefing claim must ignore the independently claimed trivia row.
create or replace function public.claim_touch(p_date date)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_id uuid; v_pick uuid;
begin
    select id into v_id
    from public.daily_touches
    where used_on = p_date and kind in ('poll', 'history')
    limit 1;
    if v_id is not null then return v_id; end if;

    v_pick := public.pick_touch(p_date);
    if v_pick is null then return null; end if;

    update public.daily_touches set used_on = p_date
    where id = v_pick and used_on is null
    returning id into v_id;

    if v_id is null then
        select id into v_id
        from public.daily_touches
        where used_on = p_date and kind in ('poll', 'history')
        limit 1;
    end if;
    return v_id;
exception when unique_violation then
    select id into v_id
    from public.daily_touches
    where used_on = p_date and kind in ('poll', 'history')
    limit 1;
    return v_id;
end;
$$;

create or replace function public.pick_trivia(p_date date)
returns uuid
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
    select id
    from public.daily_touches
    where used_on is null and kind = 'trivia'
    order by created_at, id
    limit 1;
$$;

create or replace function public.claim_trivia(p_date date)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_id uuid; v_pick uuid;
begin
    select id into v_id
    from public.daily_touches
    where used_on = p_date and kind = 'trivia'
    limit 1;
    if v_id is not null then return v_id; end if;

    v_pick := public.pick_trivia(p_date);
    if v_pick is null then return null; end if;

    update public.daily_touches set used_on = p_date
    where id = v_pick and used_on is null
    returning id into v_id;

    if v_id is null then
        select id into v_id
        from public.daily_touches
        where used_on = p_date and kind = 'trivia'
        limit 1;
    end if;
    return v_id;
exception when unique_violation then
    select id into v_id
    from public.daily_touches
    where used_on = p_date and kind = 'trivia'
    limit 1;
    return v_id;
end;
$$;

-- Publishing is the serve boundary. RLS keeps an unclaimed trivia row hidden,
-- and the existing vote trigger rejects answers until used_on is set.
create or replace function public.claim_trivia_for_published_briefing()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
    if new.status = 'published' then
        perform public.claim_trivia(new.briefing_date);
    end if;
    return new;
end;
$$;

drop trigger if exists daily_briefings_claim_trivia on public.daily_briefings;
create trigger daily_briefings_claim_trivia
    after insert or update of status on public.daily_briefings
    for each row
    when (new.status = 'published')
    execute function public.claim_trivia_for_published_briefing();

-- Town-wide aggregate hidden by touch_votes RLS. The threshold is enforced here:
-- authenticated clients cannot obtain a percentage for a sample below ten.
create or replace function public.touch_stats(p_touch_id uuid)
returns table(correct_answer_percentage smallint, response_count bigint)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
    with trivia as (
        select id, correct_idx
        from public.daily_touches
        where id = p_touch_id
          and kind = 'trivia'
          and used_on is not null
    ),
    aggregate as (
        select count(tv.user_id)::bigint as responses,
               count(tv.user_id) filter (
                   where tv.option_idx = trivia.correct_idx
               )::bigint as correct
        from trivia
        left join public.touch_votes tv on tv.touch_id = trivia.id
    )
    select case
               when responses < 10 then null
               else round((correct::numeric * 100) / responses)::smallint
           end,
           responses
    from aggregate;
$$;

-- A narrow, quiet exception to the product's no-streak rule. This returns only
-- the caller's real consecutive correct answers. An unanswered current question
-- does not erase yesterday's count; a wrong answer ends it at zero.
create or replace function public.trivia_streak(
    p_tz text default 'America/Chicago'
)
returns integer
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
    with request_context as (
        select (now() at time zone p_tz)::date as today
    ),
    served as (
        select dt.used_on,
               tv.option_idx is not null as answered,
               tv.option_idx = dt.correct_idx as correct
        from public.daily_touches dt
        cross join request_context rc
        left join public.touch_votes tv
          on tv.touch_id = dt.id
         and tv.user_id = (select auth.uid())
        where dt.kind = 'trivia'
          and dt.used_on is not null
          and dt.used_on <= rc.today
    ),
    eligible as (
        select served.*
        from served
        cross join request_context rc
        where not (served.used_on = rc.today and not served.answered)
    ),
    numbered as (
        select row_number() over (order by used_on desc)::int as rn,
               coalesce(correct, false) as correct
        from eligible
    )
    select coalesce(
        (select min(rn) - 1 from numbered where not correct),
        (select count(*)::int from numbered),
        0
    );
$$;

revoke all on function public.claim_touch(date) from public, anon, authenticated;
revoke all on function public.pick_trivia(date) from public, anon, authenticated;
revoke all on function public.claim_trivia(date) from public, anon, authenticated;
revoke all on function public.claim_trivia_for_published_briefing() from public, anon, authenticated;
revoke all on function public.touch_stats(uuid) from public, anon;
revoke all on function public.trivia_streak(text) from public, anon;

grant execute on function public.claim_touch(date) to service_role;
grant execute on function public.pick_trivia(date) to service_role;
grant execute on function public.claim_trivia(date) to service_role;
grant execute on function public.touch_stats(uuid) to authenticated;
grant execute on function public.trivia_streak(text) to authenticated;

-- Keep the existing briefing touch contract poll/history-only now that a date can
-- also carry a trivia row. This is the latest read function plus that one filter.
create or replace function public.get_today_briefing(
    p_date date default null,
    p_tz   text default 'America/Chicago'
)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
    with request_context as (
        select coalesce(p_date, (now() at time zone p_tz)::date) as v_date
    ),
    briefing as (
        select db.*
        from public.daily_briefings db
        cross join request_context rc
        where db.briefing_date = rc.v_date
          and db.status = 'published'
        limit 1
    ),
    personal_almanac as (
        select ad.body_text, ad.format_used
        from public.almanac_daily ad
        cross join request_context rc
        where ad.user_id = (select auth.uid())
          and ad.date = rc.v_date
        order by ad.updated_at desc nulls last,
                 ad.created_at desc nulls last,
                 ad.id
        limit 1
    ),
    featured_rows as (
        select bf.rank,
               jsonb_build_object(
                   'rank', row_number() over (order by bf.rank),
                   'id', e.id,
                   'title', e.title,
                   'event_date', to_char(e.event_date, 'YYYY-MM-DD'),
                   'start_time', e.start_time,
                   'location', e.location,
                   'image_url', e.image_url,
                   'club_name', c.name,
                   'category', coalesce(e.category, 'other'),
                   'going_count', coalesce(going.n, 0)::int,
                   'going_avatars', coalesce(avatars.items, '[]'::jsonb),
                   'like_count', coalesce(likes.n, 0)::int,
                   'comment_count', coalesce(comments.n, 0)::int,
                   'rsvpd', exists (
                       select 1 from public.event_rsvps own_rsvp
                       where own_rsvp.event_id = e.id
                         and own_rsvp.user_id = (select auth.uid())
                   ),
                   'saved', exists (
                       select 1 from public.event_saves own_save
                       where own_save.event_id = e.id
                         and own_save.user_id = (select auth.uid())
                   ),
                   'liked', exists (
                       select 1 from public.event_likes own_like
                       where own_like.event_id = e.id
                         and own_like.user_id = (select auth.uid())
                   )
               ) as item
        from public.briefing_featured bf
        join briefing b on b.briefing_date = bf.briefing_date
        join public.club_events e on e.id = bf.event_id
        left join public.clubs c on c.id = e.club_id
        left join lateral (
            select count(*) as n
            from public.event_rsvps er
            where er.event_id = e.id
        ) going on true
        left join lateral (
            select coalesce(
                jsonb_agg(profile.avatar_url order by profile.user_id),
                '[]'::jsonb
            ) as items
            from (
                select er.user_id, tp.avatar_url
                from public.event_rsvps er
                join public.town_profiles tp on tp.user_id = er.user_id
                where er.event_id = e.id and tp.avatar_url is not null
                order by er.user_id
                limit 3
            ) profile
        ) avatars on true
        left join lateral (
            select count(*) as n
            from public.event_likes el
            where el.event_id = e.id
        ) likes on true
        left join lateral (
            select count(*) as n
            from public.event_comments ec
            where ec.event_id = e.id
        ) comments on true
        where e.status = 'approved' and e.submitted_by is not null
    ),
    featured_module as (
        select coalesce(jsonb_agg(fr.item order by fr.rank), '[]'::jsonb) as items
        from featured_rows fr
    ),
    touch_module as (
        select jsonb_build_object(
                   'id', dt.id,
                   'kind', dt.kind,
                   'prompt', dt.prompt,
                   'options', dt.options,
                   'body', dt.body,
                   'vote_counts',
                       case
                           when dt.kind = 'poll' and jsonb_typeof(dt.options) = 'array' then
                               coalesce(
                                   (
                                       select jsonb_agg(
                                                  (
                                                      select count(*)::int
                                                      from public.touch_votes tv
                                                      where tv.touch_id = dt.id
                                                        and tv.option_idx = option_index.idx
                                                  )
                                                  order by option_index.idx
                                              )
                                       from generate_series(
                                           0,
                                           jsonb_array_length(dt.options) - 1
                                       ) as option_index (idx)
                                   ),
                                   '[]'::jsonb
                               )
                           else '[]'::jsonb
                       end,
                   'total_votes',
                       case
                           when dt.kind = 'poll' and jsonb_typeof(dt.options) = 'array' then (
                               select count(*)::int
                               from public.touch_votes tv
                               where tv.touch_id = dt.id
                                 and tv.option_idx < jsonb_array_length(dt.options)
                           )
                           else 0
                       end,
                   'my_vote', (
                       select tv.option_idx
                       from public.touch_votes tv
                       where tv.touch_id = dt.id
                         and tv.user_id = (select auth.uid())
                       limit 1
                   )
               ) as item
        from public.daily_touches dt
        cross join request_context rc
        cross join briefing b
        where dt.used_on = rc.v_date
          and dt.kind in ('poll', 'history')
        limit 1
    ),
    spotlight_module as (
        select jsonb_build_object(
                   'id', s.id,
                   'slug', s.slug,
                   'title', s.title,
                   'blurb', s.blurb,
                   'image_url', s.image_url,
                   'place_id', s.place_id
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
               'almanac',
                   case
                       when b.briefing_date is null then null
                       else jsonb_build_object(
                           'line', pa.body_text,
                           'format', pa.format_used,
                           'source', case when pa.body_text is null then 'town' else 'personal' end,
                           'town_line', b.almanac_md
                       )
                   end,
               'weather', b.weather,
               'featured', fm.items,
               'featured_fallback',
                   case
                       when jsonb_array_length(fm.items) = 0
                            and b.fallback_body is not null then
                           jsonb_build_object(
                               'kind', 'evergreen',
                               'title', b.fallback_title,
                               'body', b.fallback_body,
                               'deeplink', b.fallback_deeplink
                           )
                       else null
                   end,
               'touch', tm.item,
               'spotlight', sm.item,
               'caught_up', jsonb_build_object(
                   'next_briefing_at',
                       ((rc.v_date + 1) + time '06:00') at time zone p_tz,
                   'label', 'New briefing at 6 AM'
               )
           )
    from request_context rc
    cross join featured_module fm
    left join briefing b on true
    left join personal_almanac pa on true
    left join touch_module tm on true
    left join spotlight_module sm on true;
$$;

revoke all on function public.get_today_briefing(date, text) from public, anon;
grant execute on function public.get_today_briefing(date, text) to authenticated;
