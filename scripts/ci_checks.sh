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
            sh sources/validate
            python3 sources/scripts/test_census.py
            for s in check_flags find_calendars morning place_photos read_events verify write_judged; do
                python3 "sources/scripts/$s.py" --selftest
            done
            ;;
        *)
            echo "ci_checks.sh: no check named '$part' (rules, db, registry)" >&2
            exit 2
            ;;
    esac
done
