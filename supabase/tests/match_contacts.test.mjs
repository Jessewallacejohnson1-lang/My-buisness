// Fixed stories for Contacts (supabase/migrations/*_contacts_checked_numbers_only.sql): who your scrambled
// contacts find (a checked phone number; no email until sign-up checks one: BP app loopholes 14), everyone they never find, the 5-a-day and 2,000-a-check limits, and that nothing the phone
// sends is kept (BP app docs/plans/friends, ticket 06). Run in PGlite like the others:
// `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [ANA, BEN, CAL, DEE, EVE, ANON, NONAME, FAY] = [1, 2, 3, 4, 5, 6, 7, 8].map(id);
/** What the phone sends: SHA-256 hex of the lower-cased, trimmed email, or of a number's digits. */
const code = (s) => createHash('sha256').update(s).digest('hex');
const email = (e) => code(e.trim().toLowerCase());
/** Each person's number, n as in `id(n)`, and what the phone sends for it. */
const number = (n) => `1555123000${n}`;
const phone = (n) => code(number(n));

async function reset() {
  await db.exec(`reset role; reset request.jwt.claims;
    delete from private.contact_checks; delete from private.blocks; delete from private.friend_requests;
    delete from private.friendships; delete from public.town_follows; delete from public.town_profiles;
    delete from auth.users;`);
  const people = [[ANA, 'Ana Lee', 'ana@example.com', number(1)], [BEN, 'Ben Ortiz', 'Ben@Example.com', number(2)],
                  [CAL, 'Cal Ruiz', 'cal@example.com', number(3)], [DEE, 'Dee Moss', 'dee@example.com', number(4)],
                  [EVE, 'Eve Park', 'eve@example.com', number(5)], [FAY, 'Fay Dunn', 'fay@example.com', number(8)]];
  for (const [who, name, mail, num] of people) {
    // Every number but Fay's was checked by a text code.
    await db.query(`insert into auth.users (id, email, email_confirmed_at, phone, phone_confirmed_at)
                    values ($1, $2, now(), $3, case when $4 then now() end)`, [who, mail, num, who !== FAY]);
    await db.query('insert into public.town_profiles (user_id, display_name) values ($1, $2)', [who, name]);
  }
  await db.query(`insert into auth.users (id, is_anonymous, phone, phone_confirmed_at) values ($1, true, $2, now())`, [ANON, number(6)]);
  await db.query(`insert into auth.users (id, phone, phone_confirmed_at) values ($1, $2, now())`, [NONAME, number(7)]);
  await db.query('insert into public.town_profiles (user_id, display_name) values ($1, $2)', [NONAME, '  ']);
}

async function as(who, sql, params = [], { anonymous = false } = {}) {
  await db.exec(`set role authenticated; set request.jwt.claims = '${JSON.stringify({ sub: who, is_anonymous: anonymous })}'`);
  try {
    return (await db.query(sql, params)).rows;
  } finally {
    await db.exec('reset role; reset request.jwt.claims');
  }
}
const match = async (who, emails = [], phones = []) =>
  (await as(who, 'select * from public.match_contacts($1, $2)', [emails, phones])).map((r) => r.display_name);

test('an anonymous account matches nothing', async () => {
  await reset();
  await assert.rejects(as(ANON, 'select * from public.match_contacts($1, $2)', [[], [phone(1)]],
                          { anonymous: true }));
});

test('a number finds its account, A to Z', async () => {
  await reset();
  assert.deepEqual(await match(ANA, [], [phone(5), phone(2), code('15559990000')]), ['Ben Ortiz', 'Eve Park']);
  // Each row names the code that found it, so the phone leaves that contact out of Invite.
  const rows = await as(ANA, 'select display_name, code from public.match_contacts($1, $2)', [[], [phone(3), phone(5)]]);
  assert.deepEqual(rows.map((r) => [r.display_name, r.code]), [['Cal Ruiz', phone(3)], ['Eve Park', phone(5)]]);
});

test('an email finds nobody, even a confirmed one, because sign-up does not check it yet', async () => {
  await reset();
  assert.deepEqual(await match(ANA, [email('ben@example.com'), email('eve@example.com')]), []);
  // Sent beside a number that matches, it adds no one.
  assert.deepEqual(await match(ANA, [email('eve@example.com')], [phone(3)]), ['Cal Ruiz']);
});

test('a phone number finds its account only once a text code checked it', async () => {
  await reset();
  assert.deepEqual(await match(ANA, [], [phone(3), phone(8)]), ['Cal Ruiz']);
});

test('the day of the count is St. Joseph\'s', async () => {
  await reset();
  await match(ANA, [], [phone(5)]);
  const { rows } = await db.query(`select day = (now() at time zone 'America/Chicago')::date as ours from private.contact_checks`);
  assert.equal(rows[0].ours, true);
});

test('never yourself, anonymous, nameless, blocked either way, or someone who turned suggestions off', async () => {
  await reset();
  await as(ANA, 'select public.block_neighbor($1)', [BEN]);
  await as(CAL, 'select public.block_neighbor($1)', [ANA]);
  await db.query('update public.town_profiles set suggest_me = false where user_id = $1', [DEE]);
  assert.deepEqual(await match(ANA, [], [1, 2, 3, 4, 5, 6, 7].map(phone)), ['Eve Park']);
});

test('a friend comes back marked as a friend, a request as asked', async () => {
  await reset();
  await as(ANA, 'select public.send_friend_request($1)', [BEN]);
  await as(BEN, 'select public.confirm_friend_request($1)', [ANA]);
  await as(ANA, 'select public.send_friend_request($1)', [EVE]);
  const rows = await as(ANA, 'select display_name, relation from public.match_contacts($1, $2)',
                        [[], [phone(2), phone(5)]]);
  const relations = rows.map((r) => [r.display_name, r.relation]);
  assert.equal(relations.length, 2);
  assert.equal(relations[0][0], 'Ben Ortiz');
  assert.notEqual(relations[0][1], relations[1][1], 'a friend and a request read differently');
});

test('5 checks a day, then refused, and the count stays at 5', async () => {
  await reset();
  for (let i = 0; i < 5; i++) await match(ANA, [], [phone(5)]);
  await assert.rejects(match(ANA, [], [phone(5)]), /contacts_limit/);
  await assert.rejects(match(ANA, [], [phone(5)]), /contacts_limit/);
  assert.equal((await db.query('select checks from private.contact_checks where user_id = $1', [ANA])).rows[0].checks, 5);
  // Another account has its own 5.
  assert.deepEqual(await match(BEN, [], [phone(5)]), ['Eve Park']);
});

test('more than 2,000 contacts in one check is refused and not counted', async () => {
  await reset();
  const many = Array.from({ length: 2001 }, (_, i) => email(`p${i}@example.com`));
  await assert.rejects(match(ANA, many), /contacts_too_many/);
  assert.equal((await db.query('select count(*)::int as n from private.contact_checks')).rows[0].n, 0);
});

test('nothing the phone sends is kept: only the count of checks is written', async () => {
  await reset();
  const tables = async () => (await db.query(`select table_schema || '.' || table_name as t from information_schema.tables
                                              where table_schema in ('public', 'private', 'auth')
                                                and table_type = 'BASE TABLE' order by 1`)).rows.map((r) => r.t);
  const counts = async () => {
    const out = {};
    for (const t of await tables()) out[t] = (await db.query(`select count(*)::int as n from ${t}`)).rows[0].n;
    return out;
  };
  const before = await counts();
  await match(ANA, [email('eve@example.com'), email('zed@example.com')], [code('15559990000')]);
  const after = await counts();
  for (const t of Object.keys(before)) {
    assert.equal(after[t], before[t] + (t === 'private.contact_checks' ? 1 : 0), t);
  }
  const row = (await db.query('select * from private.contact_checks')).rows[0];
  assert.deepEqual(Object.keys(row).sort(), ['checks', 'day', 'user_id']);
});
