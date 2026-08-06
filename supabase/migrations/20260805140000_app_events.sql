-- ============================================================================
-- First-party product analytics.
--
-- The app's stated position (Log.swift) is no third-party SDK, no network, no
-- per-user tracking. This table is a deliberate, scoped exception: it is the
-- ONLY per-user event stream, it lives in this project's own database, and
-- nothing is sent anywhere else. It exists to answer one question the briefing
-- format lives or dies on — do people open it daily — plus enough context to
-- tell WHICH module earned the open.
--
-- Rules that keep it honest:
--   · own-row INSERT and own-row SELECT only. A neighbour cannot read another
--     neighbour's activity, and you can always show someone their own rows.
--   · no UPDATE, no DELETE from the client — events are append-only facts.
--   · `payload` carries module context, never message bodies, never location,
--     never anything a user typed.
-- ============================================================================

create table if not exists public.app_events (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users (id) on delete cascade,
    name        text not null,
    payload     jsonb,
    occurred_at timestamptz not null default now()
);

-- The north-star query is "distinct users per day for briefing_open", and the
-- funnel queries all filter by name then bucket by day.
create index if not exists app_events_name_occurred_idx
    on public.app_events (name, occurred_at desc);

-- Per-user history, and the ON DELETE CASCADE above scans by user_id.
create index if not exists app_events_user_occurred_idx
    on public.app_events (user_id, occurred_at desc);

alter table public.app_events enable row level security;

drop policy if exists "own events insert" on public.app_events;
create policy "own events insert" on public.app_events
    for insert to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists "own events select" on public.app_events;
create policy "own events select" on public.app_events
    for select to authenticated
    using ((select auth.uid()) = user_id);

-- No update policy and no delete policy, deliberately: an analytics row is an
-- append-only fact. Deleting a user's account still removes their rows, via the
-- cascade on user_id.
