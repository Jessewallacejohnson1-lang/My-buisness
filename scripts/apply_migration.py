#!/usr/bin/env python3
"""Apply one migration to Block Party's live database, but only when it is safe to.

    python3 scripts/apply_migration.py supabase/migrations/<file>.sql            # checks only
    python3 scripts/apply_migration.py supabase/migrations/<file>.sql --apply    # checks, then applies

Run it from the worktree whose branch holds the migration, after Jesse's yes for the change.
It refuses, naming every reason, when:
  - this branch is behind GitHub's main (fetched first): rebase or merge origin/main;
  - another migration file has the same 14-digit version (Supabase keys by it);
  - the live database already ran a migration with this file's name;
  - a function the file remakes is different live from its newest version in the repo: someone
    applied a change that isn't on main, and a copy of the repo's version would undo it. On
    2026-10-17 a get_town_feed copied from before the friends change took the friends lift out
    of the live Town feed (BP app retro);
  - the database stories fail (scripts/ci_checks.sh db).
With --apply it then applies the file through Composio and checks each remade function is live
as the file wrote it.
"""
import difflib
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'sources' / 'scripts'))
from composio import ComposioError, execute  # noqa: E402

REF = 'lxdgwhvqjqmqliobwjpi'  # Block Party's project (docs/rules/identifiers.md)
FUNCTION = re.compile(r'create\s+(?:or\s+replace\s+)?function\s+(\w+)\.(\w+)\s*\(', re.I)
DOLLAR = re.compile(r'\$(\w*)\$(.*?)\$\1\$', re.S)


def sh(*cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def query(sql):
    return execute('SUPABASE_BETA_RUN_SQL_QUERY', {'ref': REF, 'query': sql, 'read_only': True}, 80)['result']


def bodies(sql):
    """Each function a migration makes -> its body, as Postgres keeps it (prosrc)."""
    out = {}
    for m in FUNCTION.finditer(sql):
        d = DOLLAR.search(sql, m.end())
        if d:
            out[f'{m.group(1).lower()}.{m.group(2).lower()}'] = d.group(2)
    return out


def live_bodies(names):
    if not names:
        return {}
    wanted = ', '.join("'" + n + "'" for n in names)
    rows = query(f"select n.nspname || '.' || p.proname as name, p.prosrc from pg_proc p "
                 f"join pg_namespace n on n.oid = p.pronamespace where n.nspname || '.' || p.proname in ({wanted})")
    return {r['name']: r['prosrc'] for r in rows}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 1:
        sys.exit(__doc__)
    path = Path(args[0]).resolve()
    root = Path(sh('git', 'rev-parse', '--show-toplevel', cwd=path.parent).stdout.strip())
    sql = path.read_text()
    version, name = path.name[:14], path.stem[15:]
    problems, notes = [], []

    sh('git', 'fetch', '-q', 'origin', cwd=root)
    if sh('git', 'merge-base', '--is-ancestor', 'origin/main', 'HEAD', cwd=root).returncode != 0:
        problems.append("this branch is behind GitHub's main: run `git rebase origin/main` (or merge it), then again")

    migrations = sorted((root / 'supabase/migrations').glob('*.sql'))
    clash = [m.name for m in migrations if m.name[:14] == version and m != path]
    if clash:
        problems.append(f'{", ".join(clash)} has the same version {version}: renumber this file past the newest')

    applied = query("select version, name from supabase_migrations.schema_migrations "
                    f"where name = '{name}'")
    if applied:
        problems.append(f"the live database already ran '{name}' (version {applied[0]['version']})")

    made = bodies(sql)
    earlier = [m for m in migrations if m.name < path.name]
    live = live_bodies(list(made))
    for fn in made:
        previous = next((bodies(m.read_text())[fn] for m in reversed(earlier) if fn in bodies(m.read_text())), None)
        if fn not in live:
            notes.append(f'{fn}: new to the live database')
        elif previous is None:
            problems.append(f'{fn} is live but no earlier migration in the repo makes it: find where it came from first')
        elif live[fn].strip() != previous.strip():
            diff = '\n'.join(list(difflib.unified_diff(previous.strip().splitlines(), live[fn].strip().splitlines(),
                                                       'repo', 'live', lineterm='', n=1))[:40])
            problems.append(f'{fn} is different live from its newest version in the repo, so someone applied a '
                            f'change that is not on main. Fetch it, rebuild this file from it, and ask that '
                            f'chat. Repo against live:\n{diff}')
        else:
            notes.append(f'{fn}: live matches the repo, safe to remake')

    tests = sh('bash', 'scripts/ci_checks.sh', 'db', cwd=root)
    if tests.returncode != 0:
        problems.append('the database stories fail: bash scripts/ci_checks.sh db\n' + tests.stdout[-1500:])
    else:
        notes.append('database stories pass')

    for n in notes:
        print('ok  ', n)
    for p in problems:
        print('STOP', p)
    if problems:
        sys.exit(1)
    if '--apply' not in sys.argv:
        print('checks pass; apply with --apply')
        return

    try:
        out = execute('SUPABASE_APPLY_A_MIGRATION', {'ref': REF, 'name': name, 'query': sql,
                                                     'idempotency_key': path.stem}, 120)
    except ComposioError as ex:
        sys.exit(f'apply failed: {ex}')
    if not out.get('success'):
        sys.exit(f'apply failed: {out}')
    after = live_bodies(list(made))
    wrong = [fn for fn, body in made.items() if after.get(fn, '').strip() != body.strip()]
    if wrong:
        sys.exit(f'applied, but live differs from the file for: {", ".join(wrong)}')
    print(f'applied {path.name}; {len(made)} function(s) live as written')


if __name__ == '__main__':
    main()
