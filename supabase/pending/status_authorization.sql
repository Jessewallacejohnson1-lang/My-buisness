-- ⚠️ PROPOSAL — NOT APPLIED. Awaiting Jesse's sign-off before running on prod.
-- Addresses REVIEW.md correctness/foundation finding: whether a submitted event/club
-- is auto-published (status='approved') or queued is decided entirely CLIENT-SIDE
-- (CommunityAPI.submitClub / AddModel), not enforced by RLS. Any authenticated user
-- can talk to PostgREST directly and self-approve, bypassing moderation.
--
-- Fix: force status='pending' on INSERT unless the submitter is in a server-side
-- admin allowlist. This mirrors Admin.isAdmin (DateHelpers.swift) but makes it a real
-- server guarantee instead of a UI convention. RLS remains the true boundary.
--
-- Before applying:
--   1. Confirm the exact column/table names against prod (club_events.status, clubs.status).
--   2. Mirror the same guard in the Expo repo (@hygge/core) — the backend twin.
--   3. Decide the admin allowlist mechanism (a table beats a hardcoded email).

-- Option A — an admin allowlist table (preferred: no redeploy to add a moderator).
create table if not exists public.town_admins (
    email text primary key
);
alter table public.town_admins enable row level security;
-- (No policy = readable only via SECURITY DEFINER helpers / service role.)

create or replace function public.is_town_admin()
    returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.town_admins
        where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    );
$$;

-- Force non-admin inserts to 'pending' regardless of what the client sends.
create or replace function public.enforce_event_status()
    returns trigger language plpgsql as $$
begin
    if not public.is_town_admin() then
        new.status := 'pending';
    end if;
    return new;
end;
$$;

drop trigger if exists enforce_event_status on public.club_events;
create trigger enforce_event_status
    before insert on public.club_events
    for each row execute function public.enforce_event_status();

-- Repeat the same trigger for public.clubs if clubs carry a status column.
