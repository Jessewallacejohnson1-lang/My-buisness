#!/usr/bin/env python3
"""
check_repeats.py: does the cheap model, reading sources/models/repeat.md, hold back the News that repeat what their
place already has, and let the rest go up? (BP app docs/plans/smooth-mornings, ticket 16; the bar is the ticket's.)

The fixture is every News from Oct 14 to Nov 9 that had anything from its place in the two weeks before, each with
what its place had then; the check orders and cuts those as the writer does (write_judged.told). The answer key is what was taken out: a News
a take-out migration names as repeating another is a repeat of it (the later of the two is the one asked about), and
a News still published that was never taken out is not one, unless the better model's label pass found it to be a
repeat the hand check let through (32 of 197 on 2026-11-09): those score as neither. It stays in the private BP app repo, not here: this repo
is public and a post's words wait for the place's yes (ADR-020).

The check lays the questions out as the morning does (write_judged.repeat_questions), one message a day, and reads
them three times through Claude Code on Jesse's plan, as check_flags.py does. Bar: 9 of 10 repeats held back, and at
most 1 in 50 of the others. It prints each run's score, every miss and every News wrongly held, and exits 1 below the bar.

  python3 sources/scripts/check_repeats.py [--model haiku] [--runs 3] [--fixture FILE]
  python3 sources/scripts/check_repeats.py --selftest
"""

import argparse, json, sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from itertools import groupby
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_flags import ask
from write_judged import REPEAT_MODEL, repeat_questions, same_story, told

FIXTURE = Path.home() / "BP app/docs/plans/smooth-mornings/assets/16-repeat-check/fixture.json"
CAUGHT, WRONG = 0.9, 1 / 50
PER_MESSAGE = 15


def messages(questions):
    """[(day, questions)] one message a day, at most PER_MESSAGE questions each."""
    out = []
    for day, qs in groupby(sorted(questions, key=lambda q: q["day"]), key=lambda q: q["day"]):
        qs = list(qs)
        out += [(day, qs[i:i + PER_MESSAGE]) for i in range(0, len(qs), PER_MESSAGE)]
    return out


def score(questions, held):
    """held: {news id: the row it was held as repeating, or None}. A repeat counts as caught when held at all. A News
    the label pass found to be a repeat the hand check let through (`label_pass`) scores as neither."""
    caught = [q for q in questions if q["repeat_of"] and held.get(q["news"]["id"])]
    missed = [q for q in questions if q["repeat_of"] and not held.get(q["news"]["id"])]
    wrong = [q for q in questions if not q["repeat_of"] and not q.get("label_pass") and held.get(q["news"]["id"])]
    return caught, missed, wrong


def read_once(model, system, questions):
    held = {}

    def one(part):
        day, qs = part
        today = date.fromisoformat(day)
        asks = [(q["news"], told(q["news"], q["candidates"], today)) for q in qs]
        answer, _ = ask(model, system, repeat_questions(asks, today))
        got = same_story(answer, asks)
        return {q["news"]["id"]: got.get(i) for i, q in enumerate(qs, 1)}

    with ThreadPoolExecutor(max_workers=3) as pool:
        for part in pool.map(one, messages(questions)):
            held.update(part)
    return held


def selftest():
    news = lambda i, title, day="2026-11-09": {"id": i, "title": title, "blurb": "", "source_name": "A", "created_at": day + "T08:00:00-06:00"}
    qs = [{"day": "2026-11-09", "news": news("n1", "Closing soon"), "candidates": [news("o1", "Closed for winter", "2026-11-06")], "repeat_of": ["o1"]},
          {"day": "2026-11-09", "news": news("n2", "Pie of the week"), "candidates": [news("o2", "Cake of the week", "2026-11-06")], "repeat_of": []},
          {"day": "2026-11-08", "news": news("n3", "Sale"), "candidates": [news("o3", "Sale", "2026-11-07")], "repeat_of": ["o3"]},
          {"day": "2026-11-08", "news": news("n4", "Sale!"), "candidates": [news("o4", "Sale", "2026-11-07")], "repeat_of": [], "label_pass": "o4"}]
    parts = messages(qs[:3] * 10)
    caught, missed, wrong = score(qs, {"n1": qs[0]["candidates"][0], "n2": qs[1]["candidates"][0], "n3": None, "n4": qs[3]["candidates"][0]})
    checks = [
        ([(d, len(x)) for d, x in parts] == [("2026-11-08", 10), ("2026-11-09", PER_MESSAGE), ("2026-11-09", 20 - PER_MESSAGE)],
         "one message a day, cut at PER_MESSAGE"),
        ([q["news"]["id"] for q in caught] == ["n1"] and [q["news"]["id"] for q in missed] == ["n3"]
         and [q["news"]["id"] for q in wrong] == ["n2"], "caught, missed and wrongly held; a label-pass repeat is neither"),
        ("1. News written Nov 6: Closed for winter." in repeat_questions([(qs[0]["news"], qs[0]["candidates"])], date(2026, 11, 9)),
         "the message is the morning's own layout"),
    ]
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="haiku", help="the cheap model (default haiku)")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--fixture", default=FIXTURE, help="the private fixture (default: the BP app repo's)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    questions = json.loads(Path(args.fixture).read_text())["questions"]
    system = REPEAT_MODEL.read_text()
    repeats = sum(1 for q in questions if q["repeat_of"])
    found = [q for q in questions if q.get("label_pass")]
    others = len(questions) - repeats - len(found)
    total_caught = total_wrong = 0
    for n in range(1, args.runs + 1):
        held = read_once(args.model, system, questions)
        caught, missed, wrong = score(questions, held)
        total_caught, total_wrong = total_caught + len(caught), total_wrong + len(wrong)
        print(f"[repeats] run {n}, {args.model}: held back {len(caught)} of {repeats} repeats, "
              f"wrongly held {len(wrong)} of {others}; held {sum(1 for q in found if held.get(q['news']['id']))} of the "
              f"{len(found)} the label pass found")
        for q in missed:
            print(f"  MISSED {q['day']} {q['news']['source_name']}: {q['news']['title']}")
        for q in wrong:
            print(f"  WRONG  {q['day']} {q['news']['source_name']}: {q['news']['title']} (as {held[q['news']['id']]['title']!r})")
    caught_share, wrong_share = total_caught / (repeats * args.runs), total_wrong / (others * args.runs)
    ok = caught_share >= CAUGHT and wrong_share <= WRONG
    print(f"[repeats] {'PASS' if ok else 'FAIL'}: held back {total_caught} of {repeats * args.runs} repeats "
          f"({caught_share:.0%}, bar {CAUGHT:.0%}), wrongly held {total_wrong} of {others * args.runs} "
          f"({wrong_share:.1%}, bar {WRONG:.0%}) over {args.runs} runs")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
