-- Town status notices for the Today Utility Row. `kind` is intentionally free
-- text so future tiles (school, snow, …) are just new kinds — no migration.
-- Authenticated READ; writes are service-role only (the daily 6 AM content
-- routine — NOT built here). Streams over Realtime.

create table if not exists public.town_status (
    id          uuid        primary key default gen_random_uuid(),
    town        text        not null default 'st-joseph-mn',
    kind        text        not null,                  -- 'roads' | future kinds (unconstrained)
    status      text        not null default 'active', -- provider-defined ('advisory'|'closed'|'clear'…)
    headline    text        not null,
    detail      text,
    link        text,
    active      boolean     not null default true,
    updated_at  timestamptz not null default now()
);

-- Fallback-fetch path: active notices for a town+kind, newest first.
create index if not exists town_status_lookup_idx
    on public.town_status (town, kind, active, updated_at desc);

alter table public.town_status enable row level security;

-- Authenticated users may READ. NO write policies ⇒ writes are service-role only
-- (service_role bypasses RLS). Deliberately no insert/update/delete policy.
drop policy if exists "town status readable" on public.town_status;
create policy "town status readable"
    on public.town_status for select to authenticated using (true);

-- Make it stream to the app (RLS still governs delivery). Publication starts empty.
alter publication supabase_realtime add table public.town_status;
alter table public.town_status replica identity full;

-- Seed one sample roads notice so the tile has content before the routine runs.
insert into public.town_status (town, kind, status, headline, detail, active) values
('st-joseph-mn', 'roads', 'advisory',
 'Minnesota St. lane closure',
 'Eastbound Minnesota Street is one lane between College Ave and 20th Ave through Friday for utility work. Expect short delays.',
 true);
