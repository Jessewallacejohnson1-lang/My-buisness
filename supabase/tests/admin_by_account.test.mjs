// Admin is a flag on one account, not an email anyone can sign up with (supabase/migrations/*_admin_by_account.sql,
// BP app docs/plans/loopholes, ticket 20), run in PGlite. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const OLD = `select substring(pg_get_functiondef('public.is_admin'::regproc) from '''([^'' ]+@[^'' ]+)''') as email`;

async function admin(claims) {
  await db.exec(`reset role; ${claims ? `set request.jwt.claims = '${JSON.stringify(claims)}'` : 'reset request.jwt.claims'}; set role authenticated`);
  const { rows: [{ yes }] } = await db.query('select public.is_admin() as yes');
  await db.exec('reset role');
  return yes;
}

test('the flag in app_metadata, which only the service key writes, makes an account admin', async () => {
  assert.equal(await admin({ sub: '00000000-0000-0000-0000-00000000000a', app_metadata: { admin: true } }), true);
});

test('an email is no longer enough: no address in the rule, and a sign-up with any address is not admin', async () => {
  const { rows: [{ email }] } = await db.query(OLD);
  // Compared as a yes or no, so a failure never prints the address.
  assert.equal(email === null, true, 'is_admin() still names an email address');
  assert.equal(await admin({ sub: '00000000-0000-0000-0000-00000000000b', email: 'anyone@example.com' }), false);
});

test('a person can write user_metadata, so a flag there is not admin', async () => {
  assert.equal(await admin({ sub: '00000000-0000-0000-0000-00000000000c', user_metadata: { admin: true } }), false);
});

test('only a true flag counts, and an odd value is a plain no, never an error', async () => {
  for (const value of [false, 'true', 'yes', 1, null, { admin: true }]) {
    assert.equal(await admin({ sub: '00000000-0000-0000-0000-00000000000d', app_metadata: { admin: value } }), false, JSON.stringify(value));
  }
});

test('signed out is not admin', async () => {
  assert.equal(await admin(null), false);
});
