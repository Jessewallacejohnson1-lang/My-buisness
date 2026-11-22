#!/usr/bin/env python3
"""
check_same_event.py: does the model, reading sources/models/repeat.md's "Events", say a new Event is the one already
listed when it is, and nothing when it isn't? (BP app docs/plans/watch-every-place, ticket 42; the bar is the ticket's.)

The fixture is every Event a take-out from Nov 1 named as a copy of a kept one, each beside the Events that day the
writer would ask about (write_judged.worth_a_look), and every pair the rule finds among the Events still shown, labelled
by hand (BP app watch-every-place 42, `build_fixture.py`). It stays in the private BP app repo: a listing's words are
the place's.

The check lays the questions out as the morning does (write_judged.event_questions), one message a day, and reads them
three times through Claude Code on Jesse's plan, as check_repeats.py does. Bar: 9 of 10 copies named as the one kept, and
at most 1 in 50 of the others joined to anything. It prints each run's score and every miss, and exits 1 below the bar.

  python3 sources/scripts/check_same_event.py [--model sonnet] [--runs 3] [--fixture FILE]
  python3 sources/scripts/check_same_event.py --selftest
"""

import argparse, json, sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_flags import ask
from check_repeats import messages
from write_judged import REPEAT_MODEL, event_questions, same_event_answers

FIXTURE = Path.home() / "BP app/docs/plans/watch-every-place/assets/42-fb-repeats/fixture.json"
CAUGHT, WRONG = 0.9, 1 / 50


def score(questions, said):
    """said: {event id: the candidate id the model named, or None}. A copy counts only when the model names one it is."""
    caught = [q for q in questions if q["same_as"] and said.get(q["event"]["id"]) in q["same_as"]]
    missed = [q for q in questions if q["same_as"] and said.get(q["event"]["id"]) not in q["same_as"]]
    wrong = [q for q in questions if not q["same_as"] and said.get(q["event"]["id"])]
    return caught, missed, wrong


def read_once(model, system, questions):
    said = {}

    def one(part):
        day, qs = part
        asks = [(q["event"], q["candidates"]) for q in qs]
        abouts = {c["id"]: c.get("description") or "" for q in qs for c in q["candidates"]}
        answer, _ = ask(model, system, event_questions(asks, date.fromisoformat(day), abouts))
        got = same_event_answers(answer, asks)
        return {q["event"]["id"]: (q["candidates"][got[i]]["id"] if got.get(i) is not None else None)
                for i, q in enumerate(qs, 1)}

    with ThreadPoolExecutor(max_workers=3) as pool:
        for part in pool.map(one, messages(questions)):
            said.update(part)
    return said


def selftest():
    ev = lambda i, title: {"id": i, "title": title, "event_date": "2026-11-27", "start_time": "5 AM", "all_day": False,
                           "location": None, "source_name": "A"}
    qs = [{"day": "2026-11-27", "event": ev("n1", "Black Friday at W|R"), "candidates": [ev("k1", "Black Friday")],
           "same_as": ["k1"]},
          {"day": "2026-11-27", "event": ev("n2", "Mass"), "candidates": [ev("k2", "Children's Liturgy")], "same_as": []},
          {"day": "2026-11-27", "event": ev("n3", "Choir"), "candidates": [ev("k3", "Choir"), ev("k4", "Band")],
           "same_as": ["k3"]}]
    caught, missed, wrong = score(qs, {"n1": "k1", "n2": "k2", "n3": "k4"})
    checks = [
        ([q["event"]["id"] for q in caught] == ["n1"] and [q["event"]["id"] for q in missed] == ["n3"]
         and [q["event"]["id"] for q in wrong] == ["n2"], "caught, missed (the wrong one named) and wrongly joined"),
        ("## Event 1: Black Friday at W|R, listed by A: Fri Nov 27, 5 AM, at no place." in
         event_questions([(qs[0]["event"], qs[0]["candidates"])], date(2026, 11, 22)), "the message is the morning's own layout"),
    ]
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="sonnet", help="the model the morning asks (default sonnet)")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--fixture", default=FIXTURE, help="the private fixture (default: the BP app repo's)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    questions = json.loads(Path(args.fixture).read_text())["questions"]
    system = REPEAT_MODEL.read_text()
    copies = sum(1 for q in questions if q["same_as"])
    others = len(questions) - copies
    total_caught = total_wrong = 0
    for n in range(1, args.runs + 1):
        said = read_once(args.model, system, questions)
        caught, missed, wrong = score(questions, said)
        total_caught, total_wrong = total_caught + len(caught), total_wrong + len(wrong)
        print(f"[same-event] run {n}, {args.model}: named {len(caught)} of {copies} copies, wrongly joined {len(wrong)} "
              f"of {others}")
        title = {c["id"]: c["title"] for q in questions for c in q["candidates"]}
        for q in missed:
            print(f"  MISSED {q['day']} {q['event']['source_name']}: {q['event']['title']!r} "
                  f"(said {title.get(said.get(q['event']['id']))!r})")
        for q in wrong:
            print(f"  WRONG  {q['day']} {q['event']['source_name']}: {q['event']['title']!r} as "
                  f"{title.get(said[q['event']['id']])!r}")
    caught_share, wrong_share = total_caught / (copies * args.runs), total_wrong / (others * args.runs)
    ok = caught_share >= CAUGHT and wrong_share <= WRONG
    print(f"[same-event] {'PASS' if ok else 'FAIL'}: named {total_caught} of {copies * args.runs} copies "
          f"({caught_share:.0%}, bar {CAUGHT:.0%}), wrongly joined {total_wrong} of {others * args.runs} "
          f"({wrong_share:.1%}, bar {WRONG:.0%}) over {args.runs} runs")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
