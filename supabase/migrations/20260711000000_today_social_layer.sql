-- Today-tab social layer — follow / like / comment + feed RPC + on-this-day almanac.
-- Community-namespaced; shared project also backs the wellness app. Applied on a
-- Supabase BRANCH first, verified, then merged to prod. VERIFY against prod.
--
-- Privacy model: base rows are own-row RLS (a user sees only their own follows /
-- likes / comments directly). Public aggregates (counts) and public identity
-- (poster + commenter display_name / avatar_url only) are exposed through
-- SECURITY DEFINER functions, so each user's `interests` stays private.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Tables
-- ─────────────────────────────────────────────────────────────────────────────

-- Follows: a user follows a club or a community member (town_profile / user id).
create table if not exists public.town_follows (
    id          uuid primary key default gen_random_uuid(),
    follower_id uuid not null references auth.users (id) on delete cascade,
    target_type text not null check (target_type in ('club', 'profile')),
    target_id   uuid not null,
    created_at  timestamptz not null default now(),
    unique (follower_id, target_type, target_id)
);
create index if not exists town_follows_target_idx on public.town_follows (target_type, target_id);
create index if not exists town_follows_follower_idx on public.town_follows (follower_id);

-- Likes on a posting (club_events row).
create table if not exists public.event_likes (
    id         uuid primary key default gen_random_uuid(),
    event_id   uuid not null references public.club_events (id) on delete cascade,
    user_id    uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    unique (event_id, user_id)
);
create index if not exists event_likes_event_idx on public.event_likes (event_id);

-- Flat comments on a posting.
create table if not exists public.event_comments (
    id         uuid primary key default gen_random_uuid(),
    event_id   uuid not null references public.club_events (id) on delete cascade,
    user_id    uuid not null references auth.users (id) on delete cascade,
    body       text not null check (char_length(body) between 1 and 500),
    created_at timestamptz not null default now()
);
create index if not exists event_comments_event_idx on public.event_comments (event_id, created_at);

-- Curated "On this day in St. Joe" facts, keyed MM-DD. Seeded via verified
-- research only (real, cited facts). Absent day => the UI hides the line.
create table if not exists public.town_almanac (
    md         text primary key,          -- 'MM-DD'
    fact       text not null,
    source     text,
    link       text,
    updated_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. RLS — base rows are own-row; aggregates/identity come via functions below.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.town_follows   enable row level security;
alter table public.event_likes    enable row level security;
alter table public.event_comments enable row level security;
alter table public.town_almanac   enable row level security;

create policy "own follows select" on public.town_follows
    for select using (auth.uid() = follower_id);
create policy "own follows insert" on public.town_follows
    for insert with check (auth.uid() = follower_id);
create policy "own follows delete" on public.town_follows
    for delete using (auth.uid() = follower_id);

create policy "own likes select" on public.event_likes
    for select using (auth.uid() = user_id);
create policy "own likes insert" on public.event_likes
    for insert with check (auth.uid() = user_id);
create policy "own likes delete" on public.event_likes
    for delete using (auth.uid() = user_id);

create policy "own comments select" on public.event_comments
    for select using (auth.uid() = user_id);
create policy "own comments insert" on public.event_comments
    for insert with check (auth.uid() = user_id);
create policy "own comments delete" on public.event_comments
    for delete using (auth.uid() = user_id);

create policy "almanac public read" on public.town_almanac
    for select to authenticated using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Functions — public aggregates + public identity (SECURITY DEFINER).
--    Return only display_name / avatar_url + counts; never interests/emails.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.get_feed_postings(limit_n int default 30)
returns table (
    id            uuid,
    title         text,
    event_date    date,
    start_time    text,
    location      text,
    image_url     text,
    created_at    timestamptz,
    poster_type   text,
    poster_id     uuid,
    poster_name   text,
    poster_avatar text,
    like_count    int,
    comment_count int,
    going_count   int,
    follower_count int
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    with base as (
        select e.*,
               case when e.club_id is not null then 'club' else 'profile' end as p_type,
               coalesce(e.club_id, e.submitted_by)                            as p_id
        from public.club_events e
        where e.status = 'approved'
          and e.kind = 'event'
          and e.submitted_by is not null
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
returns table (
    id            uuid,
    body          text,
    created_at    timestamptz,
    author_id     uuid,
    author_name   text,
    author_avatar text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select ec.id, ec.body, ec.created_at, ec.user_id,
           coalesce(tp.display_name, 'A neighbor') as author_name,
           tp.avatar_url                            as author_avatar
    from public.event_comments ec
    left join public.town_profiles tp on tp.user_id = ec.user_id
    where ec.event_id = e_id
    order by ec.created_at asc;
$$;

revoke all on function public.get_feed_postings(int)   from public, anon;
revoke all on function public.get_event_comments(uuid) from public, anon;
grant execute on function public.get_feed_postings(int)   to authenticated;
grant execute on function public.get_event_comments(uuid) to authenticated;
