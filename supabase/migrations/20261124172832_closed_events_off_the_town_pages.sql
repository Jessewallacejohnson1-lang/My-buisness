-- An Event nobody can sign up for any more (club_events.signups_closed_by) leaves its host's page too (the City's, the
-- Town's, a campus calendar's), except for whoever is Going or Hearted it, as 20261123202252_signups_closed.sql did for
-- the Town feed and 20261124161211_closed_events_out_of_the_calendar.sql for the Event calendar (BP app watch-every-place
-- 49; Jesse, 2026-11-24: "yes"). town_page_by_id asks town_page, so it follows. A board's meetings never have sign-ups.
-- Everything else is as 20261108203849_every_door_carries_the_card.sql wrote it.
-- Roll back: run that file's town_page again.
create or replace function public.town_page(p_town text, p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id, 'name', p.name, 'kind', p.kind, 'picture', p.picture, 'picture_kind', p.picture_kind,
    'picture_credit', p.picture_credit,
    'events', coalesce((
      with y as (
        select e.id, e.title, e.event_date, e.start_time, e.location
        from public.club_events e
        where lower(e.source_name) = lower(p.source_name) and e.status = 'approved' and e.cancelled_at is null
          and not e.followers_only and e.event_date >= (now() at time zone 'America/Chicago')::date
          -- Nobody can sign up any more: only for whoever is Going or Hearted it.
          and (e.signups_closed_by is null
               or exists (select 1 from public.event_rsvps r where r.event_id = e.id and r.user_id = auth.uid())
               or exists (select 1 from public.event_likes l where l.event_id = e.id and l.user_id = auth.uid()))
        order by e.event_date, e.start_time
        limit 10
      )
      select jsonb_agg(x order by x ->> 'date', x ->> 'time')
      from (
        select jsonb_build_object('id', y.id, 'title', y.title, 'date', y.event_date, 'time', y.start_time,
                                  'location', y.location, 'recurrence', c.card ->> 'recurrence', 'card', c.card) as x
        -- The Event card, asked once for the list (inside-cards 27): the Event page's heart and the rest.
        from y left join private.event_cards(array(select y.id from y)) c on c.id = y.id
      ) z), '[]'::jsonb),
    'boards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'name', b.name,
        'following', exists (select 1 from public.town_follows f where f.follower_id = auth.uid()
                             and f.target_type = 'board' and f.target_id = b.id),
        'next', (select jsonb_build_object('date', e.event_date, 'time', e.start_time)
                 from public.club_events e
                 where e.source_name = b.city_name and e.draw = 1 and e.status = 'approved'
                   and e.cancelled_at is null and e.event_date >= (now() at time zone 'America/Chicago')::date
                   and public.meeting_board(e) = b.id
                 order by e.event_date, e.start_time
                 limit 1)) order by b.name)
      from public.city_boards b
      where b.town = p.town and b.city_name = p.source_name), '[]'::jsonb))
  from public.town_pages p
  where p.town = p_town and p.slug = p_slug
$$;
revoke execute on function public.town_page(text, text) from public;
grant execute on function public.town_page(text, text) to anon, authenticated;
