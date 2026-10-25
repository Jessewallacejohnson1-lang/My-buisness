#!/usr/bin/env python3
"""
batch.py: changed pages laid out for the cheap model (sources/models/flag.md), in batches of 12,
each page marked `=== PAGE <id> ===`. morning.py, social.py and check_flags.py all send pages
this way.

A page longer than PAGE_CHARS goes in numbered parts under its own id, cut between lines, each
part starting a little before the last one ended, so an event cut in two is whole in one part
and nothing past the cut is lost (BP app codebase-health 05: RSS feeds reach the cheap model now,
and a long one lost every event past 15,000 characters).

  python3 sources/scripts/batch.py --selftest
"""

import sys
from pathlib import Path

BATCH = 12
PAGE_CHARS = 15_000  # one part; the 2026-10-13 test run read pages cut here
OVERLAP = 1_000      # characters each part repeats from the one before


def page_id(name):
    """A page is named by its file's stem; a model that adds or drops ".txt" names the same page."""
    return Path(str(name)).name.removesuffix(".txt")


def parts(text, size=PAGE_CHARS, overlap=OVERLAP):
    """The text in parts of at most `size` characters, cut after a line where one falls past
    `overlap`, each part starting at the first line in the last `overlap` characters before it.
    ponytail: a 2 MB page (run.py's most) is ~140 parts; cap it if one ever floods the batches."""
    out, start = [], 0
    while True:
        if len(text) - start <= size:
            return out + [text[start:]]
        end = text.rfind("\n", start + overlap, start + size) + 1 or start + size
        out.append(text[start:end])
        line = text.find("\n", end - overlap, end)
        start = line + 1 if line != -1 else end - overlap


def layout(pages, today, town="St. Joseph, Minnesota"):
    """Pages ({file, url, text}) as the cheap model's messages, one per batch of BATCH parts."""
    cut = []
    for p in pages:
        bits = parts(p["text"])
        for i, text in enumerate(bits, 1):
            note = f"Part {i} of {len(bits)} of this page; the parts overlap a little.\n" if len(bits) > 1 else ""
            cut.append(f"=== PAGE {page_id(p['file'])} ===\nURL: {p['url']}\n{note}{text}\n")
    out = []
    for b in range(0, len(cut), BATCH):
        batch = cut[b:b + BATCH]
        out.append("\n".join([f"Today is {today:%A, %B %-d, %Y}. The town is {town}. "
                              f"{len(batch)} pages follow.\n"] + batch))
    return out


def selftest():
    from datetime import date
    menu = "Home | About | Menu | Gift cards | Contact us\n"
    events = [f"Trivia night {n}: Saturday, November {n % 28 + 1}, 7 PM at the taproom" for n in range(80)]
    text = "".join(menu * 12 + e + "\n" for e in events)
    long_page = {"file": "feed.txt", "url": "https://x/feed/", "text": text}
    msgs = layout([long_page], date(2026, 10, 25))
    body = "\n".join(msgs)
    pieces = parts(text)
    one_line = "x" * 40_000
    checks = [
        (len(text) >= 40_000, "the fixture page is 40,000 characters or more"),
        (all(e in body for e in events), "every event on a long page shows up in some part"),
        (all(len(p) <= PAGE_CHARS for p in pieces) and len(pieces) > 2, "each part fits under the old cut"),
        (all(any(e in p for p in pieces) for e in events), "no event is cut in two: each is whole in one part"),
        (body.count("=== PAGE feed ===") == len(pieces) and f"Part 2 of {len(pieces)}" in body,
         "every part carries the page's own id and its number"),
        ("".join(parts(one_line, 15_000, 1_000)).count("x") >= 40_000 and len(parts(one_line)) == 3,
         "a page with no line breaks is still cut, and nothing dropped"),
        (len(layout([{"file": f"p{i}", "url": "u", "text": "t"} for i in range(35)], date(2026, 10, 13))) == 3
         and "=== PAGE p ===\nURL: u\nt\n" in layout([{"file": "p.txt", "url": "u", "text": "t"}], date(2026, 10, 13))[0]
         and "Today is Tuesday, October 13, 2026." in layout([long_page], date(2026, 10, 13))[0],
         "batches of 12, each page marked, a short page whole"),
    ]
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    else:
        sys.exit(__doc__)
