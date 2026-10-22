#!/bin/bash
#
# The checks GitHub's quick jobs run (.github/workflows/ci.yml calls this script), so the same
# checks can run on this Mac before a push: the pre-push hook (scripts/install-git-hooks.sh) runs
# them for every push to main. Twice on 2026-10-16 a push went red because only the one changed
# script had been run (BP app retro, 2026-10-17).
#
#   bash scripts/ci_checks.sh                 all three
#   bash scripts/ci_checks.sh rules db        instruction files, database stories
#   bash scripts/ci_checks.sh registry        the registry's validator and the morning job's self-tests
#
# BP_CI_NODE_MODULES: a node_modules folder to use for the database stories instead of
# installing one (the pre-push hook keeps one cached).
set -euo pipefail
cd "$(dirname "$0")/.."

for part in ${*:-rules db registry}; do
    echo "== $part"
    case "$part" in
        rules)
            python3 scripts/bp_rules.py check
            (cd scripts && python3 -m unittest -q test_bp_rules)
            ;;
        db)
            (
                cd supabase/tests
                if [ -d "${BP_CI_NODE_MODULES:-/nonexistent}" ] && [ ! -e node_modules ]; then
                    ln -s "$BP_CI_NODE_MODULES" node_modules
                fi
                [ -d node_modules ] || npm install --no-audit --no-fund
                npm test
            )
            ;;
        registry)
            # A library GitHub doesn't have fails there and not here: each must be in ci-packages.txt.
            python3 - <<'EOF'
import ast, pathlib, sys
here = pathlib.Path("sources/scripts")
listed = {line.split()[0] for line in (here / "ci-packages.txt").read_text().splitlines()
          if line.strip() and not line.startswith("#")}
known = listed | {p.stem for p in here.glob("*.py")} | set(sys.stdlib_module_names)
missing = []
for p in sorted(here.glob("*.py")):
    for node in ast.walk(ast.parse(p.read_text())):
        if isinstance(node, ast.Import):
            names = [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            names = [node.module]
        else:
            continue
        missing += [f"{p}:{node.lineno} imports {n}" for n in names if n.split(".")[0] not in known]
if missing:
    sys.exit("Add each to sources/scripts/ci-packages.txt with its Ubuntu package (GitHub's runner "
             "lacks it):\n  " + "\n  ".join(missing))
EOF
            sh sources/validate
            python3 sources/scripts/test_census.py
            for s in check_flags find_calendars morning place_photos read_events run social verify write_judged; do
                python3 "sources/scripts/$s.py" --selftest
            done
            ;;
        *)
            echo "ci_checks.sh: no check named '$part' (rules, db, registry)" >&2
            exit 2
            ;;
    esac
done
