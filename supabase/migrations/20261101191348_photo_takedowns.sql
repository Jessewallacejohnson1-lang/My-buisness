-- The monthly photo refresh's take-down picks (BP app docs/plans/agent-guardrails/issues/09; Jesse's
-- yes, 2026-11-01). Each month it looks over every live photo and names the ones that aren't real
-- photos (another company's, a stock shot, a video still). Those picks lived only in its run log,
-- which comes back cut short, and on 2026-11-01 four of them were missed. Now each is a row here, and
-- the review page shows it beside the swaps with Take down or Keep.
--
-- The refresh only adds rows: a photo comes down only by Jesse's yes (the skill's `retire`). One pick
-- per photo, ever, so a photo he keeps (`kept_at`) isn't asked about again. The app never reads this.

create table if not exists public.photo_takedowns (
  photo_id    bigint primary key references public.place_photos (id) on delete cascade,
  reason      text not null,
  proposed_by text not null,
  added_at    timestamptz not null default now(),
  kept_at     timestamptz  -- Jesse's Keep; a Take down retires the photo itself
);

alter table public.photo_takedowns enable row level security;
revoke all on public.photo_takedowns from anon, authenticated;

-- The Watch key (loopholes 12): the refresh reads and adds picks, and nothing else.
grant select, insert on public.photo_takedowns to watch;
drop policy if exists "watch rows" on public.photo_takedowns;
create policy "watch rows" on public.photo_takedowns to watch using (true) with check (true);
