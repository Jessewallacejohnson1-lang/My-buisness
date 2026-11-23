#!/usr/bin/env python3
"""
signups.py: an Event you can't sign up for any more leaves the Town feed (BP app watch-every-place 49; Jesse,
2026-10-17: "if your not able ot signup or go dont recommend it").

The writer keeps an Event out only as it is first listed, and a calendar's feed never says "Registration is filled": the
Event's own page does. `keep`, a step of `morning.py finish`, reads the own page of every found Event showing in the Town feed, each
page once, through the registry's polite fetch, never a paid read. A page that says its sign-ups are full, closed or
sold out, or that they closed on a day now past, marks its Events closed (club_events.signups_closed_by = 'page'), and
a page read well that no longer says so opens the ones it closed. The Town feed leaves a closed Event out, except for
someone Going to it or who Hearted it. The writer marks the ones its own items say (write_judged.mark_signups:
'listing', and 'catalog' for the City's catalog); a page never opens those.

An own page is one Event's (or one series'): its link is no page the registry watches, no site's front page, no link
two titles share, and not a social page, a game's, or a calendar built by script (SKIP). Never a guess: a line with an
"if", "until" or "early", one about another thing (a waitlist, a tour, parking), or a page that doesn't name the Event
says nothing.

  python3 sources/scripts/signups.py look            every own page read, what it would do; nothing written
  python3 sources/scripts/signups.py --selftest
"""

import argparse, json, re, sys, urllib.parse
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run  # noqa: E402
from event_parts import MONTHS, SOCIAL, polite  # noqa: E402
from write_judged import words  # noqa: E402

# Pages built by script, or a game's: nothing about sign-ups in what the polite fetch reads.
SKIP = re.compile(r"(gobound\.com|mshsl\.org|churchcenter\.com)/|/public/events/|/api/", re.I)
LINE = 160  # a longer line is prose, not a notice
WHAT = r"(?:online\s+)?(?:pre-?)?(?:registrations?|sign[- ]?ups?|enroll?ment|ticket sales)"
# The notice ends at its state word, a waitlist aside: "This program is filled with music" is none.
CLOSED = re.compile(
    rf"(?:\b{WHAT}(?:\s+for this \w+)?\s*(?:(?:is|are|has|have)\s+(?:now\s+|been\s+|already\s+)*(?:filled|full|closed|ended|over|no longer (?:open|available))"
    r"|[:–-]\s*(?:filled|full|closed))"
    r"|\b(?:this|the) (?:event|class|workshop|retreat|session|program|course|dinner|trip|camp)\s+(?:is|has)\s+(?:now\s+|been\s+|already\s+)*(?:full|filled|sold out)"
    r"|^\W*(?:now\s+)?sold[- ]?out)\s*(?:[.!;,)–-].*|\band\b.*\bwait.*|$)", re.I)
# "Registration closes Tuesday, November 24": a month and day, never "closes when full".
DEADLINE = re.compile(rf"\b{WHAT}\s+(?:closes?|closed|ends?|ended|deadline(?:\s+is|:)?)\s*(?:on|is|:)?\s*"
                      r"(?:(?:sun|mon|tues|wednes|thurs|fri|satur)day,?\s+)?"
                      r"(" + "|".join(MONTHS) + r")[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(20\d\d))?\b", re.I)
# Words that make a line no plain notice about the Event's own sign-ups.
UNSURE = re.compile(r"\b(if|when|once|until|unless|before|after|early|late|bird|discount|price|rate|guaranteed?|t-?shirts?|last year|"
                    r"previous|parking|hotel|vendors?|volunteers?|sponsors?|booths?|lodging|overnight|childcare|vip)\b", re.I)
# Nobody is turned away: whoever comes can still go.
WALK_IN = re.compile(r"\b(walk-?ins?|drop-?ins?|at the door)\b|\b(day[- ]of|race[- ]day|same[- ]day|on-?site) "
                     r"(registration|sign[- ]?ups?|tickets?|entr(y|ies))\b", re.I)
# A button someone can still press, so a notice on the page may be another date's, tier's or Event's.
OPEN = re.compile(r"\W*(register( now| here| online| today)?|sign up( now| here| online)?|add to cart|(buy|get) tickets?( now)?)\W*", re.I)
OTHERS = re.compile(r"\W*(related|upcoming|more|other|similar) (events?|programs?|classes|retreats)\b|you (may|might) also (like|enjoy)", re.I)


def says(text, title, day, today):
    """The line of an Event's own page saying nobody can sign up any more; "" when it names the Event and says no such
    thing; None when it doesn't name the Event (a script-built page, another page), or says it beside a sign-up someone can
    still press (another date's, another ticket's): that says nothing either way."""
    lines = [" ".join(ln.split()) for ln in (text or "").splitlines()]
    lines = lines[:next((i for i, ln in enumerate(lines) if OTHERS.match(ln)), None)]  # its own part of the page
    want = words(title)
    if not want or sum(bool(want & words(ln)) for ln in lines) == 0 \
            or len(want & set().union(*(words(ln) for ln in lines))) < min(2, len(want)):
        return None
    if any(WALK_IN.search(ln) for ln in lines):
        return ""
    live = any(OPEN.fullmatch(ln) for ln in lines)
    for ln in lines:
        if not ln or len(ln) > LINE or UNSURE.search(ln):
            continue
        if CLOSED.search(ln):
            return None if live else ln
        d = DEADLINE.search(ln)
        if d:
            year = int(d[3]) if d[3] else day.year
            try:
                last = date(year, MONTHS.index(d[1].lower()[:3]) + 1, int(d[2]))
                if not d[3] and last > day:  # "closes December 28" for an Event in January
                    last = last.replace(year=year - 1)
            except ValueError:
                continue
            if last < today:
                return None if live else ln
    return ""


def one_name(rows):
    """One Event or one series: each title's words all inside the longest's ("Lenten Sacred Pause" and its "• In Person")."""
    said = [words(r["title"]) for r in rows]
    return all(w and w <= max(said, key=len) for w in said)


def own_pages(rows, watched=()):
    """{link: its Events}, for the links that are one Event's own page."""
    by = {}
    for r in rows:
        by.setdefault((r.get("source_url") or "").strip(), []).append(r)
    bare = {w.rstrip("/") for w in watched}
    return {u: rs for u, rs in by.items()
            if u.startswith("http") and not SOCIAL.search(u) and not SKIP.search(u) and u.rstrip("/") not in bare
            and (urllib.parse.urlsplit(u).path.strip("/") or urllib.parse.urlsplit(u).query)
            and one_name(rs)}


def candidates(db, today):
    """Every upcoming found Event in the Town feed (its show-from day is here), or closed by its page; games aside. One
    not showing yet is read the morning it starts to: the City's pages are 20 seconds apart."""
    return db.rest("GET", "club_events?select=id,title,event_date,source_url,source_name,signups_closed_by"
                          "&status=eq.approved&kind=eq.event&cancelled_at=is.null&sport=is.null&club_id=is.null"
                          f"&submitted_by=is.null&event_date=gte.{today}&or=(shows_from.lte.{today},signups_closed_by.eq.page)"
                          "&order=event_date,id&limit=1000") or []


def line(word, rows, why, url):
    days = ", ".join(f"{date.fromisoformat(str(r['event_date'])[:10]):%b} {int(str(r['event_date'])[8:10])}" for r in rows)
    return f"- {word}: {rows[0]['title']}, {days}" + (f': "{why}"' if why else "") + f" ({url})"


def keep(run_, dry_run=False, read=polite):
    """Anything that breaks is one line, never a lost report."""
    try:
        return kept_lines(run_, dry_run, read)
    except Exception as e:
        return [f"[morning] sign-ups failed: {' '.join(str(e).split())[:200]}"]


def kept_lines(run_, dry_run, read):
    """The report's lines. Each page is read and its Events marked in one go, kept as it goes, so a finish run again
    reads only the pages left."""
    part = run_.part(f"signups{'-dry-run' if dry_run else ''}.json", {"done": [], "lines": [], "failed": 0})
    if part.saved.get("over"):
        return part.saved["lines"]
    db, today = run_.db, run_.today
    rows = candidates(db, today)
    watched = [s["url"] for s in db.rest("GET", "sources?select=url&status=eq.active") or []]
    pages = own_pages(rows, watched)
    for url, events in pages.items():
        if url in part.saved["done"]:
            continue
        if run.late(run_.stop):
            part.save()
            return [f"[morning] run again: {len(part.saved['done'])} of {len(pages)} sign-up pages read"]
        try:
            text = read(url)
        except Exception as e:  # a page that can't be read says nothing, and the rest are still read
            part.saved["failed"] += 1
            print(f"[sign-ups] {url}: {' '.join(str(e).split())[:120]}")
            text = None
        shut, opened, why = [], [], ""
        for r in events if text else ():
            said = says(text, r["title"], date.fromisoformat(str(r["event_date"])[:10]), today)
            if said and not r.get("signups_closed_by"):
                shut.append(r)
                why = said
            elif said == "" and r.get("signups_closed_by") == "page":
                opened.append(r)
        for rs, to in ((shut, "page"), (opened, None)):
            if rs and not dry_run:
                was = "is.null" if to else "eq.page"
                db.rest("PATCH", f"club_events?id=in.({','.join(r['id'] for r in rs)})&signups_closed_by={was}",
                        {"signups_closed_by": to}, prefer="return=minimal")
        part.saved["lines"] += ([line("Sign-ups closed, out of the Town feed", shut, why, url)] if shut else []) \
            + ([line("Sign-ups open again, back in the Town feed", opened, "", url)] if opened else [])
        part.saved["done"].append(url)
        part.save()
    # A page closed them, and no page of their own is left to read (the registry watches it now): open, not shut for good.
    read_here = {r["id"] for rs in pages.values() for r in rs}
    if lost := [r for r in rows if r.get("signups_closed_by") == "page" and r["id"] not in read_here]:
        if not dry_run:
            db.rest("PATCH", f"club_events?id=in.({','.join(r['id'] for r in lost)})&signups_closed_by=eq.page",
                    {"signups_closed_by": None}, prefer="return=minimal")
        part.saved["lines"] += [line("Its page is no longer its own, back in the Town feed", [r], "", r["source_url"]) for r in lost]
    failed = part.saved["failed"]
    part.saved["lines"].insert(0, f"- Sign-up pages: {len(pages) - failed} of {len(pages)} read")
    part.saved["over"] = True
    part.save()
    return part.saved["lines"]


def selftest():
    import tempfile
    from morning_run import Run, FakeDb
    ok = lambda cond, why: checks.append((bool(cond), why))
    checks, today, dec4 = [], date(2026, 11, 23), date(2026, 12, 4)
    said = lambda *lines, title="Advent Sacred Pause", day=dec4, now=today: says("\n".join((title, *lines)), title, day, now)
    ok(said("Registration is filled.") == "Registration is filled.", "the monastery's page: full")
    for ln in ("Registration is now closed", "Registration: Closed", "Sign-ups are full", "Sold Out", "SOLD OUT!", "This class is full.",
               "Registration has ended.", "Online registration is closed.", "Sign-ups are full; join the waitlist",
               "Registration is full and there is a waitlist"):
        ok(said(ln), f"closed: {ln}")
    for ln in ("Registration is open.", "Registration closes when full.", "Registration will close once the class is full",
               "Until registration is full", "Early bird registration is closed", "Vendor registration is closed",
               "Register early, last year this event sold out fast", "Registration Fee Quantity *", "The museum is closed Mondays",
               "We fully respect if you want to refuse cookies", "Full moon hike", "Parking registration is closed", "This program is filled with music",
               "This event is full of family fun", "Registration Full Day: $45", "Registration over the phone: 320-555-0100",
               "Registration deadline Nov 20 to guarantee a T-shirt", "VIP: sold out"):
        ok(said(ln) == "", f"says nothing: {ln}")
    ok(said("Registration closes Tuesday, November 24.") == "", "its last day is still open")
    ok(said("Registration closes Tuesday, November 24.", now=date(2026, 11, 24)) == "", "open on the day itself")
    ok(said("Registration closes Tuesday, November 24.", now=date(2026, 11, 25)), "closed the day after")
    ok(said("Registration closes December 28", day=date(2027, 1, 8), now=date(2026, 12, 29)), "a January Event's December day")
    ok(said("Registration closes December 28", day=date(2027, 1, 8)) == "", "and not a year early")
    ok(said("Registration closes Nov 20", "Race day registration opens at 8") == "", "walk-ins still go")
    ok(said("Online ticket sales have ended.", "Tickets at the door $10.") == "", "tickets at the door")
    ok(said("Registration is closed.", "A day of prayer") == "Registration is closed.", "a day of prayer is no day-of sign-up")
    ok(said("December 2", "Registration is filled.", "December 9", "Register here") is None, "another date is still open")
    ok(said("Sold out", "General admission", "Add to cart") is None, "another ticket is still on sale")
    ok(said("Come along", "Related Events", "Sold Out") == "", "another Event's notice")
    ok(said("Registration is filled.", "Registration closes Tuesday, December 1.") == "Registration is filled.", "full wins over a day to come")
    ok(says("Menu\nRegistration is closed", "Advent Sacred Pause", dec4, today) is None, "a page that doesn't name the Event says nothing")
    ok(says("", "Advent Sacred Pause", dec4, today) is None, "an empty page says nothing")

    ev = lambda i, title, url, closed=None, day="2026-12-04": {"id": i, "title": title, "event_date": day, "source_url": url,
                                                              "source_name": "H", "signups_closed_by": closed}
    rows = [ev("a", "Advent Sacred Pause", "https://h/event/pause/", day="2026-12-02"),
            ev("b", "Advent Sacred Pause • Online", "https://h/event/pause/"),
            ev("c", "Praying With Icons", "https://h/event/icons/", "page"),
            ev("d", "Paint and Sip", "https://h/event/paint/", "catalog"),
            ev("e", "Bingo", "https://h/events/"), ev("f", "Trivia", "https://h/events/"),
            ev("g", "Gala", "https://h.org/"), ev("h", "Dance", "https://www.facebook.com/events/1/"),
            ev("i", "Game", "https://www.gobound.com/direct/x"), ev("j", "Concert", "https://h/calendar"),
            ev("k", "Broken Page Night", "https://h/event/broken/", "page"), ev("l", "Winter Retreat", "https://h/event/shell/", "page"),
            ev("m", "Concert", "https://h/calendar", "page")]
    ok(set(own_pages(rows, ["https://h/calendar/"])) == {f"https://h/event/{p}/" for p in ("pause", "icons", "paint", "broken", "shell")},
       "own pages: not a list two titles share, a front page, a social page, a game's or a watched page")
    text = {"https://h/event/pause/": "Advent Sacred Pause\nRegistration is filled.", "https://h/event/icons/": "Praying With Icons\nRegister here",
            "https://h/event/paint/": "Paint and Sip\nRegister", "https://h/event/shell/": "Please enable JavaScript"}
    reads = []

    def read(url):
        reads.append(url)
        return text[url]  # KeyError: the broken page
    with tempfile.TemporaryDirectory() as tmp:
        db = FakeDb(answers={"club_events?select": rows, "sources?": [{"url": "https://h/calendar/"}]})
        r = Run(Path(tmp), today, db)
        dry = keep(r, True, read)
        ok(not db.writes() and len(dry) == 4, "a dry run reads and writes nothing")
        lines = keep(r, False, read)
        ok([(c[1], c[2]) for c in db.writes()] ==
           [("club_events?id=in.(a,b)&signups_closed_by=is.null", {"signups_closed_by": "page"}),
            ("club_events?id=in.(c)&signups_closed_by=eq.page", {"signups_closed_by": None}),
            ("club_events?id=in.(m)&signups_closed_by=eq.page", {"signups_closed_by": None})],
           "a full page closes its Events; a page open again opens only what a page closed; one that can't be read changes nothing")
        ok(lines == ["- Sign-up pages: 4 of 5 read",
                     '- Sign-ups closed, out of the Town feed: Advent Sacred Pause, Dec 2, Dec 4: "Registration is filled." (https://h/event/pause/)',
                     "- Sign-ups open again, back in the Town feed: Praying With Icons, Dec 4 (https://h/event/icons/)",
                     "- Its page is no longer its own, back in the Town feed: Concert, Dec 4 (https://h/calendar)"], "the report names each")
        n = len(db.calls), len(reads)
        ok(keep(r, False, read) == lines and (len(db.calls), len(reads)) == n, "a finish run again reads and writes nothing more")
        late = Run(Path(tmp) / "late", today, db, minutes=1)
        late.folder.mkdir()
        late.stop = 0.0
        ok(keep(late, False, read)[0].startswith("[morning] run again"), "a part out of time carries on in the next")
        refused = FakeDb(answers={"club_events?select": lambda *a: 1 / 0})
        ok(keep(Run(Path(tmp) / "x", today, refused))[0].startswith("[morning] sign-ups failed"), "a step that breaks is a line")
    failed = [why for good, why in checks if not good]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    return not failed


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("step", nargs="?", choices=["look"])
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if selftest() else 1)
    if a.step == "look":
        import tempfile
        from morning_run import Run
        from read_events import LOCAL
        with tempfile.TemporaryDirectory() as tmp:
            print("\n".join(keep(Run(Path(tmp), datetime.now(LOCAL).date(), run.Supabase(), minutes=None), True)))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
