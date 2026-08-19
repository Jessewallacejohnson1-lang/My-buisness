-- Control Room · Panel 3 — the build log.
--
-- One row per Claude Code hook firing (SessionStart / UserPromptSubmit /
-- PostToolUse / Stop), POSTed by .claude/hooks/log-event.sh through the
-- log-agent-event edge function. This is an ACTIVITY log, not a reasoning
-- log — the reasoning artifacts are ADRs written on purpose.

create table public.agent_events (
  id           bigserial primary key,
  session_id   text,
  prompt_id    text,                  -- ties all events from one prompt together
  occurred_at  timestamptz not null default now(),
  event        text not null,         -- SessionStart | UserPromptSubmit | PreToolUse | PostToolUse | Stop
  tool_name    text,
  repo         text,                  -- 'ios' | 'web'
  branch       text,
  file_path    text,
  summary      text,
  raw          jsonb not null
);

create index agent_events_session_occurred
  on public.agent_events (session_id, occurred_at);

-- Ops-only: writes come from the edge function's service role; reads from
-- bizops_ro. App clients get nothing.
alter table public.agent_events enable row level security;
revoke all on table public.agent_events from anon, authenticated;
