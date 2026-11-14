-- A short note with a "Wrong info" report (BP app backlog 26). Jesse at Check-in 1, 2026-11-13: "yes to all" (mock
-- https://claude.ai/artifact/GbMjuaMFQB8QWZ7xEsNfwT). A neighbour who reports a found Event as Wrong info may say what's
-- wrong in up to 150 letters, so the admin can fix the Event instead of guessing. The note is a neighbour's own words, so
-- moderate-post reads it once before the admin sees it: list_reports shows only a note the check kept. A report still
-- keeps its Event, reason and time, and never who sent it.

-- note_ok: null not checked yet, false claimed by the check (and waiting on its answer), true kept. A no, or no answer,
-- clears the note (moderate-post), so the report stays without it.
alter table public.reports add column note text, add column note_ok boolean;

-- report_event from 20261026182034_report.sql with a third, defaulted argument, so today's app still calls it with two.
-- A note stays only with Wrong info, from an account with a sign-in (moderate-post never reads an anonymous one's), and
-- while the Event has fewer than 3, so a script can't spend the check without end; it is trimmed and cut to 150 letters
-- rather than refused, since the app and Postgres count some emoji differently.
drop function public.report_event(uuid, text);
create function public.report_event(p_event uuid, p_reason text, p_note text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_posted boolean;
  v_note text := nullif(btrim(left(btrim(p_note), 150)), '');
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  select e.submitted_by is not null and e.rechecked_at is null into v_posted
  from public.club_events e where e.id = p_event and e.status = 'approved';
  if not found then raise exception 'no such event'; end if;
  if p_reason <> 'wrong_info'
     or coalesce((select u.is_anonymous from auth.users u where u.id = auth.uid()), true)
     or (select count(*) from public.reports r where r.event_id = p_event and r.note is not null) >= 3 then
    v_note := null;
  end if;
  insert into public.reports (event_id, reason, note) values (p_event, p_reason, v_note);
  if p_reason not in ('wrong_info', 'wrong_photo') then
    insert into public.feed_actions (user_id, item_id, action) values (auth.uid(), p_event, 'reported');
  end if;
  return v_posted and p_reason not in ('wrong_info', 'wrong_photo')
         and not coalesce((select u.is_anonymous from auth.users u where u.id = auth.uid()), true);
end
$$;
revoke execute on function public.report_event(uuid, text, text) from public, anon;
grant execute on function public.report_event(uuid, text, text) to authenticated;

-- moderate-post's claim on an Event's unchecked notes (public so its service key reaches it; nobody else may run it):
-- each note comes back once, so a retry or a second report never pays for the check again.
create function public.claim_notes(p_event uuid)
returns table (id uuid, note text)
language sql
security definer
set search_path = ''
as $$
  update public.reports r set note_ok = false
  where r.event_id = p_event and r.note is not null and r.note_ok is null
  returning r.id, r.note
$$;
revoke execute on function public.claim_notes(uuid) from public, anon, authenticated;
grant execute on function public.claim_notes(uuid) to service_role;

-- list_reports from 20261107214341_review_queue_details.sql, plus the notes the check kept, the 3 newest first (an
-- empty array when none). Its columns change, so it is dropped and made again with its grants.
drop function public.list_reports();
create function public.list_reports()
returns table (event_id uuid, title text, event_date date, reasons text[], reports int, first_at timestamptz,
               card jsonb, poster jsonb, notes text[])
language sql
stable
security definer
set search_path = ''
as $$
  with q as (
    select e.id, e.title, e.event_date, e.submitted_by, array_agg(distinct r.reason order by r.reason) as reasons,
           count(*)::int as reports, min(r.at) as first_at, max(r.at) as last_at
    from public.reports r
    join public.club_events e on e.id = r.event_id
    where public.is_admin() and e.status = 'approved'
    group by e.id
  )
  select q.id, q.title, q.event_date, q.reasons, q.reports, q.first_at, c.card, private.post_poster(q.submitted_by, null),
         array(select r.note from public.reports r where r.event_id = q.id and r.note_ok
               order by r.at desc, r.id limit 3)
  from q
  left join private.event_cards(array(select q.id from q)) c on c.id = q.id
  order by q.last_at desc
$$;
revoke execute on function public.list_reports() from public, anon;
grant execute on function public.list_reports() to authenticated;
