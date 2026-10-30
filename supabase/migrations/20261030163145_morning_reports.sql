-- The morning report, one row a morning (BP app smooth-mornings 10). `morning.py finish` saves the
-- report it prints, and a second finish the same morning replaces that day's row, so the chat that
-- reports to Jesse reads one row instead of the cloud run's whole log. Only the morning job writes it,
-- with the service role (which skips row security); no one in the app reads it, so anon and
-- authenticated get no policy and no grant.

create table if not exists public.morning_reports (
  day      date primary key,
  report   text not null,
  saved_at timestamptz not null default now()
);

alter table public.morning_reports enable row level security;
revoke all on public.morning_reports from anon, authenticated;
