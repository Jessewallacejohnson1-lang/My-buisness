// Fixed stories for the moved-or-canceled notice (supabase/migrations/*_moved_notices.sql, BP app
// docs/plans/school-activities, ticket 04): which edits count as a move, and get_my_changes, what the
// bell's Notifications page lists. PGlite, like the others: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';
import { townDay } from './town_day.mjs';
import { CARD_KEYS } from './event_card.mjs';

const ME = '00000000-0000-0000-0000-00000000000a';
const OTHER = '00000000-0000-0000-0000-00000000000b';
const ANNA = '00000000-0000-0000-0000-00000000000c';
const db = await realDatabase();
await people(db, ME, OTHER, ANNA);
await db.exec(`
  insert into public.town_profiles (user_id, display_name) values ('${ANNA}', 'Anna');
  insert into private.friendships (a, b, requested_by) values ('${ME}', '${ANNA}', '${ME}');
  insert into public.teams (id, name, short_name, local, logo_url) values
    ('apollo', 'Apollo', 'Apollo', true, 'https://x/apollo.png'), ('tech', 'Tech', 'Tech', true, null),
    ('cathedral', 'Cathedral', 'Cathedral', true, null), ('apollo-cathedral', 'Apollo-Cathedral', 'Apollo-Cathedral', true, null),
    ('rocori', 'ROCORI', 'ROCORI', true, null), ('sartell', 'Sartell', 'Sartell', true, null),
    ('sauk-rapids-rice', 'Sauk Rapids-Rice', 'Sauk Rapids-Rice', true, null),
    ('saint-benedict', 'Saint Benedict', 'Saint Benedict', true, null),
    ('saint-johns', 'Saint John''s', 'Saint John''s', true, null), ('albany', 'Albany', 'Albany', false, null)
  on conflict (id) do nothing;
`);
const soon = townDay;
const game = async (fields = {}) => {
  const f = { title: 'Apollo Volleyball vs Sartell', sport: 'Volleyball', team_ids: ['apollo', 'sartell'],
    event_date: soon(3), start_time: '7 PM', location: 'Apollo High School', ...fields };
  return (await db.query(`insert into public.club_events (title, status, sport, team_ids, event_date, start_time, location)
    values ($1, 'approved', $2, $3, $4, $5, $6) returning id`,
    [f.title, f.sport, f.team_ids, f.event_date, f.start_time, f.location])).rows[0].id;
};
const edit = (id, set, args = []) => db.query(`update public.club_events set ${set} where id = $1`, [id, ...args]);
const moved = async (id) => (await db.query(`select moved_at is not null as moved, moved_from
  from public.club_events where id = $1`, [id])).rows[0];
const as = async (who, sql, args = []) => {
  await db.exec(`set role authenticated; select set_config('request.jwt.claims', '${JSON.stringify({ sub: who })}', false)`);
  try { return (await db.query(sql, args)).rows; } finally { await db.exec('reset role; reset request.jwt.claims'); }
};
// Each row as the app reads it: its Event from the card, beside the bell's own.
const mine = async (who = ME) => (await as(who, `select * from public.get_my_changes()`))
  .map(({ card, ...own }) => ({ ...card, ...own }));

test('a start 15 minutes off is no move; 30 minutes, another day or another place is', async () => {
  const id = await game();
  await edit(id, `start_time = '7:15 PM'`);
  assert.equal((await moved(id)).moved, false, 'a 15-minute nudge');
  await edit(id, `start_time = '7:45 PM'`);
  const m = await moved(id);
  assert.equal(m.moved, true);
  assert.equal(m.moved_from.start_time, '7:15 PM', 'from where it stood');

  const day = await game();
  await edit(day, `event_date = $2`, [soon(4)]);
  assert.equal((await moved(day)).moved, true, 'another day');

  const place = await game();
  await edit(place, `location = 'Apollo High School - Main Gym'`);
  assert.equal((await moved(place)).moved, false, 'the same place written longer');
  await edit(place, `location = 'Sartell High School'`);
  assert.equal((await moved(place)).moved, true, 'another place');
});

test('a time or place filled in is no move, and an Event already over never moves', async () => {
  const tba = await game({ start_time: 'TBA', location: null });
  await edit(tba, `start_time = '6 PM', location = 'Sartell High School'`);
  assert.equal((await moved(tba)).moved, false);

  const over = await game({ event_date: soon(-2) });
  await edit(over, `start_time = '3 PM'`);
  assert.equal((await moved(over)).moved, false);
});

test('moved back where it first was, it never moved; moved twice, it keeps where it first was', async () => {
  const id = await game();
  await edit(id, `start_time = '9 PM'`);
  await edit(id, `start_time = '7:00 PM'`);
  assert.deepEqual(await moved(id), { moved: false, moved_from: null }, 'a misread fixed next morning');

  await edit(id, `start_time = '8 PM'`);
  await edit(id, `start_time = '9 PM'`);
  const m = await moved(id);
  assert.equal(m.moved, true);
  assert.equal(m.moved_from.start_time, '7:00 PM');
});

test('Notifications lists what you follow and are Going to, and nothing else', async () => {
  await db.exec(`delete from public.club_events; delete from public.town_follows; delete from public.event_rsvps`);
  const volleyball = (await db.query(`select id from public.team_activities where team_id = 'apollo'
    and name ilike '%volleyball%' limit 1`)).rows[0].id;
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'activity', $2)`,
    [ME, volleyball]);

  const followedMove = await game();
  await edit(followedMove, `start_time = '6 PM'`);
  const followedOff = await game({ title: 'Apollo Volleyball vs Tech', team_ids: ['apollo', 'tech'] });
  await edit(followedOff, `cancelled_at = now()`);
  const quiet = await game({ title: 'Apollo Volleyball vs ROCORI', team_ids: ['apollo', 'rocori'] });
  const notMine = await game({ title: 'Tech Football vs Sartell', sport: 'Football', team_ids: ['tech', 'sartell'] });
  await edit(notMine, `cancelled_at = now()`);
  const going = (await db.query(`insert into public.club_events (title, status, event_date, start_time, location,
    cancelled_at) values ('Music in Millstream Park', 'approved', $1, '7 PM', 'Millstream Park', now() - interval '20 days')
    returning id`, [soon(5)])).rows[0].id;
  await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2)`, [going, ME]);
  const oldFollowed = await game({ title: 'Apollo Volleyball vs Albany', team_ids: ['apollo', 'albany'] });
  await edit(oldFollowed, `cancelled_at = now() - interval '8 days'`);

  const rows = await mine();
  assert.deepEqual(rows.map((r) => r.id).sort(), [followedMove, followedOff, going].sort(),
    'not the unchanged one, not one nobody follows, not a followed change from 8 days ago');
  const byId = Object.fromEntries(rows.map((r) => [r.id, r]));
  assert.match(byId[followedMove].followed, /^Apollo .*Volleyball/);
  assert.equal(byId[followedMove].followed_logo, 'https://x/apollo.png');
  assert.equal(byId[followedMove].moved_from.start_time, '7 PM');
  assert.equal(byId[followedMove].cancelled, false);
  assert.equal(byId[followedOff].cancelled, true);
  assert.equal(byId[going].followed, null, 'Going alone names nothing');
  assert.equal(byId[going].going, true, "a Going cancel stays until it's over, however old");
  assert.equal((await mine(OTHER)).length, 0, 'someone who follows nothing sees nothing');
  void quiet;
});

test('a whole school followed covers its activities, named with the sport', async () => {
  await db.exec(`delete from public.club_events; delete from public.town_follows; delete from public.event_rsvps`);
  const apollo = (await db.query(`select uuid from public.teams where id = 'apollo'`)).rows[0].uuid;
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'team', $2)`,
    [OTHER, apollo]);
  const id = await game({ title: 'Apollo Football vs Tech', sport: 'Football', team_ids: ['apollo', 'tech'] });
  await edit(id, `location = 'Tech High School'`);
  const [row] = await mine(OTHER);
  assert.equal(row.id, id);
  assert.match(row.followed, /^Apollo .*Football/);
});

test('a changed Event carries the friends Going, for its Event page (friends-on-event-page)', async () => {
  await db.exec(`delete from public.club_events; delete from public.town_follows; delete from public.event_rsvps`);
  const id = await game();
  await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2), ($1, $3)`, [id, ME, ANNA]);
  await edit(id, `start_time = '9 PM'`);
  const [row] = await mine();
  assert.equal(row.id, id);
  assert.deepEqual(row.friends_going, [{ name: 'Anna', photo: null }]);
  assert.equal((await db.query(`select has_function_privilege('anon', 'public.get_my_changes(timestamptz)', 'execute') as can`)).rows[0].can,
    false, 'still signed in only');
});

// The Event card (codebase-health-2 02 and 03): get_my_changes sends each changed Event's card whole and only the
// bell's own beside it, read here as PostgREST hands an RPC's rows to the app (json_agg).
const asTheAppReads = async () => JSON.parse((await as(ME,
  `select coalesce(json_agg(t), '[]')::text as body from public.get_my_changes() t`))[0].body);

test('the bell sends a full Event card: photo, found link, about, host, its live score, friends, called off', async () => {
  await db.exec(`delete from public.club_events; delete from public.town_follows; delete from public.event_rsvps;
    delete from public.place_photos;
    insert into public.sources (entry_id, url, town, name, status, method) values
      ('csb-athletics', 'https://gobennies.com/', 'st-joseph-mn', 'CSB Athletics', 'active', 'fetch');
    insert into public.clubs (name, status, own_entry_id) values ('Bennie Volleyball Boosters', 'approved', 'csb-athletics');
    insert into public.place_photos (entry_id, url, source_url, kind, status) values
      ('activities-athletic-csb', 'https://x/csb-logo.webp', 'https://gobennies.com/', 'logo', 'live');`);
  const day = soon(3);
  const id = await game({ title: 'Saint Benedict Volleyball vs Sartell', team_ids: ['saint-benedict', 'sartell'], event_date: day });
  await edit(id, `source_name = 'CSB Athletics', category = 'sports', image_url = 'https://x/flyer.jpg',
    description = 'Senior night.', what = 'Volleyball match',
    source_url = 'https://gobennies.com/sports/volleyball/schedule', occasion = 'Senior night',
    live_score = '{"score": [2, 1], "period": "Set 4", "complete": false}'`);
  await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2), ($1, $3)`, [id, ME, ANNA]);
  await edit(id, `cancelled_at = now()`);

  const [row] = await asTheAppReads();
  const { card } = row;
  assert.equal(typeof card, 'object', 'one nested value, never a string the app has to parse again');
  assert.deepEqual(Object.keys(card).sort(), CARD_KEYS);
  assert.deepEqual([card.id, card.title, card.event_date, card.start_time, card.location, card.image_url, card.category],
                   [id, 'Saint Benedict Volleyball vs Sartell', day, '7 PM', 'Apollo High School', 'https://x/flyer.jpg', 'sports']);
  assert.equal(card.club_name, 'Bennie Volleyball Boosters', 'the group it was found for, as the Town feed names it');
  assert.deepEqual([card.going_count, card.going, card.cancelled], [2, true, true]);
  // No place named, so no picture: the Going, Saved and Town feed stories show a real one.
  assert.equal(card.place_picture, null);
  assert.deepEqual(card.host_picture, { url: 'https://x/csb-logo.webp', kind: 'logo', hue: null });
  assert.deepEqual([card.description, card.what, card.source_url],
                   ['Senior night.', 'Volleyball match', 'https://gobennies.com/sports/volleyball/schedule']);
  assert.deepEqual([card.game.sport, card.game.final, card.game.plays, card.game.live],
                   ['Volleyball', null, null, { score: [2, 1], period: 'Set 4', complete: false }], 'the bell keeps the live score');
  assert.deepEqual(card.friends_going, [{ name: 'Anna', photo: null }]);
  assert.deepEqual(Object.keys(row).sort(), ['card', 'changed_at', 'followed', 'followed_logo', 'moved_from'],
                   'the card and the bell\'s own: no Event column copied beside it (ticket 03)');
  await db.exec('delete from public.place_photos; delete from public.sources; delete from public.clubs;');
});

test('the bell sends a bare Event card with empties, never a missing key', async () => {
  await db.exec(`delete from public.club_events; delete from public.town_follows; delete from public.event_rsvps`);
  const day = soon(5);
  const id = (await db.query(`insert into public.club_events (title, status, event_date, cancelled_at)
    values ('Porch jam', 'approved', $1, now()) returning id`, [day])).rows[0].id;
  await db.query(`insert into public.event_rsvps (event_id, user_id) values ($1, $2), ($1, $3)`, [id, ME, ANNA]);
  const [{ card }] = await asTheAppReads();
  assert.deepEqual(Object.keys(card).sort(), CARD_KEYS);
  assert.deepEqual(card, {
    id, title: 'Porch jam', event_date: day, start_time: null, location: null, image_url: null, category: null,
    club_name: null, source_name: null, end_at: null, all_day: false, created_at: card.created_at,
    going_count: 2, going: true, cancelled: true, place_picture: null, host_picture: null, description: null,
    what: null, source_url: null, game: null, friends_going: [{ name: 'Anna', photo: null }], live_kind: false, friends_going_at: card.friends_going_at,
  });
});
