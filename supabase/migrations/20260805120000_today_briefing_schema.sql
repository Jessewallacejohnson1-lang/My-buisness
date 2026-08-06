-- ============================================================================
-- Today briefing schema: editorial briefings, featured events, daily touches,
-- immutable votes, and rotating place spotlights for the authenticated app.
-- All client-facing tables use RLS; content writes remain service-role only.
-- ============================================================================

create table if not exists public.daily_briefings (
    briefing_date     date primary key,
    almanac_md        text not null,
    weather           jsonb,
    status            text not null default 'draft' check (status in ('draft', 'published')),
    published_at      timestamptz,
    created_at        timestamptz not null default now(),
    fallback_title    text,
    fallback_body     text,
    fallback_deeplink text
);

create table if not exists public.briefing_featured (
    briefing_date date not null references public.daily_briefings (briefing_date) on delete cascade,
    event_id      uuid not null references public.club_events (id) on delete cascade,
    rank          int not null check (rank between 1 and 3),
    primary key (briefing_date, rank),
    unique (briefing_date, event_id)
);

create table if not exists public.daily_touches (
    id         uuid primary key default gen_random_uuid(),
    kind       text not null check (kind in ('poll', 'history')),
    prompt     text not null,
    options    jsonb,
    body       text,
    used_on    date unique,
    created_at timestamptz not null default now(),
    check (
        (kind = 'poll' and options is not null)
        or (kind = 'history' and body is not null)
    )
);

create table if not exists public.touch_votes (
    touch_id   uuid not null references public.daily_touches (id) on delete cascade,
    user_id    uuid not null references auth.users (id) on delete cascade,
    option_idx int not null check (option_idx >= 0),
    created_at timestamptz not null default now(),
    primary key (touch_id, user_id)
);

create table if not exists public.spotlights (
    id         uuid primary key default gen_random_uuid(),
    slug       text unique not null,
    title      text not null,
    blurb      text not null,
    image_url  text,
    place_id   uuid references public.places (id) on delete set null,
    active     boolean not null default true,
    last_shown date
);

create index if not exists briefing_featured_event_id_idx
    on public.briefing_featured (event_id);

create index if not exists daily_touches_unused_idx
    on public.daily_touches (used_on)
    where used_on is null;

create index if not exists touch_votes_touch_id_idx
    on public.touch_votes (touch_id);

create index if not exists spotlights_active_last_shown_idx
    on public.spotlights (active, last_shown)
    where active;

alter table public.daily_briefings enable row level security;
alter table public.briefing_featured enable row level security;
alter table public.daily_touches enable row level security;
alter table public.touch_votes enable row level security;
alter table public.spotlights enable row level security;

drop policy if exists "published briefings select" on public.daily_briefings;
create policy "published briefings select" on public.daily_briefings
    for select to authenticated
    using (status = 'published');

drop policy if exists "briefing featured select" on public.briefing_featured;
create policy "briefing featured select" on public.briefing_featured
    for select to authenticated
    using (true);

drop policy if exists "daily touches select" on public.daily_touches;
create policy "daily touches select" on public.daily_touches
    for select to authenticated
    using (true);

drop policy if exists "own touch votes select" on public.touch_votes;
create policy "own touch votes select" on public.touch_votes
    for select to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists "own touch votes insert" on public.touch_votes;
create policy "own touch votes insert" on public.touch_votes
    for insert to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists "spotlights select" on public.spotlights;
create policy "spotlights select" on public.spotlights
    for select to authenticated
    using (true);
