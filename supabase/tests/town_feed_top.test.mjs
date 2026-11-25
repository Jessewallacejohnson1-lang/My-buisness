// The top five (BP app town-feed 73): an open after an hour or more away rolls a new top, and the Town feed starts
// with five real happenings from the next 7 days, big first, made yours by your interests and the kinds of Events you
// went Going to, yours before big (town-feed 76), at most 4 of them yours, drawn by chance from the best 8 of each. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, adminClaims } from './fixture.mjs';

const db = await realDatabase();
const ADMIN = await adminClaims(db);
const YOU = '00000000-0000-0000-0000-00000000000b';
const NOW = '2026-10-08 12:00';

async function reset() {
  await db.exec(`reset role; delete from public.event_rsvps; delete from public.club_events;
                 delete from public.board_items; delete from public.town_profiles;
                 reset request.jwt.claim.sub; reset request.jwt.claims;`);
}

// An Event at 7 PM on its day, from its own host unless it says, importance 3 unless it says.
async function add(title, date, { source = title, importance = 3, tags = null, time = '7 PM' } = {}) {
  await db.exec('reset role');
  const { rows: [{ id }] } = await db.query(
    `insert into public.club_events (title, event_date, source_name, start_time, status, importance, interests,
                                     interests_tagged_at, created_at)
     values ($1, $2, $3, $4, 'approved', $5, coalesce($6, '{}'::text[]), case when $6::text[] is not null then now() end,
             '2026-09-01 12:00-05') returning id`,
    [title, date, source, time, importance, tags]);
  return id;
}

async function signIn(interests = []) {
  await db.exec('reset role');
  await db.query(`insert into auth.users (id) values ($1) on conflict do nothing`, [YOU]);
  await db.query(`insert into public.town_profiles (user_id, interests) values ($1, $2)
                  on conflict (user_id) do update set interests = excluded.interests`, [YOU, interests]);
  // Signed in as you, with the admin's claims, so each row carries its score.
  await db.exec(`set role authenticated; set request.jwt.claim.sub = '${YOU}'; set request.jwt.claims = '${ADMIN}'`);
}

// The feed as the app reads it after a roll: each row's title (an Event's is its card's), kind, and the score's top
// place and weight.
async function rolled(seed, last = null) {
  const { rows } = await db.query(
    `select f.id, coalesce(f.card->>'title', f.title) as title, f.kind, (f.score->>'top')::int as top,
            (f.score->>'topWeight')::float8 as weight
     from public.get_town_feed(($1::timestamp at time zone 'America/Chicago'), true, false, $2, $3::uuid[]) f`,
    [NOW, seed, last]);
  return rows;
}
const topOf = (rows) => rows.filter((r) => r.top != null).sort((a, b) => a.top - b.top).map((r) => r.title);
const near = (a, b, why) => assert.ok(Math.abs(a - b) < 0.001, `${a} vs ${b}: ${why ?? ''}`);
const seeds = (n) => Array.from({ length: n }, (_, i) => i + 1);

test('no roll, no top: the feed is as before (town-feed 73)', async () => {
  await reset();
  await add('Big Saturday', '2026-10-13', { importance: 4 });
  await add('Trivia', '2026-10-08');
  await signIn();
  const rows = await rolled(null);
  assert.deepEqual(rows.map((r) => r.top), [null, null]);
  assert.deepEqual(rows.map((r) => r.weight), [null, null]);
});

test('a roll leads with the real happenings of the next 7 days, the big ones the likeliest first (town-feed 73)', async () => {
  await reset();
  await add('Trivia', '2026-10-08');
  await add('Big Saturday', '2026-10-13', { importance: 4 });
  await add('Art exhibit', '2026-10-09', { importance: 4 });
  await add('Garage sale', '2026-10-09', { importance: 4 });
  await add('Fall fest', '2026-10-16', { importance: 4 });
  await add('Council', '2026-10-09', { importance: 1 });
  await signIn();
  const firsts = { 'Big Saturday': 0, Trivia: 0 };
  for (const seed of seeds(60)) {
    const rows = await rolled(seed);
    assert.deepEqual(new Set(topOf(rows)), new Set(['Big Saturday', 'Trivia']),
                     'an exhibit, a sale, routine business and a day past 7 days out are never in it');
    assert.deepEqual(rows.slice(0, 2).map((r) => r.top), [1, 2], 'the top comes first');
    firsts[rows[0].title] += 1;
  }
  // Big Saturday weighs 2^4 × 0.5^(5.3 / 14) = 12.3, Trivia 2^3 = 8: each moved up to a quarter either way, Trivia could
  // lead only near the ends of both moves.
  assert.ok(firsts['Big Saturday'] >= 57, JSON.stringify(firsts));
});

test('the same roll draws the same five, and the last roll\'s first never leads the next (town-feed 73)', async () => {
  await reset();
  for (const n of [1, 2, 3, 4, 5, 6]) await add(`Show ${n}`, `2026-10-${String(8 + n).padStart(2, '0')}`);
  await signIn();
  const tops = new Set();
  for (const seed of seeds(15)) {
    const once = topOf(await rolled(seed));
    assert.deepEqual(topOf(await rolled(seed)), once);
    assert.equal(once.length, 5);
    tops.add(once.join());
    const next = topOf(await rolled(seed, [(await rolled(seed))[0].id]));
    assert.notEqual(next[0], once[0]);
    assert.deepEqual(new Set(next), new Set(once), 'the same five, its old first at the back');
    assert.equal(next[4], once[0]);
  }
  assert.ok(tops.size > 5, `rolls mix it up: ${tops.size} different tops in 15`);
});

test('yours counts two steps and comes first, at most 4 of the 5, the fifth the best not yours, one per creator (town-feed 76)', async () => {
  await reset();
  // Nine of yours: the best 8 are all yours, and the spot yours can't take still fills.
  for (const n of [1, 2, 3, 4, 5, 6, 7, 8, 9]) await add(`Poetry ${n}`, '2026-10-10', { tags: ['books'] });
  for (const n of [1, 2, 3]) await add(`Concert ${n}`, '2026-10-10', { tags: ['live_music'] });
  await add('Brewery night', '2026-10-10', { source: 'Brewery', importance: 4 });
  await add('Brewery trivia', '2026-10-10', { source: 'Brewery', importance: 4 });
  await signIn(['books']);
  const rows = await rolled(1);
  const weight = Object.fromEntries(rows.map((r) => [r.title, r.weight]));
  near(weight['Poetry 1'], 4 * weight['Concert 1'], 'yours weighs two steps more');
  near(weight['Poetry 1'], 2 * weight['Brewery night'], 'yours comes before big');
  // feed-learns 04: a 5 the whole Town turns out for ties a 3 you like; a 2 you like ties a 4.
  await add('Parade', '2026-10-10', { importance: 5 });
  await add('Poetry club', '2026-10-10', { importance: 2, tags: ['books'] });
  await signIn(['books']);
  const now = Object.fromEntries((await rolled(1)).map((r) => [r.title, r.weight]));
  near(now.Parade, now['Poetry 1'], 'a 5 ties a 3 you like');
  near(now['Poetry club'], now['Brewery night'], 'a 2 you like ties a 4');
  await db.exec('reset role');
  await db.query(`delete from public.club_events where title in ('Parade', 'Poetry club')`);
  await signIn(['books']);
  for (const seed of seeds(30)) {
    const top = topOf(await rolled(seed));
    assert.equal(top.length, 5, `five, though the best 8 are all yours: ${top}`);
    assert.ok(top.slice(0, 4).every((t) => t.startsWith('Poetry')), `yours first, 4 at most: ${top}`);
    assert.ok(top[4].startsWith('Brewery'), `the fifth is the biggest not yours, one per creator: ${top}`);
  }
});

test('4s and 5s lead the top five for someone new, and a 1 is never in it (feed-learns 04)', async () => {
  await reset();
  for (const n of [1, 2, 3, 4]) await add(`Talk ${n}`, '2026-10-09');
  for (const n of [1, 2, 3, 4]) await add(`Bingo ${n}`, '2026-10-08', { importance: 2 });
  await add('Council', '2026-10-08', { importance: 1 });
  await add('Author', '2026-10-11', { importance: 4 });
  await add('Market', '2026-10-12', { importance: 4 });
  await add('Parade', '2026-10-13', { importance: 5 });
  await signIn();
  const weight = Object.fromEntries((await rolled(1)).map((r) => [r.title, r.weight]));
  assert.ok(weight.Parade > 1.5 * weight.Author && weight.Author > weight['Talk 1'] && weight['Talk 1'] > weight['Bingo 1'], JSON.stringify(weight));
  let first3 = 0;
  for (const seed of seeds(30)) {
    const top = topOf(await rolled(seed));
    assert.equal(top[0], 'Parade', `${top}`);
    assert.ok(['Author', 'Market'].every((t) => top.includes(t)), `${top}`);
    assert.ok(!top.includes('Council') && !top.some((t) => t.startsWith('Bingo')), `${top}`);
    first3 += top.slice(0, 3).every((t) => ['Parade', 'Author', 'Market'].includes(t));
  }
  assert.ok(first3 >= 15, `the big three first in ${first3} of 30`);
});

test('a kind you went Going to is yours; where it was (a campus) is not (town-feed 73)', async () => {
  await reset();
  const reading = await add('Poet reads', '2026-10-01', { source: 'Library', tags: ['books', 'campus'] });
  await db.query(`insert into auth.users (id) values ($1) on conflict do nothing`, [YOU]);
  await db.query(`insert into public.event_rsvps (event_id, user_id, created_at) values ($1, $2, '2026-10-01 12:00-05')`,
                 [reading, YOU]);
  await add('Novelist talk', '2026-10-10', { tags: ['books'] });
  await add('Campus concert', '2026-10-10', { tags: ['campus'] });
  await add('Bingo', '2026-10-10');
  await signIn();
  const weight = Object.fromEntries((await rolled(1)).map((r) => [r.title, r.weight]));
  near(weight['Novelist talk'], 4 * weight.Bingo);
  near(weight['Campus concert'], weight.Bingo);
});

test('News waits until after the top five (town-feed 73)', async () => {
  await reset();
  for (const n of [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) await add(`Show ${n}`, '2026-10-10');
  await db.exec('reset role');
  for (const n of [1, 2]) {
    await db.query(`insert into public.board_items (title, blurb, category, source_name, source_url, status, published_at)
                    values ($1, 'A line.', 'business', $1, 'https://www.instagram.com/p/x/', 'published',
                            '2026-10-08 09:00-05')`, [`Deal ${n}`]);
  }
  await signIn();
  const rows = await rolled(3);
  assert.deepEqual(rows.slice(0, 5).map((r) => [r.kind, r.top]), [1, 2, 3, 4, 5].map((n) => ['event', n]));
  assert.deepEqual(rows.map((r) => r.kind).indexOf('news'), 9, 'the first story four cards after the five');
});
