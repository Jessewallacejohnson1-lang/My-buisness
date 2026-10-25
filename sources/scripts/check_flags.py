#!/usr/bin/env python3
"""
check_flags.py: does the cheap model, reading pages with sources/models/flag.md, catch at
least 9 of every 10 things the better model finds? (BP app docs/plans/watch-every-place,
ticket 04; the bar is Jesse's, 2026-10-13.)

The fixture is the test run of 2026-10-13 (sources/evals/flag/): 35 pages from 11 watched and
24 listed places, read through the registry's polite fetch, and the better model's 20
findings on them. The check sends the pages to the cheap model in batches of 12 (batch.py) with the
instructions as its system prompt, through Claude Code on Jesse's plan (no API key, no bill),
then matches its flags to the findings: same page, shared title words, and the same day when
both give one.

Run it whenever flag.md or the cheap model changes. A model reads the same page differently
from one run to the next, so the check reads the pages three times and scores all three
together. It prints each run's score, every miss and every extra flag (the judge's to
drop), keeps the flags in .runs/check-flags/, and exits 1 below the bar.

  python3 sources/scripts/check_flags.py [--model haiku] [--runs 3]
  python3 sources/scripts/check_flags.py --selftest
"""

import argparse, json, re, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from write_judged import words
from batch import layout, page_id

SOURCES = Path(__file__).resolve().parents[1]
INSTRUCTIONS = SOURCES / "models" / "flag.md"
FIXTURE = SOURCES / "evals" / "flag"
FIXTURE_DAY = date(2026, 10, 13)  # the day the pages were read
BAR = 0.9


def ask(model, system, text):
    """One batch through Claude Code: no tools, no CLAUDE.md, no hooks, nothing saved."""
    with tempfile.TemporaryDirectory() as empty:
        r = subprocess.run(["claude", "-p", "--safe-mode", "--tools", "", "--no-session-persistence",
                            "--model", model, "--output-format", "json", "--system-prompt", system],
                           input=text, capture_output=True, text=True, cwd=empty, timeout=600)
    if r.returncode:
        raise RuntimeError(f"claude exited {r.returncode}: {(r.stderr or r.stdout)[-300:]}")
    reply = json.loads(r.stdout)
    return reply.get("result") or "", reply.get("usage") or {}


def flags_in(answer):
    out = []
    for line in answer.splitlines():
        line = line.strip().strip(",")
        if line.startswith("{"):
            try:
                f = json.loads(line)
            except ValueError:
                continue
            if isinstance(f, dict) and f.get("page"):
                out.append(f)
    return out


def title_words(text):
    """"Saint Joseph" and "St. Joseph" are the same words."""
    return words(re.sub(r"\bsaint\b", "st", str(text or ""), flags=re.I))


def same_item(found, flag):
    if page_id(flag.get("page")) != page_id(found["file"]) or flag.get("kind") == "none":
        return False
    day, flag_day = found.get("date") or "", str(flag.get("date") or "")
    if day and flag_day and day != flag_day and day not in str(flag.get("when") or ""):
        return False
    a, b = title_words(found["title"]), title_words(flag.get("title"))
    if day and day == flag_day:
        return bool(a & b)  # same page, same day: one shared word names the same thing
    return bool(a and b) and len(a & b) / min(len(a), len(b)) >= 0.5


def match(findings, flags):
    """Each finding takes one flag: one on the same day first, else any that fits."""
    left, caught, missed = list(flags), [], []
    for f in findings:
        fits = [x for x in left if same_item(f, x)]
        hit = next((x for x in fits if str(x.get("date") or "") == (f.get("date") or "")), fits[0] if fits else None)
        if hit:
            left.remove(hit)
            caught.append((f, hit))
        else:
            missed.append(f)
    return caught, missed, [x for x in left if x.get("kind") != "none"]


def selftest():
    findings = [{"file": "m.txt", "title": "Stitch and Sip", "date": "2026-10-28"},
                {"file": "m.txt", "title": "Stitch and Sip", "date": "2026-11-19"},
                {"file": "m.txt", "title": "Plant Bingo benefiting Angel Reins Stable ($30)", "date": "2026-10-24"},
                {"file": "j.txt", "title": "Jupiter Moon shop open Tue-Fri", "date": None},
                {"file": "w.txt", "title": "Winters Family Chiropractic St. Joseph office is closed (Sauk Centre office open)"},
                {"file": "f.txt", "title": "Farmers' Market final day of 2026 season (Fridays through Oct 16)", "date": "2026-10-16"}]
    flags = [{"page": "m.txt", "kind": "event", "title": "Stitch & Sip", "date": ""},
             {"page": "m.txt", "kind": "event", "title": "Stitch and Sip", "date": "2026-11-19"},
             {"page": "m.txt", "kind": "event", "title": "Stitch and Sip", "date": "2026-10-28"},
             {"page": "m.txt", "kind": "event", "title": "Plant Bingo", "date": "2026-10-25"},
             {"page": "x.txt", "kind": "news", "title": "Jupiter Moon shop open Tue-Fri"},
             {"page": "j.txt", "kind": "news", "title": "New hours at Jupiter Moon: open Tue-Fri", "date": ""},
             {"page": "w", "kind": "news", "title": "OUR SAINT JOSEPH PRACTICE IS NOW CLOSED", "date": ""},
             {"page": "f", "kind": "event", "title": "St. Joseph Farmers' Market (weekly Friday market)", "date": "2026-10-16"}]
    caught, missed, extra = match(findings, flags)
    checks = [
        ([f["date"] for f, x in caught[:2]] == [x["date"] for f, x in caught[:2]], "a dated flag goes to its own day"),
        ([m["title"][:11] for m in missed] == ["Plant Bingo"], "another day is not the same item"),
        (caught[2][1]["page"] == "j.txt", "news matches on its words, on its own page"),
        (caught[3][1]["page"] == "w", "Saint and St. are one word, and a page is a page with or without .txt"),
        (len(caught) == 5 and caught[4][1]["page"] == "f", "same page and day: one shared word is enough"),
        (sorted(x["title"] for x in extra) == ["Jupiter Moon shop open Tue-Fri", "Plant Bingo", "Stitch & Sip"],
         "what is left over is extra"),
        (flags_in('{"page": "a", "kind": "none"}\nsome prose\n```\n{"page": "b", "kind": "event", "title": "x"},\n{bad')
         == [{"page": "a", "kind": "none"}, {"page": "b", "kind": "event", "title": "x"}], "reads JSON lines among prose"),
    ]
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="haiku", help="the cheap model (default haiku)")
    ap.add_argument("--runs", type=int, default=3, help="readings of the pages, scored together (default 3)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    system = INSTRUCTIONS.read_text()
    pages = [dict(p, text=(FIXTURE / "pages" / p["file"]).read_text())
             for p in json.loads((FIXTURE / "pages.json").read_text()) if p.get("file")]
    findings = [f for f in map(json.loads, (FIXTURE / "expected.jsonl").read_text().splitlines()) if f["kind"] != "none"]
    run = SOURCES.parent / ".runs" / "check-flags" / datetime.now().strftime("%Y%m%d-%H%M%S")
    run.mkdir(parents=True, exist_ok=True)
    total = 0
    for n in range(1, args.runs + 1):
        with ThreadPoolExecutor(max_workers=3) as pool:
            answers = list(pool.map(lambda text: ask(args.model, system, text), layout(pages, FIXTURE_DAY)))
        flags = [f for text, _ in answers for f in flags_in(text)]
        tokens = sum(u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
                     + u.get("cache_read_input_tokens", 0) + u.get("output_tokens", 0) for _, u in answers)
        caught, missed, extra = match(findings, flags)
        silent = sorted({page_id(p["file"]) for p in pages} - {page_id(f["page"]) for f in flags})
        (run / f"flags-{n}.jsonl").write_text("".join(json.dumps(f, ensure_ascii=False) + "\n" for f in flags))
        total += len(caught)
        print(f"[flags] run {n}, {args.model}: caught {len(caught)} of {len(findings)}, "
              f"{len(extra)} extra, {len(flags)} lines, {tokens:,} tokens")
        for f in missed:
            print(f"  MISSED {f['file']}: {f['title']} ({f.get('date') or 'no date'})")
        for x in extra:
            print(f"  extra  {x['page']}: {x.get('kind')} {x.get('title')} ({x.get('date') or x.get('when') or 'no date'})")
        for p in silent:
            print(f"  NO ANSWER for page {p}")
    score = total / (len(findings) * args.runs)
    print(f"[flags] {'PASS' if score >= BAR else 'FAIL'}: caught {total} of {len(findings) * args.runs} "
          f"({score:.0%}) over {args.runs} runs; bar {BAR:.0%}. Flags kept in {run}")
    sys.exit(0 if score >= BAR else 1)


if __name__ == "__main__":
    main()
