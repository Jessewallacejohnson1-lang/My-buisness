-- Going chat (BP app five-tabs 06; Jesse's "i agree to all" at Check-in 1, 2026-11-04). Everyone Going to an Event
-- and the neighbour who posted it (its host) share one chat. Applied live only with Jesse's yes.
--
-- Who is in it is never copied: it is worked out from Going itself, so leaving Going leaves the chat, with nothing
-- to fall out of step. A Going chat's chat_members row holds only your read position and your Leave; it admits no
-- one. Chat's rule stays: under 18, or no birthday, is never reached by a stranger, so neither is in a Going chat.
--
-- It lasts until a week after the Event, and goes when the Event is hidden. Words only, since strangers share it and
-- chat photos have no check. Whatever the host writes is an update, and only an update lights the red dot. No Seen
-- and no typing dots: both would show who is reading quietly.

-- 1. One chat per Event.
alter table private.chats drop constraint chats_kind_check;
alter table private.chats add constraint chats_kind_check check (kind in ('direct', 'group', 'going'));
alter table private.chats add column event_id uuid unique references public.club_events (id) on delete cascade;
alter table private.chats add constraint chats_going_event check ((kind = 'going') = (event_id is not null));

-- 2. A birthday sets once: this is what keeps someone under 18 out, so they can't rewrite theirs through the API.
-- A wrong one is fixed by hand (Jesse), which runs as the database's owner.
create function private.keep_birthday()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.birthday is not null and current_user in ('anon', 'authenticated') then
    new.birthday := old.birthday;
  end if;
  return new;
end;
$$;
create trigger town_profiles_keep_birthday before update of birthday on public.town_profiles
  for each row execute function private.keep_birthday();

-- 3. Who's in.
create function private.going_chat_open(p_event uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.club_events e
                 where e.id = p_event and e.status = 'approved' and e.kind = 'event'
                   and coalesce(e.end_at, (e.event_date + 1)::timestamp at time zone 'America/Chicago')
                       + interval '7 days' > now())
$$;

create function private.going_or_host(p_event uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_real_account() and not private.chat_minor(auth.uid())
     and (exists (select 1 from public.event_rsvps r where r.event_id = p_event and r.user_id = auth.uid())
          or exists (select 1 from public.club_events e where e.id = p_event and e.submitted_by = auth.uid()))
$$;

create or replace function private.in_chat(p_chat uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.chat_members m
                 join private.chats c on c.id = m.chat_id
                 where m.chat_id = p_chat and m.user_id = auth.uid() and c.kind <> 'going'
                   and m.left_at is null and m.declined_at is null)
      or exists (select 1 from private.chats c
                 where c.id = p_chat and c.kind = 'going' and private.going_chat_open(c.event_id)
                   and private.going_or_host(c.event_id)
                   and not exists (select 1 from private.chat_members m
                                   where m.chat_id = c.id and m.user_id = auth.uid() and m.left_at is not null))
$$;

revoke execute on function private.going_chat_open(uuid), private.going_or_host(uuid), private.keep_birthday() from public;
grant execute on function private.going_chat_open(uuid), private.going_or_host(uuid) to authenticated;

-- 4. What the Event page's row asks: whether you could be in this Event's chat, leaving Going to the app, so this
-- read can't race Attend's write. `birthday`: it asks you once.
create function public.get_going_chat(p_event uuid)
returns table (state text, is_host boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_birthday date;
begin
  if me is null or not public.is_real_account() or not private.going_chat_open(p_event) then
    return query select 'none'::text, false;
    return;
  end if;
  select p.birthday into v_birthday from public.town_profiles p where p.user_id = me;
  return query
    select case when v_birthday is null then 'birthday'
                when private.chat_minor(me) then 'none'
                else 'open' end,
           exists (select 1 from public.club_events e where e.id = p_event and e.submitted_by = me);
end;
$$;

-- The chat, opened: made with the first person in, and your Leave undone. Its row is your read position from here.
create function public.join_going_chat(p_event uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_chat uuid;
begin
  if not private.going_chat_open(p_event) or not private.going_or_host(p_event) then
    raise exception 'chat_not_going' using errcode = '42501';
  end if;
  insert into private.chats (kind, event_id) values ('going', p_event) on conflict (event_id) do nothing;
  select c.id into v_chat from private.chats c where c.event_id = p_event;
  insert into private.chat_members (chat_id, user_id, accepted_at) values (v_chat, me, now())
    on conflict on constraint chat_members_pkey do update set left_at = null;
  return v_chat;
end;
$$;

-- 5. Sending: from 20261104153317_chat_safety.sql but for a Going chat's refusals: out of it says so in its own word,
-- it takes words only, and no one person floods it.
create or replace function public.send_chat_message(p_chat uuid, p_to uuid, p_client uuid, p_body text default null,
                                         p_photo text default null, p_w int default null, p_h int default null,
                                         p_event uuid default null)
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
                                      where e.id = p_event and e.status = 'approved' and e.kind = 'event') then
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
      raise exception '%', case when v_chat_kind = 'going' then 'chat_not_going' else 'chat_not_member' end
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

  if v_chat_kind = 'going' then
    if v_kind <> 'text' then
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

  return query
    insert into public.chat_messages as m (chat_id, sender_id, client_id, kind, body, photo_path, photo_w, photo_h,
                                           event_id, request, held)
    values (v_chat, me, p_client, v_kind, v_body, p_photo, p_w, p_h, p_event, v_request, v_held)
    returning m.chat_id, m.id, m.created_at;

  update private.chat_members m set last_read_at = now(), accepted_at = coalesce(m.accepted_at, now())
  where m.chat_id = v_chat and m.user_id = me;
end;
$$;

-- 6. Your chats: from 20261104012542_chat_with_friends.sql, plus your Going chats (from Going and the Events you
-- posted, never from a member row that may be stale) with their Event's card. A Going chat names no one in `others`.
-- `unread` counts only what came after you Went; `lights` is what a dot may light for: in a Going chat, an update.
drop function public.get_chats();
create function public.get_chats()
returns table (chat_id uuid, kind text, name text, others jsonb, last_kind text, last_body text, last_mine boolean,
               last_sender text, last_at timestamptz, unread boolean, request boolean, waiting boolean,
               event jsonb, last_host boolean, is_host boolean, lights boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  return query
    with mine as materialized (
      select m.chat_id, m.accepted_at, m.last_read_at as seen_to
      from private.chat_members m
      join private.chats c on c.id = m.chat_id
      where m.user_id = me and m.left_at is null and m.declined_at is null and c.kind <> 'going'
      union all
      select c.id, now(), greatest(m.last_read_at, r.created_at)
      from private.chats c
      join public.club_events e on e.id = c.event_id
      left join public.event_rsvps r on r.event_id = e.id and r.user_id = me
      left join private.chat_members m on m.chat_id = c.id and m.user_id = me
      where c.kind = 'going' and (r.user_id is not null or e.submitted_by = me) and private.in_chat(c.id)
    ), cards as materialized (
      select k.id, k.card
      from private.event_cards(array(select c.event_id from mine x join private.chats c on c.id = x.chat_id
                                     where c.event_id is not null)) k
    )
    select c.id, c.kind, c.name, o.others, l.kind, l.body, l.sender_id = me, l.sender, l.created_at,
           not req.request and l.sender_id <> me and l.created_at > coalesce(m.seen_to, '-infinity'),
           req.request,
           c.kind = 'direct' and not o.friends and o.other_accepted is null,
           k.card,
           coalesce(l.sender_id = e.submitted_by, false),
           coalesce(e.submitted_by = me, false),
           not req.request and
             case when c.kind = 'going'
                  then e.submitted_by is distinct from me and exists (
                         select 1 from public.chat_messages n
                         where n.chat_id = c.id and n.sender_id = e.submitted_by and n.hidden_at is null
                           and n.created_at > coalesce(m.seen_to, '-infinity')
                           and not private.blocked_between(me, n.sender_id))
                  else l.sender_id <> me and l.created_at > coalesce(m.seen_to, '-infinity') end
    from mine m
    join private.chats c on c.id = m.chat_id
    left join public.club_events e on e.id = c.event_id
    left join cards k on k.id = c.event_id
    cross join lateral (
      select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) as others, max(x.accepted_at) as other_accepted,
             coalesce(bool_or(r.relation = 'friends'), false) as friends
      from private.chat_members x
      cross join lateral private.neighbor_row(me, x.user_id) r
      where c.kind <> 'going' and x.chat_id = c.id and x.user_id <> me and x.left_at is null and private.findable(x.user_id)
    ) o
    cross join lateral (
      select c.kind = 'direct' and m.accepted_at is null and not o.friends as request
    ) req
    join lateral (
      select n.kind, n.body, n.sender_id, n.created_at, btrim(p.display_name) as sender
      from public.chat_messages n
      left join public.town_profiles p on p.user_id = n.sender_id
      where n.chat_id = c.id and n.hidden_at is null
        and (n.sender_id = me or (not n.held and not private.blocked_between(me, n.sender_id)))
      order by n.created_at desc
      limit 1
    ) l on true
    where c.kind <> 'direct' or jsonb_array_length(o.others) = 1
    order by l.created_at desc;
end;
$$;

-- 7. A chat's messages: from 20261104012542_chat_with_friends.sql, plus, in a Going chat, who wrote each one (no one
-- else's row names them) and whether it's the host's. Each sender is read once; a banned one goes unnamed.
drop function public.get_chat_messages(uuid, timestamptz, int);
create function public.get_chat_messages(p_chat uuid, p_before timestamptz default null, p_limit int default 40)
returns table (id uuid, client_id uuid, sender_id uuid, kind text, body text, photo_path text, photo_w int, photo_h int,
               card jsonb, created_at timestamptz, sender jsonb, host boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_adult boolean := coalesce((select p.birthday <= (now() at time zone 'America/Chicago')::date - interval '18 years'
                               from public.town_profiles p where p.user_id = me and p.birthday is not null), true);
  v_going boolean := exists (select 1 from private.chats c where c.id = p_chat and c.kind = 'going');
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
      where e.status = 'approved' and e.kind = 'event'
        and (v_adult or not private.adults_only(e.place_entry_id, e.club_id, e.title || ' ' || coalesce(e.description, '')))
    ), senders as materialized (
      select s.sender_id, to_jsonb(r) as who
      from (select distinct p.sender_id from page p where v_going) s
      cross join lateral private.neighbor_row(me, s.sender_id) r
      where s.sender_id = me or private.findable(s.sender_id)
    )
    select m.id, m.client_id, m.sender_id, m.kind, m.body, m.photo_path, m.photo_w, m.photo_h, c.card, m.created_at,
           s.who, coalesce(m.sender_id = v_host, false)
    from page m
    left join cards c on c.id = m.event_id
    left join senders s on s.sender_id = m.sender_id
    order by m.created_at desc;
end;
$$;

-- 8. Read and Leave: from 20261104153317_chat_safety.sql. A Going chat's read writes no chat_reads, so a reader wakes
-- no one's socket and no one is shown as having read. Leave keeps you Going; the Event page's row brings you back.
create or replace function public.mark_chat_read(p_chat uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_kind text;
  v_me private.chat_members;
  v_other uuid;
begin
  select m.* into v_me from private.chat_members m where m.chat_id = p_chat and m.user_id = me;
  if v_me.chat_id is null or v_me.left_at is not null or v_me.declined_at is not null then
    return;
  end if;
  select c.kind into v_kind from private.chats c where c.id = p_chat;
  if v_kind = 'direct' and v_me.accepted_at is null then
    select m.user_id into v_other from private.chat_members m where m.chat_id = p_chat and m.user_id <> me;
    if private.relation(me, v_other) <> 'friends' then
      return;
    end if;
  end if;
  if not exists (select 1 from public.chat_messages n
                 where n.chat_id = p_chat and n.sender_id <> me and not n.held and n.hidden_at is null
                   and n.created_at > coalesce(v_me.last_read_at, '-infinity')) then
    return;
  end if;
  update private.chat_members m set last_read_at = now() where m.chat_id = p_chat and m.user_id = me;
  if v_kind <> 'going' then
    insert into public.chat_reads (chat_id, user_id, read_at) values (p_chat, me, now())
      on conflict on constraint chat_reads_member_key do update set read_at = excluded.read_at;
  end if;
end;
$$;

create or replace function public.leave_chat(p_chat uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  update private.chat_members m set left_at = now()
  from private.chats c
  where c.id = m.chat_id and c.id = p_chat and c.kind in ('group', 'going') and m.user_id = me;
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array['public.get_chats()', 'public.get_chat_messages(uuid, timestamptz, int)',
                           'public.get_going_chat(uuid)', 'public.join_going_chat(uuid)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;
