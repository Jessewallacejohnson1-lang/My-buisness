// The real database for a story: what a Supabase project has before any migration, then every
// migration, oldest first. A story keeps only its rows.
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

export const migrations = join(dirname(fileURLToPath(import.meta.url)), '..', 'migrations');

export async function realDatabase() {
  const db = await PGlite.create();
  await db.exec(`set timezone = 'UTC'`);
  // The API roles (service_role skips row security), their grants and the owner's default grants, and
  // stand-ins for the platform's auth, storage (row security on, as live), cron, Vault and pgsql-http.
  // No other role may use schema auth, as live. A web call is kept in fake.calls and answered from the
  // one row a story puts in fake.answer.
  await db.exec(`
    create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
    create schema extensions; create schema auth; create schema storage; create schema cron;
    grant usage on schema public, extensions, auth, storage to anon, authenticated, service_role;
    alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
    alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
    alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
    create table auth.users (id uuid primary key, email text, phone text, is_anonymous boolean not null default false,
      raw_user_meta_data jsonb, banned_until timestamptz, email_confirmed_at timestamptz default now(),
      phone_confirmed_at timestamptz, created_at timestamptz default now());
    create function auth.jwt() returns jsonb language sql stable as
      $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
    create function auth.uid() returns uuid language sql stable as
      $$ select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                         nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid $$;
    create function auth.role() returns text language sql stable as
      $$ select nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role' $$;
    create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint,
      allowed_mime_types text[]);
    create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
    alter table storage.objects enable row level security;
    grant all on storage.buckets, storage.objects to anon, authenticated, service_role;
    create function storage.foldername(name text) returns text[] language sql immutable as
      $$ select string_to_array(name, '/') $$;
    create function cron.schedule(name text, sched text, cmd text) returns bigint language sql as $$ select 1::bigint $$;
    create function cron.unschedule(name text) returns boolean language sql as $$ select true $$;
    create table cron.job (jobid bigint, jobname text);
    create table cron.job_run_details (jobid bigint, status text, return_message text, start_time timestamptz);
    create schema vault;
    create table vault.decrypted_secrets (name text, decrypted_secret text);
    create schema fake;
    create table fake.calls (uri text, headers text, content text);
    create table fake.answer (status int, content text);
    create type extensions.http_header as (field varchar, value varchar);
    create type extensions.http_request as (method text, uri varchar, headers extensions.http_header[],
      content_type varchar, content varchar);
    create type extensions.http_response as (status int, content_type varchar, headers extensions.http_header[],
      content varchar);
    create function extensions.http_header(varchar, varchar) returns extensions.http_header language sql
      as $$ select ($1, $2)::extensions.http_header $$;
    create function extensions.http_set_curlopt(varchar, varchar) returns boolean language sql as $$ select true $$;
    create function extensions.http(r extensions.http_request) returns extensions.http_response language plpgsql as $$
    begin
      insert into fake.calls values (r.uri, r.headers::text, r.content);
      return (select (a.status, 'application/json', null, a.content)::extensions.http_response from fake.answer a);
    end $$;
    create publication supabase_realtime;
  `);
  // The live rows aren't here, so a migration's own rows that point at them (team_activities' teams) skip
  // their foreign keys while loading. Extensions are the platform's.
  await db.exec('set session_replication_role = replica');
  for (const f of readdirSync(migrations).filter((f) => f.endsWith('.sql')).sort()) {
    try {
      await db.exec(readFileSync(join(migrations, f), 'utf8').replace(/create extension[^;]*;/gi, ''));
    } catch (e) {
      throw new Error(`${f} didn't load: ${e.message}`);
    }
  }
  await db.exec('reset session_replication_role');
  return db;
}

// The people a story names: on the real schema a row that names someone needs them in auth.users.
export const people = (db, ...ids) => db.query(
  'insert into auth.users (id) select unnest($1::uuid[]) on conflict do nothing', [ids]);

// The sign-in claims that make the real is_admin() true: it compares one email, which only its migration
// names. A story sets them with `set request.jwt.claims` and clears them with `reset request.jwt.claims`.
export async function adminClaims(db) {
  const { rows: [{ d }] } = await db.query(`select pg_get_functiondef('public.is_admin'::regproc) as d`);
  return JSON.stringify({ email: d.match(/'([^'\s]+@[^'\s]+)'/)[1] });
}
