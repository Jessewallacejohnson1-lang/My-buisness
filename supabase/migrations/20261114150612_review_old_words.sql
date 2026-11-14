-- Review shows an edited post's old words (BP app backlog 29; Jesse, 2026-11-14: "go" to pick A on the mock,
-- references/review-old-words). A neighbour can edit a post after it was reported (town-feed 44), so Review would show
-- only the new words. list_reports now also sends the words and Place as they stood at the first report, when an
-- edit changed either since: the edit log keeps the post's words and Place at each edit check, logged before the check
-- reads the edit, so the first check after the first report holds what was reported. With none, nothing changed.
--
-- list_reports from 20261114051324_report_note.sql, line for line but for `location` in q and the two last columns.
-- Its columns change, so it is dropped and made again with its grants.
--
-- Roll back: run the list_reports block of 20261114051324_report_note.sql again.

drop function public.list_reports();
create function public.list_reports()
returns table (event_id uuid, title text, event_date date, reasons text[], reports int, first_at timestamptz,
               card jsonb, poster jsonb, notes text[], was_title text, was_place text)
language sql
stable
security definer
set search_path = ''
as $$
  with q as (
    select e.id, e.title, e.location, e.event_date, e.submitted_by, array_agg(distinct r.reason order by r.reason) as reasons,
           count(*)::int as reports, min(r.at) as first_at, max(r.at) as last_at
    from public.reports r
    join public.club_events e on e.id = r.event_id
    where public.is_admin() and e.status = 'approved'
    group by e.id
  )
  select q.id, q.title, q.event_date, q.reasons, q.reports, q.first_at, c.card, private.post_poster(q.submitted_by, null),
         array(select r.note from public.reports r where r.event_id = q.id and r.note_ok
               order by r.at desc, r.id limit 3),
         case when w.changed then w.old_title end,
         case when w.changed then w.old_location end
  from q
  left join private.event_cards(array(select q.id from q)) c on c.id = q.id
  left join lateral (
    select p.old_title, p.old_location,
           (p.old_title is distinct from q.title or p.old_location is distinct from q.location) as changed
    from private.post_edit_checks p
    where p.event_id = q.id and p.at > q.first_at
    order by p.at, p.id
    limit 1
  ) w on true
  order by q.last_at desc
$$;
revoke execute on function public.list_reports() from public, anon;
grant execute on function public.list_reports() to authenticated;
