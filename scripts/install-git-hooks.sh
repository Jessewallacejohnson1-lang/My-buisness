#!/bin/bash
#
# Installs the pre-commit hook into THIS checkout. Git hooks are per-clone and
# are not committed, so every worktree needs this run once.
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
