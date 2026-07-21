-- Almanac 2.0 — per-user daily memory.
--
-- One generated almanac line per user per day, plus the fields the variety engine
-- and anti-repetition ledger read back (each user's last 7 rows). This is the
-- per-user replacement for the town-wide `daily_almanac` table (one shared row per
-- day); once the daily-almanac edge function writes here instead, `daily_almanac`
-- becomes orphaned and can be dropped in a follow-up.

create table if not exists public.almanac_daily (
    id               uuid primary key default gen_random_uuid(),
    user_id          uuid not null references auth.users (id) on delete cascade,
    date             date not null,
    body_text        text not null,
    format_used      text not null,
    places_mentioned text[] not null default '{}',
    created_at       timestamptz not null default now(),
    unique (user_id, date)
);

-- Recent-history read is `where user_id = ? order by date desc limit 7`.
-- The unique (user_id, date) index already serves it; this desc index keeps the
-- ordering cheap as rows accumulate.
create index if not exists almanac_daily_user_date_desc_idx
    on public.almanac_daily (user_id, date desc);

-- RLS: the edge function reads/writes with the service-role key, which bypasses RLS.
-- The client never needs to read this table directly, but we allow a user to read
-- their OWN history as defense-in-depth if the table is ever exposed to the Data API.
-- No insert/update/delete policy — only the service role may write.
alter table public.almanac_daily enable row level security;

create policy "almanac_daily_select_own"
    on public.almanac_daily
    for select
    to authenticated
    using ((select auth.uid()) = user_id);
