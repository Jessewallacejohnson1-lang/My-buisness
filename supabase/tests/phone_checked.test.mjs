// Fixed stories for phone_checked (supabase/migrations/*_phone_first_check_drops_password.sql), run in PGlite: a
// password a stranger put on a number goes when the number is first checked; an email account's stays, and so does
// one set later. Run: `npm install && npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
const id = '00000000-0000-0000-0000-00000000000a';

async function account(email, phone, password) {
  await db.exec(`delete from auth.users;
    insert into auth.users (id, email, phone, encrypted_password)
    values ('${id}', ${email ? `'${email}'` : 'null'}, ${phone ? `'${phone}'` : 'null'}, '${password}');`);
}
const password = async () => (await db.query('select encrypted_password p from auth.users')).rows[0].p;
const check = () => db.exec('update auth.users set phone_confirmed_at = now()');

test('a number checked for the first time loses the password put on it before', async () => {
  await account(null, '13205550142', 'a stranger');
  await check();
  assert.equal(await password(), '');
});

test('an email account that adds a number keeps its password', async () => {
  await account('avery@example.com', null, 'averys own');
  await db.exec(`update auth.users set phone = '13205550142', phone_confirmed_at = now()`);
  assert.equal(await password(), 'averys own');
});

test('a password set after the check stays through the next code', async () => {
  await account(null, '13205550142', 'a stranger');
  await check();
  await db.exec(`update auth.users set encrypted_password = 'set since'`);
  await check();
  assert.equal(await password(), 'set since');
});
