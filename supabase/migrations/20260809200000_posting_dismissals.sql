-- Author only. A human must apply this migration to lxdgwhvqjqmqliobwjpi.
-- Presence-only rows mirror event_saves: composite identity, no UPDATE policy.

create table if not exists public.posting_dismissals (
    event_id   uuid not null references public.club_events (id) on delete cascade,
    user_id    uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (event_id, user_id)
);

alter table public.posting_dismissals enable row level security;

drop policy if exists "own posting dismissals select" on public.posting_dismissals;
create policy "own posting dismissals select" on public.posting_dismissals
    for select to authenticated
    using (auth.uid() = user_id);

drop policy if exists "own posting dismissals insert" on public.posting_dismissals;
create policy "own posting dismissals insert" on public.posting_dismissals
    for insert to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "own posting dismissals delete" on public.posting_dismissals;
create policy "own posting dismissals delete" on public.posting_dismissals
    for delete to authenticated
    using (auth.uid() = user_id);
