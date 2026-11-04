// Fixed stories for anonymous accounts (supabase/migrations/*_anonymous_accounts.sql), run
// in PGlite under the live write rules they sit beside: an anonymous account can act on
// Events but can't publish. Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase, people } from './fixture.mjs';

const db = await realDatabase();
const ANON_USER = '00000000-0000-0000-0000-0000000000a1';
const REAL_USER = '00000000-0000-0000-0000-0000000000b2';
await people(db, ANON_USER, REAL_USER);
await db.exec(`
  insert into public.club_events (id, title) values ('00000000-0000-0000-0000-00000000e001', 'Fair');
  insert into public.clubs (id, name) values ('00000000-0000-0000-0000-00000000c001', 'Book Club');
`);

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

test('an anonymous account can add and remove its own heart', async () => {
  await as('authenticated', ANON_USER, true);
  const event = '00000000-0000-0000-0000-00000000e001';
  await allowed(`insert into public.event_likes (event_id, user_id) values ($1, $2)`, [event, ANON_USER]);
  await allowed(`delete from public.event_likes where event_id = $1 and user_id = $2`, [event, ANON_USER]);
  await denied(`insert into public.event_likes (event_id, user_id) values ($1, $2)`, [event, REAL_USER]);
});

test('an anonymous account can add and remove its own save', async () => {
  await as('authenticated', ANON_USER, true);
  const event = '00000000-0000-0000-0000-00000000e001';
  await allowed(`insert into public.event_saves (event_id, user_id) values ($1, $2)`, [event, ANON_USER]);
  assert.equal((await db.query(`select count(*)::int n from public.event_saves`)).rows[0].n, 1);
  await allowed(`delete from public.event_saves where event_id = $1 and user_id = $2`, [event, ANON_USER]);
  assert.equal((await db.query(`select count(*)::int n from public.event_saves`)).rows[0].n, 0);
  await denied(`insert into public.event_saves (event_id, user_id) values ($1, $2)`, [event, REAL_USER]);
});

test('an anonymous account joins no group; a real account joins and leaves its own (follows 02)', async () => {
  const club = '00000000-0000-0000-0000-00000000c001';
  await as('authenticated', ANON_USER, true);
  await denied(`insert into public.club_members (club_id, user_id) values ($1, $2)`, [club, ANON_USER]);
  await as('authenticated', REAL_USER, false);
  await denied(`insert into public.club_members (club_id, user_id) values ($1, $2)`, [club, ANON_USER]);
  await allowed(`insert into public.club_members (club_id, user_id) values ($1, $2)`, [club, REAL_USER]);
  assert.equal((await db.query(`select count(*)::int n from public.club_members`)).rows[0].n, 1);
  await as('authenticated', ANON_USER, true);
  await allowed(`delete from public.club_members where club_id = $1`, [club]);
  await db.exec('reset role');
  assert.equal((await db.query(`select count(*)::int n from public.club_members`)).rows[0].n, 1,
    "deleting someone else's membership removes nothing");
  await as('authenticated', REAL_USER, false);
  await allowed(`delete from public.club_members where club_id = $1 and user_id = $2`, [club, REAL_USER]);
  await db.exec('reset role');
  assert.equal((await db.query(`select count(*)::int n from public.club_members`)).rows[0].n, 0);
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
