// Fixed stories for New event's posting rules (supabase/migrations/*_town_plus_posting.sql, BP app
// references/town-plus), run in PGlite: the instant check claims a plain pending Event of the
// caller's once, under 10 a day; the poster can't change it once claimed; photos go only in the
// poster's own folder. Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
const files = readdirSync(migrations).filter((f) => f.endsWith('_town_plus_posting.sql')).sort();

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
    shows_from date, interests text[], interests_tagged_at timestamptz, lat double precision,
    lng double precision, followers_only boolean, cancelled_at timestamptz, moved_at timestamptz,
    moved_from jsonb, live_score jsonb, final_score jsonb, scoring_plays jsonb);
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
  grant select, insert, update, delete on all tables in schema public, storage to anon, authenticated;
`);
for (const f of files) await db.exec(readFileSync(join(migrations, f), 'utf8'));

const ME = '00000000-0000-0000-0000-0000000000b2';
const YOU = '00000000-0000-0000-0000-0000000000c3';
const PHOTOS = 'https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/event-images/';
let n = 0;

async function as(role, sub) {
  await db.exec(`reset role; set role ${role};`);
  const claims = sub ? JSON.stringify({ sub, role, is_anonymous: false }) : '';
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
}

/** A pending Event of `who`'s, made as the admin would see it, with any extra columns set. */
async function posted(who, extra = {}) {
  await db.exec('reset role');
  const id = `00000000-0000-0000-0000-${String(++n).padStart(12, '0')}`;
  const row = { id, submitted_by: who, title: 'Porch concert', event_date: '2026-12-05', start_time: '19:00',
    location: 'Millstream Park', category: 'other', ...extra };
  const cols = Object.keys(row), vals = Object.values(row);
  await db.query(`insert into public.club_events (${cols.join(', ')}) values (${cols.map((_, i) => `$${i + 1}`).join(', ')})`, vals);
  return id;
}

async function claim(id, who) {
  await db.exec('reset role');
  return (await db.query(`select public.claim_submit($1, $2) as ok`, [id, who])).rows[0].ok;
}

test('a plain pending Event of the caller is claimed once', async () => {
  const id = await posted(ME);
  assert.equal(await claim(id, ME), true);
  assert.equal(await claim(id, ME), false);
});

test('nobody claims another neighbour\'s Event', async () => {
  const id = await posted(YOU);
  assert.equal(await claim(id, ME), false);
  assert.equal(await claim(id, YOU), true);
});

test('an Event dressed as a found one, a Group\'s, a team\'s or a business\'s is never claimed', async () => {
  for (const extra of [{ source_name: 'Bad Habit Brewing' }, { club_id: '00000000-0000-0000-0000-0000000000d4' },
    { place_entry_id: 'bad-habit-brewing' }, { team_ids: ['sju'] }, { draw: 3 }, { shows_from: '2026-11-02' },
    { kind: 'trail' }, { category: 'music' }, { followers_only: true }, { lat: 45.56 }]) {
    assert.equal(await claim(await posted(ME, extra), ME), false, JSON.stringify(extra));
  }
});

test('the photo must be the poster\'s own upload', async () => {
  assert.equal(await claim(await posted(ME, { image_url: `${PHOTOS}${ME}/0a1b-2c3d.jpg` }), ME), true);
  for (const url of [`${PHOTOS}${YOU}/0a1b.jpg`, `https://example.com/event-images/${ME}/0a1b.jpg`,
    `${PHOTOS}${ME}/../${YOU}/0a1b.jpg`, `${PHOTOS}${ME}/0a1b.jpg?swap=1`]) {
    assert.equal(await claim(await posted(ME, { image_url: url }), ME), false, url);
  }
});

test('10 claims a day, then none', async () => {
  const who = '00000000-0000-0000-0000-0000000000e5';
  for (let i = 0; i < 10; i++) assert.equal(await claim(await posted(who), who), true, `claim ${i + 1}`);
  assert.equal(await claim(await posted(who), who), false);
});

test('the poster can change a pending Event until the check claims it', async () => {
  const id = await posted(ME);
  await as('authenticated', ME);
  assert.equal((await db.query(`update public.club_events set title = 'Porch concert!' where id = $1`, [id])).affectedRows, 1);
  await claim(id, ME);
  await as('authenticated', ME);
  assert.equal((await db.query(`update public.club_events set title = 'Buy my stuff' where id = $1`, [id])).affectedRows, 0);
  await db.exec('reset role');
  assert.equal((await db.query(`select title from public.club_events where id = $1`, [id])).rows[0].title, 'Porch concert!');
});

test('the check can decline with its own reason', async () => {
  const id = await posted(ME);
  await db.exec('reset role');
  await db.query(`update public.club_events set status = 'rejected', review_reason = 'declined' where id = $1`, [id]);
});

test('photos go only in the poster\'s own folder', async () => {
  await as('authenticated', ME);
  await db.query(`insert into storage.objects (bucket_id, name) values ('event-images', $1)`, [`${ME}/abc.jpg`]);
  await assert.rejects(db.query(`insert into storage.objects (bucket_id, name) values ('event-images', $1)`, [`${YOU}/abc.jpg`]),
    /row-level security/);
  await db.exec('reset role');
  const bucket = (await db.query(`select file_size_limit, allowed_mime_types from storage.buckets where id = 'event-images'`)).rows[0];
  assert.equal(Number(bucket.file_size_limit), 10485760);
  assert.deepEqual(bucket.allowed_mime_types, ['image/jpeg', 'image/png', 'image/heic', 'image/webp']);
});

test('only the server may claim', async () => {
  await as('authenticated', ME);
  await assert.rejects(db.query(`select public.claim_submit($1, $2)`, [await (async () => {
    await db.exec('reset role'); const id = await posted(ME); await as('authenticated', ME); return id;
  })(), ME]), /permission denied/);
  await db.exec('reset role');
});
