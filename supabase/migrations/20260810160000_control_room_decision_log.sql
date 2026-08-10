-- Control Room · Panel 1 — the decision log.
--
-- The almanac (and later: news, module 4, spotlight, trivia) records every
-- candidate it CONSIDERED, not just the winner. A decision with one candidate
-- is a bug, not a decision. Written by the 6am/content routines with the
-- service role; read by the bizops dashboard through the read-only bizops_ro
-- role (see 20260810161000_control_room_read_role.sql). App clients never
-- touch these tables.

create table public.content_decisions (
  id                  uuid primary key default gen_random_uuid(),
  run_id              uuid not null,            -- one execution of the routine
  decided_at          timestamptz not null default now(),
  surface             text not null,            -- 'almanac' | 'news' | 'module_4' | 'spotlight' | 'trivia'
  target_user_id      uuid,                     -- null = global / not personalized
  chosen_candidate_id uuid,
  rule_version        text not null,            -- bump whenever selection logic changes
  inputs              jsonb not null,           -- every signal the routine saw
  notes               text
);

create table public.content_candidates (
  id                uuid primary key default gen_random_uuid(),
  decision_id       uuid not null references public.content_decisions(id) on delete cascade,
  rank              int not null,
  source_url        text,
  source_name       text,
  trust_tier        text not null,              -- 'official' | 'corroborated' | 'evergreen'
  corroboration_ct  int not null default 0,
  score             numeric not null,
  score_breakdown   jsonb not null,             -- keys must sum to score
  outcome           text not null,              -- 'chosen' | 'rejected'
  rejection_reason  text,                       -- required when outcome='rejected'
  payload           jsonb not null,             -- the actual text that would render
  constraint content_candidates_outcome_check
    check (outcome in ('chosen', 'rejected')),
  constraint content_candidates_trust_tier_check
    check (trust_tier in ('official', 'corroborated', 'evergreen')),
  -- Spec write-rule 5, enforced at the schema: a rejection with no reason is
  -- exactly the black box this table exists to eliminate.
  constraint content_candidates_rejection_reason_required
    check (outcome <> 'rejected' or rejection_reason is not null)
);

create index content_decisions_surface_decided_at
  on public.content_decisions (surface, decided_at desc);
create index content_candidates_decision_rank
  on public.content_candidates (decision_id, rank);

-- Ops-only tables: RLS on, no policies for app roles, and the default
-- public-schema grants to the client roles are revoked outright.
alter table public.content_decisions enable row level security;
alter table public.content_candidates enable row level security;
revoke all on table public.content_decisions from anon, authenticated;
revoke all on table public.content_candidates from anon, authenticated;
