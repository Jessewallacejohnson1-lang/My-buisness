-- ============================================================================
-- BLOCK PARTY DATABASE — the whole live schema in one file
-- ============================================================================
-- Project lxdgwhvqjqmqliobwjpi, read from the live database on 2026-09-29.
-- This one file replaces the 41 step-by-step migrations that came before it
-- (they are in git history). Those files had drifted: nine changes applied to
-- the live project had no file here. This file is what the database is today.
--
-- Made by reading the live catalog (pg_class, pg_attribute, pg_constraint,
-- pg_indexes, pg_proc, pg_trigger, pg_policies, ACLs, storage.buckets,
-- cron.job) with a read-only role. Nothing was written to the live project.
--
-- Not in here: auth.* and storage.objects internals (Supabase owns them), row
-- data, the bizops_ro password, secrets, and the Edge Functions in ../functions.
-- ============================================================================

set check_function_bodies = false;


-- ── Extensions ──────────────────────────────────────────────────────────────
create extension if not exists pg_cron     with schema pg_catalog;
create extension if not exists pgcrypto    with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;


-- ── Read-only role for the Control Room dashboard ───────────────────────────
-- Password is set by hand, never committed:  alter role bizops_ro password '...';
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'bizops_ro') then
    create role bizops_ro login connection limit 5;
  end if;
end $$;
alter role bizops_ro set default_transaction_read_only = 'on';
alter role bizops_ro set statement_timeout = '10s';
grant usage on schema public to bizops_ro;


-- ── Tables (Block Party) ────────────────────────────────────────────────────

create table public.agent_events (
  id bigserial,
  session_id text,
  prompt_id text,
  occurred_at timestamp with time zone not null default now(),
  event text not null,
  tool_name text,
  repo text,
  branch text,
  file_path text,
  summary text,
  raw jsonb not null,
  constraint agent_events_pkey PRIMARY KEY (id)
);
alter table public.agent_events enable row level security;

create table public.app_events (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  name text not null,
  payload jsonb,
  occurred_at timestamp with time zone not null default now(),
  constraint app_events_pkey PRIMARY KEY (id)
);
alter table public.app_events enable row level security;

create table public.board_items (
  id uuid not null default gen_random_uuid(),
  title text not null,
  blurb text,
  category text not null,
  source_name text not null,
  source_url text,
  tier numeric not null default 1,
  status text not null default 'staging'::text,
  starts_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  published_at timestamp with time zone,
  image_url text,
  fetched_at timestamp with time zone,
  constraint board_items_category_check CHECK ((category = ANY (ARRAY['event'::text, 'announcement'::text, 'road'::text, 'school'::text, 'campus'::text, 'business'::text]))),
  constraint board_items_status_check CHECK ((status = ANY (ARRAY['staging'::text, 'published'::text, 'archived'::text]))),
  constraint board_items_pkey PRIMARY KEY (id)
);
alter table public.board_items enable row level security;

create table public.board_sweeps (
  id uuid not null default gen_random_uuid(),
  swept_on date not null,
  source_count integer not null,
  last_swept_at timestamp with time zone not null,
  constraint board_sweeps_pkey PRIMARY KEY (id)
);
alter table public.board_sweeps enable row level security;

create table public.briefing_featured (
  briefing_date date not null,
  event_id uuid not null,
  rank integer not null,
  constraint briefing_featured_rank_check CHECK (((rank >= 1) AND (rank <= 3))),
  constraint briefing_featured_pkey PRIMARY KEY (briefing_date, rank),
  constraint briefing_featured_briefing_date_event_id_key UNIQUE (briefing_date, event_id)
);
alter table public.briefing_featured enable row level security;

create table public.club_events (
  id uuid not null default gen_random_uuid(),
  club_id uuid,
  submitted_by uuid default auth.uid(),
  status text not null default 'pending'::text,
  title text not null,
  event_date date,
  start_time text,
  created_at timestamp with time zone not null default now(),
  location text,
  description text,
  image_url text,
  kind text not null default 'event'::text,
  length text,
  difficulty text,
  category text,
  end_at timestamp with time zone,
  all_day boolean not null default false,
  constraint club_events_kind_check CHECK ((kind = ANY (ARRAY['event'::text, 'trail'::text]))),
  constraint club_events_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text]))),
  constraint club_events_pkey PRIMARY KEY (id)
);
alter table public.club_events enable row level security;
alter table public.club_events replica identity full;
comment on column public.club_events.category is 'Optional event category id, mirroring the Expo INTERESTS taxonomy (outdoors, music_arts, food, families, faith, sports, books, service, games). Null = uncategorized (client reads as "other").';
comment on column public.club_events.end_at is 'Absolute end. NULL = unknown; Your Day falls back to the start instant for the overlap rule.';
comment on column public.club_events.all_day is 'True = spans the local day; sorts first in Your Day and shows no start time.';

create table public.club_members (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  user_id uuid not null default auth.uid(),
  created_at timestamp with time zone not null default now(),
  constraint club_members_pkey PRIMARY KEY (id),
  constraint club_members_club_id_user_id_key UNIQUE (club_id, user_id)
);
alter table public.club_members enable row level security;

create table public.clubs (
  id uuid not null default gen_random_uuid(),
  submitted_by uuid default auth.uid(),
  status text not null default 'pending'::text,
  name text not null,
  host text,
  schedule text,
  vibe text,
  created_at timestamp with time zone not null default now(),
  location text,
  description text,
  expectations text,
  image_url text,
  constraint clubs_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text]))),
  constraint clubs_pkey PRIMARY KEY (id)
);
alter table public.clubs enable row level security;

create table public.content_candidates (
  id uuid not null default gen_random_uuid(),
  decision_id uuid not null,
  rank integer not null,
  source_url text,
  source_name text,
  trust_tier text not null,
  corroboration_ct integer not null default 0,
  score numeric not null,
  score_breakdown jsonb not null,
  outcome text not null,
  rejection_reason text,
  payload jsonb not null,
  constraint content_candidates_outcome_check CHECK ((outcome = ANY (ARRAY['chosen'::text, 'rejected'::text]))),
  constraint content_candidates_rejection_reason_required CHECK (((outcome <> 'rejected'::text) OR (rejection_reason IS NOT NULL))),
  constraint content_candidates_trust_tier_check CHECK ((trust_tier = ANY (ARRAY['official'::text, 'corroborated'::text, 'evergreen'::text]))),
  constraint content_candidates_pkey PRIMARY KEY (id)
);
alter table public.content_candidates enable row level security;

create table public.content_decisions (
  id uuid not null default gen_random_uuid(),
  run_id uuid not null,
  decided_at timestamp with time zone not null default now(),
  surface text not null,
  target_user_id uuid,
  chosen_candidate_id uuid,
  rule_version text not null,
  inputs jsonb not null,
  notes text,
  constraint content_decisions_pkey PRIMARY KEY (id)
);
alter table public.content_decisions enable row level security;

create table public.daily_briefings (
  briefing_date date not null,
  weather jsonb,
  status text not null default 'draft'::text,
  published_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  fallback_title text,
  fallback_body text,
  fallback_deeplink text,
  spotlight_id uuid,
  constraint daily_briefings_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text]))),
  constraint daily_briefings_pkey PRIMARY KEY (briefing_date)
);
alter table public.daily_briefings enable row level security;

create table public.daily_quests (
  id uuid not null default gen_random_uuid(),
  title text not null,
  description text,
  date date not null,
  created_by uuid,
  created_at timestamp with time zone not null default now(),
  constraint daily_quests_pkey PRIMARY KEY (id),
  constraint daily_quests_date_key UNIQUE (date)
);
alter table public.daily_quests enable row level security;

create table public.daily_touches (
  id uuid not null default gen_random_uuid(),
  kind text not null,
  prompt text not null,
  options jsonb,
  body text,
  used_on date,
  created_at timestamp with time zone not null default now(),
  season text not null default 'any'::text,
  correct_idx smallint,
  constraint daily_touches_content_check CHECK ((((kind = 'poll'::text) AND (jsonb_typeof(options) = 'array'::text) AND (jsonb_array_length(options) > 0)) OR ((kind = 'history'::text) AND (body IS NOT NULL)) OR ((kind = 'trivia'::text) AND (jsonb_typeof(options) = 'array'::text) AND (jsonb_array_length(options) = 4)))),
  constraint daily_touches_kind_check CHECK ((kind = ANY (ARRAY['poll'::text, 'history'::text, 'trivia'::text]))),
  constraint daily_touches_season_check CHECK ((season = ANY (ARRAY['any'::text, 'winter'::text, 'spring'::text, 'summer'::text, 'fall'::text]))),
  constraint daily_touches_trivia_answer_check CHECK ((((kind = 'trivia'::text) AND (correct_idx IS NOT NULL) AND (correct_idx >= 0) AND (correct_idx < jsonb_array_length(options))) OR ((kind = ANY (ARRAY['poll'::text, 'history'::text])) AND (correct_idx IS NULL)))),
  constraint daily_touches_pkey PRIMARY KEY (id)
);
alter table public.daily_touches enable row level security;

create table public.event_comments (
  id uuid not null default gen_random_uuid(),
  event_id uuid not null,
  user_id uuid not null,
  body text not null,
  created_at timestamp with time zone not null default now(),
  constraint event_comments_body_check CHECK (((char_length(body) >= 1) AND (char_length(body) <= 500))),
  constraint event_comments_pkey PRIMARY KEY (id)
);
alter table public.event_comments enable row level security;

create table public.event_completions (
  user_id uuid not null,
  event_id uuid not null,
  completed_at timestamp with time zone not null default now(),
  constraint event_completions_pkey PRIMARY KEY (user_id, event_id)
);
alter table public.event_completions enable row level security;

create table public.event_likes (
  id uuid not null default gen_random_uuid(),
  event_id uuid not null,
  user_id uuid not null,
  created_at timestamp with time zone not null default now(),
  constraint event_likes_pkey PRIMARY KEY (id),
  constraint event_likes_event_id_user_id_key UNIQUE (event_id, user_id)
);
alter table public.event_likes enable row level security;

create table public.event_rsvps (
  id uuid not null default gen_random_uuid(),
  event_id uuid not null,
  user_id uuid not null default auth.uid(),
  created_at timestamp with time zone not null default now(),
  constraint event_rsvps_pkey PRIMARY KEY (id),
  constraint event_rsvps_event_id_user_id_key UNIQUE (event_id, user_id)
);
alter table public.event_rsvps enable row level security;

create table public.event_saves (
  event_id uuid not null,
  user_id uuid not null,
  created_at timestamp with time zone not null default now(),
  constraint event_saves_pkey PRIMARY KEY (event_id, user_id)
);
alter table public.event_saves enable row level security;

create table public.evergreen_pool (
  id uuid not null default gen_random_uuid(),
  line text not null,
  active boolean not null default true,
  constraint evergreen_pool_pkey PRIMARY KEY (id)
);
alter table public.evergreen_pool enable row level security;

create table public.places (
  id uuid not null default gen_random_uuid(),
  place_id text,
  name text not null,
  lat double precision not null,
  lon double precision not null,
  family text not null,
  primary_type text,
  types text[] not null default '{}'::text[],
  address text,
  source text not null default 'google_nearby'::text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  logo_url text,
  constraint places_family_check CHECK ((family = ANY (ARRAY['food'::text, 'business'::text]))),
  constraint places_pkey PRIMARY KEY (id),
  constraint places_place_id_key UNIQUE (place_id)
);
alter table public.places enable row level security;
comment on table public.places is 'Permanent St. Joseph POI venues (food + business) shown as map markers. Seeded once from Google Nearby Search; read by the map from Supabase (no live Places call per load). place_id + type data persisted; photos never persisted (re-fetched live).';
comment on column public.places.family is 'POI family: food | business. Derived client-side from Google primaryType via PlaceCategoryMap. Places differ by glyph within a family, not colour.';
comment on column public.places.primary_type is 'Raw Google Places (New) primaryType (e.g. cafe, hardware_store) — kept for future per-subtype granularity.';
comment on column public.places.logo_url is 'Public URL of the curated square brand logo in the place-logos bucket; null = glyph fallback.';

create table public.posting_dismissals (
  event_id uuid not null,
  user_id uuid not null,
  created_at timestamp with time zone not null default now(),
  constraint posting_dismissals_pkey PRIMARY KEY (event_id, user_id)
);
alter table public.posting_dismissals enable row level security;

create table public.quest_completions (
  id uuid not null default gen_random_uuid(),
  quest_id uuid not null,
  user_id uuid not null default auth.uid(),
  completed_at timestamp with time zone not null default now(),
  constraint quest_completions_pkey PRIMARY KEY (id),
  constraint quest_completions_quest_id_user_id_key UNIQUE (quest_id, user_id)
);
alter table public.quest_completions enable row level security;

create table public.spotlight_weeks (
  week_start date not null,
  week_key text not null,
  spotlight_id uuid not null,
  created_at timestamp with time zone not null default now(),
  constraint spotlight_weeks_week_start_check CHECK ((week_start = (date_trunc('week'::text, (week_start)::timestamp without time zone))::date)),
  constraint spotlight_weeks_pkey PRIMARY KEY (week_start),
  constraint spotlight_weeks_week_key_key UNIQUE (week_key)
);
alter table public.spotlight_weeks enable row level security;

create table public.spotlights (
  id uuid not null default gen_random_uuid(),
  slug text not null,
  title text not null,
  blurb text not null,
  image_url text,
  place_id uuid,
  active boolean not null default true,
  last_shown date,
  subject_type text not null default 'place'::text,
  constraint spotlights_subject_type_check CHECK ((subject_type = ANY (ARRAY['place'::text, 'business'::text]))),
  constraint spotlights_pkey PRIMARY KEY (id),
  constraint spotlights_slug_key UNIQUE (slug)
);
alter table public.spotlights enable row level security;

create table public.touch_votes (
  touch_id uuid not null,
  user_id uuid not null,
  option_idx integer not null,
  created_at timestamp with time zone not null default now(),
  constraint touch_votes_option_idx_check CHECK ((option_idx >= 0)),
  constraint touch_votes_pkey PRIMARY KEY (touch_id, user_id)
);
alter table public.touch_votes enable row level security;

create table public.town_follows (
  id uuid not null default gen_random_uuid(),
  follower_id uuid not null,
  target_type text not null,
  target_id uuid not null,
  created_at timestamp with time zone not null default now(),
  constraint town_follows_target_type_check CHECK ((target_type = ANY (ARRAY['club'::text, 'profile'::text]))),
  constraint town_follows_pkey PRIMARY KEY (id),
  constraint town_follows_follower_id_target_type_target_id_key UNIQUE (follower_id, target_type, target_id)
);
alter table public.town_follows enable row level security;

create table public.town_profiles (
  user_id uuid not null default auth.uid(),
  display_name text,
  avatar_url text,
  interests text[] not null default '{}'::text[],
  onboarded_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  connection text,
  town_level smallint,
  motivations text[],
  notify_cadence text,
  founding_member boolean,
  landing_choice text,
  constraint town_profiles_notify_cadence_valid CHECK (((notify_cadence IS NULL) OR (notify_cadence = ANY (ARRAY['weekly'::text, 'few'::text, 'daily'::text, 'instant'::text])))),
  constraint town_profiles_town_level_range CHECK (((town_level IS NULL) OR ((town_level >= 1) AND (town_level <= 5)))),
  constraint town_profiles_pkey PRIMARY KEY (user_id)
);
alter table public.town_profiles enable row level security;
comment on column public.town_profiles.connection is 'Onboarding S05: relationship to St. Joseph.';
comment on column public.town_profiles.town_level is 'Onboarding S08: 1-5 self-rated local knowledge. Keys the S20 closing line.';
comment on column public.town_profiles.motivations is 'Onboarding S09: why they joined. Distinct from `interests` (topics).';
comment on column public.town_profiles.notify_cadence is 'Onboarding S12: notification frequency preference.';
comment on column public.town_profiles.founding_member is 'Onboarding S17: free founding-badge tier. NOT a paid entitlement.';
comment on column public.town_profiles.landing_choice is 'Onboarding S19: which tab to land on after onboarding.';

create table public.town_status (
  id uuid not null default gen_random_uuid(),
  town text not null default 'st-joseph-mn'::text,
  kind text not null,
  status text not null default 'active'::text,
  headline text not null,
  detail text,
  link text,
  active boolean not null default true,
  updated_at timestamp with time zone not null default now(),
  constraint town_status_pkey PRIMARY KEY (id)
);
alter table public.town_status enable row level security;
alter table public.town_status replica identity full;

create table public.user_utility_prefs (
  user_id uuid not null,
  tiles jsonb not null default '["weather", "garbage", "roads", "library"]'::jsonb,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamp with time zone not null default now(),
  constraint user_utility_prefs_pkey PRIMARY KEY (user_id)
);
alter table public.user_utility_prefs enable row level security;

create table public.waitlist (
  id uuid not null default gen_random_uuid(),
  email text not null,
  first_name text not null,
  town text not null,
  created_at timestamp with time zone not null default now(),
  business_name text,
  business_kind text,
  constraint waitlist_pkey PRIMARY KEY (id)
);
alter table public.waitlist enable row level security;
comment on column public.waitlist.business_name is 'Set only when the visitor answered "Yes, I own one" on the join sheet. Null means neighbour.';
comment on column public.waitlist.business_kind is 'Optional free text from the same card ("coffee shop", "salon"). Never present without business_name.';


-- ── Tables (retired Hygge Health wellness app, still live) ──────────────────
-- ../pending/20260711_sunset_wellness_app.sql drops these. Delete this section when it runs.

create table public.food_logs (
  id uuid not null default gen_random_uuid(),
  date date not null default CURRENT_DATE,
  meal text not null,
  food_name text not null,
  brand text,
  calories integer default 0,
  protein numeric default 0,
  carbs numeric default 0,
  fat numeric default 0,
  fibre numeric default 0,
  score integer default 0,
  badges jsonb default '[]'::jsonb,
  flags jsonb default '[]'::jsonb,
  created_at timestamp with time zone default now(),
  user_id uuid default auth.uid(),
  constraint food_logs_meal_check CHECK ((meal = ANY (ARRAY['Breakfast'::text, 'Lunch'::text, 'Dinner'::text, 'Snacks'::text]))),
  constraint food_logs_pkey PRIMARY KEY (id)
);
alter table public.food_logs enable row level security;

create table public.profiles (
  user_id uuid not null default auth.uid(),
  sex text not null,
  age integer not null,
  height_cm numeric not null,
  weight_kg numeric not null,
  activity text not null,
  goal text not null,
  pace text not null,
  diet text not null,
  training_days integer not null,
  goal_calories integer not null,
  goal_protein integer not null,
  goal_carbs integer not null,
  goal_fat integer not null,
  goal_fibre integer not null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  focus text[] not null default '{}'::text[],
  constraint profiles_pkey PRIMARY KEY (user_id)
);
alter table public.profiles enable row level security;

create table public.workouts (
  id uuid not null default gen_random_uuid(),
  date date not null default CURRENT_DATE,
  name text not null,
  duration_min integer default 0,
  exercises jsonb default '[]'::jsonb,
  completed boolean default false,
  created_at timestamp with time zone default now(),
  user_id uuid default auth.uid(),
  constraint workouts_pkey PRIMARY KEY (id)
);
alter table public.workouts enable row level security;


-- ── Foreign keys ────────────────────────────────────────────────────────────
alter table public.app_events add constraint app_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.briefing_featured add constraint briefing_featured_briefing_date_fkey FOREIGN KEY (briefing_date) REFERENCES daily_briefings(briefing_date) ON DELETE CASCADE;
alter table public.briefing_featured add constraint briefing_featured_event_id_fkey FOREIGN KEY (event_id) REFERENCES club_events(id) ON DELETE CASCADE;
alter table public.club_events add constraint club_events_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.club_events add constraint club_events_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.club_members add constraint club_members_club_id_fkey FOREIGN KEY (club_id) REFERENCES clubs(id) ON DELETE CASCADE;
alter table public.club_members add constraint club_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.clubs add constraint clubs_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.content_candidates add constraint content_candidates_decision_id_fkey FOREIGN KEY (decision_id) REFERENCES content_decisions(id) ON DELETE CASCADE;
alter table public.daily_briefings add constraint daily_briefings_spotlight_id_fkey FOREIGN KEY (spotlight_id) REFERENCES spotlights(id) ON DELETE SET NULL;
alter table public.daily_quests add constraint daily_quests_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.event_comments add constraint event_comments_event_id_fkey FOREIGN KEY (event_id) REFERENCES club_events(id) ON DELETE CASCADE;
alter table public.event_comments add constraint event_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.event_completions add constraint event_completions_event_id_fkey FOREIGN KEY (event_id) REFERENCES club_events(id) ON DELETE CASCADE;
alter table public.event_completions add constraint event_completions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.event_likes add constraint event_likes_event_id_fkey FOREIGN KEY (event_id) REFERENCES club_events(id) ON DELETE CASCADE;
alter table public.event_likes add constraint event_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.event_rsvps add constraint event_rsvps_event_id_fkey FOREIGN KEY (event_id) REFERENCES club_events(id) ON DELETE CASCADE;
alter table public.event_rsvps add constraint event_rsvps_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.event_saves add constraint event_saves_event_id_fkey FOREIGN KEY (event_id) REFERENCES club_events(id) ON DELETE CASCADE;
alter table public.event_saves add constraint event_saves_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.posting_dismissals add constraint posting_dismissals_event_id_fkey FOREIGN KEY (event_id) REFERENCES club_events(id) ON DELETE CASCADE;
alter table public.posting_dismissals add constraint posting_dismissals_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.quest_completions add constraint quest_completions_quest_id_fkey FOREIGN KEY (quest_id) REFERENCES daily_quests(id) ON DELETE CASCADE;
alter table public.quest_completions add constraint quest_completions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.spotlight_weeks add constraint spotlight_weeks_spotlight_id_fkey FOREIGN KEY (spotlight_id) REFERENCES spotlights(id) ON DELETE RESTRICT;
alter table public.spotlights add constraint spotlights_place_id_fkey FOREIGN KEY (place_id) REFERENCES places(id) ON DELETE SET NULL;
alter table public.touch_votes add constraint touch_votes_touch_id_fkey FOREIGN KEY (touch_id) REFERENCES daily_touches(id) ON DELETE CASCADE;
alter table public.touch_votes add constraint touch_votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.town_follows add constraint town_follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.town_profiles add constraint town_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.user_utility_prefs add constraint user_utility_prefs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


-- ── Indexes ─────────────────────────────────────────────────────────────────
CREATE INDEX agent_events_session_occurred ON public.agent_events USING btree (session_id, occurred_at);
CREATE INDEX app_events_name_occurred_idx ON public.app_events USING btree (name, occurred_at DESC);
CREATE INDEX app_events_user_occurred_idx ON public.app_events USING btree (user_id, occurred_at DESC);
CREATE UNIQUE INDEX board_items_identity_uidx ON public.board_items USING btree (lower(title), source_name, COALESCE(starts_at, '-infinity'::timestamp with time zone));
CREATE INDEX briefing_featured_event_id_idx ON public.briefing_featured USING btree (event_id);
CREATE INDEX club_events_club_id_idx ON public.club_events USING btree (club_id);
CREATE INDEX club_events_status_date_idx ON public.club_events USING btree (status, event_date);
CREATE INDEX club_events_submitted_by_idx ON public.club_events USING btree (submitted_by);
CREATE INDEX club_members_club_idx ON public.club_members USING btree (club_id);
CREATE INDEX club_members_user_id_idx ON public.club_members USING btree (user_id);
CREATE INDEX clubs_status_idx ON public.clubs USING btree (status);
CREATE INDEX clubs_submitted_by_idx ON public.clubs USING btree (submitted_by);
CREATE INDEX content_candidates_decision_rank ON public.content_candidates USING btree (decision_id, rank);
CREATE INDEX content_decisions_surface_decided_at ON public.content_decisions USING btree (surface, decided_at DESC);
CREATE INDEX daily_briefings_spotlight_id_idx ON public.daily_briefings USING btree (spotlight_id);
CREATE INDEX daily_quests_created_by_idx ON public.daily_quests USING btree (created_by);
CREATE UNIQUE INDEX daily_touches_regular_used_on_unique_idx ON public.daily_touches USING btree (used_on) WHERE ((used_on IS NOT NULL) AND (kind = ANY (ARRAY['poll'::text, 'history'::text])));
CREATE UNIQUE INDEX daily_touches_trivia_used_on_unique_idx ON public.daily_touches USING btree (used_on) WHERE ((used_on IS NOT NULL) AND (kind = 'trivia'::text));
CREATE INDEX daily_touches_unused_season_idx ON public.daily_touches USING btree (season, created_at) WHERE (used_on IS NULL);
CREATE INDEX daily_touches_unused_trivia_idx ON public.daily_touches USING btree (created_at, id) WHERE ((used_on IS NULL) AND (kind = 'trivia'::text));
CREATE INDEX event_comments_event_idx ON public.event_comments USING btree (event_id, created_at);
CREATE INDEX event_comments_user_id_idx ON public.event_comments USING btree (user_id);
CREATE INDEX event_completions_user_idx ON public.event_completions USING btree (user_id);
CREATE INDEX event_likes_event_idx ON public.event_likes USING btree (event_id);
CREATE INDEX event_likes_user_id_idx ON public.event_likes USING btree (user_id);
CREATE INDEX event_rsvps_event_idx ON public.event_rsvps USING btree (event_id);
CREATE INDEX event_rsvps_user_id_idx ON public.event_rsvps USING btree (user_id);
CREATE INDEX event_saves_user_id_idx ON public.event_saves USING btree (user_id);
CREATE INDEX food_logs_user_date_idx ON public.food_logs USING btree (user_id, date);
CREATE INDEX places_family_idx ON public.places USING btree (family);
CREATE INDEX quest_completions_quest_idx ON public.quest_completions USING btree (quest_id);
CREATE INDEX quest_completions_user_id_idx ON public.quest_completions USING btree (user_id);
CREATE INDEX spotlight_weeks_spotlight_id_idx ON public.spotlight_weeks USING btree (spotlight_id, week_start DESC);
CREATE INDEX spotlights_active_last_shown_idx ON public.spotlights USING btree (active, last_shown) WHERE active;
CREATE INDEX touch_votes_touch_id_idx ON public.touch_votes USING btree (touch_id);
CREATE INDEX town_follows_follower_idx ON public.town_follows USING btree (follower_id);
CREATE INDEX town_follows_target_idx ON public.town_follows USING btree (target_type, target_id);
CREATE INDEX town_status_lookup_idx ON public.town_status USING btree (town, kind, active, updated_at DESC);
CREATE UNIQUE INDEX waitlist_email_lower_idx ON public.waitlist USING btree (lower(email));
CREATE INDEX workouts_user_date_idx ON public.workouts USING btree (user_id, date);


-- ── Functions ───────────────────────────────────────────────────────────────
-- is_admin() hardcodes the one admin email. An admins table is the usual fix.

CREATE OR REPLACE FUNCTION public.briefings_pending(p_from date, p_days integer DEFAULT 2)
 RETURNS TABLE(briefing_date date, state text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    select d::date,
           coalesce((select db.status from public.daily_briefings db where db.briefing_date = d::date),
                    'missing')
    from generate_series(p_from, p_from + (p_days - 1), interval '1 day') as d
    where coalesce((select db.status from public.daily_briefings db where db.briefing_date = d::date),
                   'missing') <> 'published'
    order by 1;
$function$;

CREATE OR REPLACE FUNCTION public.claim_touch(p_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id uuid; v_pick uuid;
begin
    select id into v_id
    from public.daily_touches
    where used_on = p_date and kind in ('poll', 'history')
    limit 1;
    if v_id is not null then return v_id; end if;

    v_pick := public.pick_touch(p_date);
    if v_pick is null then return null; end if;

    update public.daily_touches set used_on = p_date
    where id = v_pick and used_on is null
    returning id into v_id;

    if v_id is null then
        select id into v_id
        from public.daily_touches
        where used_on = p_date and kind in ('poll', 'history')
        limit 1;
    end if;
    return v_id;
exception when unique_violation then
    select id into v_id
    from public.daily_touches
    where used_on = p_date and kind in ('poll', 'history')
    limit 1;
    return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.claim_trivia(p_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id uuid; v_pick uuid;
begin
    select id into v_id
    from public.daily_touches
    where used_on = p_date and kind = 'trivia'
    limit 1;
    if v_id is not null then return v_id; end if;

    v_pick := public.pick_trivia(p_date);
    if v_pick is null then return null; end if;

    update public.daily_touches set used_on = p_date
    where id = v_pick and used_on is null
    returning id into v_id;

    if v_id is null then
        select id into v_id
        from public.daily_touches
        where used_on = p_date and kind = 'trivia'
        limit 1;
    end if;
    return v_id;
exception when unique_violation then
    select id into v_id
    from public.daily_touches
    where used_on = p_date and kind = 'trivia'
    limit 1;
    return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.claim_trivia_for_published_briefing()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
    if new.status = 'published' then
        perform public.claim_trivia(new.briefing_date);
    end if;
    return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.compose_briefing(p_date date, p_weather jsonb DEFAULT NULL::jsonb, p_fallback_title text DEFAULT NULL::text, p_fallback_body text DEFAULT NULL::text, p_fallback_deeplink text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
    c_near_days constant int := 14; c_bank_floor constant int := 10;
    v_yesterday_lead uuid; v_featured int := 0; v_mode text; v_touch_id uuid;
    v_spotlight_id uuid; v_bank int; v_title text; v_body text; v_deeplink text;
begin
    insert into public.daily_briefings (briefing_date, weather, status)
    values (p_date, p_weather, 'draft')
    on conflict (briefing_date) do update
        set weather = coalesce(excluded.weather, public.daily_briefings.weather);

    select event_id into v_yesterday_lead from public.briefing_featured
    where briefing_date = p_date - 1 and rank = 1;

    delete from public.briefing_featured where briefing_date = p_date;

    with candidates as (
        select e.id, e.event_date,
               (select count(*) from public.event_rsvps r where r.event_id = e.id) as rsvps
        from public.club_events e
        where e.status='approved' and e.submitted_by is not null
          and coalesce(e.kind,'event')='event' and e.event_date is not null
          and e.event_date >= p_date
    ),
    ranked as (
        select id, row_number() over (
            order by (id is not distinct from v_yesterday_lead), event_date asc, rsvps desc, id) as rnk
        from candidates where event_date <= p_date + c_near_days
    )
    insert into public.briefing_featured (briefing_date, event_id, rank)
    select p_date, id, rnk from ranked where rnk <= 3;

    get diagnostics v_featured = row_count;
    v_mode := 'near';

    if v_featured = 0 then
        insert into public.briefing_featured (briefing_date, event_id, rank)
        select p_date, e.id, 1 from public.club_events e
        where e.status='approved' and e.submitted_by is not null
          and coalesce(e.kind,'event')='event' and e.event_date is not null
          and e.event_date >= p_date
        order by e.event_date asc, e.id limit 1;
        get diagnostics v_featured = row_count;
        v_mode := case when v_featured > 0 then 'next_up' else 'evergreen' end;
    end if;

    if v_featured = 0 then
        v_title := coalesce(p_fallback_title, 'The Lake Wobegon Trail is open');
        v_body := coalesce(p_fallback_body, 'Nothing on the calendar today. The trailhead is a few blocks from here.');
        v_deeplink := coalesce(p_fallback_deeplink, 'activities');
    end if;

    v_touch_id := public.claim_touch(p_date);

    select count(*) into v_bank from public.daily_touches
    where used_on is null and kind='poll' and season in ('any', public.season_of(p_date));

    select spotlight_id into v_spotlight_id from public.daily_briefings where briefing_date = p_date;
    if v_spotlight_id is null then
        update public.spotlights set last_shown = p_date
        where id = (select id from public.spotlights where active
                    order by last_shown asc nulls first, slug limit 1)
        returning id into v_spotlight_id;
    end if;

    update public.daily_briefings
    set spotlight_id = v_spotlight_id, fallback_title = v_title,
        fallback_body = v_body, fallback_deeplink = v_deeplink
    where briefing_date = p_date;

    return jsonb_build_object(
        'briefing_date', to_char(p_date,'YYYY-MM-DD'), 'featured_mode', v_mode,
        'featured_count', v_featured, 'touch_id', v_touch_id,
        'touch_season', (select season from public.daily_touches where id = v_touch_id),
        'spotlight_id', v_spotlight_id, 'bank_remaining_in_season', v_bank,
        'bank_low', v_bank < c_bank_floor, 'status', 'draft');
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_event_comments(e_id uuid)
 RETURNS TABLE(id uuid, body text, created_at timestamp with time zone, author_id uuid, author_name text, author_avatar text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    select ec.id, ec.body, ec.created_at, ec.user_id,
           coalesce(tp.display_name, 'A neighbor') as author_name,
           tp.avatar_url                            as author_avatar
    from public.event_comments ec
    left join public.town_profiles tp on tp.user_id = ec.user_id
    where ec.event_id = e_id
    order by ec.created_at asc;
$function$;

CREATE OR REPLACE FUNCTION public.get_feed_postings(limit_n integer DEFAULT 30)
 RETURNS TABLE(id uuid, title text, event_date date, start_time text, location text, image_url text, created_at timestamp with time zone, poster_type text, poster_id uuid, poster_name text, poster_avatar text, like_count integer, comment_count integer, going_count integer, follower_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.get_today_briefing(p_date date DEFAULT NULL::date, p_tz text DEFAULT 'America/Chicago'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    with request_context as (
        select coalesce(p_date, (now() at time zone p_tz)::date) as v_date
    ),
    briefing as (
        select db.* from public.daily_briefings db
        cross join request_context rc
        where db.briefing_date = rc.v_date and db.status = 'published'
        limit 1
    ),
    featured_rows as (
        select bf.rank,
               jsonb_build_object(
                   'rank', row_number() over (order by bf.rank),
                   'id', e.id, 'title', e.title,
                   'event_date', to_char(e.event_date, 'YYYY-MM-DD'),
                   'start_time', e.start_time, 'location', e.location,
                   'image_url', e.image_url, 'club_name', c.name,
                   'category', coalesce(e.category, 'other'),
                   'going_count', coalesce(going.n, 0)::int,
                   'going_avatars', coalesce(avatars.items, '[]'::jsonb),
                   'like_count', coalesce(likes.n, 0)::int,
                   'comment_count', coalesce(comments.n, 0)::int,
                   'rsvpd', exists (select 1 from public.event_rsvps r
                                    where r.event_id = e.id and r.user_id = (select auth.uid())),
                   'saved', exists (select 1 from public.event_saves s
                                    where s.event_id = e.id and s.user_id = (select auth.uid())),
                   'liked', exists (select 1 from public.event_likes l
                                    where l.event_id = e.id and l.user_id = (select auth.uid()))
               ) as item
        from public.briefing_featured bf
        join briefing b on b.briefing_date = bf.briefing_date
        join public.club_events e on e.id = bf.event_id
        left join public.clubs c on c.id = e.club_id
        left join lateral (select count(*) as n from public.event_rsvps er where er.event_id = e.id) going on true
        left join lateral (
            select coalesce(jsonb_agg(p.avatar_url order by p.user_id), '[]'::jsonb) as items
            from (select er.user_id, tp.avatar_url
                  from public.event_rsvps er
                  join public.town_profiles tp on tp.user_id = er.user_id
                  where er.event_id = e.id and tp.avatar_url is not null
                  order by er.user_id limit 3) p
        ) avatars on true
        left join lateral (select count(*) as n from public.event_likes el where el.event_id = e.id) likes on true
        left join lateral (select count(*) as n from public.event_comments ec where ec.event_id = e.id) comments on true
        where e.status = 'approved' and e.submitted_by is not null
    ),
    featured_module as (
        select coalesce(jsonb_agg(fr.item order by fr.rank), '[]'::jsonb) as items from featured_rows fr
    ),
    touch_module as (
        select jsonb_build_object(
                   'id', dt.id, 'kind', dt.kind, 'prompt', dt.prompt,
                   'options', dt.options, 'body', dt.body,
                   'vote_counts', case when dt.kind = 'poll'
                                       then coalesce(tally.j -> 'vote_counts', '[]'::jsonb)
                                       else '[]'::jsonb end,
                   'total_votes', case when dt.kind = 'poll'
                                       then coalesce((tally.j ->> 'total_votes')::int, 0)
                                       else 0 end,
                   'my_vote', (
                       select tv.option_idx from public.touch_votes tv
                       where tv.touch_id = dt.id
                         and tv.user_id = (select auth.uid())
                         and jsonb_typeof(dt.options) = 'array'
                         and tv.option_idx < jsonb_array_length(dt.options)
                       limit 1
                   )
               ) as item
        from public.daily_touches dt
        cross join request_context rc
        cross join briefing b
        left join lateral (select public.touch_tally(dt.id) as j) tally on true
        where dt.used_on = rc.v_date
          and dt.kind in ('poll', 'history')
        limit 1
    ),
    spotlight_module as (
        select jsonb_build_object(
                   'id', s.id, 'slug', s.slug, 'title', s.title,
                   'blurb', s.blurb, 'image_url', s.image_url, 'place_id', s.place_id
               ) as item
        from public.spotlights s
        join briefing b on b.spotlight_id = s.id
        where s.active
        limit 1
    )
    select jsonb_build_object(
               'briefing_date', to_char(rc.v_date, 'YYYY-MM-DD'),
               'tz', p_tz,
               'status', case when b.briefing_date is null then 'none' else 'published' end,
               'published_at', b.published_at,
               'weather', b.weather,
               'featured', fm.items,
               'featured_fallback', case when jsonb_array_length(fm.items) = 0 and b.fallback_body is not null
                                         then jsonb_build_object('kind','evergreen','title',b.fallback_title,
                                                                 'body',b.fallback_body,'deeplink',b.fallback_deeplink)
                                         else null end,
               'touch', tm.item,
               'spotlight', sm.item,
               'caught_up', jsonb_build_object(
                   'next_briefing_at', ((rc.v_date + 1) + time '06:00') at time zone p_tz,
                   'label', 'New briefing at 6 AM')
           )
    from request_context rc
    cross join featured_module fm
    left join briefing b on true
    left join touch_module tm on true
    left join spotlight_module sm on true;
$function$;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(auth.jwt() ->> 'email', '') = 'jessewallacejohnson1@icloud.com'
$function$;

CREATE OR REPLACE FUNCTION public.pick_touch(p_date date)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    select id from public.daily_touches
    where used_on is null and kind = 'poll'
      and season in ('any', public.season_of(p_date))
    order by (season = 'any'), created_at, id
    limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.pick_trivia(p_date date)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    select id
    from public.daily_touches
    where used_on is null and kind = 'trivia'
    order by created_at, id
    limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.publish_briefing(p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_touch uuid; v_featured int;
begin
    select id into v_touch from public.daily_touches where used_on = p_date;
    select count(*) into v_featured from public.briefing_featured where briefing_date = p_date;

    if v_touch is null and v_featured = 0 then
        return jsonb_build_object('published', false,
                                  'reason', 'nothing to publish: no touch and no featured events');
    end if;

    update public.daily_briefings
    set status = 'published', published_at = coalesce(published_at, now())
    where briefing_date = p_date;

    if not found then
        return jsonb_build_object('published', false, 'reason', 'no briefing row for that date');
    end if;

    return jsonb_build_object('published', true, 'briefing_date', to_char(p_date, 'YYYY-MM-DD'));
end;
$function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.run_briefing_reconcile()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
    v_today    date;
    v_tomorrow date;
    v_status   text;
    v_actions  jsonb := '[]'::jsonb;
begin
    v_today    := (now() at time zone 'America/Chicago')::date;
    v_tomorrow := v_today + 1;

    select status into v_status from public.daily_briefings where briefing_date = v_today;

    if v_status is null then
        perform public.compose_briefing(v_today);
        v_actions := v_actions || jsonb_build_array(
            jsonb_build_object('action', 'composed_today', 'date', v_today));
        v_status := 'draft';
    end if;

    if v_status <> 'published' then
        v_actions := v_actions || jsonb_build_array(
            jsonb_build_object('action', 'published_today',
                               'result', public.publish_briefing(v_today)));
    end if;

    if not exists (select 1 from public.daily_briefings where briefing_date = v_tomorrow) then
        v_actions := v_actions || jsonb_build_array(
            jsonb_build_object('action', 'drafted_tomorrow',
                               'result', public.compose_briefing(v_tomorrow)));
    end if;

    return jsonb_build_object(
        'ran_at', now(),
        'town_date', v_today,
        'actions', v_actions,
        'bank_remaining_in_season', (
            select count(*) from public.daily_touches
            where used_on is null and kind = 'poll'
              and season in ('any', public.season_of(v_today))
        )
    );
end;
$function$;

CREATE OR REPLACE FUNCTION public.season_of(p_date date)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    select case extract(month from p_date)::int
               when 12 then 'winter' when 1 then 'winter' when 2 then 'winter'
               when 3 then 'spring'  when 4 then 'spring' when 5 then 'spring'
               when 6 then 'summer'  when 7 then 'summer' when 8 then 'summer'
               else 'fall'
           end;
$function$;

CREATE OR REPLACE FUNCTION public.touch_stats(p_touch_id uuid)
 RETURNS TABLE(correct_answer_percentage smallint, response_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    with trivia as (
        select id, correct_idx
        from public.daily_touches
        where id = p_touch_id
          and kind = 'trivia'
          and used_on is not null
    ),
    aggregate as (
        select count(tv.user_id)::bigint as responses,
               count(tv.user_id) filter (
                   where tv.option_idx = trivia.correct_idx
               )::bigint as correct
        from trivia
        left join public.touch_votes tv on tv.touch_id = trivia.id
    )
    select case
               when responses < 10 then null
               else round((correct::numeric * 100) / responses)::smallint
           end,
           responses
    from aggregate;
$function$;

CREATE OR REPLACE FUNCTION public.touch_tally(p_touch_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    with t as (
        select options from public.daily_touches where id = p_touch_id
    ),
    counted as (
        select tv.option_idx, count(*)::int as n
        from public.touch_votes tv
        where tv.touch_id = p_touch_id
        group by tv.option_idx
    ),
    aligned as (
        select idx.i, coalesce(c.n, 0) as n
        from t
        cross join lateral generate_series(
            0, greatest(jsonb_array_length(t.options) - 1, -1)
        ) as idx(i)
        left join counted c on c.option_idx = idx.i
    )
    select jsonb_build_object(
        'vote_counts', coalesce((select jsonb_agg(n order by i) from aligned), '[]'::jsonb),
        'total_votes', coalesce((select sum(n)::int from aligned), 0)
    );
$function$;

CREATE OR REPLACE FUNCTION public.trivia_streak(p_tz text DEFAULT 'America/Chicago'::text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    with request_context as (
        select (now() at time zone p_tz)::date as today
    ),
    served as (
        select dt.used_on,
               tv.option_idx is not null as answered,
               tv.option_idx = dt.correct_idx as correct
        from public.daily_touches dt
        cross join request_context rc
        left join public.touch_votes tv
          on tv.touch_id = dt.id
         and tv.user_id = (select auth.uid())
        where dt.kind = 'trivia'
          and dt.used_on is not null
          and dt.used_on <= rc.today
    ),
    eligible as (
        select served.*
        from served
        cross join request_context rc
        where not (served.used_on = rc.today and not served.answered)
    ),
    numbered as (
        select row_number() over (order by used_on desc)::int as rn,
               coalesce(correct, false) as correct
        from eligible
    )
    select coalesce(
        (select min(rn) - 1 from numbered where not correct),
        (select count(*)::int from numbered),
        0
    );
$function$;

CREATE OR REPLACE FUNCTION public.validate_touch_vote()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_options jsonb; v_used_on date;
begin
    select options, used_on into v_options, v_used_on
    from public.daily_touches where id = new.touch_id;

    if not found then
        raise exception 'touch % does not exist', new.touch_id;
    end if;

    if v_used_on is null then
        raise exception 'touch % has not been served yet', new.touch_id
            using errcode = 'check_violation';
    end if;

    if v_options is null or jsonb_typeof(v_options) <> 'array'
       or new.option_idx >= jsonb_array_length(v_options) then
        raise exception 'option_idx % is out of range for touch %', new.option_idx, new.touch_id
            using errcode = 'check_violation';
    end if;

    return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.waitlist_business_count()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select count(*) from public.waitlist where business_name is not null;
$function$;

CREATE OR REPLACE FUNCTION public.waitlist_count()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select count(*) from public.waitlist;
$function$;


-- ── Triggers ────────────────────────────────────────────────────────────────
CREATE TRIGGER daily_briefings_claim_trivia AFTER INSERT OR UPDATE OF status ON public.daily_briefings FOR EACH ROW WHEN ((new.status = 'published'::text)) EXECUTE FUNCTION claim_trivia_for_published_briefing();
CREATE TRIGGER touch_votes_validate BEFORE INSERT ON public.touch_votes FOR EACH ROW EXECUTE FUNCTION validate_touch_vote();
create event trigger ensure_rls on ddl_command_end when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function public.rls_auto_enable();


-- ── Row level security policies ─────────────────────────────────────────────

create policy "bizops_ro_read" on public.agent_events
  for select to bizops_ro
  using (true);

create policy "bizops_ro_read" on public.app_events
  for select to bizops_ro
  using (true);
create policy "own events insert" on public.app_events
  for insert to authenticated
  with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "own events select" on public.app_events
  for select to authenticated
  using ((( SELECT auth.uid() AS uid) = user_id));

create policy "bizops_ro_read" on public.board_items
  for select to bizops_ro
  using (true);
create policy "read published items" on public.board_items
  for select to public
  using ((status = 'published'::text));

create policy "bizops_ro_read" on public.board_sweeps
  for select to bizops_ro
  using (true);
create policy "board_sweeps_select_authenticated" on public.board_sweeps
  for select to authenticated
  using (true);

create policy "bizops_ro_read" on public.briefing_featured
  for select to bizops_ro
  using (true);
create policy "briefing featured select" on public.briefing_featured
  for select to authenticated
  using (true);

create policy "bizops_ro_read" on public.club_events
  for select to bizops_ro
  using (true);
create policy "delete events" on public.club_events
  for delete to public
  using ((is_admin() OR ((submitted_by = auth.uid()) AND (status = 'pending'::text))));
create policy "moderate events" on public.club_events
  for update to public
  using ((is_admin() OR ((submitted_by = auth.uid()) AND (status = 'pending'::text))))
  with check ((is_admin() OR ((submitted_by = auth.uid()) AND (status = 'pending'::text))));
create policy "read events" on public.club_events
  for select to public
  using (((status = 'approved'::text) OR (submitted_by = auth.uid()) OR is_admin()));
create policy "submit events" on public.club_events
  for insert to public
  with check ((submitted_by = auth.uid()));

create policy "bizops_ro_read" on public.club_members
  for select to bizops_ro
  using (true);
create policy "join club" on public.club_members
  for insert to public
  with check ((user_id = auth.uid()));
create policy "leave club" on public.club_members
  for delete to public
  using ((user_id = auth.uid()));
create policy "read memberships" on public.club_members
  for select to authenticated
  using (true);

create policy "bizops_ro_read" on public.clubs
  for select to bizops_ro
  using (true);
create policy "delete clubs" on public.clubs
  for delete to public
  using ((is_admin() OR ((submitted_by = auth.uid()) AND (status = 'pending'::text))));
create policy "moderate clubs" on public.clubs
  for update to public
  using ((is_admin() OR ((submitted_by = auth.uid()) AND (status = 'pending'::text))))
  with check ((is_admin() OR ((submitted_by = auth.uid()) AND (status = 'pending'::text))));
create policy "read clubs" on public.clubs
  for select to public
  using (((status = 'approved'::text) OR (submitted_by = auth.uid()) OR is_admin()));
create policy "submit clubs" on public.clubs
  for insert to public
  with check (((submitted_by = auth.uid()) AND ((status = 'pending'::text) OR is_admin())));

create policy "bizops_ro_read" on public.content_candidates
  for select to bizops_ro
  using (true);

create policy "bizops_ro_read" on public.content_decisions
  for select to bizops_ro
  using (true);

create policy "bizops_ro_read" on public.daily_briefings
  for select to bizops_ro
  using (true);
create policy "published briefings select" on public.daily_briefings
  for select to authenticated
  using ((status = 'published'::text));

create policy "bizops_ro_read" on public.daily_quests
  for select to bizops_ro
  using (true);
create policy "read quests" on public.daily_quests
  for select to public
  using (true);
create policy "write quests" on public.daily_quests
  for all to public
  using (is_admin())
  with check (is_admin());

create policy "bizops_ro_read" on public.daily_touches
  for select to bizops_ro
  using (true);
create policy "daily touches select" on public.daily_touches
  for select to authenticated
  using ((used_on IS NOT NULL));

create policy "bizops_ro_read" on public.event_comments
  for select to bizops_ro
  using (true);
create policy "own comments delete" on public.event_comments
  for delete to public
  using ((auth.uid() = user_id));
create policy "own comments insert" on public.event_comments
  for insert to public
  with check ((auth.uid() = user_id));
create policy "own comments select" on public.event_comments
  for select to public
  using ((auth.uid() = user_id));

create policy "own completions are deletable" on public.event_completions
  for delete to public
  using ((auth.uid() = user_id));
create policy "own completions are insertable" on public.event_completions
  for insert to public
  with check ((auth.uid() = user_id));
create policy "own completions are readable" on public.event_completions
  for select to public
  using ((auth.uid() = user_id));

create policy "bizops_ro_read" on public.event_likes
  for select to bizops_ro
  using (true);
create policy "own likes delete" on public.event_likes
  for delete to public
  using ((auth.uid() = user_id));
create policy "own likes insert" on public.event_likes
  for insert to public
  with check ((auth.uid() = user_id));
create policy "own likes select" on public.event_likes
  for select to public
  using ((auth.uid() = user_id));

create policy "bizops_ro_read" on public.event_rsvps
  for select to bizops_ro
  using (true);
create policy "read rsvps" on public.event_rsvps
  for select to authenticated
  using (true);
create policy "rsvp delete" on public.event_rsvps
  for delete to public
  using ((user_id = auth.uid()));
create policy "rsvp insert" on public.event_rsvps
  for insert to public
  with check ((user_id = auth.uid()));

create policy "bizops_ro_read" on public.event_saves
  for select to bizops_ro
  using (true);
create policy "event saves select" on public.event_saves
  for select to authenticated
  using (true);
create policy "own saves delete" on public.event_saves
  for delete to public
  using ((auth.uid() = user_id));
create policy "own saves insert" on public.event_saves
  for insert to public
  with check ((auth.uid() = user_id));

create policy "bizops_ro_read" on public.evergreen_pool
  for select to bizops_ro
  using (true);
create policy "read evergreen" on public.evergreen_pool
  for select to public
  using ((active = true));

create policy "own rows" on public.food_logs
  for all to public
  using ((auth.uid() = user_id))
  with check ((auth.uid() = user_id));

create policy "admin delete places" on public.places
  for delete to public
  using (is_admin());
create policy "admin insert places" on public.places
  for insert to public
  with check (is_admin());
create policy "admin update places" on public.places
  for update to public
  using (is_admin())
  with check (is_admin());
create policy "bizops_ro_read" on public.places
  for select to bizops_ro
  using (true);
create policy "read places" on public.places
  for select to public
  using (true);

create policy "bizops_ro_read" on public.posting_dismissals
  for select to bizops_ro
  using (true);
create policy "own posting dismissals delete" on public.posting_dismissals
  for delete to authenticated
  using ((auth.uid() = user_id));
create policy "own posting dismissals insert" on public.posting_dismissals
  for insert to authenticated
  with check ((auth.uid() = user_id));
create policy "own posting dismissals select" on public.posting_dismissals
  for select to authenticated
  using ((auth.uid() = user_id));

create policy "own profile" on public.profiles
  for all to public
  using ((auth.uid() = user_id))
  with check ((auth.uid() = user_id));

create policy "bizops_ro_read" on public.quest_completions
  for select to bizops_ro
  using (true);
create policy "insert completion" on public.quest_completions
  for insert to public
  with check ((user_id = auth.uid()));
create policy "read completions" on public.quest_completions
  for select to authenticated
  using (true);

create policy "bizops_ro_read" on public.spotlight_weeks
  for select to bizops_ro
  using (true);
create policy "spotlight archive select" on public.spotlight_weeks
  for select to authenticated
  using (true);

create policy "bizops_ro_read" on public.spotlights
  for select to bizops_ro
  using (true);
create policy "spotlights select" on public.spotlights
  for select to authenticated
  using (true);

create policy "bizops_ro_read" on public.touch_votes
  for select to bizops_ro
  using (true);
create policy "own touch votes insert" on public.touch_votes
  for insert to authenticated
  with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "own touch votes select" on public.touch_votes
  for select to authenticated
  using ((( SELECT auth.uid() AS uid) = user_id));

create policy "bizops_ro_read" on public.town_follows
  for select to bizops_ro
  using (true);
create policy "own follows delete" on public.town_follows
  for delete to public
  using ((auth.uid() = follower_id));
create policy "own follows insert" on public.town_follows
  for insert to public
  with check ((auth.uid() = follower_id));
create policy "own follows select" on public.town_follows
  for select to public
  using ((auth.uid() = follower_id));

create policy "bizops_ro_read" on public.town_profiles
  for select to bizops_ro
  using (true);
create policy "town_profiles_insert_own" on public.town_profiles
  for insert to public
  with check ((auth.uid() = user_id));
create policy "town_profiles_select_own" on public.town_profiles
  for select to public
  using ((auth.uid() = user_id));
create policy "town_profiles_update_own" on public.town_profiles
  for update to public
  using ((auth.uid() = user_id))
  with check ((auth.uid() = user_id));

create policy "bizops_ro_read" on public.town_status
  for select to bizops_ro
  using (true);
create policy "town status readable" on public.town_status
  for select to authenticated
  using (true);

create policy "bizops_ro_read" on public.user_utility_prefs
  for select to bizops_ro
  using (true);
create policy "own utility prefs insert" on public.user_utility_prefs
  for insert to authenticated
  with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "own utility prefs select" on public.user_utility_prefs
  for select to authenticated
  using ((( SELECT auth.uid() AS uid) = user_id));
create policy "own utility prefs update" on public.user_utility_prefs
  for update to authenticated
  using ((( SELECT auth.uid() AS uid) = user_id))
  with check ((( SELECT auth.uid() AS uid) = user_id));

create policy "anon can join the waitlist" on public.waitlist
  for insert to anon
  with check ((((char_length(email) >= 6) AND (char_length(email) <= 254)) AND (POSITION(('@'::text) IN (email)) > 1) AND ((char_length(first_name) >= 1) AND (char_length(first_name) <= 80)) AND ((char_length(town) >= 1) AND (char_length(town) <= 120)) AND ((business_name IS NULL) OR ((char_length(business_name) >= 1) AND (char_length(business_name) <= 120))) AND ((business_kind IS NULL) OR ((char_length(business_kind) >= 1) AND (char_length(business_kind) <= 80))) AND ((business_kind IS NULL) OR (business_name IS NOT NULL))));

create policy "own rows" on public.workouts
  for all to public
  using ((auth.uid() = user_id))
  with check ((auth.uid() = user_id));


-- ── Grants that differ from Supabase's defaults ─────────────────────────────
-- Supabase gives anon, authenticated and service_role every privilege on new
-- tables and execute on new functions. These take back what the app must not have.
revoke all on table public.agent_events, public.board_sweeps, public.content_candidates, public.content_decisions from anon;
revoke all on table public.agent_events, public.content_candidates, public.content_decisions, public.waitlist from authenticated;
revoke update, delete on table public.app_events, public.touch_votes from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger, maintain on table public.board_sweeps from authenticated;
revoke insert, update, delete on table public.briefing_featured, public.daily_briefings, public.daily_touches, public.spotlights from anon, authenticated;
revoke select, update, delete, truncate, references, trigger, maintain on table public.waitlist from anon;
grant select on table public.agent_events, public.app_events, public.board_items, public.board_sweeps, public.briefing_featured, public.club_events, public.club_members, public.clubs, public.content_candidates, public.content_decisions, public.daily_briefings, public.daily_quests, public.daily_touches, public.event_comments, public.event_likes, public.event_rsvps, public.event_saves, public.evergreen_pool, public.places, public.posting_dismissals, public.quest_completions, public.spotlight_weeks, public.spotlights, public.touch_votes, public.town_follows, public.town_profiles, public.town_status, public.user_utility_prefs to bizops_ro;

revoke execute on function public.briefings_pending(p_from date, p_days integer) from public, anon, authenticated;
revoke execute on function public.claim_touch(p_date date) from public, anon, authenticated;
revoke execute on function public.claim_trivia(p_date date) from public, anon, authenticated;
revoke execute on function public.claim_trivia_for_published_briefing() from public, anon, authenticated;
revoke execute on function public.get_event_comments(e_id uuid) from public, anon;
revoke execute on function public.get_feed_postings(limit_n integer) from public, anon;
revoke execute on function public.get_today_briefing(p_date date, p_tz text) from public, anon;
revoke execute on function public.pick_touch(p_date date) from public, anon, authenticated;
revoke execute on function public.pick_trivia(p_date date) from public, anon, authenticated;
revoke execute on function public.publish_briefing(p_date date) from public, anon, authenticated;
revoke execute on function public.run_briefing_reconcile() from public, anon, authenticated;
revoke execute on function public.season_of(p_date date) from public, anon, authenticated;
revoke execute on function public.touch_stats(p_touch_id uuid) from public, anon;
revoke execute on function public.touch_tally(p_touch_id uuid) from public, anon, authenticated;
revoke execute on function public.trivia_streak(p_tz text) from public, anon;
revoke execute on function public.validate_touch_vote() from public, anon, authenticated;
revoke execute on function public.waitlist_business_count() from public;
revoke execute on function public.waitlist_count() from public;


-- ── Realtime ────────────────────────────────────────────────────────────────
alter publication supabase_realtime add table public.club_events, public.town_status;


-- ── Storage buckets and their policies ──────────────────────────────────────
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('event-images', 'event-images', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('place-logos', 'place-logos', true) on conflict (id) do nothing;

create policy "avatars_insert_own" on storage.objects
  for insert to authenticated
  with check (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));

create policy "avatars_read" on storage.objects
  for select to public
  using ((bucket_id = 'avatars'::text));

create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));

create policy "event images authenticated upload" on storage.objects
  for insert to authenticated
  with check ((bucket_id = 'event-images'::text));

create policy "event images public read" on storage.objects
  for select to public
  using ((bucket_id = 'event-images'::text));

create policy "place-logos admin delete" on storage.objects
  for delete to public
  using (((bucket_id = 'place-logos'::text) AND is_admin()));

create policy "place-logos admin insert" on storage.objects
  for insert to public
  with check (((bucket_id = 'place-logos'::text) AND is_admin()));

create policy "place-logos admin update" on storage.objects
  for update to public
  using (((bucket_id = 'place-logos'::text) AND is_admin()));

create policy "place-logos public read" on storage.objects
  for select to public
  using ((bucket_id = 'place-logos'::text));


-- ── Scheduled jobs ──────────────────────────────────────────────────────────
select cron.schedule('briefing-reconcile', '0 * * * *', $$select public.run_briefing_reconcile()$$);
