-- The weekly step for what has nothing scheduled (BP app docs/plans/nothing-scheduled, ticket 04; Jesse, 2026-11-13).
-- Each week sources/scripts/nothing_scheduled.py walks about 40 confirmed things with no Event coming and no page we
-- read (a school's activity, an open Place, a Group) for a page that gives their dates. A thing walked isn't walked
-- again for four weeks: date_walks remembers when each was last walked, found or not. `thing` is the step's own key:
-- activity:<team_activities.id>, place:<places.entry_id>, group:<clubs.id>. Only the step reads or writes it.
--
-- On Sundays the morning job's finish says how many are due, as `watch`: it reads the school activities, the Groups'
-- pages and activities_next (the school page's own pairing, co-op teams included), which it couldn't until now.

create table public.date_walks (
  thing     text primary key check (thing ~ '^(activity|place|group):.+'),
  walked_at timestamptz not null default now()
);

comment on table public.date_walks is
  'When the weekly step last walked each thing with nothing scheduled (nothing-scheduled 04). Only the step uses it.';

alter table public.date_walks enable row level security;
revoke all on public.date_walks from anon, authenticated;

grant select, insert, update on public.date_walks to watch;
create policy "watch rows" on public.date_walks to watch using (true) with check (true);

-- The Sunday count, as the morning job runs it.
grant select (id, team_id, name, kind, note) on public.team_activities to watch;
create policy "watch rows" on public.team_activities for select to watch using (true);
grant select (status, kind, own_entry_id, place_entry_id, page_url) on public.clubs to watch;
grant execute on function public.activities_next(text[]) to watch;
