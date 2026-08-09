-- Town Notes: daily non-civic news plus sweep provenance.
-- Author only. A human applies this migration to the remote project.

alter table public.board_items
    add column if not exists image_url text,
    add column if not exists fetched_at timestamptz;

create table if not exists public.board_sweeps (
    id            uuid primary key default gen_random_uuid(),
    swept_on      date not null,
    source_count  integer not null,
    last_swept_at timestamptz not null
);

alter table public.board_sweeps enable row level security;

revoke all on table public.board_sweeps from public, anon, authenticated;
grant select on table public.board_sweeps to authenticated;

drop policy if exists board_sweeps_select_authenticated on public.board_sweeps;
create policy board_sweeps_select_authenticated on public.board_sweeps
    as permissive for select to authenticated
    using (true);

-- No INSERT, UPDATE, or DELETE policy exists: only a trusted server-side role
-- may record sweep provenance. Re-running this update is safe because the rows
-- stop matching as soon as they become published.
update public.board_items
set status = 'published',
    published_at = now(),
    fetched_at = now()
where status = 'staging'
  and category in ('school', 'campus', 'business', 'event')
  and blurb is not null
  and source_url is not null;
