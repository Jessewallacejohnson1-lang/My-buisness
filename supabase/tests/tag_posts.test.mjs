// Fixed stories for a #tag's own page (supabase/migrations/*_tag_posts.sql, BP app town-feed 63): every post that
// carries the tag, newest first, at any age, with the Town feed's rules on who sees what. Run in PGlite:
// `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';

const db = await realDatabase();
const ME = '00000000-0000-0000-0000-0000000000b2';
const PAL = '00000000-0000-0000-0000-0000000000d4';
const YOU = '00000000-0000-0000-0000-0000000000c3';
await people(db, ME, PAL, YOU);
await db.query(`insert into public.town_profiles (user_id, display_name) values
  ($1, 'Marlene Ostendorf'), ($2, 'Sam Rivera'), ($3, 'Ana Nguyen')`, [ME, PAL, YOU]);
await db.exec(`insert into private.friendships (a, b, requested_by) values ('${[ME, PAL].sort().join("', '")}', '${ME}')`);
let n = 0;

async function as(role, sub) {
  await db.exec(`reset role; set role ${role};`);
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [sub ? JSON.stringify({ sub, role, is_anonymous: false }) : '']);
}

/** An approved post of `who`'s, `hours` old, unless `extra` says otherwise. */
async function posted(who, words, hours, extra = {}) {
  await db.exec('reset role');
  const id = `00000000-0000-0000-0000-${String(++n).padStart(12, '0')}`;
  const row = { id, submitted_by: who, category: 'other', kind: 'post', title: words, status: 'approved',
                created_at: new Date(Date.now() - hours * 3600e3).toISOString(), ...extra };
  const cols = Object.keys(row);
  await db.query(`insert into public.club_events (${cols.join(', ')}) values (${cols.map((_, i) => `$${i + 1}`).join(', ')})`,
                 Object.values(row));
  return id;
}
const page = async (tag, who = YOU, role = 'authenticated') => {
  await as(role, who);
  const rows = (await db.query(`select id, kind, poster->>'name' as name, leaves_at > created_at as leaves from public.get_tag_posts($1)`, [tag])).rows;
  await db.exec('reset role');
  return rows;
};
const ids = async (tag, who, role) => (await page(tag, who, role)).map((r) => r.id);

test('every post carrying the tag, newest first, any age, whatever its capitals', async () => {
  await db.exec('reset role; delete from public.club_events');
  const old = await posted(ME, 'Art walk last month #JoeTownNights', 24 * 30);
  const now = await posted(PAL, 'Rocktoberfest crowd was unreal! #joetownnights', 2);
  const mid = await posted(ME, '#JOETOWNNIGHTS, porch tunes', 30);
  assert.deepEqual(await ids('JoeTownNights'), [now, mid, old]);
  assert.deepEqual(await ids('joetownnights'), [now, mid, old], 'the tapped capitals don\'t matter');
  const [row] = await page('JoeTownNights');
  assert.deepEqual([row.kind, row.name, row.leaves], ['post', 'Sam Rivera', true], 'a post as the Town feed sends it');
});

test('only the whole tag, where the app finds one', async () => {
  await db.exec('reset role; delete from public.club_events');
  const hit = await posted(ME, 'Lights tonight #JoeTownNights🎉', 1);
  await posted(ME, 'Not this one #JoeTownNightsOut', 1);
  await posted(ME, 'Nor this one#JoeTownNights', 1);
  await posted(ME, 'Nor #JoeTown_Nights', 1);
  assert.deepEqual(await ids('JoeTownNights'), [hit]);
  assert.deepEqual(await ids('JoeTown'), [], '#JoeTown is a tag of its own');
});

test('a tag with letters beyond a to z, café and Café as one', async () => {
  await db.exec('reset role; delete from public.club_events');
  const a = await posted(ME, 'Open mic #CaféNight', 1);
  const b = await posted(PAL, 'Again #cafénight', 3);
  assert.deepEqual(await ids('CaféNight'), [a, b]);
  assert.deepEqual(await ids('über_cool'), []);
});

test('a tag that isn\'t only letters, digits and _ gets nothing, so no pattern gets through', async () => {
  await db.exec('reset role; delete from public.club_events');
  await posted(ME, 'Lights #JoeTownNights', 1);
  for (const tag of ['.*', 'JoeTown.*', 'a|JoeTownNights', '', ' JoeTownNights', 'x'.repeat(101)]) {
    assert.deepEqual(await ids(tag), [], JSON.stringify(tag));
  }
});

test('the Town feed\'s rules: never a hidden, held, refused, muted or blocked post, nor a stranger\'s Friends-only one', async () => {
  await db.exec('reset role; delete from public.club_events');
  const shown = await posted(ME, 'Sledding #Hill', 1);
  const friends = await posted(ME, 'Just friends #Hill', 2, { friends_only: true });
  const hidden = await posted(PAL, 'Hide me #Hill', 3);
  await posted(ME, 'Waiting for the check #Hill', 4, { status: 'pending' });
  await posted(ME, 'Refused #Hill', 4, { status: 'rejected' });
  await posted(ME, 'An Event, not a post #Hill', 4, { kind: 'event', event_date: '2026-12-05', start_time: '19:00', location: 'Millstream Park' });

  assert.deepEqual(await ids('Hill', PAL), [shown, friends, hidden], 'a friend sees the Friends-only post');
  assert.deepEqual(await ids('Hill', YOU), [shown, hidden], 'a stranger doesn\'t');
  assert.deepEqual(await ids('Hill', null, 'anon'), [shown, hidden], 'signed out, as the Town feed');

  await db.query(`insert into public.feed_actions (user_id, item_id, action) values ($1, $2, 'not_interested')`, [YOU, hidden]);
  assert.deepEqual(await ids('Hill', YOU), [shown], 'Not interested');
  await db.exec('delete from public.feed_actions');

  await db.query(`insert into public.feed_mutes (user_id, host, name) values ($1, $2, 'Marlene Ostendorf')`, [YOU, ME]);
  assert.deepEqual(await ids('Hill', YOU), [hidden], 'muted');
  await db.exec('delete from public.feed_mutes');

  await db.exec(`insert into private.blocks (blocker_id, blocked_id) values ('${ME}', '${YOU}')`);
  assert.deepEqual(await ids('Hill', YOU), [hidden], 'blocked by the poster');
  await db.exec('delete from private.blocks');
  assert.deepEqual(await ids('Hill', YOU), [shown, hidden]);
});
