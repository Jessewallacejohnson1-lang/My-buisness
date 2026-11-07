-- The Review queue shows what each item is and why it waits (BP app launch-ready 07). Jesse, 2026-11-07, after
-- clearing the first report from his phone: "i cant go into card no photo or discription and no claim on why it was
-- held back". Each of the queue's two reads now sends the item's Event card (private.event_cards: its picture, else
-- its place's, its words, its host and its page) and who posted it (private.post_poster: first name and photo; none
-- for a found Event or a deleted account), so the queue can show them and open the Event page. Both stay the
-- admin's alone: is_admin() is in each read's own filter, and signed out can't call either.

-- list_reports from 20261026182034_report.sql, plus the first report's time, the card and the poster. Its columns
-- change, so it is dropped and made again with its grants.
drop function public.list_reports();
create function public.list_reports()
returns table (event_id uuid, title text, event_date date, reasons text[], reports int, first_at timestamptz,
               card jsonb, poster jsonb)
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
  select q.id, q.title, q.event_date, q.reasons, q.reports, q.first_at, c.card, private.post_poster(q.submitted_by, null)
  from q
  left join private.event_cards(array(select q.id from q)) c on c.id = q.id
  order by q.last_at desc
$$;
revoke execute on function public.list_reports() from public, anon;
grant execute on function public.list_reports() to authenticated;

-- What waits for the admin's yes: a neighbour's post the instant check didn't pass on (moderate-post leaves it
-- pending when the model gives no answer, or when claim_submit never let it through), or a found Event that waits.
-- checked_at is sent as it is: set means the check was asked and gave no answer, none means it was never checked.
-- Same order as the app's old read of club_events: soonest first, then newest.
create function public.list_held()
returns table (id uuid, kind text, checked_at timestamptz, card jsonb, poster jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  with q as (
    select e.id, e.kind, e.checked_at, e.submitted_by, e.event_date, e.created_at
    from public.club_events e
    where public.is_admin() and e.status = 'pending'
  )
  select q.id, q.kind, q.checked_at, c.card, private.post_poster(q.submitted_by, null)
  from q
  left join private.event_cards(array(select q.id from q)) c on c.id = q.id
  order by q.event_date asc nulls last, q.created_at desc
$$;
revoke execute on function public.list_held() from public, anon;
grant execute on function public.list_held() to authenticated;
