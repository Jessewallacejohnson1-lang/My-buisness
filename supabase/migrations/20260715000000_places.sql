-- places — the town's permanent Saint Joseph venues rendered as POI markers on the
-- map (Food & Drink and Business / Retail / Services this pass). Populated once by
-- the in-app PlaceSeeder (a Google Nearby Search sweep), then read by the map from
-- Supabase — so a map load never makes a live Places call.
--
-- Google ToS: we persist `place_id` (allowed indefinitely) + our own derived
-- category (`family`) and Google's *type data* (`primary_type`, `types`). Photos are
-- NEVER persisted — re-fetched live via `place_id` at display time, attributions shown
-- with them. name / lat / lon / address are SEEDED from Google and treated as our town
-- directory data: marquee venues are overridden with hand-curated KnownVenues coords,
-- the rest keep Google's values (a fixed, small, single-town set). If a stricter ToS
-- reading is wanted, store only place_id + type data and re-fetch name/coords live.
--
-- Shared project also backs the Expo/RN app; the `places` table does not exist there,
-- and this is additive + RLS-guarded, so no @hygge/core mirror is needed. `is_admin()`
-- is owned by the shared community baseline (migration-community.sql in the Expo twin)
-- and already exists on the live project; it is guard-created below so this file also
-- stands up on a fresh database.

create table if not exists public.places (
    id            uuid primary key default gen_random_uuid(),
    place_id      text unique,                                  -- Google Places (New) id; null for hand-curated
    name          text not null,
    lat           double precision not null,
    lon           double precision not null,
    family        text not null check (family in ('food', 'business')),
    primary_type  text,                                         -- raw Google primaryType (future granularity)
    types         text[] not null default '{}',                 -- raw Google types[]
    address       text,
    source        text not null default 'google_nearby',        -- provenance of the row
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

comment on table public.places is
    'Permanent St. Joseph POI venues (food + business) shown as map markers. Seeded once from Google Nearby Search; read by the map from Supabase (no live Places call per load). place_id + type data persisted; photos never persisted (re-fetched live).';
comment on column public.places.family is
    'POI family: food | business. Derived client-side from Google primaryType via PlaceCategoryMap. Places differ by glyph within a family, not colour.';
comment on column public.places.primary_type is
    'Raw Google Places (New) primaryType (e.g. cafe, hardware_store) — kept for future per-subtype granularity.';

create index if not exists places_family_idx on public.places (family);

-- Self-contained admin check: a no-op where is_admin() already exists (the live
-- project + the Expo community baseline), created only on a fresh DB. Kept
-- byte-identical to migration-community.sql so the two repos stay in lockstep.
do $$
begin
    if to_regprocedure('public.is_admin()') is null then
        create function public.is_admin() returns boolean language sql stable as $fn$
            select coalesce(auth.jwt() ->> 'email', '') = 'jessewallacejohnson1@icloud.com'
        $fn$;
    end if;
end $$;

alter table public.places enable row level security;

-- Reads: open to clients (non-sensitive curated town directory; the app is auth-gated).
create policy "read places" on public.places
    for select using (true);

-- Writes: admins only (the seed runs as a signed-in admin; is_admin() enforces it).
create policy "admin insert places" on public.places
    for insert with check (is_admin());
create policy "admin update places" on public.places
    for update using (is_admin()) with check (is_admin());
create policy "admin delete places" on public.places
    for delete using (is_admin());
