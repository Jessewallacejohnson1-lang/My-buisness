// Fixed stories for a neighbour's post (supabase/migrations/*_post_screen_posts.sql, BP app
// references/post-screen, town-feed 29), run in PGlite on top of town-plus's posting rules: the check
// also claims a post (no day, words or a photo, tagged ids kept only for friends), an Event stays the
// Town's, Friends-only holds in the read rule, and the poster deletes their own post and its photo.
// The feed's side is in town_feed.test.mjs. Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
const files = readdirSync(migrations)
  .filter((f) => ['_town_plus_posting.sql', '_town_plus_empty_interests.sql', '_post_screen_posts.sql', '_post_screen_tag_order.sql']
    .some((end) => f.endsWith(end))).sort();

const db = await PGlite.create();
await db.exec(`
  create role anon; create role authenticated; create role service_role;
  create schema auth; create schema storage;
  grant usage on schema auth, storage to anon, authenticated;
  create function auth.jwt() returns jsonb language sql stable as
    $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(auth.jwt() ->> 'sub', '')::uuid $$;
  create function public.is_admin() returns boolean language sql stable as $$ select false $$;
  create function storage.foldername(name text) returns text[] language sql immutable as
    $$ select string_to_array(name, '/') $$;

  create table public.club_events (id uuid primary key default gen_random_uuid(),
    club_id uuid, submitted_by uuid, status text not null default 'pending', title text not null,
    event_date date, start_time text, location text, description text, image_url text,
    kind text not null default 'event', category text, review_reason text, rechecked_at timestamptz,
    source_name text, source_uid text, source_url text, place_entry_id text, team_ids text[],
    activity_team text, activity_name text, sport text, occasion text, what text, draw smallint,
    shows_from date, interests text[] default '{}', interests_tagged_at timestamptz, lat double precision,
    lng double precision, followers_only boolean default false, cancelled_at timestamptz, moved_at timestamptz,
    moved_from jsonb, live_score jsonb, final_score jsonb, scoring_plays jsonb,
    created_at timestamptz not null default now(), end_at timestamptz, all_day boolean not null default false,
    constraint club_events_kind_check check (kind in ('event', 'trail')));
  create schema private;
  grant usage on schema private to anon, authenticated;
  create table private.friendships (a uuid not null, b uuid not null, primary key (a, b), check (a < b));
  create table storage.buckets (id text primary key, name text, public boolean,
    file_size_limit bigint, allowed_mime_types text[]);
  insert into storage.buckets (id, name, public) values ('event-images', 'event-images', true);
  create table storage.objects (id uuid primary key default gen_random_uuid(),
    bucket_id text not null, name text not null);

  alter table public.club_events enable row level security;
  alter table storage.objects enable row level security;
  create policy "read events" on public.club_events for select to anon, authenticated using (true);
  create policy "submit events" on public.club_events for insert to public
    with check (submitted_by = (select auth.uid()) and (status = 'pending' or public.is_admin()));
  create policy "moderate events" on public.club_events for update to public
    using (public.is_admin() or (submitted_by = (select auth.uid()) and status = 'pending'))
    with check (public.is_admin() or (submitted_by = (select auth.uid()) and status = 'pending'));
  create policy "delete events" on public.club_events for delete to public
    using (public.is_admin() or (submitted_by = (select auth.uid()) and status = 'pending'));
  create policy "read photos" on storage.objects for select to anon, authenticated using (true);
  grant select, insert, update, delete on all tables in schema public, storage to anon, authenticated;
`);
for (const f of files) await db.exec(readFileSync(join(migrations, f), 'utf8'));

const ME = '00000000-0000-0000-0000-0000000000b2';
const YOU = '00000000-0000-0000-0000-0000000000c3';
const PHOTOS = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/';
const PAL = '00000000-0000-0000-0000-0000000000d4';
let n = 0;

async function as(role, sub) {
  await db.exec(`reset role; set role ${role};`);
  const claims = sub ? JSON.stringify({ sub, role, is_anonymous: false }) : '';
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
}

/** A pending post of `who`'s (or, with kind 'event', town-plus's plain Event), with any extra columns. */
async function posted(who, extra = {}) {
  await db.exec('reset role');
  const id = `00000000-0000-0000-0000-${String(++n).padStart(12, '0')}`;
  const base = extra.kind === 'event'
    ? { title: 'Porch concert', event_date: '2026-12-05', start_time: '19:00', location: 'Millstream Park' }
    : { kind: 'post', title: 'Anyone up for sledding?' };
  const row = { id, submitted_by: who, category: 'other', ...base, ...extra };
  const cols = Object.keys(row), vals = Object.values(row);
  await db.query(`insert into public.club_events (${cols.join(', ')}) values (${cols.map((_, i) => `$${i + 1}`).join(', ')})`, vals);
  return id;
}

async function claim(id, who) {
  await db.exec('reset role');
  return (await db.query(`select public.claim_submit($1, $2) as ok`, [id, who])).rows[0].ok;
}
const row = async (id) => { await db.exec('reset role');
  return (await db.query(`select * from public.club_events where id = $1`, [id])).rows[0]; };
await db.exec(`insert into private.friendships (a, b) values ('${[ME, PAL].sort().join("', '")}')`);

test('a post is claimed once, with words or a photo', async () => {
  const id = await posted(ME);
  assert.equal(await claim(id, ME), true);
  assert.equal(await claim(id, ME), false);
  assert.equal(await claim(await posted(ME, { title: '', image_url: `${PHOTOS}${ME}/0a1b.jpg` }), ME), true, 'a photo alone');
  assert.equal(await claim(await posted(ME, { title: '  ' }), ME), false, 'nothing at all');
  assert.equal(await claim(await posted(ME, { title: 'x'.repeat(2001) }), ME), false, 'over 2,000 letters');
});

test('a post has no day, time or end; a found, Group\'s or team\'s one is never claimed', async () => {
  for (const extra of [{ event_date: '2026-12-05' }, { start_time: '19:00' }, { end_at: '2026-12-05T20:00:00Z' },
    { all_day: true }, { source_name: 'Bad Habit Brewing' }, { club_id: '00000000-0000-0000-0000-0000000000f6' },
    { team_ids: ['sju'] }, { image_url: `${PHOTOS}${YOU}/0a1b.jpg` }]) {
    assert.equal(await claim(await posted(ME, extra), ME), false, JSON.stringify(extra));
  }
});

test('an Event stays the Town\'s: never Friends-only, never tagged', async () => {
  assert.equal(await claim(await posted(ME, { kind: 'event' }), ME), true, 'town-plus\'s plain Event still goes');
  assert.equal(await claim(await posted(ME, { kind: 'event', friends_only: true }), ME), false);
  assert.equal(await claim(await posted(ME, { kind: 'event', tagged: [PAL] }), ME), false);
});

test('tagged friends stay, anyone else is dropped, and the post still goes', async () => {
  const id = await posted(ME, { tagged: [YOU, PAL, PAL] });
  assert.equal(await claim(id, ME), true);
  assert.deepEqual((await row(id)).tagged, [PAL]);
  const none = await posted(ME, { tagged: [YOU] });
  assert.equal(await claim(none, ME), true);
  assert.equal((await row(none)).tagged, null);
  assert.equal(await claim(await posted(ME, { tagged: Array.from({ length: 21 }, () => PAL) }), ME), false, 'over 20 tags');
});

test('posts and Events share the 10 a day', async () => {
  const who = '00000000-0000-0000-0000-0000000000e5';
  for (let i = 0; i < 5; i++) assert.equal(await claim(await posted(who), who), true);
  for (let i = 0; i < 5; i++) assert.equal(await claim(await posted(who, { kind: 'event' }), who), true);
  assert.equal(await claim(await posted(who), who), false);
});

test('a Friends-only post is read only by the poster and their friends', async () => {
  await db.exec('reset role');
  const id = await posted(ME, { friends_only: true, status: 'approved' });
  const sees = async (role, who) => { await as(role, who);
    return (await db.query(`select 1 from public.club_events where id = $1`, [id])).rows.length === 1; };
  assert.equal(await sees('authenticated', ME), true);
  assert.equal(await sees('authenticated', PAL), true);
  assert.equal(await sees('authenticated', YOU), false);
  assert.equal(await sees('anon', null), false);
  await db.exec('reset role');
  await db.query(`update public.club_events set friends_only = false where id = $1`, [id]);
  assert.equal(await sees('authenticated', YOU), true, 'a Town post, everyone');
  await db.exec('reset role');
});

test('the poster deletes their own post, live or not, and its photo; never anyone else\'s', async () => {
  const live = await posted(ME, { status: 'approved' });
  const theirs = await posted(YOU, { status: 'approved' });
  const event = await posted(ME, { kind: 'event', status: 'approved' });
  await as('authenticated', ME);
  assert.equal((await db.query(`delete from public.club_events where id = $1`, [live])).affectedRows, 1);
  assert.equal((await db.query(`delete from public.club_events where id = $1`, [theirs])).affectedRows, 0);
  assert.equal((await db.query(`delete from public.club_events where id = $1`, [event])).affectedRows, 0,
               'a live Event stays: only a pending one is the poster\'s to delete');
  await db.exec('reset role');
  await db.query(`insert into storage.objects (bucket_id, name) values ('event-images', $1), ('event-images', $2)`,
                 [`${ME}/a.jpg`, `${YOU}/b.jpg`]);
  await as('authenticated', ME);
  assert.equal((await db.query(`delete from storage.objects where name = $1`, [`${ME}/a.jpg`])).affectedRows, 1);
  assert.equal((await db.query(`delete from storage.objects where name = $1`, [`${YOU}/b.jpg`])).affectedRows, 0);
  await db.exec('reset role');
});

test('a kind the app doesn\'t know is refused', async () => {
  await assert.rejects(posted(ME, { kind: 'poll' }), /club_events_kind_check/);
});

test('a photo\'s shape stays inside Instagram\'s limits, 4:5 tall to 1.91:1 wide', async () => {
  for (const aspect of [0.8, 1, 1.91]) assert.ok(await posted(ME, { image_aspect: aspect }));
  for (const aspect of [0.5, 2.5]) await assert.rejects(posted(ME, { image_aspect: aspect }), /club_events_image_aspect_check/);
});

test('tagged friends keep the order they were tagged in, once each', async () => {
  const PAL2 = '00000000-0000-0000-0000-0000000000e5';
  await db.exec(`reset role; insert into private.friendships (a, b) values ('${[ME, PAL2].sort().join("', '")}')`);
  const id = await posted(ME, { tagged: [PAL2, YOU, PAL, PAL2] });
  assert.equal(await claim(id, ME), true);
  assert.deepEqual((await row(id)).tagged, [PAL2, PAL]);
});
