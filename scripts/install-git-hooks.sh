#!/bin/bash
#
# Installs the pre-commit hook into THIS checkout. Git hooks are per-clone and
# are not committed, so every worktree needs this run once.
#
# NOTE: this deliberately does NOT use `git rev-parse --git-path hooks`. On a
# machine where core.hooksPath is set globally (this one has a machine-wide
# gitleaks secret scanner installed that way), --git-path follows that
# override and resolves to the GLOBAL hooks directory shared by every repo on
# the machine — writing there would silently replace that scanner for every
# other project. That global hook already anticipates this: it chains to
# "$(git rev-parse --git-dir)/hooks/pre-commit" if one exists, specifically so
# a repo can add its own hook without touching the global one. We install at
# that exact path so the chain finds us. `--git-dir` also does the right thing
# in a worktree (.git there is a file, not a directory) and in a plain clone
# (where it is just .git), so one path works everywhere.
set -euo pipefail

hooks_dir="$(git rev-parse --git-dir)/hooks"
mkdir -p "$hooks_dir"

cat > "$hooks_dir/pre-commit" <<'HOOK'
#!/bin/bash
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

chmod +x "$hooks_dir/pre-commit"
echo "installed $hooks_dir/pre-commit"
