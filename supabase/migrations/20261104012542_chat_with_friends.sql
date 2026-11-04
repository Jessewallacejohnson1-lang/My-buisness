-- Chat with friends (BP app five-tabs 05; Jesse's yes at Check-in 1, 2026-11-03). Real messages: one friend
-- or a group of friends, text, a photo or an Event. Applied live only with Jesse's yes.
--
-- Who is in what lives in the private schema, as friendships do: no one can ask who accepted or declined
-- whom. Only what Realtime must deliver is public, the messages and who read how far, each behind a read rule
-- that itself says Block, Hide and Leave, so REST and live updates obey them as the functions do. Nothing is
-- written directly: every write is a function below.
--
-- Friends message freely. Someone who isn't your friend reaches your Requests: one text until you accept.
-- Delete stays remembered, so they can't ask again. Anyone under 18, or with no birthday, gets no message from
-- a non-friend: it is kept `held`, seen only by its sender, who isn't told (Jesse, 2026-11-03).

-- 1. Chats and members.
create table private.chats (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('direct', 'group')),
  -- The two ids in order, so two people have one direct chat however it starts.
  direct_key text unique,
  name text check (name is null or char_length(name) between 1 and 60),
  created_at timestamptz not null default now(),
  check ((kind = 'direct') = (direct_key is not null))
);

create table private.chat_members (
  chat_id uuid not null references private.chats (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  -- Null: a direct chat waiting in this person's Requests, unless the two are friends.
  accepted_at timestamptz,
  -- Delete on a request, or a message kept from someone under 18: gone from their list.
  declined_at timestamptz,
  left_at timestamptz,
  last_read_at timestamptz,
  primary key (chat_id, user_id)
);
create index chat_members_user_idx on private.chat_members (user_id);
revoke all on private.chats, private.chat_members from public, anon, authenticated;

-- 2. Messages, and how far each person has read: Realtime needs them public, so each has its read rule.
create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references private.chats (id) on delete cascade,
  sender_id uuid not null references auth.users (id) on delete cascade,
  -- The phone's id for it: a send retried after a lost answer is the same message.
  client_id uuid not null,
  kind text not null check (kind in ('text', 'photo', 'event')),
  body text check (char_length(body) between 1 and 2000),
  -- In the private bucket below, in the sender's own folder. Read through this row.
  photo_path text,
  photo_w int check (photo_w between 1 and 20000),
  photo_h int check (photo_h between 1 and 20000),
  -- A removed Event leaves the message, which then says it's no longer available.
  event_id uuid references public.club_events (id) on delete set null,
  -- Sent while waiting to be accepted: what the day's limit counts.
  request boolean not null default false,
  -- Never delivered: its sender alone sees it.
  held boolean not null default false,
  hidden_at timestamptz,
  created_at timestamptz not null default now(),
  unique (sender_id, client_id),
  check ((kind = 'text') = (body is not null)),
  check ((kind = 'photo') = (photo_path is not null))
);
create index chat_messages_chat_idx on public.chat_messages (chat_id, created_at desc);
create index chat_messages_event_idx on public.chat_messages (event_id) where event_id is not null;
create index chat_messages_photo_idx on public.chat_messages (photo_path) where photo_path is not null;

create table public.chat_reads (
  chat_id uuid not null references private.chats (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  read_at timestamptz not null,
  primary key (chat_id, user_id)
);

-- A report keeps its own copy, so it outlives the message and the account, and never who sent it.
create table private.chat_reports (
  id uuid primary key default gen_random_uuid(),
  message_id uuid references public.chat_messages (id) on delete set null,
  sender_name text,
  kind text not null,
  body text,
  photo_path text,
  event_title text,
  reason text not null check (reason in ('scam', 'bullying', 'violence', 'nudity', 'restricted', 'self_harm')),
  at timestamptz not null default now(),
  resolved_at timestamptz
);
revoke all on private.chat_reports from public, anon, authenticated;

-- 3. The read rules.
create function private.blocked_between(p_x uuid, p_y uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.blocks b
                 where (b.blocker_id = p_x and b.blocked_id = p_y) or (b.blocker_id = p_y and b.blocked_id = p_x))
$$;

-- In the chat now: not left, and not a request they deleted or that was kept from them.
create function private.in_chat(p_chat uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.chat_members m
                 where m.chat_id = p_chat and m.user_id = auth.uid()
                   and m.left_at is null and m.declined_at is null)
$$;

create function private.sees_message(p_chat uuid, p_sender uuid, p_held boolean, p_hidden timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_hidden is null and private.in_chat(p_chat)
     and (p_sender = auth.uid() or (not p_held and not private.blocked_between(auth.uid(), p_sender)))
$$;

revoke execute on function private.blocked_between(uuid, uuid), private.in_chat(uuid),
  private.sees_message(uuid, uuid, boolean, timestamptz) from public;
grant execute on function private.blocked_between(uuid, uuid), private.in_chat(uuid),
  private.sees_message(uuid, uuid, boolean, timestamptz) to authenticated;

alter table public.chat_messages enable row level security;
alter table public.chat_reads enable row level security;
revoke all on public.chat_messages, public.chat_reads from public, anon, authenticated;
grant select on public.chat_messages, public.chat_reads to authenticated;
create policy "chat messages read" on public.chat_messages for select to authenticated
  using (private.sees_message(chat_id, sender_id, held, hidden_at));
create policy "chat reads read" on public.chat_reads for select to authenticated
  using (private.in_chat(chat_id) and not private.blocked_between((select auth.uid()), user_id));

alter publication supabase_realtime add table public.chat_messages, public.chat_reads;

-- 4. Unfriend and Block end an acceptance: messaging starts over as a request.
create function private.chat_unaccept(p_x uuid, p_y uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update private.chat_members m set accepted_at = null
  from private.chats c
  where c.id = m.chat_id and m.user_id in (p_x, p_y)
    and c.direct_key = least(p_x, p_y)::text || ':' || greatest(p_x, p_y)::text
$$;

create function private.chat_after_unfriend()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.chat_unaccept(old.a, old.b);
  return null;
end;
$$;
create trigger chat_after_unfriend after delete on private.friendships
  for each row execute function private.chat_after_unfriend();

create function private.chat_after_block()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.chat_unaccept(new.blocker_id, new.blocked_id);
  return null;
end;
$$;
create trigger chat_after_block after insert on private.blocks
  for each row execute function private.chat_after_block();

-- Under 18 by their birthday, and no birthday counts: this rule keeps strangers out, so it errs safe.
create function private.chat_minor(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select p.birthday > (now() at time zone 'America/Chicago')::date - interval '18 years'
                   from public.town_profiles p where p.user_id = p_user and p.birthday is not null), true)
$$;

-- 5. Sending. A retry of the same client id answers the message it already made.
create function public.send_chat_message(p_chat uuid, p_to uuid, p_client uuid, p_body text default null,
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
    if private.relation(me, v_other) = 'friends' then
      update private.chat_members m set accepted_at = coalesce(m.accepted_at, now()), declined_at = null
      where m.chat_id = v_chat and m.user_id = v_other;
    elsif v_them.accepted_at is null then
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
      v_held := v_them.declined_at is not null or private.chat_minor(v_other);
      if v_held then
        update private.chat_members m set declined_at = coalesce(m.declined_at, now())
        where m.chat_id = v_chat and m.user_id = v_other;
      end if;
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

-- A group of your friends. Someone under 18 joins only if they're friends with everyone else in it; anyone else
-- you can't reach is left out. It reaches the others' lists with its first message.
create function public.start_group_chat(p_members uuid[], p_name text default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_name text := left(nullif(btrim(coalesce(p_name, '')), ''), 60);
  v_chat uuid;
  v_asked uuid[];
  v_in uuid[];
begin
  select array_agg(distinct u) into v_asked from unnest(p_members) u where u <> me;
  if coalesce(cardinality(v_asked), 0) = 0 or cardinality(v_asked) > 31 then
    raise exception 'chat_bad_group' using errcode = '22023';
  end if;
  select array_agg(u) into v_in from unnest(v_asked) u
  where private.findable(u) and private.relation(me, u) = 'friends';
  select array_agg(u) into v_in from unnest(v_in) u
  where not private.chat_minor(u)
     or not exists (select 1 from unnest(v_in) o
                    where o <> u and (private.relation(u, o) <> 'friends' or private.blocked_between(u, o)));
  if coalesce(cardinality(v_in), 0) = 0 then
    raise exception 'chat_not_available' using errcode = '42501';
  end if;
  insert into private.chats (kind, name) values ('group', v_name) returning id into v_chat;
  insert into private.chat_members (chat_id, user_id, accepted_at)
    select v_chat, u, now() from unnest(array_append(v_in, me)) u;
  return v_chat;
end;
$$;

-- 6. Reading. Your chats newest first, each with who else is in it as a neighbour's row, its last message you can
-- see and whether it's unread. `request`: it waits in your Requests. `waiting`: yours waits in theirs, which reads
-- the same whether they've seen it, deleted it or it was kept from them.
create function public.get_chats()
returns table (chat_id uuid, kind text, name text, others jsonb, last_kind text, last_body text, last_mine boolean,
               last_sender text, last_at timestamptz, unread boolean, request boolean, waiting boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  return query
    select c.id, c.kind, c.name, o.others, l.kind, l.body, l.sender_id = me, l.sender, l.created_at,
           not req.request and l.sender_id <> me and l.created_at > coalesce(m.last_read_at, '-infinity'),
           req.request,
           c.kind = 'direct' and not o.friends and o.other_accepted is null
    from private.chat_members m
    join private.chats c on c.id = m.chat_id
    cross join lateral (
      select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) as others, max(x.accepted_at) as other_accepted,
             coalesce(bool_or(r.relation = 'friends'), false) as friends
      from private.chat_members x
      cross join lateral private.neighbor_row(me, x.user_id) r
      where x.chat_id = c.id and x.user_id <> me and x.left_at is null and private.findable(x.user_id)
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
    where m.user_id = me and m.left_at is null and m.declined_at is null
      and (c.kind = 'group' or jsonb_array_length(o.others) = 1)
    order by l.created_at desc;
end;
$$;

-- A chat's messages you can see, newest first, `p_limit` at most before `p_before`. An Event's card is the same
-- card as everywhere (`private.event_cards`); null when it's gone or kept to adults from someone under 18.
create function public.get_chat_messages(p_chat uuid, p_before timestamptz default null, p_limit int default 40)
returns table (id uuid, client_id uuid, sender_id uuid, kind text, body text, photo_path text, photo_w int, photo_h int,
               card jsonb, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v_adult boolean := coalesce((select p.birthday <= (now() at time zone 'America/Chicago')::date - interval '18 years'
                               from public.town_profiles p where p.user_id = me and p.birthday is not null), true);
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
    )
    select m.id, m.client_id, m.sender_id, m.kind, m.body, m.photo_path, m.photo_w, m.photo_h, c.card, m.created_at
    from page m
    left join cards c on c.id = m.event_id
    order by m.created_at desc;
end;
$$;

-- Read up to now, and only when there's something new from someone else, so "Seen" doesn't wake everyone. A chat
-- still in your Requests reads nothing: its sender isn't told you've seen it until you accept.
create function public.mark_chat_read(p_chat uuid)
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
    on conflict on constraint chat_reads_pkey do update set read_at = excluded.read_at;
end;
$$;

-- Accept a request: it joins your chats, and they can write on.
create function public.accept_chat(p_chat uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
begin
  if not private.in_chat(p_chat) then
    raise exception 'chat_not_member' using errcode = '42501';
  end if;
  update private.chat_members m set accepted_at = coalesce(m.accepted_at, now())
  where m.chat_id = p_chat and m.user_id = me;
  perform public.mark_chat_read(p_chat);
end;
$$;

-- Delete a request: gone from your list, remembered, so its sender's next word is kept from you too.
create function public.decline_chat(p_chat uuid)
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
  delete from public.chat_reads r where r.chat_id = p_chat and r.user_id = me;
end;
$$;

create function public.leave_chat(p_chat uuid)
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
  delete from public.chat_reads r where r.chat_id = p_chat and r.user_id = me;
end;
$$;

-- 7. Report: a message you can see, kept as it was for the admin's review queue, never who reported it.
create function public.report_chat_message(p_message uuid, p_reason text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := private.need_real();
  v public.chat_messages;
begin
  select m.* into v from public.chat_messages m
  where m.id = p_message and m.sender_id <> me and private.sees_message(m.chat_id, m.sender_id, m.held, m.hidden_at);
  if v.id is null then
    raise exception 'chat_not_member' using errcode = '42501';
  end if;
  insert into private.chat_reports (message_id, sender_name, kind, body, photo_path, event_title, reason)
  select v.id, (select btrim(p.display_name) from public.town_profiles p where p.user_id = v.sender_id),
         v.kind, v.body, v.photo_path, (select e.title from public.club_events e where e.id = v.event_id), p_reason;
end;
$$;

create function public.get_chat_reports()
returns table (id uuid, message_id uuid, sender_name text, kind text, body text, photo_path text, event_title text,
               reason text, at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'admins only' using errcode = '42501';
  end if;
  return query select r.id, r.message_id, r.sender_name, r.kind, r.body, r.photo_path, r.event_title, r.reason, r.at
               from private.chat_reports r where r.resolved_at is null order by r.at;
end;
$$;

-- `p_hide` takes the message out of the chat for everyone; either way the report leaves the queue.
create function public.resolve_chat_report(p_report uuid, p_hide boolean)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'admins only' using errcode = '42501';
  end if;
  update public.chat_messages m set hidden_at = now()
  from private.chat_reports r
  where p_hide and r.id = p_report and m.id = r.message_id;
  update private.chat_reports r set resolved_at = now() where r.id = p_report;
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.send_chat_message(uuid, uuid, uuid, text, text, int, int, uuid)',
    'public.start_group_chat(uuid[], text)', 'public.get_chats()',
    'public.get_chat_messages(uuid, timestamptz, int)', 'public.mark_chat_read(uuid)', 'public.accept_chat(uuid)',
    'public.decline_chat(uuid)', 'public.leave_chat(uuid)', 'public.report_chat_message(uuid, text)',
    'public.get_chat_reports()', 'public.resolve_chat_report(uuid, boolean)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;

-- 8. Photos: a private bucket. Sent from your own folder; read only by someone who can see a message holding it,
-- its sender, or the admin for a report.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-photos', 'chat-photos', false, 10485760, array['image/jpeg'])
on conflict (id) do nothing;

create function private.sees_chat_photo(p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select split_part(p_path, '/', 1) = auth.uid()::text
      or public.is_admin()
      or exists (select 1 from public.chat_messages m
                 where m.photo_path = p_path and private.sees_message(m.chat_id, m.sender_id, m.held, m.hidden_at))
$$;
revoke execute on function private.sees_chat_photo(text) from public;
grant execute on function private.sees_chat_photo(text) to authenticated;

create policy "chat photos own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-photos' and (storage.foldername(name))[1] = (select auth.uid())::text
              and public.is_real_account());
create policy "chat photos read" on storage.objects for select to authenticated
  using (bucket_id = 'chat-photos' and private.sees_chat_photo(name));

-- 9. Typing dots: Broadcast on a private channel, `chat:<id>`, only for the people in that chat.
create function private.chat_topic_ok(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case when p_topic ~ '^chat:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then private.in_chat(substr(p_topic, 6)::uuid) else false end
$$;
revoke execute on function private.chat_topic_ok(text) from public;
grant execute on function private.chat_topic_ok(text) to authenticated;

create policy "chat typing read" on realtime.messages for select to authenticated
  using (realtime.messages.extension = 'broadcast' and private.chat_topic_ok((select realtime.topic())));
create policy "chat typing send" on realtime.messages for insert to authenticated
  with check (realtime.messages.extension = 'broadcast' and private.chat_topic_ok((select realtime.topic())));
