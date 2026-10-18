// Fixed stories for get_groups and group_meetings (supabase/migrations/*_groups.sql), the Search
// tab's Groups shelf and a Group page's one read, and the 14 groups St. Joseph starts with
// (*_st_joseph_groups.sql), run in PGlite under the live read rules (BP app docs/plans/rsvp-and-groups,
// ticket 05). Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { creating } from './migrations.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const migrations = process.env.MIGRATIONS ?? join(here, '..', 'migrations');
const run = (f) => db.exec(readFileSync(join(migrations, f), 'utf8'));
const groupsFiles = creating(migrations, ['public.get_groups', 'public.group_meetings', 'private.member_count']);
const loadFile = readdirSync(migrations).find((f) => f.endsWith('_st_joseph_groups.sql'));

const db = await PGlite.create();
await db.exec(`
  set timezone = 'UTC';
  create role anon; create role authenticated;
  create schema auth; create schema private;
  grant usage on schema auth, private to anon, authenticated;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create function public.is_admin() returns boolean language sql stable as $$ select false $$;

  -- public.clubs and public.club_members as schema.sql makes them, with their live read rules.
  create table public.clubs (
    id uuid primary key default gen_random_uuid(), submitted_by uuid default auth.uid(),
    status text not null default 'pending', name text not null, host text, schedule text, vibe text,
    created_at timestamptz not null default now(), location text, description text, expectations text,
    image_url text);
  create table public.club_members (
    id uuid primary key default gen_random_uuid(), club_id uuid not null,
    user_id uuid not null default auth.uid(), created_at timestamptz not null default now(),
    unique (club_id, user_id));
  create table public.places (id uuid primary key default gen_random_uuid(), name text, entry_id text,
    search_logo jsonb);
  alter table public.clubs enable row level security;
  alter table public.club_members enable row level security;
  create policy "read clubs" on public.clubs for select to public
    using (status = 'approved' or submitted_by = auth.uid() or is_admin());
  create policy "read memberships" on public.club_members for select to authenticated using (true);
  grant select on all tables in schema public to anon, authenticated;
`);
await run('20261016150000_place_photos.sql');
await run('20261016170000_place_photo_kind.sql');
await db.exec('grant select on public.place_photos to anon, authenticated');
for (const f of creating(migrations, ['public.place_picture'])) await run(f);
for (const f of groupsFiles) await run(f);
await run(loadFile);

const ME = '00000000-0000-0000-0000-00000000000a';
const NEIGHBOUR = '00000000-0000-0000-0000-00000000000b';

async function groups(as) {
  await db.exec(as ? `set role authenticated; set request.jwt.claim.sub = '${as}'` : 'set role anon; reset request.jwt.claim.sub');
  const { rows } = await db.query('select * from public.get_groups()');
  await db.exec('reset role; reset request.jwt.claim.sub');
  return rows;
}
const idOf = async (name) => (await db.query('select id from public.clubs where name = $1', [name])).rows[0].id;
const join_ = (club, user) => db.query('insert into public.club_members (club_id, user_id) values ($1, $2)', [club, user]);
const meetings = async (meets, from) =>
  (await db.query('select public.group_meetings($1::jsonb, $2::date) as m', [JSON.stringify(meets), from])).rows[0].m;

test("St. Joseph's 14 groups load once, approved", async () => {
  await run(loadFile);
  const { rows } = await db.query("select count(*)::int as n, count(*) filter (where status = 'approved')::int as approved from public.clubs");
  assert.deepEqual(rows[0], { n: 14, approved: 14 }, 'running it again adds nothing');
});

test('only approved groups come back', async () => {
  await db.query("insert into public.clubs (name, status, submitted_by) values ('Waiting', 'pending', $1), ('Turned down', 'rejected', $1)", [ME]);
  const names = (await groups(ME)).map((g) => g.name);
  assert.equal(names.length, 14);
  assert.ok(!names.includes('Waiting') && !names.includes('Turned down'), 'not even the caller\'s own pending one');
  await db.exec("delete from public.clubs where status <> 'approved'");
});

test('the member count counts everyone; joined is the caller\'s own', async () => {
  const lions = await idOf('St. Joseph Lions Club'), book = await idOf('Book Discussion Group');
  await join_(lions, ME);
  await join_(lions, NEIGHBOUR);
  await join_(book, NEIGHBOUR);
  const mine = await groups(ME);
  const lionsRow = mine.find((g) => g.name === 'St. Joseph Lions Club'), bookRow = mine.find((g) => g.name === 'Book Discussion Group');
  assert.deepEqual([lionsRow.member_count, lionsRow.joined], [2, true]);
  assert.deepEqual([bookRow.member_count, bookRow.joined], [1, false]);
  assert.equal(mine[0].name, 'St. Joseph Lions Club', 'most members first');
  await db.exec('delete from public.club_members');
});

test('the public key reads it too: counts, never joined', async () => {
  await join_(await idOf('Laundry Love'), NEIGHBOUR);
  const rows = await groups(null);
  assert.equal(rows.length, 14);
  assert.equal(rows.find((g) => g.name === 'Laundry Love').member_count, 1, 'counted though anon can\'t read memberships');
  assert.ok(rows.every((g) => g.joined === false));
  await db.exec('delete from public.club_members');
});

test("pictures: the group's own first, else where it meets", async () => {
  await db.exec(`
    insert into public.place_photos (entry_id, url, source_url, position, kind, status, hue) values
      ('group-st-joseph-lions-club', 'https://x/lions-2.webp', 'https://e-clubhouse.org/', 1, 'photo', 'live', null),
      ('group-st-joseph-lions-club', 'https://x/lions-1.webp', 'https://e-clubhouse.org/', 0, 'photo', 'live', null),
      ('group-st-joseph-lions-club', 'https://x/old.webp', 'https://e-clubhouse.org/', 2, 'photo', 'retired', null),
      ('group-st-joe-rod-and-gun-club', 'https://x/deer.webp', 'https://stjoerodandgunclub.org/', 0, 'logo', 'live', 31),
      ('resurrection-lutheran-church', 'https://x/church.webp', 'https://rlcstjoe.com/', 0, 'photo', 'live', null);
    insert into public.places (name, entry_id, search_logo) values
      ('Legion', '328-american-legion-post', '{"url": "https://x/legion.webp", "hue": 25, "chroma": true}');`);
  const rows = Object.fromEntries((await groups(null)).map((g) => [g.name, g]));
  assert.deepEqual(rows['St. Joseph Lions Club'].photos.map((p) => p.url), ['https://x/lions-1.webp', 'https://x/lions-2.webp'],
    'its own live photos, cover first');
  assert.equal(rows['St. Joseph Lions Club'].logo, null);
  assert.deepEqual(rows['St. Joe Rod and Gun Club'].photos, [], 'its place, the Legion, has only a logo');
  assert.deepEqual(rows['St. Joe Rod and Gun Club'].logo, { url: 'https://x/deer.webp', kind: 'logo', hue: 31 }, 'its own logo over the Legion\'s');
  assert.equal(rows['Sons of the American Legion'].logo.url, 'https://x/legion.webp', 'no logo of its own: where it meets');
  assert.deepEqual(rows['Book Discussion Group'].photos.map((p) => [p.url, p.site]), [['https://x/church.webp', 'https://rlcstjoe.com/']]);
  assert.deepEqual([rows['St. Joseph Women of Today'].photos, rows['St. Joseph Women of Today'].logo], [[], null], 'nothing to show: nothing');
  const order = (await groups(null)).map((g) => g.name);
  assert.ok(order.indexOf('St. Joseph Lions Club') < order.indexOf('St. Joe Rod and Gun Club'), 'photos before logos');
  assert.ok(order.indexOf('St. Joe Rod and Gun Club') < order.indexOf('St. Joseph Women of Today'), 'logos before nothing');
  await db.exec('delete from public.place_photos; delete from public.places');
});

test("meetings: the Lions' 1st and 3rd Tuesdays", async () => {
  const m = await meetings([{ what: 'Meeting', days: ['tue'], weeks: [1, 3], time: '18:00' }], '2026-10-18');
  assert.deepEqual(m.map((x) => x.day), ['2026-10-20', '2026-11-03', '2026-11-17'], 'their calendar\'s dates');
  assert.deepEqual(m[0], { what: 'Meeting', day: '2026-10-20', time: '18:00', where: null });
});

test('meetings: rules mixed, soonest first, today counts', async () => {
  const m = await meetings([
    { what: 'Membership meeting', days: ['tue'], weeks: [4], time: '19:00' },
    { what: '500 cards', days: ['wed'], time: '13:30' },
    { what: 'Bingo', days: ['mon'], weeks: [2, 4], time: '18:30' }], '2026-10-21');
  assert.deepEqual(m.map((x) => `${x.day} ${x.what}`),
    ['2026-10-21 500 cards', '2026-10-26 Bingo', '2026-10-27 Membership meeting']);
});

test('meetings: months off, no time, where, and nothing for no rules', async () => {
  const bee = await meetings([{ what: 'Crafting Bee', days: ['sat'], weeks: [1], time: '13:00', months_off: [5, 6, 7, 8, 9, 10] }], '2026-10-18');
  assert.deepEqual(bee.map((x) => x.day), ['2026-11-07', '2026-12-05', '2027-01-02']);
  const summer = await meetings([{ what: 'Stitch and Sip', days: ['wed'], weeks: [4], time: '18:00', months_off: [1, 2, 3, 4, 9, 10, 11, 12] }], '2026-10-18');
  assert.deepEqual(summer, [], 'nothing within 120 days');
  const knights = await meetings([{ what: 'Meeting', days: ['mon'], weeks: [2] },
    { what: 'Parish breakfast', days: ['sun'], weeks: [1], time: '08:30', months_off: [6, 7, 8, 9], where: 'Heritage Hall' }], '2026-10-18');
  assert.deepEqual(knights.map((x) => [x.day, x.time, x.where]),
    [['2026-11-01', '08:30', 'Heritage Hall'], ['2026-11-09', null, null], ['2026-12-06', '08:30', 'Heritage Hall']]);
  assert.deepEqual(await meetings(null, '2026-10-18'), []);
});
