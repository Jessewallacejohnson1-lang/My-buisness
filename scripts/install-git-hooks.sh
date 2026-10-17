#!/bin/bash
#
# Installs the pre-commit hook into THIS checkout, and the pre-push hook into the repo's
# common git dir, which every worktree shares (so one run covers every checkout and every
# chat). Git hooks are not committed, so the pre-commit hook needs this run once per worktree.
#
# Which directory git actually reads for hooks depends on core.hooksPath:
#
#   - core.hooksPath IS set (this machine has one globally, for a shared
#     gitleaks secret scanner): git runs ONLY that directory and nothing else.
#     Writing there would silently replace the scanner for every repo on the
#     machine, so we don't. Instead we rely on the fact that the scanner
#     itself chains to "$(git rev-parse --git-dir)/hooks/pre-commit" when one
#     exists (see its own comment to that effect) — so that is the one path
#     it will actually reach, and that's where we install.
#
#   - core.hooksPath is NOT set (the normal case, most machines): git resolves
#     hooks to the COMMON dir, shared across all worktrees of a repo — hooks
#     are git's one per-repo-not-per-worktree file. `--git-dir` here would be
#     the worktree-PRIVATE dir, which git never looks at for hooks in this
#     case, so a hook installed there would be silently ignored while this
#     script prints "installed" — worse than not installing anything.
#
# So we branch on whether the override is set, rather than assuming one path
# works everywhere.
set -euo pipefail

if git config --get core.hooksPath >/dev/null 2>&1; then
    hooks_dir="$(git rev-parse --git-dir)/hooks"
else
    hooks_dir="$(git rev-parse --git-common-dir)/hooks"
fi
mkdir -p "$hooks_dir"

target="$hooks_dir/pre-commit"

# Refuse to clobber a hook we didn't install. The common dir in particular
# can already be live with hooks belonging to other tooling; overwriting one
# silently would be exactly the failure mode this script exists to avoid.
# Re-running this installer over its OWN previous output must still succeed,
# which is what the marker line is for.
if [ -e "$target" ] && ! grep -q '# bp-rules-managed-hook' "$target" 2>/dev/null; then
    echo "refusing to overwrite an existing pre-commit hook at $target" >&2
    echo "It was not installed by this script. Back it up and re-run, or merge" >&2
    echo "the bp_rules check into it by hand." >&2
    exit 1
fi

cat > "$target" <<'HOOK'
#!/bin/bash
# bp-rules-managed-hook
# Refuses a commit whose AGENTS.md or CLAUDE.md does not match rules/.
# Bypassable with --no-verify; CI checks the same thing and is not.
set -uo pipefail
repo="$(git rev-parse --show-toplevel)"
[ -f "$repo/scripts/bp_rules.py" ] || exit 0
if ! python3 "$repo/scripts/bp_rules.py" check --repo "$repo"; then
    echo ""
    echo "pre-commit: instruction files are out of sync with rules/."
    echo "Fix with:   python3 scripts/bp_rules.py build && git add AGENTS.md CLAUDE.md"
    exit 1
fi
HOOK

chmod +x "$target"
echo "installed $target"

# The pre-push hook: every push to main first runs the checks GitHub's quick jobs run
# (scripts/ci_checks.sh), on the exact commit being pushed. It lives in the common dir, shared
# by every worktree; this machine's global hook (core.hooksPath) chains to it there.
push_target="$(git rev-parse --path-format=absolute --git-common-dir)/hooks/pre-push"
if [ -e "$push_target" ] && ! grep -q '# bp-ci-managed-hook' "$push_target" 2>/dev/null; then
    echo "refusing to overwrite an existing pre-push hook at $push_target" >&2
    exit 1
fi
mkdir -p "$(dirname "$push_target")"
cat > "$push_target" <<'HOOK'
#!/bin/bash
# bp-ci-managed-hook
# A push to main runs the checks GitHub's quick jobs run (scripts/ci_checks.sh) on the commit
# being pushed, in a scratch copy, and stops the push when one fails (BP app retro, 2026-10-17).
# Commits from before the script existed pass through. Emergency only: git push --no-verify.
set -uo pipefail
zero=0000000000000000000000000000000000000000
cache="${HOME}/Library/Caches/bp-ci"
status=0
while read -r local_ref local_sha remote_ref remote_sha; do
    [ "$remote_ref" = "refs/heads/main" ] || continue
    [ "$local_sha" = "$zero" ] && continue
    git cat-file -e "$local_sha:scripts/ci_checks.sh" 2>/dev/null || continue
    tree=$(mktemp -d /tmp/bp-push-check.XXXXXX)
    git archive "$local_sha" | tar -x -C "$tree"
    # One node_modules for every push, kept until PGlite's pinned version changes.
    pkg=$(git show "$local_sha:supabase/tests/package.json" | shasum | cut -c1-12)
    if [ ! -d "$cache/$pkg/node_modules" ]; then
        mkdir -p "$cache/$pkg" && cp "$tree/supabase/tests/package.json" "$cache/$pkg/"
        (cd "$cache/$pkg" && npm install --no-audit --no-fund --silent >/dev/null 2>&1) || rm -rf "$cache/$pkg"
    fi
    echo "pre-push: running GitHub's quick checks on ${local_sha:0:7} before it goes to main (about 30 s)" >&2
    if BP_CI_NODE_MODULES="$cache/$pkg/node_modules" bash "$tree/scripts/ci_checks.sh" > "$tree.log" 2>&1; then
        echo "pre-push: checks passed" >&2
        rm -f "$tree.log"
    else
        echo "pre-push: a check failed, so ${local_sha:0:7} was not pushed. The end of the log:" >&2
        tail -25 "$tree.log" >&2
        echo "Full log: $tree.log. Run it yourself: bash scripts/ci_checks.sh" >&2
        status=1
    fi
    rm -rf "$tree"
done
exit $status
HOOK
chmod +x "$push_target"
echo "installed $push_target"
