"""Stories for apply_migration.py's version rules and its answer after applying (BP app
agent-guardrails 02 and 03). No database: Composio's execute is a fake.

    python3 scripts/test_apply_migration.py
"""
import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apply_migration as am  # noqa: E402


class Fake:
    """Answers a script of results in order: a dict to return, or an exception to raise."""
    def __init__(self, *answers):
        self.answers, self.calls = list(answers), []

    def __call__(self, slug, args, timeout):
        self.calls.append(slug)
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return answer


class Base(unittest.TestCase):
    def setUp(self):
        self.real, am.WAIT = am.execute, 0

    def tearDown(self):
        am.execute = self.real


class Versions(unittest.TestCase):
    now = '20261027130000'

    def test_a_new_round_version_is_refused(self):
        self.assertTrue(am.round_version('20261027120000', on_main=False, now=self.now))

    def test_a_version_later_than_now_is_refused(self):
        self.assertTrue(am.round_version('20261027141534', on_main=False, now=self.now))

    def test_a_stamped_version_passes(self):
        self.assertFalse(am.round_version('20261027121534', on_main=False, now=self.now))

    def test_old_and_shipped_round_versions_stay(self):
        self.assertFalse(am.round_version('20261025235000', on_main=False, now=self.now))
        self.assertFalse(am.round_version('20261027120000', on_main=True, now=self.now))

    def test_another_worktree_with_the_version_is_named(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            for folder, name in ((a, '20261027121534_mine.sql'), (b, '20261027121534_theirs.sql')):
                (Path(folder) / 'supabase/migrations').mkdir(parents=True)
                (Path(folder) / 'supabase/migrations' / name).write_text('')
            mine = Path(a) / 'supabase/migrations/20261027121534_mine.sql'
            self.assertEqual(am.worktree_clashes('20261027121534', mine, [Path(b)]),
                             [f'20261027121534_theirs.sql in {b}'])
            self.assertEqual(am.worktree_clashes('20261027121534', mine, [Path(a)]), [],
                             'its own copy elsewhere is the same file, not a clash')


class Reads(Base):
    def test_a_hiccup_is_tried_again(self):
        am.execute = Fake(am.ComposioError('no answer'), {'result': [{'x': 1}]})
        self.assertEqual(am.query('select 1'), [{'x': 1}])

    def test_three_hiccups_give_up(self):
        am.execute = Fake(*[am.ComposioError('no answer')] * 3)
        with self.assertRaises(am.ComposioError):
            am.query('select 1')


class Apply(Base):
    made = {'public.f': 'select 1'}

    def run_apply(self, *answers):
        am.execute = Fake(*answers)
        out = io.StringIO()
        code = 0
        with contextlib.redirect_stdout(out):
            try:
                am.apply(Path('20261027121534_f.sql'), 'f', 'sql', self.made)
            except SystemExit as ex:
                code = ex.code
        return code, out.getvalue()

    def test_applied_and_confirmed(self):
        code, out = self.run_apply({'success': True}, {'result': [{'name': 'public.f', 'prosrc': 'select 1'}]})
        self.assertEqual(code, 0)
        self.assertIn('live as written', out)

    def test_a_confirm_hiccup_is_tried_again(self):
        code, out = self.run_apply({'success': True}, am.ComposioError('no answer'),
                                   {'result': [{'name': 'public.f', 'prosrc': 'select 1'}]})
        self.assertEqual(code, 0)

    def test_applied_but_unconfirmed_says_so_and_how_to_check(self):
        code, out = self.run_apply({'success': True}, *[am.ComposioError('no answer')] * 3)
        self.assertEqual(code, 3)
        self.assertIn('applied 20261027121534_f.sql; could not confirm', out)
        self.assertIn("where name = 'f'", out)

    def test_a_failed_apply_says_nothing_was_applied(self):
        code, _ = self.run_apply(am.ComposioError('refused'))
        self.assertIn('nothing applied', str(code))


if __name__ == '__main__':
    unittest.main()
