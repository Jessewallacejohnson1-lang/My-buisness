import contextlib
import io
import tempfile
import unittest
from pathlib import Path

import bp_rules


class ComposeTests(unittest.TestCase):
    def test_fragments_concatenate_in_filename_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp) / "router"
            d.mkdir()
            (d / "20-second.md").write_text("second\n", encoding="utf-8")
            (d / "10-first.md").write_text("first\n", encoding="utf-8")
            out = bp_rules.compose([d])
            self.assertTrue(out.startswith(bp_rules.BANNER))
            self.assertLess(out.index("first"), out.index("second"))

    def test_missing_fragment_directory_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(FileNotFoundError):
                bp_rules.compose([Path(tmp) / "nope"])


class CheckTests(unittest.TestCase):
    def _repo(self, tmp: str, agents_text: str) -> Path:
        repo = Path(tmp)
        (repo / "rules" / "router").mkdir(parents=True)
        (repo / "rules" / "claude").mkdir(parents=True)
        (repo / "rules" / "router" / "10-a.md").write_text("router body\n", encoding="utf-8")
        (repo / "rules" / "claude" / "10-a.md").write_text("shim body\n", encoding="utf-8")
        (repo / "AGENTS.md").write_text(agents_text, encoding="utf-8")
        (repo / "CLAUDE.md").write_text(bp_rules.compose([repo / "rules" / "claude"]), encoding="utf-8")
        return repo

    def test_check_passes_when_in_sync(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self._repo(tmp, "")
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                bp_rules.cmd_build(repo)
            with contextlib.redirect_stdout(buf):
                self.assertEqual(bp_rules.cmd_check(repo), 0)

    def test_check_fails_on_a_hand_edit(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self._repo(tmp, "hand-edited, not composed\n")
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                code = bp_rules.cmd_check(repo)
            self.assertEqual(code, 1)


class UnmigratedRepoTests(unittest.TestCase):
    def test_check_on_a_repo_without_rules_exits_2_with_a_message(self):
        with tempfile.TemporaryDirectory() as tmp:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                code = bp_rules.main(["check", "--repo", tmp])
            self.assertEqual(code, 2)
            self.assertIn("has not been", buf.getvalue())


class TriggerTableTests(unittest.TestCase):
    ROWS = (
        "| About to… | Read first |\n"
        "| --- | --- |\n"
        "| build or test | `docs/rules/build.md` |\n"
    )

    def _repo(self, tmp: str, rows: str, leaves: list[str]) -> Path:
        repo = Path(tmp)
        (repo / "docs" / "rules").mkdir(parents=True)
        for leaf in leaves:
            (repo / "docs" / "rules" / leaf).write_text("leaf\n", encoding="utf-8")
        (repo / "AGENTS.md").write_text(rows, encoding="utf-8")
        return repo

    def test_passes_when_every_row_resolves_and_every_leaf_is_referenced(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self._repo(tmp, self.ROWS, ["build.md"])
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                result = bp_rules.check_triggers(repo)
            self.assertEqual(result, 0)

    def test_fails_when_a_row_points_at_a_missing_leaf(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self._repo(tmp, self.ROWS, [])
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                result = bp_rules.check_triggers(repo)
            self.assertEqual(result, 1)

    def test_fails_when_a_leaf_is_unreachable_from_the_table(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self._repo(tmp, self.ROWS, ["build.md", "orphan.md"])
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                result = bp_rules.check_triggers(repo)
            self.assertEqual(result, 1)


class SizeTests(unittest.TestCase):
    def test_fails_when_the_router_is_over_cap(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            (repo / "AGENTS.md").write_text("x" * (bp_rules.ROUTER_MAX + 1), encoding="utf-8")
            (repo / "CLAUDE.md").write_text("y\n", encoding="utf-8")
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                result = bp_rules.check_sizes(repo)
            self.assertGreaterEqual(result, 1)


if __name__ == "__main__":
    unittest.main()
