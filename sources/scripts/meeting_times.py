#!/usr/bin/env python3
"""A school club's meeting time, read from its school's activities page (BP app nothing-scheduled 03).

    python3 meeting_times.py <saved page.html> <activity name>...   # {name: [rule]} as JSON, only clubs with a time
    python3 meeting_times.py --selftest

A rule is a Group's meeting rule (`clubs.meets`, BP app rsvp-and-groups 05), stored in `team_activities.meets`:
{"days": ["fri"], "time": "08:00"}, plus "weeks": [2] for "2nd Tuesday of each month", "every": 2 for "every other
Friday", and a time the school gives only in words ("After school"). The app says it "Fridays · 8 AM"
(`MeetingRule.words`). A page is fetched once (run.fetch) and read here offline; nothing here touches the network.

ponytail: Sartell's page only (isd748.org/activities: a club's name, "Advisor -", then its words). Ticket 05's weekly
step reads every school's page with this and grows it for the next page's layout.
"""
import html
import json
import re
import sys

DAY = re.compile(r"\b(mon|tues?|wed(?:nes)?|thu(?:rs)?|fri|sat(?:ur)?|sun)day'?s?\b", re.I)
CLOCK = re.compile(r"\b(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\b", re.I)
MEETS = re.compile(r"\bmeetings?\b|\bmeet\b|\bmeets (?:on|every)\b", re.I)
ADVISOR = re.compile(r"^(?:\w+ )?advisor", re.I)


def rule(text):
    """The first sentence that says when it meets, as a rule; None when none does."""
    for sentence in re.split(r"(?<=[.!?])\s+", text):
        days = [m.group(1)[:3].lower() for m in DAY.finditer(sentence)]
        if not MEETS.search(sentence) or not days:
            continue
        r = {"days": list(dict.fromkeys(days))}
        if "month" in sentence.lower():
            weeks = [int(w) for w in re.findall(r"\b([1-5])(?:st|nd|rd|th)\b", sentence)]
            if weeks:
                r["weeks"] = weeks
        if re.search(r"\bevery other\b", sentence, re.I):
            r["every"] = 2
        clock = CLOCK.search(sentence)
        if clock:
            hour = int(clock.group(1)) % 12 + (12 if clock.group(3).lower() == "p" else 0)
            r["time"] = f"{hour:02d}:{clock.group(2) or '00'}"
        elif re.search(r"\bafter school\b", sentence, re.I):
            r["time"] = "After school"
        return r
    return None


def page_rules(page, names):
    """{name: [rule]} for each of `names` whose block on the page says when it meets. A block is a club's
    heading (one of the two lines above its "Advisor -") down to the next club's heading; the first block
    whose heading holds the name is the club's."""
    text = html.unescape(re.sub(r"<[^>]+>", "\n", re.sub(r"(?s)<(script|style).*?</\1>", " ", page)))
    lines = [line.strip() for line in text.split("\n") if line.strip()]
    starts = [i for i, line in enumerate(lines) if ADVISOR.match(line)]
    blocks = []
    for n, i in enumerate(starts):
        end = starts[n + 1] - 2 if n + 1 < len(starts) else len(lines)
        blocks.append((" | ".join(lines[max(0, i - 2):i]).lower(), " ".join(lines[i + 1:end])))
    found = {}
    for name in names:
        block = next((words for heading, words in blocks if name.lower() in heading), None)
        r = block and rule(block)
        if r:
            found[name] = [r]
    return found


def selftest():
    cases = [  # Sartell's own words, 2026-11-13
        ("Bible Study will meet every Friday at 8:00am in Mrs. Smith's room.", {"days": ["fri"], "time": "08:00"}),
        ("Meetings take place on the 2nd Tuesday of each month. Members", {"days": ["tue"], "weeks": [2]}),
        ("Meetings will be held on Wednesday's after school in the Art/Meadows Learning Commons.",
         {"days": ["wed"], "time": "After school"}),
        ("Meetings will be held at 7:45am every other Friday in room C220.", {"days": ["fri"], "every": 2, "time": "07:45"}),
        ("Meetings are held the 1st and 3rd Monday of each month @ 8am in C228.",
         {"days": ["mon"], "weeks": [1, 3], "time": "08:00"}),
        ("Meetings are held every Thursday from 7:15am to 8:15am in room M101.", {"days": ["thu"], "time": "07:15"}),
        ("Morning meetings occur 1-2 times a month.", None),
        ("Individual and team awards are given at meets which occur on Saturdays throughout the season.", None),
        ("Practice is held after school on Tuesdays and Thursdays from 3:30-5:00pm.", None),
    ]
    failed = 0
    for words, want in cases:
        got = rule(words)
        if got != want:
            failed += 1
            print(f"FAIL {words!r}: {got} != {want}")
    page = ("<h3>Bible Study</h3><p>BIBLE STUDY</p><p>Faculty Advisor -</p><p>Rachel Smith</p>"
            "<p>Bible Study will meet every Friday at 8:00am.</p><h3>Chess Club</h3><p>CHESS CLUB</p><p>Advisor -</p>"
            "<p>Open</p>")
    got = page_rules(page, ["Bible Study", "Chess Club"])
    if got != {"Bible Study": [{"days": ["fri"], "time": "08:00"}]}:
        failed += 1
        print(f"FAIL page_rules: {got}")
    print(f"{len(cases) + 1 - failed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    with open(sys.argv[1], encoding="utf-8") as f:
        print(json.dumps(page_rules(f.read(), sys.argv[2:]), indent=1))
