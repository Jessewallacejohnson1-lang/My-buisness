-- Who's Going stays private (BP app docs/plans/town-feed, ticket 19): get_today_briefing
-- (schema.sql) line for line, except going_avatars is always empty. It is security definer
-- and callable by every account, Anonymous ones included, so it handed out the photos of
-- who's Going to each featured Event. Nothing in the app draws them.
CREATE OR REPLACE FUNCTION public.get_today_briefing(p_date date DEFAULT NULL::date, p_tz text DEFAULT 'America/Chicago'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
                   'going_avatars', '[]'::jsonb,
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
$function$;
