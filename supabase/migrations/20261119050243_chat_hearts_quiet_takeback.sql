-- Hearts and replies, quieter (BP app messages 03's review, under Jesse's yes of 2026-11-18). Applied live only with
-- that yes.
--
-- Taking an emoji back now leaves its row with no emoji, an UPDATE: Realtime sends a DELETE to every phone listening,
-- and each phone with a chat open reads its chats again, so a take-back woke the whole town. An UPDATE reaches only
-- those the read rule lets see it. A row goes for good only with its message or its person.
--
-- And the two new links get their indexes, so deleting a message or an account doesn't read every row.

alter table public.chat_reactions alter column emoji drop not null;
create index chat_reactions_user_idx on public.chat_reactions (user_id);
create index chat_messages_reply_idx on public.chat_messages (reply_to) where reply_to is not null;

-- React, or take it back (p_emoji null): from 20261119041243_chat_hearts_and_replies.sql.
create or replace function public.react_chat_message(p_message uuid, p_emoji text default null)
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
    update public.chat_reactions r set emoji = null, updated_at = now()
    where r.message_id = p_message and r.user_id = me and r.emoji is not null;
  else
    insert into public.chat_reactions as r (message_id, user_id, emoji) values (p_message, me, p_emoji)
    on conflict (message_id, user_id) do update set emoji = excluded.emoji, updated_at = now()
    where r.emoji is distinct from excluded.emoji;
  end if;
end;
$$;


-- A chat's messages: from 20261119041243_chat_hearts_and_replies.sql, less any emoji taken back.
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
                     where r.message_id = m.id and r.emoji is not null
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

