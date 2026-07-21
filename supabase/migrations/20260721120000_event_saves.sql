-- STAGED: not yet applied to the live project.

create table if not exists public.event_saves (
    event_id   uuid not null references public.club_events (id) on delete cascade,
    user_id    uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (event_id, user_id)
);

alter table public.event_saves enable row level security;

create policy "event saves select" on public.event_saves
    for select to authenticated using (true);
create policy "own saves insert" on public.event_saves
    for insert with check (auth.uid() = user_id);
create policy "own saves delete" on public.event_saves
    for delete using (auth.uid() = user_id);
