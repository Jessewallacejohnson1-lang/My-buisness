// Fixed stories for following a school's activity (supabase/migrations/*_activity_follows.sql, BP app
// docs/plans/school-activities, ticket 02): what can be followed, the school's page listing its
// activities with each one's next event and your star, and an activity's coming events. PGlite, like
// the others: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';
import { townDay } from './town_day.mjs';

const ME = '00000000-0000-0000-0000-00000000000a';
const db = await realDatabase();
await people(db, ME);
await db.exec(`
  insert into public.teams (id, name, short_name, local, school_name) values
    ('apollo', 'Apollo', 'Apollo', true, 'Apollo High School')
  on conflict (id) do nothing;
  insert into public.teams (id, name, short_name, local) values
    ('tech', 'Tech', 'Tech', true),
    ('cathedral', 'Cathedral', 'Cathedral', true), ('apollo-cathedral', 'Apollo-Cathedral', 'Apollo-Cathedral', true),
    ('rocori', 'ROCORI', 'ROCORI', true), ('sartell', 'Sartell', 'Sartell', true),
    ('sauk-rapids-rice', 'Sauk Rapids-Rice', 'Sauk Rapids-Rice', true),
    ('saint-benedict', 'Saint Benedict', 'Saint Benedict', true), ('saint-johns', 'Saint John''s', 'Saint John''s', true),
    ('albany', 'Albany', 'Albany', false)
  on conflict (id) do nothing;
`);
const soon = townDay;
const apollo = (await db.query(`select uuid from public.teams where id = 'apollo'`)).rows[0].uuid;
const id = async (team, name) =>
  (await db.query(`select id from public.team_activities where team_id = $1 and name = $2`, [team, name])).rows[0].id;
const as = async (who, sql, args = []) => {
  await db.exec(`set role authenticated; select set_config('request.jwt.claims', '${JSON.stringify({ sub: who })}', false)`);
  try { return (await db.query(sql, args)).rows; } finally { await db.exec('reset role'); }
};

test("an activity of a local school can be followed; anything else can't", async () => {
  const soccer = await id('apollo', 'Girls Soccer');
  assert.equal((await db.query(`select private.followable('activity', $1) ok`, [soccer])).rows[0].ok, true);
  assert.equal((await db.query(`select private.followable('activity', gen_random_uuid()) ok`)).rows[0].ok, false);
  await db.exec(`update public.teams set local = false where id = 'tech'`);
  const techSoccer = await id('tech', 'Boys Soccer');
  assert.equal((await db.query(`select private.followable('activity', $1) ok`, [techSoccer])).rows[0].ok, false);
  await db.exec(`update public.teams set local = true where id = 'tech'`);
  await db.query(`insert into public.town_follows (follower_id, target_type, target_id) values ($1, 'activity', $2)`,
    [ME, soccer]);
});

test("the school's page lists its activities in order, each with its next game and your star", async () => {
  await db.query(`insert into public.club_events (status, title, sport, team_ids, event_date, start_time) values
    ('approved', 'Apollo Girls Soccer vs Albany', 'Girls Soccer', array['apollo', 'albany'], $1, '7 PM'),
    ('approved', 'Apollo Girls Soccer vs Tech', 'Girls Soccer', array['apollo', 'tech'], $2, '5 PM'),
    ('approved', 'Apollo Girls Soccer vs Foley', 'Girls Soccer', array['apollo', 'albany'], $3, '6 PM')`,
    [soon(9), soon(2), soon(-3)]);
  const [page] = await as(ME, `select public.team_page($1) p`, [apollo]);
  assert.equal(page.p.name, 'Apollo High School', "the school's own name; game cards keep Apollo");
  const acts = page.p.activities;
  assert.equal(acts.length, 67);
  assert.deepEqual(acts.slice(0, 2).map((a) => a.name), ['Adapted Soccer', 'Girls Soccer']);
  const soccer = acts.find((a) => a.name === 'Girls Soccer');
  assert.equal(soccer.note, 'St. Cloud Crush co-op');
  assert.equal(soccer.following, true);
  assert.deepEqual([soccer.next.title, soccer.next.date, soccer.next.time], ['Apollo Girls Soccer vs Tech', soon(2), '5 PM']);
  const boys = acts.find((a) => a.name === 'Boys Soccer');
  assert.equal(boys.next, null, 'no game yet: "No events yet"');
  assert.equal(boys.following, false);
  const [signedOut] = await as(null, `select public.team_page($1) p`, [apollo]);
  assert.equal(signedOut.p.activities.find((a) => a.name === 'Girls Soccer').following, false);
});

test("an activity's coming events, soonest first, never a cancelled one", async () => {
  await db.query(`update public.club_events set cancelled_at = now() where title = 'Apollo Girls Soccer vs Albany'`);
  const rows = await as(ME, `select public.activity_events($1) e`, [await id('apollo', 'Girls Soccer')]);
  assert.deepEqual(rows[0].e.map((e) => e.title), ['Apollo Girls Soccer vs Tech']);
  const none = await as(ME, `select public.activity_events($1) e`, [await id('apollo', 'Boys Soccer')]);
  assert.deepEqual(none[0].e, []);
});

test('Kennedy has its logo and colours, navy first', async () => {
  const { rows } = await db.query(`select colors, logo_url like '%kennedy-community-school/logo-%' logo from public.teams where id = 'kennedy'`);
  assert.deepEqual(rows[0], { colors: ['#1B2859', '#1C532F', '#CDCECF'], logo: true });
});

test("the school's games stay what everyone sees; an activity's own list has every level, its concerts too", async () => {
  await db.exec('delete from public.club_events');
  await db.query(`insert into public.club_events (status, title, sport, team_ids, event_date, start_time, followers_only) values
    ('approved', 'Apollo Girls Soccer vs Tech', 'Girls Soccer', array['apollo', 'tech'], $1, '7 PM', false),
    ('approved', 'Apollo Girls Soccer vs Tech · JV', 'Girls Soccer', array['apollo', 'tech'], $1, '5 PM', true)`, [soon(2)]);
  await db.query(`insert into public.club_events (status, title, event_date, start_time, followers_only, activity_team, activity_name)
    values ('approved', 'Fall Choir Concert', $1, '7 PM', true, 'apollo', 'Choir')`, [soon(3)]);
  const [page] = await as(ME, `select public.team_page($1) p`, [apollo]);
  assert.deepEqual(page.p.games.map((g) => g.time), ['7 PM'], 'the JV game stays off the games list');
  assert.equal(page.p.activities.find((a) => a.name === 'Girls Soccer').next.title, 'Apollo Girls Soccer vs Tech · JV');
  assert.equal(page.p.activities.find((a) => a.name === 'Choir').next.title, 'Fall Choir Concert');
  assert.equal(page.p.activities.find((a) => a.name === 'Chamber Choir').next, null);
  const [soccer] = await as(ME, `select public.activity_events($1) e`, [await id('apollo', 'Girls Soccer')]);
  assert.deepEqual(soccer.e.map((e) => e.title), ['Apollo Girls Soccer vs Tech · JV', 'Apollo Girls Soccer vs Tech']);
});
