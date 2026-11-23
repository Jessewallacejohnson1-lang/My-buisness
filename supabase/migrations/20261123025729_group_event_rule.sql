-- A Group's Event is held to those who see the Group on the paths that don't read as the caller (BP app
-- docs/plans/start-a-group, assets/04-second-fix-pass.md, fault 2). private.sees_members (20261122204701) says who; the
-- Town feed, the Event page, Search, Going, You and every other read under "read events" follow it already. This file
-- brings the rest to it: a closed, waiting, turned-down or private Group's Event gives nothing away in a chat.
--   1. private.sees_group_event: that rule for one Event, by its id; every Event that isn't a Group's passes.
--   2. going_chat_open from 20261104172812_going_chat.sql: every door to a Going chat asks it (private.in_chat,
--      get_chats, get_going_chat, join_going_chat), so the chat, and the card get_chats draws for it, go with the Event.
--   3. send_chat_message from 20261119041243_chat_hearts_and_replies.sql: only an Event its sender sees.
--   4. get_chat_messages from 20261119050243_chat_hearts_quiet_takeback.sql: a shared Event's card, and its title in a
--      quote, only to a reader who sees it. Anyone else gets the card of an Event that's gone.
--   5. "rsvp insert": Going to a Group's Event only from someone who sees it.
--   6. mute_host from 20261030000956_news_menu.sql: it keeps the host's name where the caller reads it.
-- Each function is line for line but for that one test.

-- 1. Its poster always sees their own, as "read events" says.
create function private.sees_group_event(p_event uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from public.club_events e
    where e.id = p_event and e.club_id is not null and e.submitted_by is distinct from auth.uid()
      and not private.sees_members(e.club_id))
$$;
revoke execute on function private.sees_group_event(uuid) from public;
grant execute on function private.sees_group_event(uuid) to anon, authenticated;

-- 2.
create or replace function private.going_chat_open(p_event uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.club_events e
                 where e.id = p_event and e.status = 'approved' and e.kind = 'event'
                   and private.sees_group_event(e.id)
                   and coalesce(e.end_at, (e.event_date + 1)::timestamp at time zone 'America/Chicago')
                       + interval '7 days' > now())
$$;

-- 3.
create or replace function public.send_chat_message(p_chat uuid, p_to uuid, p_client uuid, p_body text default null,
                                         p_photo text default null, p_w int default null, p_h int default null,
                                         p_event uuid default null, p_reply uuid default null)
returns table (chat_id uuid, id uuid, created_at timestamptz)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_body text := nullif(btrim(coalesce(p_body, '')), '');
  v_kind text;
  v_chat uuid := p_chat;
  v_chat_kind text;
  v_other uuid;
  v_key text;
  v_them private.chat_members;
  v_request boolean := false;
  v_held boolean := false;
  v_young boolean := false;
  v_reply uuid;
begin
  v_kind := case when v_body is not null and p_photo is null and p_event is null then 'text'
                 when v_body is null and p_photo is not null and p_event is null then 'photo'
                 when v_body is null and p_photo is null and p_event is not null then 'event' end;
  if v_kind is null or p_client is null or char_length(v_body) > 2000 then
    raise exception 'chat_bad_message' using errcode = '22023';
  end if;
  if v_kind = 'photo' and (p_photo !~ ('^' || me::text || '/[0-9a-f-]{36}\.jpg$') or p_w is null or p_h is null) then
    raise exception 'chat_bad_message' using errcode = '22023';
  end if;
  if v_kind = 'event' and not exists (select 1 from public.club_events e
                                      where e.id = p_event and e.status = 'approved' and e.kind = 'event'
                                        and private.sees_group_event(e.id)) then
    raise exception 'chat_event_gone' using errcode = '22023';
  end if;

  return query select m.chat_id, m.id, m.created_at from public.chat_messages m
               where m.sender_id = me and m.client_id = p_client;
  if found then return; end if;

  if v_chat is null then
    if p_to is null or p_to = me or not private.findable(p_to) then
      raise exception 'chat_not_available' using errcode = '42501';
    end if;
    perform private.lock_pair(me, p_to);
    v_key := least(me, p_to)::text || ':' || greatest(me, p_to)::text;
    insert into private.chats (kind, direct_key) values ('direct', v_key) on conflict (direct_key) do nothing;
    select c.id into v_chat from private.chats c where c.direct_key = v_key;
    -- Writing to someone again takes back your own Delete.
    insert into private.chat_members (chat_id, user_id, accepted_at) values (v_chat, me, now())
      on conflict on constraint chat_members_pkey do update
      set accepted_at = coalesce(private.chat_members.accepted_at, excluded.accepted_at), declined_at = null;
    insert into private.chat_members (chat_id, user_id) values (v_chat, p_to)
      on conflict on constraint chat_members_pkey do nothing;
    v_other := p_to;
    v_chat_kind := 'direct';
  else
    select c.kind into v_chat_kind from private.chats c where c.id = v_chat;
    if not private.in_chat(v_chat) then
      raise exception '%', case when v_chat_kind in ('going', 'club') then 'chat_not_going' else 'chat_not_member' end
        using errcode = '42501';
    end if;
    if v_chat_kind = 'direct' then
      select m.user_id into v_other from private.chat_members m where m.chat_id = v_chat and m.user_id <> me;
      if v_other is null or not private.findable(v_other) then
        raise exception 'chat_not_available' using errcode = '42501';
      end if;
      perform private.lock_pair(me, v_other);
    end if;
  end if;

  if v_chat_kind in ('going', 'club') then
    if v_kind = 'photo' or (v_kind = 'event' and v_chat_kind = 'going') then
      raise exception 'chat_text_only' using errcode = '42501';
    end if;
    if (select count(*) from public.chat_messages m
        where m.chat_id = v_chat and m.sender_id = me and m.created_at > now() - interval '10 minutes') >= 30 then
      raise exception 'chat_slow_down' using errcode = '42501';
    end if;
  end if;

  if v_chat_kind = 'direct' then
    select m.* into v_them from private.chat_members m where m.chat_id = v_chat and m.user_id = v_other;
    v_young := private.chat_minor(v_other) or private.chat_minor(me);
    if private.relation(me, v_other) = 'friends' then
      update private.chat_members m set accepted_at = coalesce(m.accepted_at, now()), declined_at = null
      where m.chat_id = v_chat and m.user_id = v_other;
    elsif v_them.accepted_at is null or v_young then
      if v_kind <> 'text' then
        raise exception 'chat_text_only' using errcode = '42501';
      end if;
      if exists (select 1 from public.chat_messages m where m.chat_id = v_chat and m.sender_id = me) then
        raise exception 'chat_waiting' using errcode = '42501';
      end if;
      if (select count(*) from public.chat_messages m
          where m.sender_id = me and m.request and m.created_at > now() - interval '24 hours') >= 20 then
        raise exception 'chat_limit' using errcode = '42501';
      end if;
      v_request := true;
      -- Kept with its sender: a chat with nothing its reader can see isn't on their list.
      v_held := v_them.declined_at is not null or v_young;
    end if;
  end if;

  -- The message it answers: only one in this chat that you can see. Gone or hidden meanwhile, the words still go.
  select m.id into v_reply from public.chat_messages m
  where m.id = p_reply and m.chat_id = v_chat and private.sees_message(m.chat_id, m.sender_id, m.held, m.hidden_at);

  return query
    insert into public.chat_messages as m (chat_id, sender_id, client_id, kind, body, photo_path, photo_w, photo_h,
                                           event_id, request, held, reply_to)
    values (v_chat, me, p_client, v_kind, v_body, p_photo, p_w, p_h, p_event, v_request, v_held, v_reply)
    returning m.chat_id, m.id, m.created_at;

  update private.chat_members m set last_read_at = now(), accepted_at = coalesce(m.accepted_at, now())
  where m.chat_id = v_chat and m.user_id = me;
end;
$$;

-- 4.
create or replace function public.get_chat_messages(p_chat uuid, p_before timestamptz default null, p_limit int default 40)
returns table (id uuid, client_id uuid, sender_id uuid, kind text, body text, photo_path text, photo_w int, photo_h int,
               card jsonb, created_at timestamptz, sender jsonb, host boolean, reply jsonb, reactions jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_adult boolean := coalesce((select p.birthday <= (now() at time zone 'America/Chicago')::date - interval '18 years'
                               from public.town_profiles p where p.user_id = me and p.birthday is not null), true);
  v_named boolean := exists (select 1 from private.chats c where c.id = p_chat and c.kind in ('going', 'club'));
  v_host uuid := (select e.submitted_by from private.chats c join public.club_events e on e.id = c.event_id
                  where c.id = p_chat);
begin
  return query
    with page as materialized (
      select m.* from public.chat_messages m
      where m.chat_id = p_chat and private.sees_message(m.chat_id, m.sender_id, m.held, m.hidden_at)
        and (p_before is null or m.created_at < p_before)
      order by m.created_at desc
      limit least(greatest(coalesce(p_limit, 40), 1), 100)
    ), cards as (
      select c.id, c.card
      from private.event_cards(array(select e.event_id from page e where e.event_id is not null)) c
      join public.club_events e on e.id = c.id
      where e.status = 'approved' and e.kind = 'event' and private.sees_group_event(e.id)
        and (v_adult or not private.adults_only(e.place_entry_id, e.club_id, e.title || ' ' || coalesce(e.description, '')))
    ), senders as materialized (
      select s.sender_id, to_jsonb(r) as who
      from (select distinct p.sender_id from page p where v_named) s
      cross join lateral private.neighbor_row(me, s.sender_id) r
      where s.sender_id = me or private.findable(s.sender_id)
    )
    select m.id, m.client_id, m.sender_id, m.kind, m.body, m.photo_path, m.photo_w, m.photo_h, c.card, m.created_at,
           s.who, coalesce(m.sender_id = v_host, false),
           case when m.reply_to is null then null
                when q.id is null then jsonb_build_object('gone', true)
                else jsonb_build_object('gone', false, 'sender_id', q.sender_id, 'kind', q.kind, 'name', qp.display_name,
                                        'body', case q.kind when 'text' then left(q.body, 200)
                                                            when 'event' then qe.title end) end,
           coalesce((select jsonb_agg(jsonb_build_object('user_id', r.user_id, 'emoji', r.emoji) order by r.updated_at, r.user_id)
                     from public.chat_reactions r
                     where r.message_id = m.id and r.emoji is not null
                       and (r.user_id = me or not private.blocked_between(me, r.user_id))), '[]'::jsonb)
    from page m
    left join public.chat_messages q
      on q.id = m.reply_to and private.sees_message(q.chat_id, q.sender_id, q.held, q.hidden_at)
    -- Its writer's name only where the chat would show it.
    left join public.town_profiles qp on qp.user_id = q.sender_id and (q.sender_id = me or private.findable(q.sender_id))
    -- A quoted Event's title, under the same rules as its card: a Group's only to who sees it, and one kept to adults
    -- not to someone under 18.
    left join public.club_events qe
      on qe.id = q.event_id and qe.status = 'approved' and qe.kind = 'event' and private.sees_group_event(qe.id)
     and (v_adult or not private.adults_only(qe.place_entry_id, qe.club_id, qe.title || ' ' || coalesce(qe.description, '')))
    left join cards c on c.id = m.event_id
    left join senders s on s.sender_id = m.sender_id
    order by m.created_at desc;
end;
$$;

-- 5.
alter policy "rsvp insert" on public.event_rsvps
  with check (user_id = (select auth.uid()) and private.sees_group_event(event_id));

-- 6.
create or replace function public.mute_host(p_item uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_host text;
  v_name text;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  select coalesce(e.club_id::text, e.source_name, e.submitted_by::text),
         coalesce(c.name, e.source_name)
    into v_host, v_name
  from public.club_events e
  left join public.clubs c on c.id = coalesce(e.club_id,
    case when e.submitted_by is null and e.source_name is not null
         then private.event_group(e.source_name, e.place_entry_id, e.title) end)
  where e.id = p_item and private.sees_group_event(e.id);
  -- A news item mutes its place, named as its card names it (news-menu).
  if v_host is null then
    select b.source_name, b.source_name into v_host, v_name from public.board_items b where b.id = p_item;
  end if;
  if v_host is null or v_name is null then raise exception 'nothing to mute'; end if;
  insert into public.feed_mutes (user_id, host, name) values (auth.uid(), v_host, v_name)
  on conflict (user_id, host) do update set name = excluded.name;
  return v_host;
end
$$;
