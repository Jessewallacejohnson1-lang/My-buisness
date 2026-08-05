-- ============================================================================
-- BASELINE SCHEMA  —  public + storage, as of 2026-08-04
-- ============================================================================
-- The `supabase/README.md` "Baseline is incomplete" note asked for this: a true
-- baseline of the live project (lxdgwhvqjqmqliobwjpi), so the pre-existing
-- tables (clubs, club_events, club_members, daily_quests, quest_completions,
-- board_items, evergreen_pool, event_*) stop being invisible to this directory.
--
-- HOW IT WAS MADE
--   Reconstructed by introspecting the live project on 2026-08-04 (pg_class,
--   pg_constraint, pg_indexes, pg_policies, pg_proc, storage.buckets). Not a
--   `supabase db pull` — the CLI is not installed on this machine — so treat it
--   as verified-by-introspection rather than tool-generated, and re-check
--   anything surprising before relying on it for a production restore.
--
--   It captures CURRENT state, which means it already includes the columns the
--   later dated migrations in this directory add (club_events.category,
--   places.logo_url, town_profiles onboarding fields, …). Those files are all
--   `add column if not exists`, so replaying baseline -> 20260706 -> … on a
--   fresh project is correct: the later files simply become no-ops. This file
--   is dated 20260705000000 so it always sorts first.
--
-- IDEMPOTENT BY CONSTRUCTION
--   Constraints are inlined into `create table if not exists` rather than added
--   with `alter table`, so re-running is a no-op instead of a duplicate-object
--   error. Policies are `drop policy if exists` + `create`. Safe to run against
--   the live project (it will change nothing) and correct on an empty one.
--
-- WHAT IT DOES NOT COVER
--   auth.* and storage.objects internals (Supabase-managed), row data, secrets,
--   and the Edge Functions in ../functions (deployed separately).
-- ============================================================================


-- ── Extensions ──────────────────────────────────────────────────────────────
create extension if not exists pgcrypto     with schema extensions;
create extension if not exists "uuid-ossp"  with schema extensions;


-- ── Helper functions that policies depend on ────────────────────────────────

-- NOTE: the admin allowlist is a hardcoded email compiled into this function.
-- That is how it exists in production today. It means "admin" cannot be granted
-- or revoked without a schema change, and the address is committed to git. If
-- that matters, the usual fix is an `admins` table (or a custom JWT claim)
-- checked here instead — deliberately NOT changed in this baseline, whose job
-- is to record reality, not improve it.
create or replace function public.is_admin()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() ->> 'email', '') = 'jessewallacejohnson1@icloud.com'
$$;

-- Belt-and-braces: auto-enable RLS on any new table created in `public`, so a
-- table added in a hurry is never silently world-readable.
create or replace function public.rls_auto_enable()
returns event_trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT * FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public')
        AND cmd.schema_name NOT IN ('pg_catalog','information_schema')
        AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION WHEN OTHERS THEN
        RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (system schema or not enforced: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;

-- `create event trigger` needs superuser, which the migration role may not have.
-- Guarded so a restricted environment logs a notice instead of failing the run.
do $$
begin
  if not exists (select 1 from pg_event_trigger where evtname = 'ensure_rls') then
    execute 'create event trigger ensure_rls on ddl_command_end execute function public.rls_auto_enable()';
  end if;
exception when insufficient_privilege or others then
  raise notice 'ensure_rls event trigger not created (needs superuser) — create it manually in the SQL editor';
end $$;


-- ── Community tables ────────────────────────────────────────────────────────
-- Order matters: parents before the tables that reference them.

create table if not exists public.clubs (
    id           uuid primary key default gen_random_uuid(),
    submitted_by uuid default auth.uid() references auth.users (id) on delete set null,
    status       text not null default 'pending' check (status in ('pending','approved','rejected')),
    name         text not null,
    host         text,
    schedule     text,
    vibe         text,
    created_at   timestamptz not null default now(),
    location     text,
    description  text,
    expectations text,
    image_url    text
);

create table if not exists public.club_events (
    id           uuid primary key default gen_random_uuid(),
    club_id      uuid references public.clubs (id) on delete cascade,
    submitted_by uuid default auth.uid() references auth.users (id) on delete set null,
    status       text not null default 'pending' check (status in ('pending','approved','rejected')),
    title        text not null,
    event_date   date,
    start_time   text,
    created_at   timestamptz not null default now(),
    location     text,
    description  text,
    image_url    text,
    -- trails are club_events with kind='trail'; there is no separate table
    kind         text not null default 'event' check (kind in ('event','trail')),
    length       text,
    difficulty   text,
    category     text
);

create table if not exists public.club_members (
    id         uuid primary key default gen_random_uuid(),
    club_id    uuid not null references public.clubs (id) on delete cascade,
    user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    unique (club_id, user_id)
);

create table if not exists public.daily_quests (
    id          uuid primary key default gen_random_uuid(),
    title       text not null,
    description text,
    date        date not null unique,
    created_by  uuid references auth.users (id) on delete set null,
    created_at  timestamptz not null default now()
);

create table if not exists public.quest_completions (
    id           uuid primary key default gen_random_uuid(),
    quest_id     uuid not null references public.daily_quests (id) on delete cascade,
    user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
    completed_at timestamptz not null default now(),
    unique (quest_id, user_id)
);

create table if not exists public.event_comments (
    id         uuid primary key default gen_random_uuid(),
    event_id   uuid not null references public.club_events (id) on delete cascade,
    user_id    uuid not null references auth.users (id) on delete cascade,
    body       text not null check (char_length(body) >= 1 and char_length(body) <= 500),
    created_at timestamptz not null default now()
);

create table if not exists public.event_likes (
    id         uuid primary key default gen_random_uuid(),
    event_id   uuid not null references public.club_events (id) on delete cascade,
    user_id    uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    unique (event_id, user_id)
);

create table if not exists public.event_rsvps (
    id         uuid primary key default gen_random_uuid(),
    event_id   uuid not null references public.club_events (id) on delete cascade,
    user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    unique (event_id, user_id)
);

create table if not exists public.event_saves (
    event_id   uuid not null references public.club_events (id) on delete cascade,
    user_id    uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (event_id, user_id)
);

-- One generated almanac line per user per day; written only by the service role
-- from the `daily-almanac` Edge Function (see ../functions/daily-almanac).
create table if not exists public.almanac_daily (
    id               uuid primary key default gen_random_uuid(),
    user_id          uuid not null references auth.users (id) on delete cascade,
    date             date not null,
    body_text        text not null,
    format_used      text not null,
    places_mentioned text[] not null default '{}'::text[],
    facts_hash       text,
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now(),
    unique (user_id, date)
);

create table if not exists public.board_items (
    id           uuid primary key default gen_random_uuid(),
    title        text not null,
    blurb        text,
    category     text not null check (category in ('event','announcement','road','school','campus','business')),
    source_name  text not null,
    source_url   text,
    tier         numeric not null default 1,
    status       text not null default 'staging' check (status in ('staging','published','archived')),
    starts_at    timestamptz,
    created_at   timestamptz not null default now(),
    published_at timestamptz
);

create table if not exists public.evergreen_pool (
    id     uuid primary key default gen_random_uuid(),
    line   text not null,
    active boolean not null default true
);

create table if not exists public.places (
    id           uuid primary key default gen_random_uuid(),
    place_id     text unique,
    name         text not null,
    lat          double precision not null,
    lon          double precision not null,
    family       text not null check (family in ('food','business')),
    primary_type text,
    types        text[] not null default '{}'::text[],
    address      text,
    source       text not null default 'google_nearby',
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    logo_url     text
);

create table if not exists public.town_almanac (
    md         text primary key,
    fact       text not null,
    source     text,
    link       text,
    updated_at timestamptz not null default now()
);

create table if not exists public.town_follows (
    id          uuid primary key default gen_random_uuid(),
    follower_id uuid not null references auth.users (id) on delete cascade,
    target_type text not null check (target_type in ('club','profile')),
    target_id   uuid not null,
    created_at  timestamptz not null default now(),
    unique (follower_id, target_type, target_id)
);

-- NOTE: the two checks below exist in production as NOT VALID (added to a table
-- that already had rows). Declared valid here because a fresh database starts
-- empty — the enforced rule is identical for all new writes.
create table if not exists public.town_profiles (
    user_id         uuid primary key default auth.uid() references auth.users (id) on delete cascade,
    display_name    text,
    avatar_url      text,
    interests       text[] not null default '{}'::text[],
    onboarded_at    timestamptz,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    connection      text,
    town_level      smallint,
    motivations     text[],
    notify_cadence  text,
    founding_member boolean,
    landing_choice  text,
    constraint town_profiles_town_level_range
        check (town_level is null or (town_level >= 1 and town_level <= 5)),
    constraint town_profiles_notify_cadence_valid
        check (notify_cadence is null or notify_cadence in ('weekly','few','daily','instant'))
);

create table if not exists public.town_status (
    id         uuid primary key default gen_random_uuid(),
    town       text not null default 'st-joseph-mn',
    kind       text not null,
    status     text not null default 'active',
    headline   text not null,
    detail     text,
    link       text,
    active     boolean not null default true,
    updated_at timestamptz not null default now()
);

create table if not exists public.user_utility_prefs (
    user_id    uuid primary key references auth.users (id) on delete cascade,
    tiles      jsonb not null default '["weather", "garbage", "roads", "library"]'::jsonb,
    settings   jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now()
);


-- ── Wellness tables (legacy — pending sunset) ───────────────────────────────
-- These belong to the retired Hygge Health product, not to Block Party. They
-- are still live: `supabase/pending/20260711_sunset_wellness_app.sql` drops
-- them but has NOT been run (verified present on 2026-08-04). Recorded here so
-- the baseline matches reality. Delete this section when the sunset is run.
--
-- Note they carry no foreign key to auth.users — that is how they exist in prod.

create table if not exists public.profiles (
    user_id       uuid primary key default auth.uid(),
    sex           text not null,
    age           integer not null,
    height_cm     numeric not null,
    weight_kg     numeric not null,
    activity      text not null,
    goal          text not null,
    pace          text not null,
    diet          text not null,
    training_days integer not null,
    goal_calories integer not null,
    goal_protein  integer not null,
    goal_carbs    integer not null,
    goal_fat      integer not null,
    goal_fibre    integer not null,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    focus         text[] not null default '{}'::text[]
);

create table if not exists public.food_logs (
    id         uuid primary key default gen_random_uuid(),
    date       date not null default current_date,
    meal       text not null check (meal in ('Breakfast','Lunch','Dinner','Snacks')),
    food_name  text not null,
    brand      text,
    calories   integer default 0,
    protein    numeric default 0,
    carbs      numeric default 0,
    fat        numeric default 0,
    fibre      numeric default 0,
    score      integer default 0,
    badges     jsonb default '[]'::jsonb,
    flags      jsonb default '[]'::jsonb,
    created_at timestamptz default now(),
    user_id    uuid default auth.uid()
);

create table if not exists public.workouts (
    id           uuid primary key default gen_random_uuid(),
    date         date not null default current_date,
    name         text not null,
    duration_min integer default 0,
    exercises    jsonb default '[]'::jsonb,
    completed    boolean default false,
    created_at   timestamptz default now(),
    user_id      uuid default auth.uid()
);


-- ── Indexes ─────────────────────────────────────────────────────────────────

create index if not exists almanac_daily_user_date_desc_idx on public.almanac_daily using btree (user_id, date desc);
create index if not exists club_events_status_date_idx      on public.club_events   using btree (status, event_date);
create index if not exists club_members_club_idx            on public.club_members  using btree (club_id);
create index if not exists clubs_status_idx                 on public.clubs         using btree (status);
create index if not exists event_comments_event_idx         on public.event_comments using btree (event_id, created_at);
create index if not exists event_likes_event_idx            on public.event_likes   using btree (event_id);
create index if not exists event_rsvps_event_idx            on public.event_rsvps   using btree (event_id);
create index if not exists places_family_idx                on public.places        using btree (family);
create index if not exists quest_completions_quest_idx      on public.quest_completions using btree (quest_id);
create index if not exists town_follows_follower_idx        on public.town_follows  using btree (follower_id);
create index if not exists town_follows_target_idx          on public.town_follows  using btree (target_type, target_id);
create index if not exists town_status_lookup_idx           on public.town_status   using btree (town, kind, active, updated_at desc);

-- The board de-dup identity: same title (case-insensitive) + source + start time
-- is the same item, however many times the ingest sees it.
create unique index if not exists board_items_identity_uidx
    on public.board_items using btree (lower(title), source_name, coalesce(starts_at, '-infinity'::timestamptz));

-- legacy (wellness)
create index if not exists food_logs_user_date_idx on public.food_logs using btree (user_id, date);
create index if not exists workouts_user_date_idx  on public.workouts  using btree (user_id, date);


-- ── Row level security ──────────────────────────────────────────────────────

alter table public.almanac_daily      enable row level security;
alter table public.board_items        enable row level security;
alter table public.club_events        enable row level security;
alter table public.club_members       enable row level security;
alter table public.clubs              enable row level security;
alter table public.daily_quests       enable row level security;
alter table public.event_comments     enable row level security;
alter table public.event_likes        enable row level security;
alter table public.event_rsvps        enable row level security;
alter table public.event_saves        enable row level security;
alter table public.evergreen_pool     enable row level security;
alter table public.food_logs          enable row level security;
alter table public.places             enable row level security;
alter table public.profiles           enable row level security;
alter table public.quest_completions  enable row level security;
alter table public.town_almanac       enable row level security;
alter table public.town_follows       enable row level security;
alter table public.town_profiles      enable row level security;
alter table public.town_status        enable row level security;
alter table public.user_utility_prefs enable row level security;
alter table public.workouts           enable row level security;


-- ── Policies ────────────────────────────────────────────────────────────────
-- `drop if exists` + `create` so this file stays re-runnable. The whole
-- migration runs in one transaction, so there is no window where a policy is
-- missing on a live table.
--
-- READ MODEL, worth understanding before changing anything here: direct reads
-- of event_comments / event_likes are deliberately restricted to the caller's
-- OWN rows. Other people's comments and the like/RSVP counts are served by the
-- SECURITY DEFINER functions further down (get_event_comments, get_feed_postings),
-- which bypass RLS on purpose. Loosening these policies to `using (true)` is
-- therefore not required by the UI, and would expose more than it needs to.

drop policy if exists almanac_daily_select_own on public.almanac_daily;
create policy almanac_daily_select_own on public.almanac_daily
    as permissive for select to authenticated
    using ((select auth.uid()) = user_id);
-- no insert/update/delete policy: only the service role writes almanac lines

drop policy if exists "read published items" on public.board_items;
create policy "read published items" on public.board_items
    as permissive for select to public
    using (status = 'published');

drop policy if exists "read events" on public.club_events;
create policy "read events" on public.club_events
    as permissive for select to public
    using (status = 'approved' or submitted_by = auth.uid() or is_admin());

drop policy if exists "submit events" on public.club_events;
create policy "submit events" on public.club_events
    as permissive for insert to public
    with check (submitted_by = auth.uid());

drop policy if exists "moderate events" on public.club_events;
create policy "moderate events" on public.club_events
    as permissive for update to public
    using (is_admin() or (submitted_by = auth.uid() and status = 'pending'))
    with check (is_admin() or (submitted_by = auth.uid() and status = 'pending'));

drop policy if exists "delete events" on public.club_events;
create policy "delete events" on public.club_events
    as permissive for delete to public
    using (is_admin() or (submitted_by = auth.uid() and status = 'pending'));

drop policy if exists "read memberships" on public.club_members;
create policy "read memberships" on public.club_members
    as permissive for select to public using (true);

drop policy if exists "join club" on public.club_members;
create policy "join club" on public.club_members
    as permissive for insert to public with check (user_id = auth.uid());

drop policy if exists "leave club" on public.club_members;
create policy "leave club" on public.club_members
    as permissive for delete to public using (user_id = auth.uid());

drop policy if exists "read clubs" on public.clubs;
create policy "read clubs" on public.clubs
    as permissive for select to public
    using (status = 'approved' or submitted_by = auth.uid() or is_admin());

drop policy if exists "submit clubs" on public.clubs;
create policy "submit clubs" on public.clubs
    as permissive for insert to public
    with check (submitted_by = auth.uid() and (status = 'pending' or is_admin()));

drop policy if exists "moderate clubs" on public.clubs;
create policy "moderate clubs" on public.clubs
    as permissive for update to public
    using (is_admin() or (submitted_by = auth.uid() and status = 'pending'))
    with check (is_admin() or (submitted_by = auth.uid() and status = 'pending'));

drop policy if exists "delete clubs" on public.clubs;
create policy "delete clubs" on public.clubs
    as permissive for delete to public
    using (is_admin() or (submitted_by = auth.uid() and status = 'pending'));

drop policy if exists "read quests" on public.daily_quests;
create policy "read quests" on public.daily_quests
    as permissive for select to public using (true);

drop policy if exists "write quests" on public.daily_quests;
create policy "write quests" on public.daily_quests
    as permissive for all to public using (is_admin()) with check (is_admin());

drop policy if exists "own comments select" on public.event_comments;
create policy "own comments select" on public.event_comments
    as permissive for select to public using (auth.uid() = user_id);

drop policy if exists "own comments insert" on public.event_comments;
create policy "own comments insert" on public.event_comments
    as permissive for insert to public with check (auth.uid() = user_id);

drop policy if exists "own comments delete" on public.event_comments;
create policy "own comments delete" on public.event_comments
    as permissive for delete to public using (auth.uid() = user_id);

drop policy if exists "own likes select" on public.event_likes;
create policy "own likes select" on public.event_likes
    as permissive for select to public using (auth.uid() = user_id);

drop policy if exists "own likes insert" on public.event_likes;
create policy "own likes insert" on public.event_likes
    as permissive for insert to public with check (auth.uid() = user_id);

drop policy if exists "own likes delete" on public.event_likes;
create policy "own likes delete" on public.event_likes
    as permissive for delete to public using (auth.uid() = user_id);

drop policy if exists "read rsvps" on public.event_rsvps;
create policy "read rsvps" on public.event_rsvps
    as permissive for select to public using (true);

drop policy if exists "rsvp insert" on public.event_rsvps;
create policy "rsvp insert" on public.event_rsvps
    as permissive for insert to public with check (user_id = auth.uid());

drop policy if exists "rsvp delete" on public.event_rsvps;
create policy "rsvp delete" on public.event_rsvps
    as permissive for delete to public using (user_id = auth.uid());

drop policy if exists "event saves select" on public.event_saves;
create policy "event saves select" on public.event_saves
    as permissive for select to authenticated using (true);

drop policy if exists "own saves insert" on public.event_saves;
create policy "own saves insert" on public.event_saves
    as permissive for insert to public with check (auth.uid() = user_id);

drop policy if exists "own saves delete" on public.event_saves;
create policy "own saves delete" on public.event_saves
    as permissive for delete to public using (auth.uid() = user_id);

drop policy if exists "read evergreen" on public.evergreen_pool;
create policy "read evergreen" on public.evergreen_pool
    as permissive for select to public using (active = true);

drop policy if exists "read places" on public.places;
create policy "read places" on public.places
    as permissive for select to public using (true);

drop policy if exists "admin insert places" on public.places;
create policy "admin insert places" on public.places
    as permissive for insert to public with check (is_admin());

drop policy if exists "admin update places" on public.places;
create policy "admin update places" on public.places
    as permissive for update to public using (is_admin()) with check (is_admin());

drop policy if exists "admin delete places" on public.places;
create policy "admin delete places" on public.places
    as permissive for delete to public using (is_admin());

drop policy if exists "read completions" on public.quest_completions;
create policy "read completions" on public.quest_completions
    as permissive for select to public using (true);

drop policy if exists "insert completion" on public.quest_completions;
create policy "insert completion" on public.quest_completions
    as permissive for insert to public with check (user_id = auth.uid());

drop policy if exists "almanac public read" on public.town_almanac;
create policy "almanac public read" on public.town_almanac
    as permissive for select to authenticated using (true);

drop policy if exists "own follows select" on public.town_follows;
create policy "own follows select" on public.town_follows
    as permissive for select to public using (auth.uid() = follower_id);

drop policy if exists "own follows insert" on public.town_follows;
create policy "own follows insert" on public.town_follows
    as permissive for insert to public with check (auth.uid() = follower_id);

drop policy if exists "own follows delete" on public.town_follows;
create policy "own follows delete" on public.town_follows
    as permissive for delete to public using (auth.uid() = follower_id);

drop policy if exists town_profiles_select_own on public.town_profiles;
create policy town_profiles_select_own on public.town_profiles
    as permissive for select to public using (auth.uid() = user_id);

drop policy if exists town_profiles_insert_own on public.town_profiles;
create policy town_profiles_insert_own on public.town_profiles
    as permissive for insert to public with check (auth.uid() = user_id);

drop policy if exists town_profiles_update_own on public.town_profiles;
create policy town_profiles_update_own on public.town_profiles
    as permissive for update to public
    using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "town status readable" on public.town_status;
create policy "town status readable" on public.town_status
    as permissive for select to authenticated using (true);

drop policy if exists "own utility prefs select" on public.user_utility_prefs;
create policy "own utility prefs select" on public.user_utility_prefs
    as permissive for select to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists "own utility prefs insert" on public.user_utility_prefs;
create policy "own utility prefs insert" on public.user_utility_prefs
    as permissive for insert to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists "own utility prefs update" on public.user_utility_prefs;
create policy "own utility prefs update" on public.user_utility_prefs
    as permissive for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

-- legacy (wellness)
drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles
    as permissive for all to public
    using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own rows" on public.food_logs;
create policy "own rows" on public.food_logs
    as permissive for all to public
    using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own rows" on public.workouts;
create policy "own rows" on public.workouts
    as permissive for all to public
    using (auth.uid() = user_id) with check (auth.uid() = user_id);


-- ── SECURITY DEFINER read models ────────────────────────────────────────────
-- These bypass RLS on purpose, to serve public aggregates (counts, other
-- people's comments) that the per-row policies above intentionally withhold.
-- Both pin search_path, and neither takes a caller-supplied table or column
-- name, so they are not an injection surface.

create or replace function public.get_feed_postings(limit_n integer default 30)
returns table(id uuid, title text, event_date date, start_time text, location text,
              image_url text, created_at timestamptz, poster_type text, poster_id uuid,
              poster_name text, poster_avatar text, like_count integer, comment_count integer,
              going_count integer, follower_count integer)
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $$
    with base as (
        select e.*,
               case when e.club_id is not null then 'club' else 'profile' end as p_type,
               coalesce(e.club_id, e.submitted_by)                            as p_id
        from public.club_events e
        where e.status = 'approved'
          and e.kind = 'event'
          and e.submitted_by is not null
          -- Today-or-future only. Without this the feed hands the client past
          -- events, and FeedSectioning's `default:` arm files any negative day
          -- offset under LATER — stale events surface as upcoming ones.
          -- Anchored to the town's zone, NOT the server's UTC `current_date`:
          -- after ~7pm local, UTC has already rolled over and today's events
          -- would drop out of the feed for the rest of the evening.
          and e.event_date >= (now() at time zone 'America/Chicago')::date
    )
    select b.id, b.title, b.event_date, b.start_time, b.location,
           b.image_url, b.created_at,
           b.p_type, b.p_id,
           coalesce(c.name, tp.display_name, 'A neighbor')                    as poster_name,
           case when b.p_type = 'profile' then tp.avatar_url else null end     as poster_avatar,
           coalesce(l.n, 0)::int, coalesce(cm.n, 0)::int,
           coalesce(r.n, 0)::int, coalesce(f.n, 0)::int
    from base b
    left join public.clubs c          on c.id = b.club_id
    left join public.town_profiles tp on tp.user_id = b.submitted_by
    left join lateral (select count(*) n from public.event_likes    where event_id = b.id) l  on true
    left join lateral (select count(*) n from public.event_comments where event_id = b.id) cm on true
    left join lateral (select count(*) n from public.event_rsvps    where event_id = b.id) r  on true
    left join lateral (select count(*) n from public.town_follows
                       where target_type = b.p_type and target_id = b.p_id)   f  on true
    order by b.created_at desc
    limit limit_n;
$$;

create or replace function public.get_event_comments(e_id uuid)
returns table(id uuid, body text, created_at timestamptz, author_id uuid,
              author_name text, author_avatar text)
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $$
    select ec.id, ec.body, ec.created_at, ec.user_id,
           coalesce(tp.display_name, 'A neighbor') as author_name,
           tp.avatar_url                            as author_avatar
    from public.event_comments ec
    left join public.town_profiles tp on tp.user_id = ec.user_id
    where ec.event_id = e_id
    order by ec.created_at asc;
$$;


-- ── Realtime ────────────────────────────────────────────────────────────────
-- `replica identity full` so UPDATE/DELETE payloads carry the old row, which the
-- map + status subscriptions need to diff.

alter table public.club_events replica identity full;
alter table public.town_status replica identity full;

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'club_events') then
    alter publication supabase_realtime add table public.club_events;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'town_status') then
    alter publication supabase_realtime add table public.town_status;
  end if;
end $$;


-- ── Storage ─────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public)
values ('event-images', 'event-images', true),
       ('avatars',      'avatars',      true),
       ('place-logos',  'place-logos',  true)
on conflict (id) do nothing;

-- avatars: read-all, write only inside your own uid-named folder.
drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects
    for select to public using (bucket_id = 'avatars');

drop policy if exists avatars_insert_own on storage.objects;
create policy avatars_insert_own on storage.objects
    for insert to public
    with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists avatars_update_own on storage.objects;
create policy avatars_update_own on storage.objects
    for update to public
    using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- event-images: read-all; any authenticated user may upload to ANY key in the
-- bucket. Deliberately path-agnostic — club photos live under `clubs/…` and
-- event photos under their own prefix, and both are written by the same call.
-- The trade-off is that it is not scoped per-user the way `avatars` is; there
-- is no update or delete policy, so uploads cannot be overwritten or removed
-- by other users, only added to.
drop policy if exists "event images public read" on storage.objects;
create policy "event images public read" on storage.objects
    for select to public using (bucket_id = 'event-images');

drop policy if exists "event images authenticated upload" on storage.objects;
create policy "event images authenticated upload" on storage.objects
    for insert to authenticated with check (bucket_id = 'event-images');

-- place-logos: read-all, admin-only writes.
drop policy if exists "place-logos public read" on storage.objects;
create policy "place-logos public read" on storage.objects
    for select to public using (bucket_id = 'place-logos');

drop policy if exists "place-logos admin insert" on storage.objects;
create policy "place-logos admin insert" on storage.objects
    for insert to public with check (bucket_id = 'place-logos' and is_admin());

drop policy if exists "place-logos admin update" on storage.objects;
create policy "place-logos admin update" on storage.objects
    for update to public using (bucket_id = 'place-logos' and is_admin());

drop policy if exists "place-logos admin delete" on storage.objects;
create policy "place-logos admin delete" on storage.objects
    for delete to public using (bucket_id = 'place-logos' and is_admin());
