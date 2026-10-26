// briefing_reconcile.test.mjs — offline proof that one failed write does not stop
// the morning run (supabase/migrations/20261026120000_briefing_reconcile_carries_on.sql).
//
// Stands up a throwaway Postgres in a temp folder (unix socket only, no network,
// no Supabase project), stubs the tables and helpers run_briefing_reconcile()
// touches, loads the REAL function from the migration file, then makes one write
// fail at a time and checks the run still finishes the other steps and reports
// the failure as exactly one line.
//
// It also loads the previous version from 20260806090000_briefing_cron.sql and
// shows it aborting under the same fault, so the test is known to tell the two apart.
//
// Run:  node supabase/tests/briefing_reconcile.test.mjs     (exit 1 on any failure)
// Needs a local Postgres install (initdb, pg_ctl, psql). Set PG_BIN to its bin
// folder if `pg_config --bindir` cannot find it. Postgres refuses to run as root.
import { execFileSync } from "node:child_process"
import { mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const HERE = dirname(fileURLToPath(import.meta.url))
const MIGRATIONS = join(HERE, "..", "migrations")
const NEW_SQL = readFileSync(join(MIGRATIONS, "20261026120000_briefing_reconcile_carries_on.sql"), "utf8")
const OLD_SQL = readFileSync(join(MIGRATIONS, "20260806090000_briefing_cron.sql"), "utf8")
  .match(/create or replace function public\.run_briefing_reconcile\(\)[\s\S]*?\n\$\$;/)[0]

const BIN = process.env.PG_BIN ?? execFileSync("pg_config", ["--bindir"], { encoding: "utf8" }).trim()
const DIR = mkdtempSync(join(tmpdir(), "bp-reconcile-"))
const DATA = join(DIR, "data")
const pg = (tool, args, opts = {}) =>
  execFileSync(join(BIN, tool), args, { encoding: "utf8", stdio: ["pipe", "pipe", "pipe"], ...opts })

// Runs SQL and returns stdout. -At prints bare values, so a jsonb comes back as JSON text.
const sql = (text) =>
  pg("psql", ["-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-h", DIR, "-d", "postgres"], { input: text }).trim()

// The minimum the routine reads and writes. compose/publish are stubs that can be
// told to fail for one date; compose inserts its row BEFORE raising, so a passing
// test also proves the failed step's partial write was rolled back.
const STUBS = `
create role anon; create role authenticated; create role service_role;

create table public.daily_briefings (briefing_date date primary key, status text not null);
create table public.daily_touches (used_on date, kind text, season text);
create table public.test_faults (step text, on_date date);
insert into public.daily_touches values (null, 'poll', 'any'), (null, 'poll', 'any');

create function public.season_of(p_date date) returns text language sql as $$ select 'fall' $$;
create function public.town_almanac_line(p_date date) returns text language sql as $$ select 'A quiet day.' $$;

create function public.compose_briefing(p_date date, p_almanac_md text, p_weather jsonb default null,
    p_a text default null, p_b text default null, p_c text default null)
returns jsonb language plpgsql as $$
begin
    insert into public.daily_briefings values (p_date, 'draft')
        on conflict (briefing_date) do nothing;
    if exists (select 1 from public.test_faults where step = 'compose' and on_date = p_date) then
        raise exception 'simulated write failure composing %', p_date;
    end if;
    return jsonb_build_object('briefing_date', p_date, 'status', 'draft');
end $$;

create function public.publish_briefing(p_date date) returns jsonb language plpgsql as $$
begin
    if exists (select 1 from public.test_faults where step = 'publish' and on_date = p_date) then
        raise exception 'simulated write failure publishing %', p_date;
    end if;
    update public.daily_briefings set status = 'published' where briefing_date = p_date;
    return jsonb_build_object('published', true);
end $$;
`

let failed = 0
const check = (name, ok, detail = "") => {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${ok || !detail ? "" : `\n      ${detail}`}`)
  if (!ok) failed++
}

// Fresh state for each case: no briefings, the given faults armed.
const reset = (faults) => {
  sql(`truncate public.daily_briefings, public.test_faults;` +
    faults.map(([step, day]) => `insert into public.test_faults values ('${step}', ${day});`).join(""))
}
const rows = () =>
  Object.fromEntries(sql(`select briefing_date, status from public.daily_briefings order by 1`)
    .split("\n").filter(Boolean).map((l) => l.split("|")))

const TODAY = `(now() at time zone 'America/Chicago')::date`
const TOMORROW = `(${TODAY} + 1)`

try {
  pg("initdb", ["-D", DATA, "-A", "trust", "-U", process.env.USER || "postgres", "--no-sync"])
  // listen_addresses='' means unix socket only: nothing on the network, ever.
  pg("pg_ctl", ["-D", DATA, "-l", join(DIR, "log"), "-w", "-o", `-k ${DIR} -c listen_addresses=''`, "start"])
  sql(STUBS)
  const today = sql(`select ${TODAY}`)
  const tomorrow = sql(`select ${TOMORROW}`)

  // --- Before: the old function, one fault, the whole run dies ----------------
  sql(OLD_SQL)
  reset([["compose", TOMORROW]])
  let oldThrew = false
  try { sql(`select public.run_briefing_reconcile()`) } catch { oldThrew = true }
  check("before the fix: a failed draft of tomorrow aborts the whole run", oldThrew)
  check("before the fix: ...and today is left unpublished", rows()[today] === undefined,
    JSON.stringify(rows()))

  // --- After: the migration as it will ship -----------------------------------
  sql(NEW_SQL)

  reset([])
  let r = JSON.parse(sql(`select public.run_briefing_reconcile()`))
  check("healthy run: no failures reported", r.failures.length === 0, JSON.stringify(r.failures))
  check("healthy run: today published, tomorrow drafted",
    rows()[today] === "published" && rows()[tomorrow] === "draft", JSON.stringify(rows()))

  reset([["compose", TOMORROW]])
  r = JSON.parse(sql(`select public.run_briefing_reconcile()`))
  check("drafting tomorrow fails: the run still returns its report", Array.isArray(r.failures))
  check("drafting tomorrow fails: exactly one failure line", r.failures.length === 1, JSON.stringify(r.failures))
  check("drafting tomorrow fails: the line names the step and date",
    /^drafted_tomorrow \S+ failed: simulated write failure/.test(r.failures[0] ?? "") &&
      r.failures[0].includes(tomorrow), r.failures[0])
  console.log(`      report line: ${r.failures[0]}`)
  check("drafting tomorrow fails: today is still published", rows()[today] === "published", JSON.stringify(rows()))
  check("drafting tomorrow fails: its half-written row was rolled back", rows()[tomorrow] === undefined,
    JSON.stringify(rows()))

  reset([["compose", TODAY]])
  r = JSON.parse(sql(`select public.run_briefing_reconcile()`))
  check("composing today fails: exactly one failure line (publish is skipped, not failed twice)",
    r.failures.length === 1 && r.failures[0].startsWith(`composed_today ${today} failed:`), JSON.stringify(r.failures))
  check("composing today fails: tomorrow is still drafted", rows()[tomorrow] === "draft", JSON.stringify(rows()))
  check("composing today fails: no half-written row for today", rows()[today] === undefined, JSON.stringify(rows()))

  reset([["publish", TODAY]])
  r = JSON.parse(sql(`select public.run_briefing_reconcile()`))
  check("publishing today fails: exactly one failure line",
    r.failures.length === 1 && r.failures[0].startsWith(`published_today ${today} failed:`), JSON.stringify(r.failures))
  check("publishing today fails: today stays a draft and tomorrow is drafted",
    rows()[today] === "draft" && rows()[tomorrow] === "draft", JSON.stringify(rows()))

  // Next hour, fault cleared: the retry finishes the job with nothing reported.
  sql(`truncate public.test_faults`)
  r = JSON.parse(sql(`select public.run_briefing_reconcile()`))
  check("next hour's run recovers: today published, no failures",
    rows()[today] === "published" && r.failures.length === 0, JSON.stringify({ rows: rows(), r }))
} catch (e) {
  console.error(e.stderr?.toString() || e)
  failed++
} finally {
  try { pg("pg_ctl", ["-D", DATA, "-m", "immediate", "stop"]) } catch {}
  rmSync(DIR, { recursive: true, force: true })
}

console.log(failed ? `\n${failed} check(s) failed` : "\nall checks passed")
process.exit(failed ? 1 : 0)
