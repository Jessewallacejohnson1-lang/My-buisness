-- Every door to the Event page carries its card (BP app inside-cards 27). Since inside-cards 16 the Event card
-- (private.event_cards) carries the heart and its count, but a Town page's Events and a City board's meetings sent
-- only a few facts of their own, so an Event page opened from them showed only what this visit's Town feed knew: an
-- Event outside the feed's window showed not hearted, with no count, even when you hearted it. Each row now sends its
-- Event card in `card`, asked once for the list, as get_my_going does. The row's own keys stay, so apps from before
-- the card still read it; its `recurrence` is now the card's (the same private.series_repeats answer, asked once).
--
-- town_page_by_id is town_page by another key, so it sends the card with no change of its own. Both reads stay
-- security definer: the card reads the caller's heart and Going by auth.uid(), as the chats' cards do.
--
-- Roll back: re-run 20261107145814_repeat_from_every_door.sql's town_page and board_meetings.

-- 20261107145814_repeat_from_every_door.sql but for the card on each Event row.
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

-- 20261107145814_repeat_from_every_door.sql but for the card on each meeting.
create or replace function public.board_meetings(p_board uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with y as (
    select e.id, e.title, e.event_date, e.start_time, e.location
    from public.city_boards b
    join public.club_events e on e.source_name = b.city_name and e.draw = 1
    where b.id = p_board and e.status = 'approved' and e.cancelled_at is null
      and e.event_date >= (now() at time zone 'America/Chicago')::date
      and public.meeting_board(e) = b.id
    order by e.event_date, e.start_time
    limit 20
  )
  select coalesce(jsonb_agg(x order by x ->> 'date', x ->> 'time'), '[]'::jsonb)
  from (
    select jsonb_build_object('id', y.id, 'title', y.title, 'date', y.event_date, 'time', y.start_time,
                              'location', y.location, 'recurrence', c.card ->> 'recurrence', 'card', c.card) as x
    -- The Event card, asked once for the list (inside-cards 27): the Event page's heart and the rest.
    from y left join private.event_cards(array(select y.id from y)) c on c.id = y.id
  ) z
$$;
revoke execute on function public.board_meetings(uuid) from public;
grant execute on function public.board_meetings(uuid) to anon, authenticated;
