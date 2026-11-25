#!/usr/bin/env python3
"""Pushes this branch to GitHub's main, after Jesse's yes or a standing one (`MEMORY.md`): the one way to
push there from this Mac.

    python3 scripts/push_main.py     from the worktree whose branch holds the change; as background Bash,
                                     since it waits its turn

GitHub refused 13 pushes in 7 days because main moved while a push's own checks ran (BP app
agent-guardrails 30). So the pushes of every chat wait in one line, a machine-wide lock whose waiters go
in the order they came. With its turn it fetches and merges main, runs the checks the pre-push hook runs
(scripts/ci_checks.sh, in a scratch copy), and only then opens the connection. Git opens it before it runs
the hook, so a wait or a check in there holds it idle, and GitHub drops an idle one on a loaded Mac
(2026-11-05, 11-14, 11-17). The hook (scripts/install-git-hooks.sh) lets a commit through that passed here
and refuses any other push to main. The last line always says what to do next.

Exits:
  0  landed: GitHub's main was read back and holds the commit, and local main moved to it. Or it was
     there already
  2  nothing pushed, something is in the way: uncommitted files, no branch, an open merge, not the branch the
     session started on, or a lock or a record of passed commits that can't be written
  3  waited 30 minutes in line
  4  main doesn't merge: the merge is undone, the branch as it was. Once you have merged it by hand the next
     run can't tell, so test app code first
  5  app code (*.swift, *.xcassets, *.pbxproj) changed both in what main brought and in this branch:
     merged, not pushed, so it can be tested merged
  6  a check failed
  7  GitHub couldn't be read, or the push landed nothing
  8  main moved during each of three tries (the first, and two more)
"""
import fcntl
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# BP_PUSH_LOCK and BP_PUSH_WAIT are for test_push_main.py.
LOCK = os.environ.get("BP_PUSH_LOCK", "/tmp/bp-push.lock")
WAIT = int(os.environ.get("BP_PUSH_WAIT", 30 * 60))
CACHE = Path.home() / "Library/Caches/bp-ci"
PASSED = CACHE / "passed"
SSH = ("-c", "core.sshCommand=ssh -o ServerAliveInterval=15 -o ServerAliveCountMax=60")

# The pre-push hook's own checks (install-git-hooks.sh): the commit in a scratch copy, one node_modules
# for every push, kept until PGlite's pinned version changes.
CHECKS = r"""
set -uo pipefail
sha=$1 tree=$2 cache=$3
git archive "$sha" | tar -x -C "$tree" || exit 1
pkg=$(git show "$sha:supabase/tests/package.json" | shasum | cut -c1-12)
if [ ! -d "$cache/$pkg/node_modules" ]; then
    mkdir -p "$cache/$pkg" && cp "$tree/supabase/tests/package.json" "$cache/$pkg/"
    (cd "$cache/$pkg" && npm install --no-audit --no-fund --silent >/dev/null 2>&1) || rm -rf "$cache/$pkg"
fi
BP_CI_NODE_MODULES="$cache/$pkg/node_modules" bash "$tree/scripts/ci_checks.sh"
"""


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def rev(name):
    return git("rev-parse", "-q", "--verify", f"{name}^{{commit}}").stdout.strip()


def say(line):
    print(f"push_main: {line}", flush=True)


class Stop(Exception):
    """Stop(exit code, what happened, what to do next)."""


def ready():
    """The worktree as it must be, before the wait and again once it is over."""
    branch = git("branch", "--show-current").stdout.strip()
    if not branch:
        raise Stop(2, "this worktree is on no branch, so nothing was pushed.",
                   "Switch to the branch that holds the change, then run this again.")
    # The iOS git-guard's rule for a typed push: a parallel session can move a worktree mid-task (2026-09-19).
    started = Path(git("rev-parse", "--git-path", "bp-session-branch").stdout.strip())
    began = started.read_text().strip() if started.is_file() else ""
    if began not in ("", branch) and os.environ.get("BP_GUARD_OFF") != "1":
        raise Stop(2, f"this session started on {began} and the worktree is now on {branch}, so nothing was pushed.",
                   f"If {branch} is right: git branch --show-current > \"{started}\", then run this again.")
    if rev("MERGE_HEAD"):
        raise Stop(2, "a merge is open here, so nothing was pushed.", "Commit or abort it, then run this again.")
    dirty = git("status", "--porcelain").stdout.rstrip()
    if dirty:
        raise Stop(2, f"uncommitted changes, so nothing was pushed:\n{dirty}", "Commit them, then run this again.")
    return branch


def app_code(across):
    """Whether a range like HEAD...main changes the app's own code."""
    out = git("diff", "--name-only", "--no-renames", "-z", across)
    return out.returncode != 0 or any(n.endswith((".swift", ".pbxproj")) or ".xcassets/" in n
                                      for n in out.stdout.split("\0"))


def merge(main):
    """Merges GitHub's main into the branch, when the branch lacks it."""
    if contains("HEAD", main):
        return
    untested = app_code(f"HEAD...{main}") and app_code(f"{main}...HEAD")
    out = git("merge", "-q", "--no-edit", main)
    if out.returncode:
        files = git("diff", "--name-only", "--diff-filter=U", "-z").stdout.split("\0")[:-1]
        if rev("MERGE_HEAD"):
            git("merge", "--abort")
        why = f"conflicts in {', '.join(files)}" if files else f"failed: {(out.stderr or out.stdout).strip()}"
        raise Stop(4, f"merging main {main[:7]} {why}. The merge was undone and nothing was pushed.",
                   "Merge origin/main, resolve and commit it; app code then needs xc.sh test; then run this again.")
    if untested:
        raise Stop(5, f"main moved in app code, and this branch changes app code too. "
                      f"Main {main[:7]} is merged here and nothing was pushed.",
                   "Test it merged (xc.sh test), then run this again.")


def passed(sha=""):
    """The commits that passed the checks, sha added when there is one: the hook lets through no other."""
    try:
        CACHE.mkdir(parents=True, exist_ok=True)
        with PASSED.open("a+") as f:
            if sha:
                f.write(f"{sha}\n")
            f.seek(0)
            return f.read().split()
    except OSError as e:
        raise Stop(2, f"the record of passed commits can't be written, so nothing was pushed: {e}",
                   f"Make {PASSED} writable, then run this again.")


def check(sha):
    """Runs the checks on the commit, unless it passed them before, and records that it passed."""
    if sha in passed():
        return
    tree = tempfile.mkdtemp(prefix="bp-push-check.", dir="/tmp")
    say(f"running GitHub's quick checks on {sha[:7]} (about a minute)")
    log = Path(f"{tree}.log")
    try:
        with log.open("w") as f:
            out = subprocess.run(["bash", "-c", CHECKS, "checks", sha, tree, str(CACHE)], stdout=f, stderr=f)
    finally:
        shutil.rmtree(tree, ignore_errors=True)
    if out.returncode:
        end = "\n".join(log.read_text(errors="replace").splitlines()[-25:])
        raise Stop(6, f"a check failed, so {sha[:7]} was not pushed. The end of {log}:\n{end}",
                   "Fix it (bash scripts/ci_checks.sh runs them all) and commit, then run this again.")
    log.unlink()
    passed(sha)


def github_main():
    for _ in range(2):  # a second try: another chat's fetch in a sibling worktree can hold the ref
        out = git(*SSH, "fetch", "-q", "origin", "main")
        if not out.returncode:
            return rev("FETCH_HEAD")
    raise Stop(7, f"couldn't read GitHub's main: {out.stderr.strip()}",
               "When the network is back, run this again: it says so if the commit landed.")


def contains(commit, sha):
    return not git("merge-base", "--is-ancestor", sha, commit).returncode


def push(sha):
    """Opens the connection last, so it lasts seconds: GitHub drops one held idle on a loaded Mac
    (2026-11-05, 11-14, 11-17). Never forced. Its exit proves nothing either way: the caller reads GitHub's main."""
    return git(*SSH, "push", "origin", f"{sha}:refs/heads/main")


def in_line(branch):
    """This push's turn: the lock, held until the script ends."""
    lock = open(LOCK, "a+")

    def who():
        lock.seek(0)
        return lock.read().strip() or "another push"

    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        say(f"waiting in line behind {who()}")

        def give_up(*_):
            raise TimeoutError
        signal.signal(signal.SIGALRM, give_up)
        signal.alarm(WAIT)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX)
        except TimeoutError:
            raise Stop(3, f"waited {WAIT // 60} minutes in line and nothing was pushed. {who()} has the turn.",
                       "Look at that push, then run this again.")
        finally:
            signal.alarm(0)
    lock.truncate(0)
    lock.write(f"{branch} in {os.getcwd()} (pid {os.getpid()}, since {time.strftime('%H:%M')})")
    lock.flush()
    return lock


def move_local_main(main, branch):
    """Local main follows GitHub's, unless it holds work GitHub's doesn't."""
    old = rev("refs/heads/main")
    if branch == "main" or old == main:
        return
    if old and not contains(main, old):
        say(f"local main stays at {old[:7]}: it holds commits GitHub's main doesn't")
    elif git("update-ref", "refs/heads/main", main, old).returncode:
        say(f"local main stays at {old[:7]}: git update-ref refused")


def land(branch):
    """With the turn: fetch, merge, check, push and read back, again when main moved anyway."""
    for _ in range(3):
        # Again each time: the wait and the checks take minutes, and another session can use this worktree.
        if ready() != branch:
            raise Stop(2, f"this worktree left {branch} meanwhile, so nothing was pushed.",
                       "Find out who moved it and switch back, then run this again.")
        main = github_main()
        merge(main)
        sha = rev("HEAD")
        if contains(main, sha):
            move_local_main(main, branch)
            say(f"{sha[:7]} is already on main, so there was nothing to push.")
            return
        check(sha)
        out = push(sha)
        now = github_main()
        if contains(now, sha):
            move_local_main(now, branch)
            say(f"landed {sha[:7]}: GitHub's main holds it. Next, GitHub's verdict: BP app's ci_wait.sh {sha}")
            return
        if now == main:
            raise Stop(7, f"the push landed nothing (git's exit {out.returncode}): GitHub's main is still {main[:7]}. "
                          f"git said:\n{out.stderr.strip()}",
                       "If that was the network, run this again: the checks passed and won't run twice.")
        say(f"main moved to {now[:7]} while the checks ran (a cloud push): starting again")
    raise Stop(8, "main moved during each of three tries, so nothing was pushed.", "In a few minutes, run this again.")


def main():
    os.chdir(git("rev-parse", "--show-toplevel").stdout.strip() or ".")
    try:
        branch = ready()
        try:
            lock = in_line(branch)
        except OSError as e:
            raise Stop(2, f"the lock can't be used, so nothing was pushed: {e}",
                       f"Make {LOCK} writable, then run this again.")
        with lock:
            land(branch)
    except Stop as stop:
        code, what, then = stop.args
        say(what)
        say(then)
        return code
    return 0


if __name__ == "__main__":
    sys.exit(main())
