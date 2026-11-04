#!/usr/bin/env python3
"""Says whether a CI run needs the iPhone tests: ci.yml's first job runs it (BP app ci-skip 01).

The tests are skipped only when every changed file is on the known-safe list below. Anything
else, or any doubt about what changed, runs them. Prints `tests=run` or `tests=skip` for
$GITHUB_OUTPUT and the reason on stderr. Its self-check is test_ci_scope.py, which ci_checks.sh
runs, so GitHub and the pre-push hook both run it.

What changed: for a PR, everything the PR changes against its base (GitHub tests a merge commit
whose first parent is the base); for a push to main, everything since the commit before the push.
A push to another branch runs them: its runs cancel each other, so a docs-only push there could
hide an earlier app change. So does a run started by hand.
"""
import os
import subprocess
import sys

# Nothing in these builds the app or is read by a test. test_ci_scope.py's drift guard fails when
# the app or a test starts reading a file the rule would skip; that file goes in TESTS_READ.
SAFE_FOLDERS = ("supabase/", "sources/", "rules/", "scripts/", "refs/", ".claude/", ".agents/", "docs/")
SAFE_FILES = {"AGENTS.md", "CLAUDE.md", "MEMORY.md", "DECISIONS.md", "DESIGN.md", "PRODUCT.md",
              "REVIEW.md", "ONBOARDING.md", "BlockPartyUITests/FLAKY.md"}
TESTS_READ = {"docs/debug-flags.md"}  # LaunchFlagsTests reads it; lower case, as a Mac ignores case


def safe(path):
    return path.lower() not in TESTS_READ and (path in SAFE_FILES or path.startswith(SAFE_FOLDERS))


def needs_tests(files):
    """files: every changed path, or None when they can't be known. An empty change runs too."""
    return not files or not all(map(safe, files))


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)


def changed_files(old, new, cwd=None):
    """Every path that differs between two commits, both sides of a rename; None when unknown."""
    if git("cat-file", "-e", f"{old}^{{commit}}", cwd=cwd).returncode:
        git("fetch", "-q", "--depth=1", "origin", old, cwd=cwd)
    out = git("diff", "--name-only", "--no-renames", "-z", old, new, cwd=cwd)
    return out.stdout.split("\0")[:-1] if out.returncode == 0 else None


def changes(event, ref, before, cwd=None):
    if event == "pull_request":
        parents = git("rev-list", "--parents", "-n1", "HEAD", cwd=cwd).stdout.split()
        return changed_files("HEAD^1", "HEAD", cwd) if len(parents) == 3 else None
    if event == "push" and ref == "refs/heads/main" and before and before.strip("0"):
        return changed_files(before, "HEAD", cwd)
    return None


def main():
    env = os.environ
    files = changes(env.get("GITHUB_EVENT_NAME"), env.get("GITHUB_REF"), env.get("BEFORE"))
    if files is None:
        why = "the changed files can't be known for sure"
    else:
        app = [f for f in files if not safe(f)]
        why = f"{len(files)} files changed, {len(app)} not on the safe list: {app[:10]}"
    print(f"tests={'run' if needs_tests(files) else 'skip'}")
    print(f"ci_scope: {why}", file=sys.stderr)


if __name__ == "__main__":
    main()
