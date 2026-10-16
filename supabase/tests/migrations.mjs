// The migrations that create any of the named functions, oldest first. A test loads its
// functions by what the files do, never by their names, so a new file that re-creates one is
// always tested: a name pattern once missed `town_feed_cancelled_flag` and would have tested
// the old feed (BP app retro, 2026-10-16).
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

export function creating(dir, names) {
  const made = names.map((n) => new RegExp(`create\\s+(or\\s+replace\\s+)?function\\s+${n.replace('.', '\\.')}\\s*\\(`, 'i'));
  return readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()
    .filter((f) => { const sql = readFileSync(join(dir, f), 'utf8'); return made.some((m) => m.test(sql)); });
}
