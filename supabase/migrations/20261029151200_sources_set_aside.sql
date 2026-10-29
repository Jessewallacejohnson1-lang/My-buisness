-- A watched page that keeps failing is set aside (BP app smooth-mornings 04; sources/CONTEXT.md,
-- "Set aside"). The fetch table remembers since when a page has been failing and when it was set
-- aside; run.py writes both and a good read clears both. A page failing three mornings in a row is
-- set aside: the morning job skips it except on Mondays. Its registry entry stays watched
-- (registry ADR-014, ADR-022).

alter table public.sources
  add column if not exists failing_since timestamptz,
  add column if not exists set_aside_at  timestamptz;
