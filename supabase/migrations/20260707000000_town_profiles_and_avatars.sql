-- Community profiles + avatars — reconstructed from MAP_BUILD_LOG.md (applied 2026-07-07).
-- Community identity lives in town_profiles (own-row RLS), NOT the wellness app's
-- `profiles` table — the shared project backs two apps. VERIFY against prod.

-- town_profiles: one row per user, own-row RLS.
create table if not exists public.town_profiles (
    user_id      uuid primary key references auth.users (id) on delete cascade,
    display_name text,
    avatar_url   text,
    interests    text[] not null default '{}',
    onboarded_at timestamptz,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

alter table public.town_profiles enable row level security;

create policy "own row select" on public.town_profiles
    for select using (auth.uid() = user_id);
create policy "own row insert" on public.town_profiles
    for insert with check (auth.uid() = user_id);
create policy "own row update" on public.town_profiles
    for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Public `avatars` bucket: folder-scoped write ({uid}/avatar-*.jpg), public read.
insert into storage.buckets (id, name, public)
    values ('avatars', 'avatars', true)
    on conflict (id) do nothing;

create policy "avatars public read" on storage.objects
    for select using (bucket_id = 'avatars');
create policy "avatars owner insert" on storage.objects
    for insert with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars owner update" on storage.objects
    for update using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
