import re
import subprocess
import tempfile
import unittest
from pathlib import Path

import ci_scope

ROOT = Path(__file__).resolve().parent.parent


class RuleTests(unittest.TestCase):
    def test_docs_only_skips(self):
        self.assertFalse(ci_scope.needs_tests(["docs/plans/x.md", "MEMORY.md", "supabase/migrations/1.sql",
                                               "sources/st-joseph-mn.md", ".claude/hooks/a.sh"]))

    def test_the_docs_file_a_test_reads_runs(self):
        self.assertTrue(ci_scope.needs_tests(["docs/plans/x.md", "docs/debug-flags.md"]))

    def test_a_swift_file_runs(self):
        self.assertTrue(ci_scope.needs_tests(["docs/plans/x.md", "BlockParty/App/RootView.swift"]))

    def test_an_unknown_top_level_folder_runs(self):
        self.assertTrue(ci_scope.needs_tests(["docs/plans/x.md", "newthing/a.md"]))

    def test_app_project_and_ci_files_run(self):
        for f in ["BlockPartyTests/A.swift", "BlockPartyUITests/A.swift", "BlockParty.xcodeproj/project.pbxproj",
                  "BlockParty.xctestplan", ".github/workflows/ci.yml", ".gitignore", ".gitattributes",
                  "docs", "Docs/a.md", "README.md"]:
            self.assertTrue(ci_scope.needs_tests([f]), f)

    def test_unknown_or_empty_change_runs(self):
        self.assertTrue(ci_scope.needs_tests(None))
        self.assertTrue(ci_scope.needs_tests([]))


class ChangesTests(unittest.TestCase):
    """The git half, on a throwaway repo: what counts as changed, and when it can't be known."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = self.tmp.name
        self.git("init", "-q")
        self.shas = [self.commit({"BlockParty/A.swift": "a", "docs/a.md": "a"})]

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
                               *args], cwd=self.repo, check=True, capture_output=True, text=True).stdout

    def commit(self, files):
        for name, text in files.items():
            p = Path(self.repo, name)
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "c")
        return self.git("rev-parse", "HEAD").strip()

    def needs(self, event="push", ref="refs/heads/main", before=None):
        before = self.shas[0] if before is None else before
        return ci_scope.needs_tests(ci_scope.changes(event, ref, before, cwd=self.repo))

    def test_docs_only_push_to_main_skips(self):
        self.commit({"docs/a.md": "b"})
        self.assertFalse(self.needs())

    def test_every_commit_since_before_counts(self):
        self.commit({"BlockParty/A.swift": "b"})
        self.commit({"docs/a.md": "b"})
        self.assertTrue(self.needs())

    def test_a_missing_before_commit_runs(self):
        self.commit({"docs/a.md": "b"})
        self.assertTrue(self.needs(before="1234567" * 5 + "12345"))
        self.assertTrue(self.needs(before="0" * 40))
        self.assertTrue(self.needs(before=""))

    def test_other_branches_and_hand_started_runs_run(self):
        self.commit({"docs/a.md": "b"})
        self.assertTrue(self.needs(ref="refs/heads/integration/block-party"))
        self.assertTrue(self.needs(event="workflow_dispatch"))

    def test_moving_an_app_file_into_docs_runs(self):
        self.git("mv", "BlockParty/A.swift", "docs/A.swift")
        self.git("commit", "-q", "-m", "mv")
        self.assertTrue(self.needs())

    def test_a_pr_counts_its_whole_change_against_the_base(self):
        self.git("checkout", "-q", "-b", "pr")
        self.commit({"BlockParty/A.swift": "b"})
        self.commit({"docs/a.md": "b"})
        self.git("checkout", "-q", "-")
        self.commit({"docs/b.md": "b"})  # the base moved on
        self.git("merge", "-q", "--no-ff", "--no-edit", "pr")
        self.assertTrue(self.needs(event="pull_request", ref="refs/pull/1/merge"))

    def test_a_docs_only_pr_skips(self):
        self.git("checkout", "-q", "-b", "pr")
        self.commit({"docs/a.md": "b"})
        self.git("checkout", "-q", "-")
        self.commit({"BlockParty/A.swift": "b"})  # the base's own app change is not the PR's
        self.git("merge", "-q", "--no-ff", "--no-edit", "pr")
        self.assertFalse(self.needs(event="pull_request", ref="refs/pull/1/merge"))

    def test_a_pr_that_is_not_a_merge_commit_runs(self):
        self.commit({"docs/a.md": "b"})
        self.assertTrue(self.needs(event="pull_request", ref="refs/pull/1/merge"))


class DriftGuardTests(unittest.TestCase):
    """Every repo path a test names must run the tests when it changes: a test that starts reading,
    say, a sources/ file would otherwise be skipped when that file changes."""

    def test_no_file_a_test_reads_is_skipped(self):
        tops = {p.name for p in ROOT.iterdir()}
        read = set()
        for folder in ("BlockPartyTests", "BlockPartyUITests"):
            for swift in (ROOT / folder).rglob("*.swift"):
                for lit in re.findall(r'"((?:[^"\\\n]|\\.)*)"', swift.read_text(encoding="utf-8")):
                    if lit.split("/")[0] in tops:
                        read.add(lit)
        outside = sorted(p for p in read if p != "BlockParty" and not p.startswith("BlockParty/"))
        self.assertIn("docs/debug-flags.md", outside, "the scan found nothing it should: is it broken?")
        for p in outside:
            self.assertTrue(ci_scope.needs_tests([p]), f"a test reads {p}, but changing it skips the tests")
            if (ROOT / p).is_dir():
                self.assertTrue(ci_scope.needs_tests([p + "/x"]), f"a test reads {p}/, but it's skipped")


if __name__ == "__main__":
    unittest.main()
