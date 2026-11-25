import fcntl
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
# The fake ci_checks.sh: one line a run in $CHECK_LOG, a command run meanwhile ($DURING), red when
# the commit holds bad.txt.
CHECKS = 'echo run >> "$CHECK_LOG"\neval "${DURING:-}"\ncd "$(dirname "$0")/.." && [ ! -e bad.txt ] || { echo bad.txt is bad; exit 1; }\n'


class PushMainTests(unittest.TestCase):
    """The real push_main.py and the real pre-push hook, on a temp bare repo standing in for GitHub."""

    @classmethod
    def setUpClass(cls):
        """GitHub and a clone with the hook installed, made once and copied for each test."""
        tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(tmp.cleanup)
        made = cls("main")
        made.tmp = Path(tmp.name).resolve() / "made"
        made.tmp.mkdir()
        made.make()
        cls.made, cls.old = made.tmp, made.old

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name).resolve() / "t"
        shutil.copytree(self.made, self.tmp)
        self.point()
        self.git(self.repo, "remote", "set-url", "origin", str(self.tmp / "origin.git"))

    def make(self):
        (self.tmp / "bin").mkdir()
        self.script("bin/npm", "mkdir -p node_modules\n")
        (self.tmp / "gitconfig").write_text("[user]\nname = t\nemail = t@t\n[init]\ndefaultBranch = main\n")
        self.point()
        self.git(self.tmp, "init", "-q", "--bare", "origin.git")
        self.git(self.tmp, "clone", "-q", str(self.tmp / "origin.git"), "repo")
        self.commit(self.repo, {"scripts/ci_checks.sh": CHECKS, "supabase/tests/package.json": "{}",
                                "App.swift": "0", "notes.txt": "0"}, "before the script")
        self.git(self.repo, "push", "-q", "origin", "HEAD:main")
        self.old = self.main()
        for name in ("install-git-hooks.sh", "push_main.py"):
            shutil.copy(HERE / name, self.repo / "scripts" / name)
        self.commit(self.repo, {}, "the script")
        self.git(self.repo, "push", "-q", "origin", "HEAD:main")
        subprocess.run(["bash", "scripts/install-git-hooks.sh"], cwd=self.repo, env=self.env, check=True,
                       stdout=subprocess.DEVNULL)
        self.git(self.repo, "switch", "-q", "--detach")

    def point(self):
        # No GIT_DIR and friends (a hook's would aim every git call here at the real repo, 2026-11-02),
        # no hooks but the ones installed here, and no cache or lock but these.
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "BP_"))}
        self.env.update(HOME=str(self.tmp), PATH=f"{self.tmp / 'bin'}{os.pathsep}{os.environ['PATH']}",
                        GIT_CONFIG_GLOBAL=str(self.tmp / "gitconfig"), GIT_CONFIG_NOSYSTEM="1",
                        BP_PUSH_LOCK=str(self.tmp / "push.lock"), CHECK_LOG=str(self.tmp / "checks.log"))
        self.repo = self.tmp / "repo"

    def script(self, path, body):
        (self.tmp / path).write_text("#!/bin/bash\n" + body)
        (self.tmp / path).chmod(0o755)

    def git(self, cwd, *args):
        out = subprocess.run(["git", *args], cwd=cwd, env=self.env, capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, f"git {args}: {out.stderr}")
        return out.stdout.strip()

    def commit(self, cwd, files, message):
        for path, text in files.items():
            (cwd / path).parent.mkdir(parents=True, exist_ok=True)
            (cwd / path).write_text(text)
        self.git(cwd, "add", "-A")
        self.git(cwd, "commit", "-q", "-m", message)
        return self.git(cwd, "rev-parse", "HEAD")

    def worktree(self, name, files, start="origin/main"):
        """A worktree on feat/<name> with one commit."""
        self.git(self.repo, "worktree", "add", "-q", "-b", f"feat/{name}", str(self.tmp / name), start)
        self.commit(self.tmp / name, files, f"{name} work")
        return self.tmp / name

    def cloud(self, files, message="cloud work"):
        """A push from elsewhere (the morning job): no hooks, no line."""
        path = self.tmp / "cloud"
        if not path.exists():
            self.git(self.tmp, "clone", "-q", "origin.git", "cloud")
        self.git(path, "pull", "-q", "--ff-only")
        sha = self.commit(path, files, message)
        self.git(path, "push", "-q", "origin", "HEAD:main")
        return sha

    def main(self):
        return self.git(self.tmp / "origin.git", "rev-parse", "main")

    def start(self, cwd, **env):
        return subprocess.Popen([sys.executable, "scripts/push_main.py"], cwd=cwd, env={**self.env, **env}, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def push(self, cwd, **env):
        """Runs push_main.py: its exit code, all it printed, and the last line."""
        run = self.start(cwd, **env)
        out = run.communicate(timeout=300)[0]
        return run.returncode, out, out.strip().splitlines()[-1]

    def test_two_at_once_both_land_the_second_on_the_first(self):
        runs = [self.start(self.worktree(n, {f"{n}.txt": n}), DURING="sleep 1") for n in ("a", "b")]
        outs = [r.communicate(timeout=300)[0] for r in runs]
        self.assertEqual([r.returncode for r in runs], [0, 0], outs)
        shas = [self.git(self.tmp / n, "rev-parse", "HEAD") for n in ("a", "b")]
        self.assertIn(self.main(), shas)
        first = shas[1 - shas.index(self.main())]
        self.git(self.tmp / "origin.git", "merge-base", "--is-ancestor", first, "main")
        self.assertNotIn("starting again", "".join(outs))  # no push was refused
        self.assertEqual(self.checks(), 2)  # each ran its checks once

    def bare(self, cwd, *args):
        return subprocess.run(["git", "push", "origin", *(args or ["HEAD:main"])], cwd=cwd, env=self.env,
                              capture_output=True, text=True)

    def checks(self):
        log = self.tmp / "checks.log"
        return len(log.read_text().splitlines()) if log.exists() else 0

    def test_a_bare_push_is_refused_with_the_command(self):
        before, a = self.main(), self.worktree("a", {"a.txt": "a"})
        out = self.bare(a)
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("python3 scripts/push_main.py", out.stderr)
        self.assertEqual((self.main(), self.checks()), (before, 0))
        self.assertEqual(self.bare(a, "HEAD:feat/a").returncode, 0)  # any other branch: no line

    def test_an_old_branchs_push_runs_the_checks_as_today(self):
        self.git(self.tmp / "origin.git", "update-ref", "refs/heads/main", self.old)
        bad = self.worktree("bad", {"bad.txt": "b"}, self.old)
        out = self.bare(bad)
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("bad.txt is bad", out.stderr)
        os.remove(re.search(r"Full log: (\S+\.log)", out.stderr)[1])
        self.assertEqual((self.main(), self.checks()), (self.old, 1))
        a = self.worktree("a", {"a.txt": "a"}, self.old)
        out = self.bare(a)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual((self.main(), self.checks()), (self.git(a, "rev-parse", "HEAD"), 2))

    def head(self, cwd):
        return self.git(cwd, "rev-parse", "HEAD")

    def stopped(self, cwd, code, *words, checks=0, **env):
        """Runs push_main.py, which must exit with code, leave main alone and the worktree clean."""
        before = self.main()
        got, out, last = self.push(cwd, **env)
        self.assertEqual((got, self.main(), self.checks()), (code, before, checks), out)
        self.assertEqual(self.git(cwd, "status", "--porcelain"), "")
        for word in words:
            self.assertIn(word, out)
        self.assertRegex(last, "run this again|xc.sh test")  # every stop's last line says what to do
        return out

    def test_uncommitted_changes_are_refused(self):
        a, before = self.worktree("a", {"a.txt": "a"}), self.main()
        for name in ("a.txt", "new.txt"):  # changed, and never added: each would be left out of the push
            (a / name).write_text("changed")
            code, out, last = self.push(a)
            self.assertEqual((code, self.main()), (2, before), out)
            self.assertIn(name, out)
            self.assertIn("Commit them", last)
            self.git(a, "stash", "-q", "-u")

    def test_a_worktree_on_no_branch_or_mid_merge_is_refused(self):
        a = self.worktree("a", {"a.txt": "a"})
        self.git(a, "switch", "-q", "--detach")
        self.assertEqual(self.push(a)[0], 2)
        self.git(a, "switch", "-q", "feat/a")
        self.cloud({"b.txt": "b"})
        self.git(a, "fetch", "-q")
        self.git(a, "merge", "-q", "--no-commit", "--no-ff", "origin/main")
        self.git(a, "rm", "-q", "-f", "b.txt")  # nothing left to see in git status, the merge still open
        self.assertEqual(self.git(a, "status", "--porcelain"), "")
        code, out, _ = self.push(a)
        self.assertEqual(code, 2, out)
        self.git(a, "rev-parse", "MERGE_HEAD")  # and not thrown away

    def test_a_branch_the_session_did_not_start_on_is_refused(self):
        a = self.worktree("a", {"a.txt": "a"})
        started = Path(self.git(a, "rev-parse", "--path-format=absolute", "--git-path", "bp-session-branch"))
        started.write_text("feat/other\n")
        code, out, _ = self.push(a)
        self.assertEqual(code, 2, out)
        self.assertIn("feat/other", out)
        started.write_text("feat/a\n")
        self.assertEqual(self.push(a)[0], 0)

    def test_a_conflict_is_undone_and_named(self):
        a = self.worktree("a", {"notes.txt": "ours"})
        self.cloud({"notes.txt": "theirs"})
        head = self.head(a)
        self.stopped(a, 4, "notes.txt")
        self.assertEqual(self.head(a), head)

    def test_app_code_on_both_sides_stops_merged(self):
        for ours, theirs in (({"App.swift": "1"}, {"Other.swift": "1"}),
                             ({"A/Assets.xcassets/i.imageset/Contents.json": "1"}, {"A.xcodeproj/project.pbxproj": "1"})):
            name = "a" if "App.swift" in ours else "b"
            a, new = self.worktree(name, ours), self.cloud(theirs)
            self.stopped(a, 5, "app code", new[:7], "xc.sh test", checks=self.checks())
            self.git(a, "merge-base", "--is-ancestor", new, "HEAD")  # merged, to be tested
            self.assertEqual(self.push(a)[0], 0)  # tested, so run again: it lands
            self.assertEqual(self.main(), self.head(a))

    def test_data_lands_beside_new_app_code(self):
        a, new = self.worktree("a", {"supabase/migrations/1.sql": "1"}), self.cloud({"App.swift": "1"})
        code, out, _ = self.push(a)
        self.assertEqual((code, self.main()), (0, self.head(a)), out)
        self.git(a, "merge-base", "--is-ancestor", new, "HEAD")

    def test_a_failed_check_is_not_pushed(self):
        a = self.worktree("a", {"bad.txt": "b"})
        out = self.stopped(a, 6, "bad.txt is bad", checks=1)
        log = next(w for w in out.split() if w.startswith("/tmp/bp-push-check")).rstrip(":")
        self.assertIn("bad.txt is bad", Path(log).read_text())
        os.remove(log)
        self.assertNotEqual(self.bare(a).returncode, 0)  # nor recorded as passed

    def fake_push(self, body):
        """Every later git push runs body, with $REAL as git itself; any other git command is git's."""
        self.script("bin/git", f'REAL={shutil.which("git", path=os.environ["PATH"])}\n'
                    f'for a in "$@"; do [ "$a" = push ] && {{ {body}; }}; done\nexec "$REAL" "$@"\n')

    def test_a_push_that_lands_nothing_is_a_failure(self):
        a = self.worktree("a", {"a.txt": "a"})
        self.fake_push("exit 0")  # 2026-11-14: exit 0, "checks passed", and GitHub had nothing
        self.stopped(a, 7, "GitHub's main is still", checks=1)
        (self.tmp / "bin/git").unlink()
        self.assertEqual(self.push(a)[0], 0)
        self.assertEqual((self.main(), self.checks()), (self.head(a), 1))  # it passed already, so no second run

    def test_a_push_the_server_refuses_is_a_failure_with_its_words(self):
        a = self.worktree("a", {"a.txt": "a"})
        hook = self.tmp / "origin.git/hooks/pre-receive"
        hook.write_text("#!/bin/sh\necho no thanks >&2\nexit 1\n")
        hook.chmod(0o755)
        self.stopped(a, 7, "no thanks", checks=1)

    def test_a_connection_lost_after_landing_is_landed(self):
        a = self.worktree("a", {"a.txt": "a"})
        self.fake_push('"$REAL" "$@"; exit 1')
        code, out, _ = self.push(a)
        self.assertEqual((code, self.main()), (0, self.head(a)), out)

    def test_github_out_of_reach_is_a_failure(self):
        a = self.worktree("a", {"a.txt": "a"})
        self.git(a, "remote", "set-url", "origin", str(self.tmp / "gone.git"))
        self.stopped(a, 7, "gone.git")

    def test_main_moving_meanwhile_starts_again(self):
        a = self.worktree("a", {"a.txt": "a"})
        self.git(self.tmp, "clone", "-q", "origin.git", "late")
        late = f"cd {self.tmp}/late && [ ! -e c.txt ] && echo c > c.txt && git add c.txt && git commit -qm late && git push -q; cd - >/dev/null"
        code, out, _ = self.push(a, DURING=late)
        self.assertEqual((code, self.main(), self.checks()), (0, self.head(a), 2), out)
        self.git(a, "cat-file", "-e", "HEAD:c.txt")

    def test_main_that_keeps_moving_is_given_up_after_two_more_tries(self):
        a = self.worktree("a", {"a.txt": "a"})
        self.git(self.tmp, "clone", "-q", "origin.git", "late")
        late = f"cd {self.tmp}/late && git commit -q --allow-empty -m late && git push -q origin HEAD:main; cd - >/dev/null"
        code, out, last = self.push(a, DURING=late)
        self.assertEqual((code, self.checks()), (8, 3), out)
        self.assertIn("run this again", last)
        self.assertEqual(self.main(), self.head(self.tmp / "late"))

    def test_a_chat_in_line_hears_who_has_the_turn_once_and_gives_up(self):
        a, b = self.worktree("a", {"a.txt": "a"}), self.worktree("b", {"b.txt": "b"})
        done = self.tmp / "done"
        holder = self.start(a, DURING=f"until [ -e {done} ]; do sleep 0.05; done")
        while not self.checks():
            time.sleep(0.05)
        out = self.stopped(b, 3, "feat/a", str(a), str(holder.pid), checks=1, BP_PUSH_WAIT="1")
        self.assertEqual(out.count("waiting"), 1, out)
        done.touch()
        self.assertEqual(holder.wait(300), 0)
        holder.stdout.close()

    def test_a_worktree_moved_to_another_branch_while_in_line_is_refused(self):
        a = self.worktree("a", {"a.txt": "a"})
        with open(self.env["BP_PUSH_LOCK"], "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            run = self.start(a)
            self.assertIn("waiting", run.stdout.readline())
            self.git(a, "switch", "-q", "-c", "feat/other")
        out = run.communicate(timeout=300)[0]
        self.assertEqual((run.returncode, self.checks()), (2, 0), out)

    def test_the_connection_opens_after_the_checks_with_keep_alives(self):
        a = self.worktree("a", {"a.txt": "a"})
        self.script("bin/ssh", 'echo "ssh $*" >> "$CHECK_LOG"\neval "${@: -1}"\n')
        self.git(a, "remote", "set-url", "origin", f"t@github:{self.tmp}/origin.git")
        code, out, _ = self.push(a, GIT_SSH_VARIANT="ssh")
        self.assertEqual((code, self.main()), (0, self.head(a)), out)
        log = (self.tmp / "checks.log").read_text().splitlines()
        pushes = [n for n, line in enumerate(log) if "git-receive-pack" in line]
        self.assertEqual(len(pushes), 1, log)
        self.assertGreater(pushes[0], log.index("run"))
        self.assertIn("ServerAliveInterval=15", log[pushes[0]])

    def test_landed_moves_local_main_and_says_the_commit(self):
        a = self.worktree("a", {"a.txt": "a"})
        code, out, last = self.push(a)
        self.assertEqual((code, self.git(self.repo, "rev-parse", "main")), (0, self.main()), out)
        self.assertIn(self.main()[:7], last)
        code, out, last = self.push(a)  # nothing left to push
        self.assertEqual((code, self.checks()), (0, 1), out)
        self.assertIn("already on main", last)

    def test_a_local_main_with_work_of_its_own_keeps_it(self):
        self.git(self.repo, "switch", "-q", "main")
        theirs = self.commit(self.repo, {"c.txt": "c"}, "not on GitHub")
        self.git(self.repo, "switch", "-q", "--detach")
        a = self.worktree("a", {"a.txt": "a"})
        code, out, _ = self.push(a)
        self.assertEqual((code, self.git(self.repo, "rev-parse", "main")), (0, theirs), out)
        self.assertIn("local main", out)

    def test_works_from_a_branch_whose_folder_is_not_the_top(self):
        a = self.worktree("a", {"a.txt": "a"})
        run = subprocess.run([sys.executable, "push_main.py"], cwd=a / "scripts", env=self.env, capture_output=True)
        self.assertEqual((run.returncode, self.main()), (0, self.head(a)))


if __name__ == "__main__":
    unittest.main()
