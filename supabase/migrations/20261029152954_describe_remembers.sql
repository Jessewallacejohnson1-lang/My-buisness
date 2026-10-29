-- The morning's describe step remembers each Event its helpers have researched (BP app smooth-mornings
-- 06), so an Event with nothing more to find isn't laid out again the next morning. `morning.py describe`
-- stamps it; `morning.py thin` lays out only Events without it. Only the job (service_role) writes it.
alter table public.club_events add column if not exists described_at timestamptz;
