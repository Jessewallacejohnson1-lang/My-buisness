-- Hearts and replies in a chat (BP app messages 03; Jesse's "yes agree with all" to the plan, 2026-11-18). Applied live
-- only with that yes.
--
-- A reaction is one emoji per person per message, from six: a new one takes the old one's place, and taking it back
-- deletes it. Everyone who sees the message sees its reactions, less those of anyone blocked either way. A reaction
-- never lights the unread dot: get_chats is untouched. A request not yet accepted takes none, since a reaction would
-- tell its sender you'd read it.
--
-- A reply names the message it answers. The read sends a quote of it: who wrote it and its words or its Event's title,
-- or only that it's gone once it's hidden or out of your sight.

-- 1. The message a reply answers. Realtime reads chat_messages column by column (20261104153317_chat_safety.sql).
alter table public.chat_messages add column reply_to uuid references public.chat_messages (id) on delete set null;
grant select (reply_to) on public.chat_messages to authenticated;

-- 2. Reactions. Public so Realtime can carry them; written only through react_chat_message.
-- Its key is its own id, as chat_reads' is: Realtime sends a DELETE to every phone listening with only the key, which
-- must not say who reacted to what.
create table public.chat_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.chat_messages (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  emoji text not null check (emoji in ('❤️', '😂', '😮', '😢', '😡', '👍')),
  updated_at timestamptz not null default now(),
  unique (message_id, user_id)
);
alter table public.chat_reactions enable row level security;
revoke all on public.chat_reactions from public, anon, authenticated;
grant select on public.chat_reactions to authenticated;

-- Its read rule: you see the message, and neither of you blocked the other.
create function private.sees_reaction(p_message uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.chat_messages m
                 where m.id = p_message and private.sees_message(m.chat_id, m.sender_id, m.held, m.hidden_at))
     and (p_user = auth.uid() or not private.blocked_between(auth.uid(), p_user))
$$;
revoke execute on function private.sees_reaction(uuid, uuid) from public;
grant execute on function private.sees_reaction(uuid, uuid) to authenticated;
create policy "chat reactions read" on public.chat_reactions for select to authenticated
  using (private.sees_reaction(message_id, user_id));
alter publication supabase_realtime add table public.chat_reactions;

-- 3. React, or take it back (p_emoji null).
create function public.react_chat_message(p_message uuid, p_emoji text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_chat uuid;
begin
  if p_emoji is not null and p_emoji not in ('❤️', '😂', '😮', '😢', '😡', '👍') then
    raise exception 'chat_bad_reaction' using errcode = '22023';
  end if;
  select m.chat_id into v_chat from public.chat_messages m
  where m.id = p_message and private.sees_message(m.chat_id, m.sender_id, m.held, m.hidden_at);
  if v_chat is null then
    raise exception 'chat_not_member' using errcode = '42501';
  end if;
  -- A request: a direct chat you haven't accepted, unless you're friends now, as mark_chat_read has it.
  if exists (select 1 from private.chat_members cm join private.chats c on c.id = cm.chat_id
             where cm.chat_id = v_chat and cm.user_id = me and c.kind = 'direct' and cm.accepted_at is null
               and not exists (select 1 from private.chat_members o
                               where o.chat_id = v_chat and o.user_id <> me
                                 and private.relation(me, o.user_id) = 'friends')) then
    raise exception 'chat_not_accepted' using errcode = '42501';
  end if;
  if p_emoji is null then
    delete from public.chat_reactions r where r.message_id = p_message and r.user_id = me;
  else
    insert into public.chat_reactions as r (message_id, user_id, emoji) values (p_message, me, p_emoji)
    on conflict (message_id, user_id) do update set emoji = excluded.emoji, updated_at = now()
    where r.emoji is distinct from excluded.emoji;
  end if;
end;
$$;

-- 4. Sending: from 20261104232336_group_chat.sql, plus the message it answers. A new argument makes a new function, so
-- the old one goes first; an older app's call without it still matches this one.
drop function public.send_chat_message(uuid, uuid, uuid, text, text, int, int, uuid);
create function public.send_chat_message(p_chat uuid, p_to uuid, p_client uuid, p_body text default null,
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

-- 5. A chat's messages: from 20261104232336_group_chat.sql, plus each one's reactions and the quote of the one it answers.
-- New columns change what it returns, so the old one goes first; an older app reads past them.
drop function public.get_chat_messages(uuid, timestamptz, int);
create function public.get_chat_messages(p_chat uuid, p_before timestamptz default null, p_limit int default 40)
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
      where e.status = 'approved' and e.kind = 'event'
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
                     where r.message_id = m.id
                       and (r.user_id = me or not private.blocked_between(me, r.user_id))), '[]'::jsonb)
    from page m
    left join public.chat_messages q
      on q.id = m.reply_to and private.sees_message(q.chat_id, q.sender_id, q.held, q.hidden_at)
    -- Its writer's name only where the chat would show it.
    left join public.town_profiles qp on qp.user_id = q.sender_id and (q.sender_id = me or private.findable(q.sender_id))
    -- A quoted Event's title, under the same rule as its card: kept to adults from someone under 18.
    left join public.club_events qe
      on qe.id = q.event_id and qe.status = 'approved' and qe.kind = 'event'
     and (v_adult or not private.adults_only(qe.place_entry_id, qe.club_id, qe.title || ' ' || coalesce(qe.description, '')))
    left join cards c on c.id = m.event_id
    left join senders s on s.sender_id = m.sender_id
    order by m.created_at desc;
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array['public.react_chat_message(uuid, text)',
                           'public.send_chat_message(uuid, uuid, uuid, text, text, int, int, uuid, uuid)',
                           'public.get_chat_messages(uuid, timestamptz, int)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;
