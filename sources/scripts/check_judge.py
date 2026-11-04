#!/usr/bin/env python3
"""
check_judge.py: does the judge, reading the cheap model's flags with sources/models/judge.md and
social.md's judging rules, still decide what Jesse decided? (BP app docs/plans/watch-every-place,
ticket 16.)

The fixture is the social watch's own posts, grouped by the day each was read so "today" is right, with
one Haiku run's flags frozen. It stays in the private BP app repo, not here: this repo is public and a
post's words wait for the place's yes (ADR-020; Jesse, 2026-11-03). So the check runs on the Mac.

It scores the judge's keep or drop, Event or News, and the day; merging is the writer's (ticket 15).
- Keeps: an Event or News still live must come out the same, an Event on its day.
- Mistakes: what was taken out for a written reason the judge should have seen must not come back.
- Extras: anything else it kept. No score: the labels only cover what the judge once kept, so the check
  can't call an extra wrong, or see a good post dropped. A jump in extras is the sign to look.

Run it after any change to judge.md, social.md's judging rules or the routine's model. A model reads
the same flags differently from one run to the next, so it reads them three times through Claude Code on
Jesse's plan (no API key, no bill) and scores all three together: about 640,000 tokens and 7 minutes. It
exits 1 below the bar.

The first baseline (2026-11-03): 332 of 369 right (90%), with keeps 313 of 342, mistakes stopped 19 of 27
and about 41 extras a reading. Its readings ran from 109 to 112 of 123, so the bar sits one such swing
below it, at 87.5%.

  python3 sources/scripts/check_judge.py [--model sonnet] [--runs 3] [--judge FILE] [--fixture FILE]
  python3 sources/scripts/check_judge.py --selftest
"""

import argparse, json, re, sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from batch import page_id
from check_flags import ask, flags_in
from towns import TOWNS, DEFAULT

SOURCES = Path(__file__).resolve().parents[1]
JUDGE = SOURCES / "models" / "judge.md"
SOCIAL = SOURCES / "models" / "social.md"
FIXTURE = Path.home() / "BP app/docs/plans/watch-every-place/assets/16-judge-check/fixture.json"
BAR = 0.875
CHUNK = 30  # posts in one message; a real check's whole day would outrun one answer
RULE = re.compile(r"\b(every|each|weekly|through|until|\w+days)\b", re.I)  # "Fridays through Oct 16"
RULES_FROM, RULES_TO = "Each page is one post, and its first line", "**Photos.**"
THIS_CHECK = """

## This run is a check

The files named above aren't here: the message below holds the pages and the flags on them. You can't open
a post's pictures: a flag's note starting "From the picture:" has been checked. Skip the title skill. Give
every item `interest` null. Answer with the judged items only, one JSON object per line and nothing else,
and give each item one more field: `page`, the page id of the flag it came from.
"""


def system_prompt(judge=JUDGE):
    social = SOCIAL.read_text()
    return Path(judge).read_text() + "\n\n## Social posts\n\n" \
        + social[social.index(RULES_FROM):social.index(RULES_TO)] + THIS_CHECK


def messages(fixture):
    """The judge's messages: each day's flagged posts, a place's posts together (the rules fold them), in
    chunks of CHUNK. A post with no flags never reaches the judge."""
    out = []
    for group in fixture["groups"]:
        flagged = sorted((p for p in group["pages"] if p["flags"]), key=lambda p: p["name"])
        day = date.fromisoformat(group["day"])
        for i in range(0, len(flagged), CHUNK):
            part = flagged[i:i + CHUNK]
            pages = "\n".join(f"=== PAGE {p['file']} ===\nName: {p['name']}\nURL: {p['url']}\nCategory: {p['category']}\n"
                              f"Trust: {p['trust']}\n{p['text']}\n" for p in part)
            flags = "".join(json.dumps(f, ensure_ascii=False) + "\n" for p in part for f in p["flags"])
            out.append(f"Today is {day:%A, %B %-d, %Y}. The town is {TOWNS[DEFAULT]['display']}, Minnesota.\n\n"
                       f"THE PAGES\n\n{pages}\nTHE FLAGS\n\n{flags}")
    return out


def by_post(items):
    out = defaultdict(list)
    for x in items:
        out[page_id(x.get("page"))].append(x)
    return out


def counts(x):
    """An item that reaches the Town feed. `outside` is skipped by the writer; `closed` shows nobody can go."""
    return x.get("area") != "outside"


def check_label(label, items):
    """(right?, why not, the items this label accounts for). One item can answer several labels: a post's
    two teams on one night, or a post's several offers in one News. Merging isn't the judge's score."""
    kept = [x for x in items if counts(x)]
    want = label["expect"]
    if want == "event":
        events = [x for x in kept if x.get("kind") == "event"]
        on_day = [x for x in events if str(x.get("start") or "")[:10] == label["day"]]
        if on_day:
            return True, "", on_day
        if events:
            return False, f"on {str(events[0].get('start'))[:10]}", []
        if kept:
            return False, "as News", []
        return False, "marked outside" if items else "dropped", []
    if want == "news":
        news = [x for x in kept if x.get("kind") == "news"]
        if news:
            return True, "", news
        if kept:
            return False, "as an Event", []
        return False, "marked outside" if items else "dropped", []
    if want == "drop":
        wrong = [x for x in kept if not x.get("closed")]
        return not wrong, f"kept as {wrong[0].get('title')!r}" if wrong else "", items
    wrong = [x for x in kept if label["has"].lower() in str(x.get(label["field"]) or "").lower()]
    return not wrong, f"{label['field']} {wrong[0].get(label['field'])!r}" if wrong else "", items


def day_shows(iso, page):
    """Does this day show in the post's flags or words, as 2026-11-07, Nov. 7, November 7 or 11/7?"""
    day = date.fromisoformat(iso)
    seen = json.dumps(page["flags"], ensure_ascii=False) + page["text"]
    return iso in seen or bool(re.search(rf"\b{day:%b}\w*\.? {day.day}\b|\b{day.month}/{day.day}\b", seen, re.I))


def testable(label, page):
    """A label the judge could get right: nothing set it aside, its post has flags, and an Event's day shows
    in them or on the page, or a flag gives its rule. The rest can't be its mistake (a dead picture link,
    the cheap model's own miss), so they're counted and left out."""
    if label.get("aside") or not page["flags"]:
        return False
    return label["expect"] != "event" or day_shows(label["day"], page) \
        or any(not f.get("date") and f.get("kind") == "event" and RULE.search(str(f.get("when"))) for f in page["flags"])


def score(labels, items):
    """One reading against the labels: {keeps, keeps_right, mistakes, mistakes_right, misses, extras}."""
    posts, used = by_post(items), set()
    out = {"keeps": 0, "keeps_right": 0, "mistakes": 0, "mistakes_right": 0, "misses": [], "extras": []}
    for label in labels:
        right, why, took = check_label(label, posts[page_id(label["post"])])
        used |= {id(x) for x in took}
        part = "keeps" if label["expect"] in ("event", "news") else "mistakes"
        out[part] += 1
        out[part + "_right"] += right
        if not right:
            out["misses"].append({**label, "got": why})
    out["extras"] = [x for x in items if id(x) not in used and counts(x)]
    return out


def say(label):
    if label["expect"] == "event":
        return f"MISSED Event {label['day']} {label['source']}: {label['title']} ({label['got']})"
    if label["expect"] == "news":
        return f"MISSED News {label['source']}: {label['title']} ({label['got']})"
    return f"MISTAKE {label['source']}: {label['title']}: {label['got']}; taken out because {label['why']}"


def read_once(model, system, msgs):
    def one(text):
        for attempt in (1, 2):
            answer, usage = ask(model, system, text)
            got = flags_in(answer)
            if got:
                not_json = [ln for ln in answer.splitlines() if ln.strip() and not ln.lstrip().startswith("{")]
                return got, usage, len(not_json)
        raise RuntimeError(f"no items in the answer, twice: {answer[-300:]}")
    with ThreadPoolExecutor(max_workers=3) as pool:
        return list(pool.map(one, msgs))


def selftest():
    labels = [{"post": "a", "expect": "event", "day": "2026-11-07", "title": "Fair", "source": "S"},
              {"post": "b", "expect": "event", "day": "2026-11-07", "title": "Sale", "source": "S"},
              {"post": "c", "expect": "event", "day": "2026-11-07", "title": "Wrong kind", "source": "S"},
              {"post": "d", "expect": "news", "title": "Hours", "source": "S"},
              {"post": "e", "expect": "news", "title": "Gone", "source": "S"},
              {"post": "n", "expect": "news", "title": "Went out", "source": "S"},
              {"post": "f", "expect": "drop", "title": "Far", "why": "far", "source": "S"},
              {"post": "g", "expect": "drop", "title": "Far 2", "why": "far", "source": "S"},
              {"post": "h", "expect": "drop", "title": "Members", "why": "members", "source": "S"},
              {"post": "i", "expect": "not", "field": "town", "has": "St. Cloud", "title": "T", "why": "w", "source": "S"},
              {"post": "j", "expect": "not", "field": "title", "has": "johnnies win", "title": "J", "why": "w", "source": "S"},
              {"post": "m", "expect": "event", "day": "2026-11-07", "title": "Both", "source": "S"},
              {"post": "m", "expect": "news", "title": "Both too", "source": "S"},
              {"post": "m", "expect": "event", "day": "2026-11-07", "title": "Second team", "source": "S"},
              {"post": "m", "expect": "news", "title": "Second offer", "source": "S"}]
    items = [{"page": "a.txt", "kind": "event", "start": "2026-11-07T08:00:00-06:00", "area": "town"},
             {"page": "b", "kind": "event", "start": "2026-11-08", "area": "town"},
             {"page": "c", "kind": "news", "area": "town"},
             {"page": "d", "kind": "news", "area": "town"},
             {"page": "f", "kind": "event", "title": "Far", "start": "2026-11-07", "area": "outside"},
             {"page": "g", "kind": "event", "title": "Far 2", "start": "2026-11-07", "area": "announced"},
             {"page": "h", "kind": "event", "title": "Members", "start": "2026-11-07", "area": "town", "closed": True},
             {"page": "i", "kind": "event", "town": "St. Cloud", "area": "announced"},
             {"page": "j", "kind": "news", "title": "Johnnies third at MIAC", "area": "town"},
             {"page": "n", "kind": "news", "area": "outside"},
             {"page": "m", "kind": "event", "start": "2026-11-07", "area": "town"},
             {"page": "m", "kind": "news", "area": "town"},
             {"page": "z", "kind": "news", "title": "Unlabeled", "area": "town"},
             {"page": "z", "kind": "event", "title": "Skipped", "area": "outside"}]
    s = score(labels, items)
    got = {(m["post"], m["got"]) for m in s["misses"]}
    page = {"flags": [{"kind": "event", "date": "2026-11-07"}], "text": ""}
    no_day = {"flags": [{"kind": "event", "date": "2026-11-02", "when": "Monday"}], "text": "Come Monday"}
    rule = {"flags": [{"kind": "event", "date": "", "when": "Fridays through Nov 20"}], "text": ""}
    vague = {"flags": [{"kind": "event", "date": "", "when": "this holiday season"}], "text": ""}
    text = {"flags": [{"kind": "event", "date": "2026-11-02", "when": "Monday"}], "text": "Sale Nov. 7 at the shop"}
    social = SOCIAL.read_text()
    fixture = {"groups": [{"day": "2026-10-29", "pages": [
        {"file": "z", "name": "Zed", "url": "u", "category": None, "trust": "official", "text": "t", "flags": [{"page": "z"}]},
        {"file": "a", "name": "Abe", "url": "u", "category": None, "trust": "official", "text": "t", "flags": [{"page": "a"}]},
        {"file": "q", "name": "Quiet", "url": "u", "category": None, "trust": "official", "text": "t", "flags": []}]}]}
    msg = messages(fixture)
    checks = [
        ((s["keeps"], s["keeps_right"]) == (10, 6), "an Event on its day and a News are keeps; the rest are misses"),
        ((s["mistakes"], s["mistakes_right"]) == (5, 3), "outside, closed and a fair title stop a mistake; a kept one and a wrong town don't"),
        (("b", "on 2026-11-08") in got, "an Event on another day says which"),
        (("c", "as News") in got, "an Event written as News says so"),
        (("e", "dropped") in got and ("n", "marked outside") in got, "dropped and marked outside are told apart"),
        (any(p == "g" and "Far 2" in w for p, w in got), "a mistake kept names the item"),
        ("Unlabeled" in [x.get("title") for x in s["extras"]] and "Skipped" not in [x.get("title") for x in s["extras"]]
         and "Far 2" not in [x.get("title") for x in s["extras"]], "extras: an unlabeled item, not an outside one or a mistake"),
        (not any(m["post"] == "m" for m in s["misses"]), "one item answers two labels: merging isn't scored"),
        (testable(labels[0], page) and not testable(labels[0], {"flags": [], "text": "x"}), "no flags: set aside"),
        (not testable(labels[0], no_day) and not testable(labels[0], vague), "an Event whose day shows nowhere: set aside"),
        (not testable({**labels[0], "aside": "picture gone"}, page), "a label set aside by hand stays aside"),
        (testable(labels[0], rule) and testable(labels[0], text), "a rule, or the day in the page's words, is testable"),
        (RULES_FROM in social and RULES_TO in social and "Keep everything" in system_prompt(), "social.md's rules are found"),
        (len(msg) == 1 and "Quiet" not in msg[0] and msg[0].index("Abe") < msg[0].index("Zed")
         and "Thursday, October 29, 2026" in msg[0], "the day, a place's posts together, an unflagged post left out"),
    ]
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="sonnet", help="the judge's model (default sonnet, the routine's)")
    ap.add_argument("--runs", type=int, default=3, help="readings, scored together (default 3)")
    ap.add_argument("--judge", default=JUDGE, help="another copy of judge.md, to try a change")
    ap.add_argument("--fixture", default=FIXTURE, help="the private fixture (default: the BP app repo's)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    fixture = json.loads(Path(args.fixture).read_text())
    pages = {p["file"]: p for g in fixture["groups"] for p in g["pages"]}
    labels = [l for l in fixture["labels"] if testable(l, pages[l["post"]])]
    aside = len(fixture["labels"]) - len(labels)
    system, msgs = system_prompt(args.judge), messages(fixture)
    run = SOURCES.parent / ".runs" / "check-judge" / datetime.now().strftime("%Y%m%d-%H%M%S")
    run.mkdir(parents=True, exist_ok=True)
    print(f"[judge] {len(labels)} labels on {len(pages)} posts ({aside} set aside: nothing to judge them on), "
          f"{len(msgs)} messages, {args.runs} readings", flush=True)
    keeps = mistakes = extras = 0
    rights = []
    for n in range(1, args.runs + 1):
        answers = read_once(args.model, system, msgs)
        items = [x for got, _, _ in answers for x in got]
        tokens = sum(u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                     + u.get("output_tokens", 0) for _, u, _ in answers)
        stray = sum(s for _, _, s in answers)
        s = score(labels, items)
        (run / f"items-{n}.jsonl").write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in items))
        keeps += s["keeps_right"]
        mistakes += s["mistakes_right"]
        extras += len(s["extras"])
        rights.append(s["keeps_right"] + s["mistakes_right"])
        print(f"[judge] run {n}, {args.model}: keeps {s['keeps_right']} of {s['keeps']}, mistakes stopped "
              f"{s['mistakes_right']} of {s['mistakes']}, {len(s['extras'])} extra, {stray} lines not JSON, {tokens:,} tokens", flush=True)
        for m in s["misses"]:
            print(f"  {say(m)}")
        for x in s["extras"]:
            print(f"  extra {x.get('source_name')}: {x.get('kind')} {x.get('title')} ({str(x.get('start') or 'no date')[:10]})")
    k, m = s["keeps"] * args.runs, s["mistakes"] * args.runs
    right = (keeps + mistakes) / (k + m)
    print(f"[judge] {'PASS' if right >= BAR else 'FAIL'}: {keeps + mistakes} of {k + m} right ({right:.0%}); bar {BAR:.1%}. "
          f"Keeps {keeps} of {k} ({keeps / k:.0%}), mistakes stopped {mistakes} of {m} ({mistakes / m:.0%}), "
          f"{extras / args.runs:.0f} extras a reading; right per reading {rights}. Items kept in {run}")
    sys.exit(0 if right >= BAR else 1)


if __name__ == "__main__":
    main()
