#!/usr/bin/env python3
"""A school club's meeting time, read from its school's activities page (BP app nothing-scheduled 03), kept current
each Sunday by the morning job (ticket 05).

    python3 meeting_times.py <saved page.html> <activity name>...   # {name: [rule]} as JSON, only clubs with a time
    python3 meeting_times.py --selftest

A rule is a Group's meeting rule (`clubs.meets`, BP app rsvp-and-groups 05), stored in `team_activities.meets`:
{"days": ["fri"], "time": "08:00"}, plus "weeks": [2] for "2nd Tuesday of each month", "every": 2 for "every other
Friday", and a time the school gives only in words ("After school"). The app says it "Fridays · 8 AM"
(`MeetingRule.words`; `words` here says it the same way for the report).

The Sunday step (`sunday`, from morning.py finish): each school whose registry entry names its `clubs_page` is read
once through the polite fetcher (run.fetch: robots.txt, Crawl-delay). A club's time that differs from the stored one
replaces it, and a club whose block no longer gives one goes back to none ("No events yet" on its row), each a line in
the morning report; an unchanged week says so. A page that won't read, or names none of the school's clubs, changes
nothing, and so does one that no longer names most of the school's clubs with a time at once (a new page, not
moved clubs); otherwise a club the page no longer names goes back to none too.

The reader knows one layout, Sartell's (a club's name, "Advisor -", then its words). A page it can't place clubs on
gets a line when it says when something meets anywhere.
"""
import html
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run import fetch  # noqa: E402
from read_events import CLOCK  # noqa: E402

DAY = re.compile(r"\b(mon|tues?|wed(?:nes)?|thu(?:rs)?|fri|sat(?:ur)?|sun)day'?s?\b", re.I)
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
            hour = int(clock.group(1)) % 12 + (12 if clock.group(5).lower() == "p" else 0)
            r["time"] = f"{hour:02d}:{clock.group(2) or '00'}"
        elif re.search(r"\bafter school\b", sentence, re.I):
            r["time"] = "After school"
        return r
    return None


def page_lines(page):
    """A page's text, one line per tag."""
    text = html.unescape(re.sub(r"<[^>]+>", "\n", re.sub(r"(?s)<(script|style).*?</\1>", " ", page)))
    return [line.strip() for line in text.split("\n") if line.strip()]


def page_rules(page, names):
    """{name: [rule], or None when its block gives no time} for each of `names` the page names. A block is a club's
    heading (one of the two lines above its "Advisor -") down to the next club's heading; the first block whose heading
    holds the name is the club's. A name no heading holds is left out."""
    lines = page_lines(page)
    starts = [i for i, line in enumerate(lines) if ADVISOR.match(line)]
    blocks = []
    for n, i in enumerate(starts):
        end = starts[n + 1] - 2 if n + 1 < len(starts) else len(lines)
        blocks.append((" | ".join(lines[max(0, i - 2):i]).lower(), " ".join(lines[i + 1:end])))
    found = {}
    for name in names:
        block = next((words for heading, words in blocks if name.lower() in heading), None)
        if block is not None:
            r = rule(block)
            found[name] = [r] if r else None
    return found


DAY_NAMES = {"mon": "Monday", "tue": "Tuesday", "wed": "Wednesday", "thu": "Thursday", "fri": "Friday",
             "sat": "Saturday", "sun": "Sunday"}


def words(meets):
    """A club's rules as the app says them (MeetingRule.words): "Fridays · 8 AM"; None for no rule."""
    def joined(parts):
        return " and ".join(parts) if len(parts) < 3 else ", ".join(parts[:-1]) + " and " + parts[-1]

    said = []
    for r in meets or []:
        names = [DAY_NAMES[d[:3].lower()] for d in r.get("days") or [] if d[:3].lower() in DAY_NAMES]
        if not names:
            continue
        weeks = [w for w in r.get("weeks") or [] if 1 <= w <= 5]
        pattern = (joined([("1st", "2nd", "3rd", "4th", "5th")[w - 1] for w in weeks]) + f" {joined(names)} of each month"
                   if weeks else f"Every other {joined(names)}" if r.get("every") == 2 else joined([n + "s" for n in names]))
        time = (r.get("time") or "").strip()
        clock = re.fullmatch(r"(\d{1,2}):(\d{2})", time)
        if clock:
            h, m = int(clock[1]), int(clock[2])
            time = {0: "Midnight", 720: "Noon"}.get(h * 60 + m) or (
                f"{h % 12 or 12}{f':{m:02d}' if m else ''} {'AM' if h < 12 else 'PM'}")
        said.append(" · ".join(filter(None, [pattern, time])))
    return "; ".join(said) or None


def sunday(db, entries, write=True, get=fetch):
    """The morning report's lines on Sundays (morning.sunday_lines): each school's club page read, its clubs' times
    compared with the stored ones, and each change written to its row (`write`), one line each."""
    import read_events
    schools = [(read_events.bound_team(e), e["_name"], e["clubs_page"]) for e in entries if e.get("clubs_page")]
    if not schools:
        return []
    rows = db.rest("GET", "team_activities?select=id,team_id,name,meets&kind=eq.club"
                          f"&team_id=in.({','.join(t for t, _, _ in schools)})&order=name") or []
    read, unread, lines, changed = [], [], [], 0
    for team, school, url in schools:
        clubs = [r for r in rows if r["team_id"] == team]
        try:
            _, page = get(url)
        except Exception as e:  # a page that won't read is a line, never a lost report
            why = " ".join(str(e).split())[:200]
            unread.append(f"{school} won't read: " + ("its robots.txt keeps us out" if "robots.txt disallows" in why else why))
            continue
        found = page_rules(page, [r["name"] for r in clubs])
        timed = sum(1 for r in found.values() if r)
        read.append(f"{school} {timed} of {len(clubs)} clubs with a time" if timed else f"{school} none")
        if not found:
            said = sum(1 for s in re.split(r"(?<=[.!?])\s+", " ".join(page_lines(page))) if rule(s))
            if said:
                lines.append(f"[meets] {school}'s page gives {said} meeting time{'s' * (said > 1)} the reader can't "
                             "place on a club: teach sources/scripts/meeting_times.py its layout")
            if any(r["meets"] for r in clubs):
                lines.append(f"[meets] {school}'s page names none of its {len(clubs)} clubs: their times are kept")
            continue
        timed = [r for r in clubs if r["meets"]]
        gone = [r for r in timed if r["name"] not in found]
        if len(gone) > 1 and 2 * len(gone) > len(timed):  # as apple_maps' MAX_AT_ONCE: the page changed, not the clubs
            lines.append(f"[meets] {school}'s page no longer names {len(gone)} of its {len(timed)} clubs with a time: "
                         "none changed, check the page by hand")
            continue
        for r in clubs:
            new, old = found.get(r["name"]), r["meets"]
            if new == (old or None):
                continue
            if write:
                try:
                    db.rest("PATCH", f"team_activities?id=eq.{r['id']}", {"meets": new}, prefer="return=minimal")
                except Exception as e:  # unsaved, it reads as a change again next Sunday
                    lines.append(f"[meets] {school}'s {r['name']}: not saved ({' '.join(str(e).split())[:200]})")
                    continue
            changed += 1
            lines.append(f"[meets] {school}'s {r['name']}: "
                         + (f"{words(new)}, was {words(old) or 'no time'}" if new else
                            f"{'no time on its page now' if r['name'] in found else 'no longer on its page'}, was "
                            f"{words(old)}: back to No events yet"))
    n = len(schools)
    head = f"[meets] {n} schools' club pages: " if n != 1 else "[meets] 1 school's club page: "
    verb = "changed" if write else "would change"
    what = "1 club's meeting time" if changed == 1 else f"{changed} clubs' meeting times"
    return ([head + ", ".join(read) + ("; " + "; ".join(unread) if unread else "")] + lines
            + [f"[meets] {verb} {what}" if changed else "[meets] no meeting time changed"])


def selftest():
    from morning_run import FakeDb
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
    checks = [(rule(text) == want, f"rule {text!r}: {rule(text)} != {want}") for text, want in cases]

    def check(ok, why):
        checks.append((bool(ok), why))

    page = ("<h3>Bible Study</h3><p>BIBLE STUDY</p><p>Faculty Advisor -</p><p>Rachel Smith</p>"
            "<p>Bible Study will meet every Friday at 8:00am.</p><h3>Chess Club</h3><p>CHESS CLUB</p><p>Advisor -</p>"
            "<p>Open</p>")
    got = page_rules(page, ["Bible Study", "Chess Club", "Pickleball Club"])
    check(got == {"Bible Study": [{"days": ["fri"], "time": "08:00"}], "Chess Club": None},
          f"page_rules: a club with a time, one named with none, one not named: {got}")

    # The saved page reads into the 12 times ticket 03's migration stored (its own values, read from the file).
    root = Path(__file__).resolve().parents[2]
    sql = (root / "supabase/migrations/20261113202211_club_meeting_times.sql").read_text()
    stored = {name: json.loads(meets) for name, meets in re.findall(r"\('([^']+)', '(\[.*?\])'\)", sql)}
    saved = (Path(__file__).resolve().parent / "samples/sartell-activities.html").read_text()
    names = sorted(set(stored) | {"Art Club", "Chess Club", "DECA Club", "Robotics", "Speech", "Knowledge Bowl", "Prom"})
    read = {n: r for n, r in page_rules(saved, names).items() if r}
    check(len(stored) == 12 and read == stored, f"the saved Sartell page reads into the 12 times stored: {read}")

    check([words(m) for m in ([{"days": ["fri"], "time": "08:00"}], [{"days": ["tue"], "weeks": [2]}],
                              [{"days": ["fri"], "every": 2, "time": "07:45"}],
                              [{"days": ["mon"], "weeks": [1, 3], "time": "08:00"}],
                              [{"days": ["wed"], "time": "After school"}], [{"days": ["tue", "thu"], "time": "12:00"}],
                              None)]
          == ["Fridays · 8 AM", "2nd Tuesday of each month", "Every other Friday · 7:45 AM",
              "1st and 3rd Monday of each month · 8 AM", "Wednesdays · After school", "Tuesdays and Thursdays · Noon",
              None], "a rule in the app's words (MeetingRule.words)")

    # The Sunday step: Sartell's page against what is stored, the other schools' pages beside it.
    entries = [
        {"id": "sartell-high-school", "_name": "Sartell High School", "status": "active",
         "clubs_page": "https://sartell.example/activities"},
        {"id": "apollo-high-school", "_name": "Apollo High School", "status": "active",
         "clubs_page": "https://apollo.example/activities"},
        {"id": "sauk-rapids-rice-high-school", "_name": "Sauk Rapids-Rice High School", "status": "active",
         "clubs_page": "https://srr.example/activities"},
        {"id": "tech-high-school", "_name": "Tech High School", "status": "active",
         "clubs_page": "https://tech.example/activities"},
        {"id": "kennedy-community-school", "_name": "Kennedy Community School", "status": "active"},
    ]
    rows = ([{"id": f"s{i}", "team_id": "sartell", "name": n, "meets": stored.get(n)} for i, n in enumerate(names)]
            + [{"id": "a1", "team_id": "apollo", "name": "Art Club", "meets": None},
               {"id": "a2", "team_id": "apollo", "name": "DECA", "meets": None},
               {"id": "t1", "team_id": "tech", "name": "Art Club", "meets": None},
               {"id": "r1", "team_id": "sauk-rapids-rice", "name": "FFA", "meets": None}])
    apollo = "<td>Activity</td><td>Start Date</td><td>Advisor</td><td>Art Club</td><td>All Year</td><td>DECA</td>"
    tech = ("<p>ACTIVITY</p><p>START DATE</p><p>ADVISOR</p><p>ART CLUB</p><p>All Year</p>"
            "<p>Robotics meets every Tuesday at 3:30pm in room 12.</p>")

    def pages(sartell):
        def get(url):
            if "srr" in url:
                raise RuntimeError("robots.txt disallows -> switch method to search_snippet")
            return 200, {"sartell": sartell, "apollo": apollo, "tech": tech}[url.split("//")[1].split(".")[0]]
        return get

    db = FakeDb(answers={"team_activities": rows})
    said = sunday(db, entries, get=pages(saved))
    check(said == ["[meets] 4 schools' club pages: Sartell High School 12 of 19 clubs with a time, Apollo High "
                   "School none, Tech High School none; Sauk Rapids-Rice High School won't read: its robots.txt keeps us out",
                   "[meets] Tech High School's page gives 1 meeting time the reader can't place on a club: teach "
                   "sources/scripts/meeting_times.py its layout",
                   "[meets] no meeting time changed"] and not db.writes(),
          f"an unchanged week: what it read, and none changed: {said}")
    check("kind=eq.club" in db.calls[0][1] and "meets" in db.calls[0][1], f"only clubs are read: {db.calls[0]}")

    # A changed copy: Bible Study moves, Letters of Love drops its time, Chess Club starts giving one, Prom is gone.
    changed = (saved.replace("meet every Friday at 8:00am", "meet every Thursday at 7:30am")
               .replace("The Letters of Love club meets on the 2nd Friday of every month to", "The Letters of Love club tries to")
               .replace("<h2>Prom</h2>", "<h2>Gone</h2>").replace("<strong>PROM</strong>", "<strong>GONE</strong>")
               .replace("Advisor -&nbsp;<strong>Open</strong>",
                        "Advisor -&nbsp;<strong>Open</strong><br />Meetings are held every Monday at 3pm."))
    rows[names.index("Prom")]["meets"] = [{"days": ["wed"], "time": "08:00"}]
    db = FakeDb(answers={"team_activities": rows})
    said = sunday(db, entries, get=pages(changed))
    by = {n: r["id"] for n, r in zip(names, rows)}
    check(said[1:5] + said[-1:] == ["[meets] Sartell High School's Bible Study: Thursdays · 7:30 AM, was Fridays · 8 AM",
                       "[meets] Sartell High School's Chess Club: Mondays · 3 PM, was no time",
                       "[meets] Sartell High School's Letters of Love: no time on its page now, was 2nd Friday of each "
                       "month: back to No events yet",
                       "[meets] Sartell High School's Prom: no longer on its page, was Wednesdays · 8 AM: back to No "
                       "events yet",
                       "[meets] changed 4 clubs' meeting times"]
          and said[0].startswith("[meets] 4 schools' club pages: Sartell High School 12 of 19 clubs"),
          f"a changed copy: each change a line, a dropped time or a club no longer named back to none: {said}")
    check(sorted((p, b) for _, p, b in db.writes()) == sorted([
        (f"team_activities?id=eq.{by['Bible Study']}", {"meets": [{"days": ["thu"], "time": "07:30"}]}),
        (f"team_activities?id=eq.{by['Chess Club']}", {"meets": [{"days": ["mon"], "time": "15:00"}]}),
        (f"team_activities?id=eq.{by['Letters of Love']}", {"meets": None}),
        (f"team_activities?id=eq.{by['Prom']}", {"meets": None})]),
          f"each change written to its club's row, nothing else: {db.writes()}")
    db = FakeDb(answers={"team_activities": rows})
    dry = sunday(db, entries, write=False, get=pages(changed))
    check(not db.writes() and dry[-1] == "[meets] would change 4 clubs' meeting times", f"a dry run writes nothing: {dry}")

    # Most of a school's clubs with a time gone from its page at once is the page, not the clubs: nothing changes.
    one_left = saved[:saved.index("<h2>", saved.index("BIBLE STUDY"))]
    db = FakeDb(answers={"team_activities": rows})
    said = sunday(db, entries[:1], get=pages(one_left.replace("every Friday at 8:00am", "every Thursday at 7:30am")))
    check(said[1:] == ["[meets] Sartell High School's page no longer names 12 of its 13 clubs with a time: none changed, "
                       "check the page by hand",
                       "[meets] no meeting time changed"] and not db.writes(),
          f"most clubs with a time gone at once changes nothing, Bible Study's move included: {said}")

    # A page that won't read, or names none of the school's clubs, changes nothing: its stored times stay.
    db = FakeDb(answers={"team_activities": rows})
    said = sunday(db, entries[:1], get=pages("<p>Our new website is coming soon.</p>"))
    check(said == ["[meets] 1 school's club page: Sartell High School none",
                   "[meets] Sartell High School's page names none of its 19 clubs: their times are kept",
                   "[meets] no meeting time changed"] and not db.writes(), f"a page with no club on it drops nothing: {said}")
    db = FakeDb(answers={"team_activities": lambda *a: 1 / 0})
    try:
        sunday(db, entries, get=pages(saved))
        check(False, "a failed read of the stored times stops the step")
    except ZeroDivisionError:
        check(True, "")

    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    with open(sys.argv[1], encoding="utf-8") as f:
        print(json.dumps({n: r for n, r in page_rules(f.read(), sys.argv[2:]).items() if r}, indent=1))
