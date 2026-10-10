// Fixed stories for anonymous accounts (supabase/migrations/*_anonymous_accounts.sql), run
// in PGlite under the live write rules they sit beside: an anonymous account can act on
// Events but can't publish. Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
const files = readdirSync(migrations)
  .filter((f) => f.endsWith('_anonymous_accounts.sql') || f.endsWith('_anonymous_profile_photos.sql'))
  .sort();

const db = await PGlite.create();
await db.exec(`
  create role anon; create role authenticated;
  create schema auth; create schema storage;
  grant usage on schema auth, storage to anon, authenticated;
  -- One claims JSON feeds both, as on Supabase.
  create function auth.jwt() returns jsonb language sql stable as
    $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(auth.jwt() ->> 'sub', '')::uuid $$;
  create function public.is_admin() returns boolean language sql stable as $$ select false $$;
  create function storage.foldername(name text) returns text[] language sql immutable as
    $$ select string_to_array(name, '/') $$;
  create function public.compose_briefing(p_date date, p_weather jsonb default null,
    p_fallback_title text default null, p_fallback_body text default null,
    p_fallback_deeplink text default null) returns void language sql as $$ select $$;

  create table public.club_events (id uuid primary key default gen_random_uuid(),
    submitted_by uuid, status text not null default 'pending', title text not null);
  create table public.clubs (id uuid primary key default gen_random_uuid(),
    submitted_by uuid, status text not null default 'pending', name text not null);
  create table public.event_comments (id uuid primary key default gen_random_uuid(),
    event_id uuid not null, user_id uuid not null, body text not null);
  create table public.event_rsvps (id uuid primary key default gen_random_uuid(),
    event_id uuid not null, user_id uuid not null);
  create table public.town_profiles (user_id uuid primary key, display_name text, avatar_url text);
  create table storage.objects (id uuid primary key default gen_random_uuid(),
    bucket_id text not null, name text not null);

  -- The live rules (schema.sql) these sit beside.
  alter table public.club_events enable row level security;
  alter table public.clubs enable row level security;
  alter table public.event_comments enable row level security;
  alter table public.event_rsvps enable row level security;
  alter table public.town_profiles enable row level security;
  alter table storage.objects enable row level security;
  create policy "submit events" on public.club_events for insert to public
    with check (submitted_by = auth.uid());
  create policy "submit clubs" on public.clubs for insert to public
    with check (submitted_by = auth.uid() and (status = 'pending' or is_admin()));
  create policy "own comments insert" on public.event_comments for insert to public
    with check (auth.uid() = user_id);
  create policy "rsvp insert" on public.event_rsvps for insert to public
    with check (user_id = auth.uid());
  create policy "rsvp delete" on public.event_rsvps for delete to public
    using (user_id = auth.uid());
  create policy "read rsvps" on public.event_rsvps for select to authenticated using (true);
  create policy "town_profiles_insert_own" on public.town_profiles for insert to public
    with check (auth.uid() = user_id);
  create policy "town_profiles_update_own" on public.town_profiles for update to public
    using (auth.uid() = user_id);
  create policy "town_profiles_select_own" on public.town_profiles for select to public
    using (auth.uid() = user_id);
  create policy "avatars_insert_own" on storage.objects for insert to authenticated
    with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
  create policy "event images authenticated upload" on storage.objects for insert to authenticated
    with check (bucket_id = 'event-images');
  grant select, insert, update, delete on all tables in schema public, storage to anon, authenticated;
`);
for (const f of files) await db.exec(readFileSync(join(migrations, f), 'utf8'));

const ANON_USER = '00000000-0000-0000-0000-0000000000a1';
const REAL_USER = '00000000-0000-0000-0000-0000000000b2';

async function as(role, sub, anonymous) {
  await db.exec(`reset role; set role ${role};`);
  const claims = sub ? JSON.stringify({ sub, role, is_anonymous: anonymous }) : '';
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
}
const denied = (sql, params = []) =>
  assert.rejects(db.query(sql, params), /row-level security|permission denied/);
const allowed = (sql, params = []) => db.query(sql, params);

test('an anonymous account can add and remove its own Going', async () => {
  await as('authenticated', ANON_USER, true);
  const event = '00000000-0000-0000-0000-00000000e001';
  await allowed(`insert into public.event_rsvps (event_id, user_id) values ($1, $2)`, [event, ANON_USER]);
  await allowed(`delete from public.event_rsvps where event_id = $1 and user_id = $2`, [event, ANON_USER]);
  await denied(`insert into public.event_rsvps (event_id, user_id) values ($1, $2)`, [event, REAL_USER]);
});

test('an anonymous account keeps its own profile name, but no photo link', async () => {
  await as('authenticated', ANON_USER, true);
  await allowed(`insert into public.town_profiles (user_id, display_name) values ($1, 'Sam')`, [ANON_USER]);
  await allowed(`update public.town_profiles set display_name = 'Sam B' where user_id = $1`, [ANON_USER]);
  await denied(`update public.town_profiles set avatar_url = 'https://example.com/x.jpg' where user_id = $1`, [ANON_USER]);
  await as('authenticated', REAL_USER, false);
  await allowed(`insert into public.town_profiles (user_id, avatar_url) values ($1, 'https://example.com/me.jpg')`, [REAL_USER]);
});

test('an anonymous account cannot post an Event, a club, a comment or a photo', async () => {
  await as('authenticated', ANON_USER, true);
  await denied(`insert into public.club_events (submitted_by, title, status) values ($1, 'Spam', 'approved')`, [ANON_USER]);
  await denied(`insert into public.clubs (submitted_by, name) values ($1, 'Spam club')`, [ANON_USER]);
  await denied(`insert into public.event_comments (event_id, user_id, body)
                values ('00000000-0000-0000-0000-00000000e001', $1, 'spam')`, [ANON_USER]);
  await denied(`insert into storage.objects (bucket_id, name) values ('event-images', 'x.jpg')`);
  await denied(`insert into storage.objects (bucket_id, name) values ('avatars', $1)`, [`${ANON_USER}/me.jpg`]);
});

test('a real account still posts, comments and uploads as before', async () => {
  await as('authenticated', REAL_USER, false);
  await allowed(`insert into public.club_events (submitted_by, title) values ($1, 'Trivia')`, [REAL_USER]);
  await allowed(`insert into public.clubs (submitted_by, name) values ($1, 'Book club')`, [REAL_USER]);
  await allowed(`insert into public.event_comments (event_id, user_id, body)
                 values ('00000000-0000-0000-0000-00000000e001', $1, 'See you there')`, [REAL_USER]);
  await allowed(`insert into storage.objects (bucket_id, name) values ('avatars', $1)`, [`${REAL_USER}/me.jpg`]);
  // A session from before anonymous sign-in carries no is_anonymous claim: still real.
  await as('authenticated', REAL_USER, undefined);
  await allowed(`insert into public.club_events (submitted_by, title) values ($1, 'Quiz')`, [REAL_USER]);
});

test('nobody outside the nightly job can write a briefing', async () => {
  for (const role of ['anon', 'authenticated']) {
    await as(role, role === 'anon' ? null : REAL_USER, false);
    await assert.rejects(db.query(`select public.compose_briefing(current_date)`), /permission denied/);
  }
  await db.exec('reset role');
});
