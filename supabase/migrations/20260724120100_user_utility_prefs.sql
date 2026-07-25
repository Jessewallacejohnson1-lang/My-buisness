-- Per-user Utility Row prefs: which tiles show, in what order, per-tile settings.
-- Mirrored to UserDefaults on-device for instant offline render. Mutable per-user
-- row ⇒ own-row RLS INCLUDING update (unlike the presence like/save tables).

create table if not exists public.user_utility_prefs (
    user_id     uuid        primary key references auth.users(id) on delete cascade,
    tiles       jsonb       not null default '["weather","garbage","roads","library"]'::jsonb, -- ordered id array
    settings    jsonb       not null default '{}'::jsonb,   -- per-tile, keyed by id: {"garbage":{"day":3}}
    updated_at  timestamptz not null default now()
);

alter table public.user_utility_prefs enable row level security;

drop policy if exists "own utility prefs select" on public.user_utility_prefs;
create policy "own utility prefs select" on public.user_utility_prefs
    for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "own utility prefs insert" on public.user_utility_prefs;
create policy "own utility prefs insert" on public.user_utility_prefs
    for insert to authenticated with check ((select auth.uid()) = user_id);

-- REQUIRED: the client upserts via merge-duplicates (ON CONFLICT DO UPDATE).
-- Without this UPDATE policy PostgREST upsert 42501s — the RLS trap.
drop policy if exists "own utility prefs update" on public.user_utility_prefs;
create policy "own utility prefs update" on public.user_utility_prefs
    for update to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
