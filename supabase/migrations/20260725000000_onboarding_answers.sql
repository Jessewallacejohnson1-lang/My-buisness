-- Onboarding answers on town_profiles.
--
-- The 20-screen onboarding collects six answers. None of these columns existed; every
-- one is added here. Additive and nullable only — no existing column is touched, no data
-- is rewritten, and no default backfills anything, so a profile written before this
-- migration stays exactly as it was.
--
-- All six are nullable ON PURPOSE. The flow runs pre-auth and flushes once at sign-in,
-- so a row can legitimately exist with none of them set (a user who signed in through
-- "I already have an account" and never answered). Making them NOT NULL with defaults
-- would invent answers nobody gave, which the repo's "real data only" rule forbids.
--
-- RLS: town_profiles already has own-row select/insert/update policies, which is what
-- the client's PostgREST upsert (`resolution=merge-duplicates`) needs — an upsert emits
-- ON CONFLICT DO UPDATE and returns 42501 without an UPDATE policy. No policy change
-- is required here, and none is made.
--
-- APPLIED to the live project (lxdgwhvqjqmqliobwjpi) on 2026-07-25 via the Management
-- API, and verified by reading back information_schema.columns.

alter table public.town_profiles
    -- S05/S06 — 'live_here' | 'moving_here' | 'student' | 'live_nearby' | 'visiting'
    add column if not exists connection text,

    -- S08 — 1..5, how well the user knows town. Drives S20's line and feed defaults.
    add column if not exists town_level smallint,

    -- S09/S10 — multi-select. Mirrors the shape of the existing `interests text[]`
    -- column, but is a DIFFERENT question: interests are topics, motivations are why
    -- they came. Kept separate rather than merged into interests.
    add column if not exists motivations text[],

    -- S12 — 'weekly' | 'few' | 'daily' | 'instant'. Sets the notification default.
    add column if not exists notify_cadence text,

    -- S17/S18 — a FREE badge tier. There is no payment anywhere in the flow, so this
    -- is not an entitlement and must not be treated as one.
    add column if not exists founding_member boolean,

    -- S19 — 'this_week' | 'the_map'. Routes the post-onboarding landing tab.
    add column if not exists landing_choice text;

-- Guard the two enumerated columns at the database level so a client typo cannot quietly
-- write a value the app will never match against. `not valid` is deliberate: it applies
-- to new writes without forcing a validation scan, and there are no existing rows with
-- these columns populated anyway.
do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'town_profiles_town_level_range') then
        alter table public.town_profiles
            add constraint town_profiles_town_level_range
            check (town_level is null or town_level between 1 and 5) not valid;
    end if;

    if not exists (select 1 from pg_constraint where conname = 'town_profiles_notify_cadence_valid') then
        alter table public.town_profiles
            add constraint town_profiles_notify_cadence_valid
            check (notify_cadence is null
                   or notify_cadence in ('weekly', 'few', 'daily', 'instant')) not valid;
    end if;
end $$;

comment on column public.town_profiles.connection is
    'Onboarding S05: relationship to St. Joseph.';
comment on column public.town_profiles.town_level is
    'Onboarding S08: 1-5 self-rated local knowledge. Keys the S20 closing line.';
comment on column public.town_profiles.motivations is
    'Onboarding S09: why they joined. Distinct from `interests` (topics).';
comment on column public.town_profiles.notify_cadence is
    'Onboarding S12: notification frequency preference.';
comment on column public.town_profiles.founding_member is
    'Onboarding S17: free founding-badge tier. NOT a paid entitlement.';
comment on column public.town_profiles.landing_choice is
    'Onboarding S19: which tab to land on after onboarding.';
