// Fixed stories for the every-minute live-scores job (supabase/migrations/*_live_scores_fail_out_loud.sql, BP app
// docs/plans/loopholes, ticket 05), run in PGlite with a stand-in for pgsql-http. A refused call has to fail the
// run, so pg_cron records it. Run: `npm test` in this folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { creating } from './migrations.mjs';

const migrations = process.env.MIGRATIONS ?? new URL('../migrations', import.meta.url).pathname;
const db = await PGlite.create();
await db.exec(`
  create schema extensions; create schema private;
  create type extensions.http_header as (field varchar, value varchar);
  create type extensions.http_request as (method text, uri varchar, headers extensions.http_header[],
    content_type varchar, content varchar);
  create type extensions.http_response as (status int, content_type varchar, headers extensions.http_header[],
    content varchar);
  create function extensions.http_header(varchar, varchar) returns extensions.http_header language sql
    as $$ select ($1, $2)::extensions.http_header $$;
  create function extensions.http_set_curlopt(varchar, varchar) returns boolean language sql as $$ select true $$;
  -- The edge function's answer, set by each story.
  create table calls (uri text);
  create table answer (status int, content text);
  create function extensions.http(r extensions.http_request) returns extensions.http_response language plpgsql as $$
  begin
    insert into public.calls values (r.uri);
    return (select (a.status, 'application/json', null, a.content)::extensions.http_response from public.answer a);
  end $$;
  create table games (id uuid, grp text);
  create function private.live_games(timestamptz) returns table (id uuid, grp text) language sql
    as $$ select * from public.games $$;
`);
// The job as it is now: the newest file that re-creates it.
await db.exec(readFileSync(join(migrations, creating(migrations, ['private.wake_live_scores']).at(-1)), 'utf8'));

const wake = () => db.query('select private.wake_live_scores()');
const story = async (game, status, content) => {
  await db.exec('delete from calls; delete from answer; delete from games;');
  if (game) await db.query(`insert into games values (gen_random_uuid(), 'livestats/csbsju/football/game')`);
  await db.query('insert into answer values ($1, $2)', [status, content]);
};

test('no game on: the function is not called', async () => {
  await story(false, 401, 'nope');
  await wake();
  assert.equal((await db.query('select count(*)::int n from calls')).rows[0].n, 0);
});

test('a game on and the function listening: the run succeeds', async () => {
  await story(true, 202, '{"games":1}');
  await wake();
  assert.equal((await db.query('select count(*)::int n from calls')).rows[0].n, 1);
});

test('the login check back on: the run fails with the status and what the function said', async () => {
  await story(true, 401, '{"code":401,"message":"Missing authorization header"}');
  await assert.rejects(wake(), /live-scores answered 401: \{"code":401,"message":"Missing authorization header"\}/);
});

test('the function erroring: the run fails', async () => {
  await story(true, 500, '{"error":"misconfigured"}');
  await assert.rejects(wake(), /live-scores answered 500/);
});
