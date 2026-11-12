// Fixed stories for @ names in a post's words (supabase/migrations/*_at_names.sql, BP app town-feed 60): the check
// keeps a friend's or an open place's name whose own name holds it and whose @name is in the words; the feed sends
// the ones still good for the reader; the bell's read finds the posts that name or tag you. Run in PGlite:
// `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';

const db = await realDatabase();
const ME = '00000000-0000-0000-0000-0000000000b2';
const PAL = '00000000-0000-0000-0000-0000000000d4';
const YOU = '00000000-0000-0000-0000-0000000000c3';
const PAL2 = '00000000-0000-0000-0000-0000000000e5';
const HABIT = '00000000-0000-0000-0000-00000000aa01';
const SHUT = '00000000-0000-0000-0000-00000000aa02';
await people(db, ME, PAL, YOU, PAL2);
await db.query(`insert into public.town_profiles (user_id, display_name) values
  ($1, 'Marlene Ostendorf'), ($2, 'Sam Rivera'), ($3, 'Ana Nguyen'), ($4, 'Dale Brunner')`, [ME, PAL, YOU, PAL2]);
await db.query(`insert into public.places (id, name, lat, lon, family, entry_id, closed_at) values
  ($1, 'Bad Habit Brewing Company', 45.56, -94.32, 'food', 'bad-habit', null),
  ($2, 'Bello Cucina', 45.56, -94.32, 'food', 'bello', now())`, [HABIT, SHUT]);
for (const pal of [PAL, PAL2]) {
  await db.exec(`insert into private.friendships (a, b, requested_by) values ('${[ME, pal].sort().join("', '")}', '${ME}')`);
}
let n = 0;

async function as(role, sub) {
  await db.exec(`reset role; set role ${role};`);
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [sub ? JSON.stringify({ sub, role, is_anonymous: false }) : '']);
}

/** A post of `who`'s, pending unless `extra` says, with its words and names. */
async function posted(who, words, names, extra = {}) {
  await db.exec('reset role');
  const id = `00000000-0000-0000-0000-${String(++n).padStart(12, '0')}`;
  const row = { id, submitted_by: who, category: 'other', kind: 'post', title: words,
                at_names: names === undefined ? null : JSON.stringify(names), ...extra };
  const cols = Object.keys(row);
  await db.query(`insert into public.club_events (${cols.join(', ')}) values (${cols.map((_, i) => `$${i + 1}`).join(', ')})`,
                 Object.values(row));
  return id;
}
const claim = async (id, who) => { await db.exec('reset role');
  return (await db.query(`select public.claim_submit($1, $2) as ok`, [id, who])).rows[0].ok; };
const kept = async (id) => { await db.exec('reset role');
  return (await db.query(`select at_names from public.club_events where id = $1`, [id])).rows[0].at_names; };
const user = (id, name) => ({ kind: 'user', id, name });
const place = (id, name) => ({ kind: 'place', id, name });

test('the check keeps a friend\'s and an open place\'s name, in the order picked, once each', async () => {
  const id = await posted(ME, 'Pint night at @Bad Habit Brewing with @Sam Rivera',
    [place(HABIT.toUpperCase(), 'Bad Habit Brewing'), user(PAL, 'Sam Rivera'), user(PAL, 'Sam Rivera')]);
  assert.equal(await claim(id, ME), true);
  assert.deepEqual(await kept(id), [place(HABIT, 'Bad Habit Brewing'), user(PAL, 'Sam Rivera')],
                   'Search\'s shown name is inside the place\'s own; the id comes back as the row\'s');
});

test('a place\'s name as Search shows it keeps its link though a word was dropped from its middle', async () => {
  const CLINIC = '00000000-0000-0000-0000-00000000aa03';
  await db.query(`insert into public.places (id, name, lat, lon, family, entry_id) values
    ($1, 'CentraCare - St. Joseph Clinic', 45.56, -94.32, 'business', 'centracare')`, [CLINIC]);
  const id = await posted(ME, 'Flu shots at @CentraCare Clinic and @CentraCare Mayo',
    [place(CLINIC, 'CentraCare Clinic'), place(CLINIC, 'CentraCare Mayo')]);
  assert.equal(await claim(id, ME), true);
  assert.deepEqual(await kept(id), [place(CLINIC, 'CentraCare Clinic')], 'a word the place\'s name hasn\'t is no name of its');
});

test('a stranger, a borrowed name, a name not in the words and a closed place are dropped; the post still goes', async () => {
  const id = await posted(ME, 'Hi @Ana Nguyen @Mayor @Bello Cucina and nobody else',
    [user(YOU, 'Ana Nguyen'), user(PAL, 'Mayor'), user(PAL2, 'Dale Brunner'), place(SHUT, 'Bello Cucina'),
     { kind: 'group', id: PAL, name: 'Sam' }, 'not an object']);
  assert.equal(await claim(id, ME), true);
  assert.equal(await kept(id), null);
});

test('over 20 names is never claimed; an Event never carries one', async () => {
  const many = Array.from({ length: 21 }, () => user(PAL, 'Sam Rivera'));
  assert.equal(await claim(await posted(ME, '@Sam Rivera', many), ME), false);
  const event = await posted(ME, 'Porch concert with @Sam Rivera', [user(PAL, 'Sam Rivera')],
                             { kind: 'event', event_date: '2026-12-05', start_time: '19:00', location: 'Millstream Park' });
  assert.equal(await claim(event, ME), false);
});

test('a name list is a list', async () => {
  await assert.rejects(posted(ME, 'x', { kind: 'user' }), /club_events_at_names_list/);
});

test('the reader gets the names still good for them: never a blocked one, always their own', async () => {
  const names = [user(PAL, 'Sam Rivera'), user(YOU, 'Ana Nguyen'), place(HABIT, 'Bad Habit Brewing'), place(SHUT, 'Bello Cucina')];
  const read = async (who) => { await as('authenticated', who);
    return (await db.query(`select private.post_at_names($1::jsonb) as v`, [JSON.stringify(names)])).rows[0].v; };
  assert.deepEqual(await read(PAL2), [user(PAL, 'Sam Rivera'), user(YOU, 'Ana Nguyen'), place(HABIT, 'Bad Habit Brewing')]);
  await db.exec(`reset role; insert into private.blocks (blocker_id, blocked_id) values ('${YOU}', '${PAL2}')`);
  assert.deepEqual(await read(PAL2), [user(PAL, 'Sam Rivera'), place(HABIT, 'Bad Habit Brewing')], 'Ana blocked Dale');
  assert.deepEqual(await read(YOU), [user(PAL, 'Sam Rivera'), user(YOU, 'Ana Nguyen'), place(HABIT, 'Bad Habit Brewing')],
                   'your own name stays a link');
  await db.exec(`reset role; delete from private.blocks`);
});

test('the bell finds the posts that name or tag you, newest first, never your own', async () => {
  const named = await posted(ME, 'Thanks @Sam Rivera!', [user(PAL, 'Sam Rivera')], { status: 'approved' });
  const tagged = await posted(ME, 'Sledding', undefined, { status: 'approved', tagged: [PAL2],
                                                           created_at: new Date(Date.now() - 3600e3).toISOString() });
  await posted(ME, 'Waiting for the check @Sam Rivera', [user(PAL, 'Sam Rivera')]);
  await posted(ME, 'Last month @Sam Rivera', [user(PAL, 'Sam Rivera')],
               { status: 'approved', created_at: new Date(Date.now() - 8 * 86400e3).toISOString() });
  const bell = async (who) => { await as('authenticated', who);
    return (await db.query(`select id, how, poster->'at_names' as names, poster->>'name' as name from public.get_my_mentions()`)).rows; };
  assert.deepEqual((await bell(PAL)).map((r) => [r.id, r.how, r.name]), [[named, 'named', 'Marlene Ostendorf']]);
  assert.deepEqual((await bell(PAL)).at(0).names, [user(PAL, 'Sam Rivera')]);
  assert.deepEqual((await bell(PAL2)).map((r) => [r.id, r.how]), [[tagged, 'tagged']]);
  assert.deepEqual(await bell(ME), [], 'your own post');
  assert.deepEqual(await bell(YOU), []);
  await as('anon', null);
  await assert.rejects(db.query('select * from public.get_my_mentions()'), /permission denied/);
  await db.exec('reset role');
});

test('the bell leaves out a poster you muted or blocked, a post you hid, and a Friends-only one after unfriending', async () => {
  await db.exec('reset role; delete from public.club_events');
  const id = await posted(ME, 'Thanks @Sam Rivera!', [user(PAL, 'Sam Rivera')], { status: 'approved', friends_only: true });
  const count = async () => { await as('authenticated', PAL);
    return (await db.query('select count(*)::int as n from public.get_my_mentions()')).rows[0].n; };
  assert.equal(await count(), 1);
  await db.exec('reset role');
  await db.query(`insert into public.feed_mutes (user_id, host, name) values ($1, $2, 'Marlene Ostendorf')`, [PAL, ME]);
  assert.equal(await count(), 0, 'muted');
  await db.exec('reset role; delete from public.feed_mutes');
  await db.exec(`insert into private.blocks (blocker_id, blocked_id) values ('${PAL}', '${ME}')`);
  assert.equal(await count(), 0, 'blocked');
  await db.exec('reset role; delete from private.blocks');
  await db.exec(`delete from private.friendships where '${PAL}' in (a, b)`);
  assert.equal(await count(), 0, 'no longer friends: the read rule keeps a Friends-only post away');
  await db.exec(`reset role; insert into private.friendships (a, b, requested_by) values ('${[ME, PAL].sort().join("', '")}', '${ME}')`);
  assert.equal(await count(), 1);
  await db.exec('reset role');
  await db.query(`insert into public.feed_actions (user_id, item_id, action) values ($1, $2, 'not_interested')`, [PAL, id]);
  assert.equal(await count(), 0, 'Not interested');
  await db.exec('reset role');
});
