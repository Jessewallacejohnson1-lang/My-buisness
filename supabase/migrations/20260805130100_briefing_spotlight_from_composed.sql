-- ============================================================================
-- Re-point the briefing read model's spotlight module at daily_briefings
-- .spotlight_id, which compose_briefing now records. Everything else in this
-- function is unchanged from 20260805120100.
-- ============================================================================

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
                   -- Densified, NOT bf.rank. A featured row whose event was since
                   -- unapproved or had its submitter cleared is dropped by the WHERE
                   -- below, which would otherwise emit a gap (ranks 1,3). The contract
                   -- guarantees the client 1..n contiguous. WHERE is applied before
                   -- window functions, so this numbers the surviving rows.
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
                       select 1
                       from public.event_rsvps own_rsvp
                       where own_rsvp.event_id = e.id
                         and own_rsvp.user_id = (select auth.uid())
                   ),
                   'saved', exists (
                       select 1
                       from public.event_saves own_save
                       where own_save.event_id = e.id
                         and own_save.user_id = (select auth.uid())
                   ),
                   'liked', exists (
                       select 1
                       from public.event_likes own_like
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
            select coalesce(jsonb_agg(profile.avatar_url order by profile.user_id), '[]'::jsonb) as items
            from (
                select er.user_id, tp.avatar_url
                from public.event_rsvps er
                join public.town_profiles tp on tp.user_id = er.user_id
                where er.event_id = e.id
                  and tp.avatar_url is not null
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
        where e.status = 'approved'
          and e.submitted_by is not null
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
                   -- Bounded to valid option indices so total_votes always equals
                   -- sum(vote_counts). touch_votes only checks option_idx >= 0, so an
                   -- out-of-range index would otherwise inflate the total without
                   -- appearing in any bar, and the percentages would not close.
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
        -- Read the spotlight the routine COMPOSED, not a fresh rotation pick.
        -- compose_briefing stamps last_shown, after which "oldest last_shown
        -- first" resolves to a different row than the one chosen for this date.
        -- s.active is still honoured so a spotlight can be pulled same-day.
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
