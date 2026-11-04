-- What the review of chat found (BP app five-tabs 05). Applied live only with Jesse's yes.
--
-- 1. `held` says a message was kept from its reader, which on a first message means they're under 18 or have no
--    birthday. Its sender could read that column through the API or the socket, so neither `held` nor `request`
--    can be read now; the read rule still uses them, and every read the app makes goes through a function.
-- 2. Once someone under 18 wrote first, a stranger could write back freely. Now a direct chat with anyone under 18
--    needs a friendship, whoever wrote first: their words are kept with their sender, who isn't told.
-- 3. Realtime sends a DELETE to everyone subscribed, without the read rule, carrying the row's primary key. On
--    chat_reads that key said who is in which chat. It has its own id now, and Leave and Delete keep their row: an
--    old read can't mark a newer message Seen.

revoke select on public.chat_messages from authenticated;
grant select (id, chat_id, sender_id, client_id, kind, body, photo_path, photo_w, photo_h, event_id, hidden_at, created_at)
  on public.chat_messages to authenticated;

alter table public.chat_reads drop constraint chat_reads_pkey;
alter table public.chat_reads add column id uuid not null default gen_random_uuid();
alter table public.chat_reads add primary key (id);
alter table public.chat_reads add constraint chat_reads_member_key unique (chat_id, user_id);

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
    if not private.in_chat(v_chat) then
      raise exception 'chat_not_member' using errcode = '42501';
    end if;
    select c.kind into v_chat_kind from private.chats c where c.id = v_chat;
    if v_chat_kind = 'direct' then
      select m.user_id into v_other from private.chat_members m where m.chat_id = v_chat and m.user_id <> me;
      if v_other is null or not private.findable(v_other) then
        raise exception 'chat_not_available' using errcode = '42501';
      end if;
      perform private.lock_pair(me, v_other);
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
  insert into public.chat_reads (chat_id, user_id, read_at) values (p_chat, me, now())
    on conflict on constraint chat_reads_member_key do update set read_at = excluded.read_at;
end;
$$;

create or replace function public.decline_chat(p_chat uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  update private.chat_members m set declined_at = now(), accepted_at = null
  where m.chat_id = p_chat and m.user_id = me and m.declined_at is null;
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
  where c.id = m.chat_id and c.id = p_chat and c.kind = 'group' and m.user_id = me;
end;
$$;
