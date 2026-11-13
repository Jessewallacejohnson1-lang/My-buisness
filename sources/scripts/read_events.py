#!/usr/bin/env python3
"""
read_events.py: the registry's sources that need no model, read exactly and handed to
write_judged.py as judged items (ADR-013, ADR-021; BP app docs/plans/watch-every-place,
tickets 10 and 11).

Calendar feeds, and sites whose pages are built by JavaScript (a plain fetch of the page
reads almost nothing), are read from the data itself by a small reader per kind of site:
exact dates, no model. A source is read when its entry is active and it names a `reader:`
(an iCal feed needs none):

  ical                an iCal feed (the City's)
  pathify             a Pathify campus portal's public events JSON (CSB/SJU's my.csbsju.edu);
                      the calendars to read are in the source's own url
  cars511             Minnesota 511's road reports within `miles` of `around` (its map's feed)
  finalsite-calendar  a Finalsite calendar page, this month and next (?cal_date=). Its iCal
                      export sits under the robots-disallowed /fs/, so never that (Kennedy); with
                      `own_calendar_only`, only the school's own calendar, not the district's beside it (Tech)
  csbsju-music        the CSB/SJU music department's season page, a page made by hand: each concert on
                      campus, on its ensemble's row
  finalsite-news      a Finalsite news page: titles only, dated the day first seen; the story
                      pages are robots-disallowed (Kennedy)
  civicplus-hcms      CivicPlus's content service: news, notices and events, read with the
                      read-only token the county's own page gives every visitor, taken fresh
                      each run and never stored (Stearns County; Jesse, 2026-10-14)
  rec1                a Rec1 registration catalog's programs (the City's rec sign-ups), read from
                      the JSON its own page loads; each program once, at its next date
  mshsl               the Minnesota State High School League's schedule data for one school
                      (`league_id`, `team` as the league names it): varsity games, meets and
                      tournaments in the next four weeks at venues within 20 miles (NEARBY)
  gobound             a school's Bound activities calendar (its iCal export): every event of every
                      activity; plays, concerts and clubs within 20 miles and games at the levels in
                      `game_levels` (Kennedy's middle school) for everyone, the rest for followers only;
                      varsity games within 20 miles stay the league's
  diocese             the diocesan paper's iCal feed (The Central Minnesota Catholic): Events within 20 miles,
                      in person, each once, hosted by who its description names

Every request goes through run.py's fetch, so robots rules and Crawl-delay are obeyed on
every run, not only on the day a reader was written (ADR-014). A source that fails is named
in the summary and the others carry on.

What the readers keep (Jesse, 2026-10-14): events in the next 90 days, and News. Each is one
sure mention at its source's trust, sized everyday (it shows two weeks ahead), with an
interest only where the calendar says what it is: games Watch sports, the library
Library & books, the Monastery Faith. CSB/SJU: the public calendars named in the registry,
home games only (no away games, rec-center classes or halftime shows), and a repeating
event once, at its next date, with its calendar's description but a game's (only its title and
links; Jesse, 2026-10-19). 511: road work as News. Stearns County: news and notices from
the last 7 days, and events only in the town (ADR-019). Every St. Joseph source's events
are kept wherever they happen (the spec's Area rule, amending ADR-021's in-town-only rule).
High school games (Jesse, 2026-10-14): played within 20 miles, whichever schools play; the same
game from both teams is one Event, a tournament day one Event; playoff games are notable; a
playoff game with no opponent yet waits. On a morning every school was read, a game gone from
the schedules is marked cancelled by the writer (Jesse, 2026-10-15); a school whose schedule came
back with nothing on it is left out of that, so its games stay as they are (Jesse, 2026-10-27).
Games arrive complete (BP app smooth-mornings 06): every game the league, Bound and the CSB/SJU
Athletics calendars bring has a title of 40 characters or fewer (game_title, the title-and-place
rules) and an About made of its schedule's facts (game_about), so no game reaches the morning's
titles or describe work.

Dry-run by default (ADR-009): prints what each reader found. `--items FILE` writes the
judged items, one per line, for the writer, which merges them with what is already listed
and writes the SQL; it sets each event's show-from day too:

  python3 sources/scripts/read_events.py --items items.jsonl [--include-proposed] [--reader mshsl]
  python3 sources/scripts/write_judged.py items.jsonl --existing existing.json --sql out.sql
  python3 sources/scripts/read_events.py --selftest
"""

import argparse, html, json, math, re, sys, urllib.error
from collections import Counter
from time import sleep
from urllib.parse import quote, urlencode, urljoin, urlparse
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from run import fetch, read_page, to_text, deadline, late, part_state, resume_part
from morning_run import Part
from towns import TOWNS

DAYS_AHEAD = 90
LOCAL = ZoneInfo("America/Chicago")
# A day a place is shut or a school day runs short. It waits until a week before (BP app town-feed 50). "Holiday" alone
# isn't one: "Holiday Door Hangers" and "Holiday Sales" are News from the day they're read.
CLOSING = re.compile(r"\b(closed(?! caption)|closure|no school|no classes|late start|early (release|dismissal))\b", re.I)
CLOSING_DAYS = 7
# Something to know rather than go to is News, even with a date (ADR-021).
NEWS = re.compile(CLOSING.pattern + r"|\bholiday\b", re.I)
SAMPLES = Path(__file__).resolve().parent / "samples"


def day_line(day, last=None):
    """A closing's day on its card, which shows no date of its own: "Thursday, Nov 26", or "Nov 25 to Nov 28"."""
    return f"{day:%b} {day.day} to {last:%b} {last.day}" if last and last > day else f"{day:%A, %b} {day.day}"


def judged(entry, src, **kw):
    """One item in write_judged.py's contract. No model read it: it is sure, sized everyday,
    and as trusted as the registry says its source is. A calendar's closing says when it goes up, and its day when
    the calendar has no words for it (BP app town-feed 50); a road report is News as soon as it's known."""
    if kw.get("kind") == "news" and kw.get("start") and kw.get("category") != "road" and CLOSING.search(kw["title"]):
        day = date.fromisoformat(kw["start"][:10])
        kw["shows_from"] = (day - timedelta(CLOSING_DAYS)).isoformat()
        last = date.fromisoformat(kw["end"][:10]) if kw.get("end") else None
        kw["blurb"] = kw.get("blurb") or day_line(day, last)
    return {"kind": "event", "all_day": False, "place": "", "town": None, "area": "announced",
            "source_name": entry["_name"], "trust": src.get("trust") or "official", "sure": True,
            "size": "everyday", "interest": None, **kw}


def plain(markup):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", markup or ""))).strip()


# Where one sentence ends and the next begins: not after "St.", "Nov.", "a.m." or an initial, only before a capital.
SENTENCE_END = re.compile(r"(?<=[.!?])(?<!\b[A-Z]\.)(?<!\b(?:St|Mr|Dr|Ms|Mt)\.)(?<![ap]\.m\.)\s+(?=[A-Z\"“])")


def news_line(text, limit=75):
    """A News second line from a reader the judge never sees, held to judge.md's 75 characters (BP app
    inside-cards 12): the whole sentences that fit, else none. Never cut mid-sentence."""
    line = ""
    for sentence in SENTENCE_END.split(text or ""):
        longer = f"{line} {sentence}".strip()
        if len(longer) > limit:
            break
        line = longer
    return line or None


def said(text):
    """The text, or None when it says nothing but a link: the City's feed gives each event's
    page as its description, and an Event page's About is never a bare link (Jesse, 2026-10-19)."""
    return text if text and re.sub(r"https?://\S+", "", text).strip() else None


def utc_local(stamp):
    return datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone(LOCAL)


def ahead(day, today):
    return today <= day <= today + timedelta(days=DAYS_AHEAD)


# A game's title and About (BP app smooth-mornings 06) ------------------------------------

TITLE_MAX = 40  # characters: past it the Town's Event of the day poster takes three lines (write_judged's)
# A school's kind after its name, which the level already says: "Willmar MS", "North Junior High".
SCHOOL_KIND = re.compile(r"\s+(?:MS|Middle School|Junior High|Jr\.? High|High School|School)$")
LEVEL_SHORT = {"Middle school": "MS"}  # "C-squad" stays whole: the merge rule tells it from varsity by it


def game_title(teams, sport, ours=None, level=""):
    """A game's title by the title-and-place rules, "<home> <sport> vs <away>", then " · <level>"
    below varsity, in 40 characters or fewer so the poster fits without the morning's model. Too
    long, it gives up a little at a time and never cuts a word: a school's kind ("Willmar MS" is
    "Willmar"); our own team, which the host line names ("Boys Basketball vs Willmar · C-squad");
    a co-op's or district's later towns ("Sartell-Sauk Rapids" is "Sartell"); the level's short
    form ("8th", "MS"); the boys or girls; then the level. The About keeps all of it. `ours`:
    which of the two teams is the host's own, when known."""
    names, lv = list(teams), level

    def title():
        head = f"{names[0]} {sport} vs {names[1]}" if all(names) else f"{sport} vs {''.join(names)}"
        return head + (f" · {lv}" if lv else "")
    if len(title()) > TITLE_MAX:
        names = [SCHOOL_KIND.sub("", n) for n in names]
    if len(title()) > TITLE_MAX and ours is not None:
        names[ours] = ""
    if len(title()) > TITLE_MAX:
        names = [n.split("-")[0] for n in names]
    if len(title()) > TITLE_MAX:
        lv = LEVEL_SHORT.get(lv) or re.sub(r"^(\d+th) grade$", r"\1", lv, flags=re.I)
    if len(title()) > TITLE_MAX:
        # ponytail: the boys or girls go only when nothing else fits (48 of Bound's 791 games on
        # 2026-10-29, a C-squad or JV with a long opponent); two names longer still stay long.
        sport = re.sub(r"^(Boys|Girls) ", "", sport)
    if len(title()) > TITLE_MAX:
        lv = ""
    return title()


def plays_for(team, school):
    """A team is this registry school's, its co-op's included: "St. Cloud Apollo" and Apollo High
    School, "Sartell-Sauk Rapids" and Sartell High School."""
    name, team = re.sub(r" (Area )?(High|Community) School$", "", school).lower(), short_team(team).lower()
    return name == team or name in team.split("-")


def game_about(level, sport, home, away, hosted=True, occasion=None):
    """A game's About from its schedule alone: its level and sport, who hosts whom (or who plays
    whom, on ground that is neither's), and the night or playoff round the schedule names. Never
    where: the page's place line says that (inside-cards 14, Jesse 2026-11-08). Nothing here to
    research, so the describe layout leaves games out."""
    what = f"{level} {sport.lower()}".strip()
    who = f"{home} hosts {away}" if hosted else f"{home} and {away} play"
    return f"{what[:1].upper()}{what[1:]}: {who}." + (f" {occasion}." if occasion else "")


# iCal ------------------------------------------------------------------------------------

def unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text)


def unescape(v):
    v = v.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\")
    v = html.unescape(re.sub(r"<[^>]+>", " ", v))
    return re.sub(r"[ \t]+", " ", v).strip(" -\n")


def parse_ics(text):
    """Each VEVENT as {NAME: (params, value)}."""
    out = []
    for block in unfold(text).split("BEGIN:VEVENT")[1:]:
        ev = {}
        for line in block.split("END:VEVENT")[0].splitlines():
            m = re.match(r"([A-Z\-]+)((?:;[^:]*)?):(.*)", line.strip("\r"))
            if m:
                ev[m.group(1)] = (m.group(2), m.group(3))
        out.append(ev)
    return out


def when(prop):
    """(local datetime or date, all_day) from a DTSTART/DTEND property."""
    params, v = prop
    v = v.strip()
    if "VALUE=DATE" in params or re.fullmatch(r"\d{8}", v):
        return date(int(v[:4]), int(v[4:6]), int(v[6:8])), True
    dt = datetime.strptime(v.rstrip("Z"), "%Y%m%dT%H%M%S")
    if v.endswith("Z"):
        return dt.replace(tzinfo=timezone.utc).astimezone(LOCAL), False
    tz = re.search(r"TZID=([^;:]+)", params)
    # A WordPress events plugin on a site left at UTC labels the town's own clock "UTC": Sal's feed
    # said 18:30 UTC for its 6:30 PM bingo (2026-10-20). A real UTC time ends in Z.
    # ponytail: every TZID=UTC feed reads as town time (the city's, the Monastery's and Rod & Gun's
    # say America/Chicago); one that truly means UTC would read 5 to 6 hours late, so give it a
    # registry flag if one shows up.
    zone = tz and tz.group(1) not in ("UTC", "GMT", "Etc/UTC") and ZoneInfo(tz.group(1))
    return dt.replace(tzinfo=zone or LOCAL), False


def clock(dt):
    """'6 PM' / '6:30 PM', the way clubs write start_time."""
    h = dt.strftime("%I").lstrip("0")
    return f"{h} {dt.strftime('%p')}" if dt.minute == 0 else f"{h}:{dt.strftime('%M %p')}"


def page_url(ev, feed_url):
    """A link a person can open. CivicPlus feeds (the City's) give each event a relative URL
    pointing back at the feed itself; the event's own page is Calendar.aspx?EID=<UID>."""
    url = urljoin(feed_url, unescape(ev["URL"][1])) if "URL" in ev else feed_url
    if "iCalendar.aspx" in url:
        host = urlparse(feed_url)
        return f"{host.scheme}://{host.netloc}/Calendar.aspx?EID={ev['UID'][1].strip()}"
    return url


def ical_items(text, entry, src, today):
    out = []
    for ev in parse_ics(text):
        if "DTSTART" not in ev or "UID" not in ev:
            continue
        start, all_day = when(ev["DTSTART"])
        if not ahead(start if all_day else start.date(), today):
            continue
        title = unescape(ev.get("SUMMARY", ("", ""))[1])
        end = when(ev["DTEND"])[0] if "DTEND" in ev else None
        if all_day:  # an all-day DTEND is the day after the last; a run over days keeps its last day
            last = end - timedelta(days=1) if end and not isinstance(end, datetime) else None
            end = last if last and last > start else None
        out.append(judged(entry, src, kind="news" if NEWS.search(title) else "event", title=title,
                          start=start.isoformat(), end=end and end.isoformat(), all_day=all_day,
                          # "St. Joseph MN 56374" alone is no place; the writer drops it.
                          place=unescape(ev.get("LOCATION", ("", ""))[1]),
                          blurb=said(unescape(ev.get("DESCRIPTION", ("", ""))[1])),
                          source_url=page_url(ev, src["url"]), source_uid=ev["UID"][1].strip()))
    return out


def read_ical(src, entry, today):
    return ical_items(fetch(src["url"])[1], entry, src, today)


# CSB/SJU: Pathify ------------------------------------------------------------------------

# Each campus calendar names who is hosting, because the card shows it as the host.
CAMPUS_HOSTS = {"Campus Events": "CSB SJU Campus Events", "CSB Athletics": "CSB Athletics",
                "SJU Athletics": "SJU Athletics", "Library": "CSB SJU Libraries",
                "St. Benedict's Monastery": "Saint Benedict's Monastery",
                "School of Theology": "Saint John's School of Theology"}
# A calendar whose events are at home gives only the street address; the card names the place.
CAMPUS_HOMES = {"St. Benedict's Monastery": ("104 Chapel Lane", "Saint Benedict's Monastery")}
# A campus listing that gives only a street address, and the place at it (title-and-place, The place line).
CAMPUS_ADDRESSES = {"14215 Fruit Farm Road": "Episcopal House of Prayer, Collegeville",
                    # Saint John's listing names only its rink; Saint Ben's writes the town first.
                    "Herb Brooks National Hockey Center": "St. Cloud, Minn., Herb Brooks National Hockey Center"}
CAMPUS_INTERESTS = {"CSB Athletics": "watch_sports", "SJU Athletics": "watch_sports",
                    "Library": "books", "St. Benedict's Monastery": "faith"}
# Campus Events also lists what only students go to: career workshops and fairs (Jesse, 2026-10-14).
STUDENT_ONLY = re.compile(r"admission event|networking workshop|charting conversations|employer tabling|"
                          r"johnnie development institute|\bJDI\b|exploration fair|study session", re.I)
# Hockey's home rinks are in St. Cloud (BP app game-card 09; Jesse, 2026-11-05, yes to counting those two as home).
HOME_GAME = re.compile(r"\b(st\.?|saint) joseph\b|collegeville|herb brooks national hockey center|ritsche arena", re.I)
# ponytail: SJU's own building names, for a place with no town in it. A building not listed
# reads as St. Joseph; add it here when one shows up wrong.
SJU = re.compile(r"collegeville|\bsju\b|saint john'?s|st\.? john'?s|alcuin|learning commons|\bquad\b|sexton|"
                 r"clemens stadium|haws field|palaestra|guild hall|luke hall|pengl|simons|abbey", re.I)


def campus_town(place):
    m = re.search(r"([A-Z][A-Za-z.' ]+?),\s*(?:MN|Minn\.)", place)
    town = m.group(1).strip() if m else "Collegeville" if SJU.search(place) else "St. Joseph"
    return "St. Joseph" if re.fullmatch(r"(st\.?|saint) joseph", town, re.I) else town


# A playoff round in an opponent's place: "vs MIAC Quarterfinals", "vs TBD: MIAC Quarterfinals".
ROUND = re.compile(r"^(tbd|tba)$|\b(quarterfinals?|semifinals?|finals?|playoffs?)\b", re.I)


def campus_game(title, place, host):
    """An Athletics calendar's game as the writer reads it ("SJU Football vs Concordia: Homecoming",
    tidy_title and game_of, so the card reads the same), and its About from the schedule's facts
    (smooth-mornings 06): (title, About), or (title, None) for a meet."""
    from write_judged import tidy_title, tidy_place, game_of  # the writer imports this file
    g = game_of({"source_name": host}, tidy_title(title, host, event=False))  # its night, which a long title gives up
    if not g:
        return title, None
    (home, away), night, place = g["teams"], g["occasion"], tidy_place(place)
    if ROUND.search(away):  # its opponent still to come
        away, night = f"the {night if ROUND.match(away) and night else away}", None
    return tidy_title(title, host), game_about("", g["sport"], home, away, occasion=night)


def campus_blurb(markup, cal):
    """The calendar's own description as plain text, a line to each paragraph, for the Event
    page's About (Jesse, 2026-10-19). None for an Athletics calendar: its description is only the
    title and the links to its stream and tickets (a game's About is its facts, campus_game)."""
    if "Athletics" in cal:
        return None
    paras = (plain(p) for p in re.split(r"</p>|<br\s*/?>", markup or "", flags=re.I))
    return "\n".join(p for p in paras if p) or None


def pathify_url(url, today):
    after, before = (datetime.combine(d, time(), LOCAL).astimezone(timezone.utc)
                     for d in (today, today + timedelta(days=DAYS_AHEAD)))
    fields = "".join(f"&field={f}" for f in ("id", "title", "start_date", "end_date", "all_day", "start_day",
                                             "calendar__name", "recurrence_rule", "location", "description",
                                             "ticket_url"))
    return (f"{url}{'&' if '?' in url else '?'}in_range_after={after:%Y-%m-%dT%H:%M:%SZ}"
            f"&in_range_before={before:%Y-%m-%dT%H:%M:%SZ}{fields}&paginate=false&published=true")


TITLE_CLOCK = re.compile(r"(\d{1,2})(?::(\d\d))?\s*([ap])\.?\s?m\b\.?", re.I)


def title_clock(title, start, end):
    """A title that opens with its own time beats the calendar's: "9 p.m. Student Mass" was
    entered at 9 AM (2026-10-20), and Campus Ministry holds it at 9 PM."""
    m = TITLE_CLOCK.match(title)
    if not m:
        return start, end
    shift = start.replace(hour=int(m[1]) % 12 + (12 if m[3].lower() == "p" else 0), minute=int(m[2] or 0)) - start
    return start + shift, end and end + shift


SHOW_SITTING = timedelta(hours=4)  # open this long a day, on two or more days a week: a show (an exhibit), not a performance


def show_runs(rows):
    """The repeating listings that are one show open for days (Reflection: Selected Works, Mon to Sat 10 to 9,
    Oct 28 to Dec 14): by title, the last day it is open. The calendar lists each day under its own id, so
    without this each day was a new Event and the morning picked it again (BP app town-feed 62). A play on
    three nights sits under four hours and stays a card a night."""
    last = {}
    for r in rows:
        rule, start, end = r.get("recurrence_rule") or "", r.get("start_date"), r.get("end_date")
        days = re.search(r"BYDAY=([A-Z,]+)", rule)
        if r.get("all_day") or not (days and "," in days[1] and start and end):
            continue
        if utc_local(end) - utc_local(start) >= SHOW_SITTING:
            day = utc_local(start).date().isoformat()
            last[r["title"].strip()] = max(last.get(r["title"].strip(), day), day)
    return last


def pathify_items(rows, entry, src, today):
    site = urlparse(src["url"])
    out, series, shows = [], set(), show_runs(rows)
    for r in sorted(rows, key=lambda r: r["start_date"]):
        cal = (r.get("calendar") or {}).get("name") or ""
        title, place = r["title"].strip(), re.sub(r",\s*USA$", "", (r.get("location") or "").strip())
        address, home_name = CAMPUS_HOMES.get(cal, (None, None))
        if address and place.startswith(address):
            place = home_name
        place = next((name for a, name in CAMPUS_ADDRESSES.items() if place.startswith(a)), place)
        if "Athletics" in cal and ("group exercise" in place.lower() or "dance team" in title.lower()
                                   or not HOME_GAME.search(place)):
            continue  # a rec-center class, a halftime show or an away game
        if STUDENT_ONLY.search(title):
            continue  # a visit day, a career workshop: for students, not neighbours
        if r.get("recurrence_rule"):
            if (cal, title) in series:
                continue  # a repeating event shows once, at its next date
            series.add((cal, title))
        if r.get("all_day"):
            start, last = r.get("start_day") or r["start_date"][:10], (r.get("end_date") or "")[:10]
            end = last if last > start else None  # Festival of Cultures runs Nov 9 to 14
        else:
            at, until = title_clock(title, utc_local(r["start_date"]), r.get("end_date") and utc_local(r["end_date"]))
            start, end = at.isoformat(), until and until.isoformat()
            if title in shows and r.get("recurrence_rule") and shows[title] > start[:10]:
                end = shows[title]  # open to its last day: one Event the whole run
        if not ahead(date.fromisoformat(start[:10]), today):
            continue
        news = bool(NEWS.search(title))
        about = campus_blurb(r.get("description"), cal)
        if "Athletics" in cal:
            title, about = campus_game(title, place, CAMPUS_HOSTS.get(cal, f"CSB SJU {cal}"))
        out.append(judged(entry, src, kind="news" if news else "event", category="campus" if news else None,
                          title=title, start=start, end=end, all_day=bool(r.get("all_day")),
                          place=place, town=campus_town(place), area="campus",
                          blurb=about,
                          source_name=CAMPUS_HOSTS.get(cal, f"CSB SJU {cal}"), interest=CAMPUS_INTERESTS.get(cal),
                          # Its sign-up page when the calendar names one, so the Event page's link
                          # registers in one tap and the describe step reads its fee and dates (BP app
                          # event-details; Jesse, 2026-10-29); the id stays the calendar's.
                          source_url=(r.get("ticket_url") or "").strip()
                          or f"{site.scheme}://{site.netloc}/public/events/{r['id']}",
                          # A show keeps one id for its whole run, so each morning's read is the same Event.
                          source_uid=f"run:{title}" if title in shows and r.get("recurrence_rule") else str(r["id"])))
    return out


def read_pathify(src, entry, today):
    return pathify_items(json.loads(fetch(pathify_url(src["url"], today))[1]), entry, src, today)


# CSB/SJU music: the department's season page, made by hand, no feed (BP app nothing-scheduled 01) ---------------

MUSIC_DAY = re.compile(r"(Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day,\s+([A-Z][a-z]+)\s+(\d{1,2})\b")
MUSIC_CLOCK = re.compile(r"(\d{1,2})(?::(\d\d))?\s*(?:-\s*(\d{1,2})(?::(\d\d))?\s*)?([ap])\.?m\b", re.I)
# The campus a place line ends with; the Benedicta Arts Center is CSB's. A place with none is off campus and left out.
MUSIC_CAMPUS = {"SJU": ("saint-johns", "Collegeville"), "CSB": ("saint-benedict", "St. Joseph"),
                "BAC": ("saint-benedict", "St. Joseph")}
# The joint ensembles, as both colleges' activity rows name them (BP app school-activities 01).
MUSIC_ACTIVITIES = [(n, re.compile(r"\b" + n.replace("'", "['’]").replace("-", " ").replace(" ", r"[-\s]+") + r"\b", re.I))
                    for n in ("All-College Choir", "Chamber Choir", "Women's Choir", "Men's Chorus", "Brass Choir",
                              "Orchestra", "Wind Ensemble", "Jazz Ensemble", "Guitar Ensemble", "Vocal Performance Workshop")]


def music_day(m, today):
    """The page gives no year: the year, of last, this or next, whose date falls on the weekday it names."""
    month = datetime.strptime(m.group(2)[:3], "%b").month
    for year in (today.year - 1, today.year, today.year + 1):
        try:
            d = date(year, month, int(m.group(3)))
        except ValueError:
            continue
        if d.strftime("%A") == m.group(1) + "day":
            return d
    return None


def music_at(day, clock, end=False):
    h, mi = (clock.group(3), clock.group(4)) if end else (clock.group(1), clock.group(2))
    hour = int(h) % 12 + (12 if clock.group(5).lower() == "p" else 0)
    return datetime.combine(day, time(hour, int(mi or 0)), LOCAL).isoformat()


def music_items(page, url, entry, src, today):
    """Each performance on campus: a block's title, then lines of days (a time on the line or the next), each run
    of days closed by its place ("Gertken Organ Studio, SJU"). A bold line before the days names them instead (a
    tour's "Chamber Choir Home Concert"). It lands on its ensemble's row at the college whose campus it is at. The
    past events at the page's foot are never read."""
    out = []
    for block in re.split(r'<div class="wp-block-cover[" ]', page.split('id="past-events"')[0])[1:]:
        head = re.search(r"<p [^>]*has-large-font-size[^>]*>(.*?)</p>", block, re.S)
        when = head and re.search(r'<p class="has-text-align-center[^>]*>(.*?)</p>', block[head.end():], re.S)
        if not when:
            continue
        about = re.search(r"<details.*?</summary>\s*<p[^>]*>(.*?)</p>(.*?)</details>", block, re.S)
        # "All-College Choir" as the campus calendar writes it, so the two copies are one Event: the writer reads a
        # hyphen inside a word as no break ("Boo-tique").
        title, name, days = re.sub(r"(?<=[a-z])-(?=[A-Z])", " ", plain(head.group(1))), None, []
        for line in filter(None, (plain(x).strip(" •") for x in re.split(r"<br\s*/?>", when.group(1)))):
            day = MUSIC_DAY.match(line)
            if day:
                last = MUSIC_DAY.search(line, day.end())
                days.append([music_day(day, today), MUSIC_CLOCK.search(line), last and music_day(last, today)])
            elif MUSIC_CLOCK.fullmatch(line):
                for d in days:
                    d[1] = d[1] or MUSIC_CLOCK.fullmatch(line)
            elif days:
                place = re.fullmatch(r"(.+?),\s*(SJU|CSB|BAC)", line)
                for first, clock, last in days if place else ():
                    if not first or not ahead(first, today):
                        continue
                    team, town = MUSIC_CAMPUS[place.group(2)]
                    what = name or title
                    act = next((n for n, pattern in MUSIC_ACTIVITIES if pattern.search(what)), None)
                    out.append(judged(entry, src, title=what, start=music_at(first, clock) if clock else first.isoformat(),
                                      end=(music_at(first, clock, end=True) if clock and clock.group(3)
                                           else last.isoformat() if last else None),
                                      all_day=not clock, place=place.group(1), town=town, area="campus",
                                      interest="live_music", blurb=plain(about.group(1)) if about else None, source_url=url,
                                      **({"price": "Free"} if about and re.search(r"\bfree\b", plain(about.group(2)), re.I)
                                         else {}),
                                      **({"activity_team": team, "activity_name": act} if act else {})))
                days = []
            else:
                name = line
    return out


def read_csbsju_music(src, entry, today):
    return music_items(fetch(src["url"])[1], src["url"], entry, src, today)


# Minnesota 511 ---------------------------------------------------------------------------

# 511mn.org moved to a new map on 2026-10-21 and its old GraphQL address now answers with the
# map's page. The new map loads every road report in the state from one address; the ones on a
# road inside the box are kept. Closures and work zones are what the old map called road reports;
# the registry's address leaves out incidents (crashes came through from 2026-10-17 to 2026-11-01).


def box(lat, lon, miles):
    dlat, dlon = miles / 69.0, miles / (69.0 * math.cos(math.radians(lat)))
    return {"north": lat + dlat, "south": lat - dlat, "east": lon + dlon, "west": lon - dlon}


def points(coords):
    if isinstance(coords[0], (int, float)):
        yield coords
    else:
        for c in coords:
            yield from points(c)


def inside(geometry, b):
    """A report's point, or any point along its stretch of road, in the box."""
    return any(b["south"] <= lat <= b["north"] and b["west"] <= lon <= b["east"]
               for lon, lat in points(geometry["coordinates"]))


def road_items(features, entry, src, b):
    out = []
    for f in features:
        e = f["properties"]
        if e.get("active") is False or not inside(f["geometry"], b):
            continue
        about = re.sub(r"\s+", " ", to_text(e.get("description") or "").split("Comment:")[0]).strip()
        near = re.search(r"\((?:near )?([^)]+)\)", about)
        out.append(judged(entry, src, kind="news", category="road", all_day=True,
                          title=e["title"].strip().rstrip(".") + (f" near {near.group(1)}" if near else ""),
                          start=datetime.fromtimestamp(e["startTime"]["time"] / 1000, LOCAL).date().isoformat(),
                          blurb=about or None, source_url=f"https://511mn.org/events/{e['id']}",
                          source_uid=e["id"]))
    return out


def read_roads(src, entry, today):
    lat, lon = src["around"]
    return road_items(json.loads(fetch(src["url"])[1])["features"], entry, src, box(lat, lon, src.get("miles", 10)))


# Kennedy: Finalsite ----------------------------------------------------------------------

OCCURRENCE = re.compile(r'<a [^>]*data-occur-id="([^"]+)"[^>]*>')
# A school's own gatherings reach those following it (Jesse, 2026-11-05: "following"): a banquet, a club's
# meeting, an assembly, the PTO. Its concerts, shows and school board stay everyone's.
SCHOOL_ONLY = re.compile(r"\b(banquet|club|assembly|assemblies|pto|pta|parent meeting|parent planning meeting|signing day)\b", re.I)
# The school's activities a calendar title names, so the event lands on each one's row (public.activity_has_event; BP app
# school-search 02): "Band/Choir/Orchestra Concert" is all three's, "PTO Meeting at Kennedy" the PTO's.
ACTIVITY_WORDS = {w.lower(): w for w in ("Band", "Choir", "Orchestra", "Knowledge Bowl", "Spelling Bee", "Geography Bee",
                                         "Robotics", "Musical", "One Act", "PTO", "Art Club")}
NAMES_ACTIVITY = re.compile(r"\b(" + "|".join(ACTIVITY_WORDS) + r")\b", re.I)


def calendar_activity(title, entry):
    """The activity fields a school calendar's event carries: the activities its title names, joined by "/", and
    followers only for the school's own gatherings."""
    named = "/".join(dict.fromkeys(ACTIVITY_WORDS[w.lower()] for w in NAMES_ACTIVITY.findall(title)))
    mark = {"activity_name": named} if named else {}
    if SCHOOL_ONLY.search(title):
        mark["followers_only"] = True
    return {"activity_team": bound_team(entry), **mark} if mark else {}


def finalsite_calendar_items(page, url, entry, src, today):
    """Each occurrence once (a long event repeats in every day box it spans), with the exact
    times from <time datetime>; an all-day one takes its days from the occurrence id, whose end is the
    morning after the last ("Winter Break", Dec 21 to Jan 2, is out through Jan 1). An event
    on the place's own calendar (`own_calendar`) with no place given is at the place. With `own_calendar_only`
    nothing else is read: a district calendar another school's page already gives (Tech; nothing-scheduled 01)."""
    out, seen = [], set()
    tags = list(OCCURRENCE.finditer(page))
    # An event's calendar: the label before it, or for an all-day run, whose box has none, its colour's.
    colours = dict(re.findall(r"""background:(#\w+)['"][^>]*title=['"]([^'"]*)['"]""", page))
    for i, m in enumerate(tags):
        occur = m.group(1)
        if occur in seen:
            continue
        seen.add(occur)
        marks = re.findall(r"""fsStyleSROnly['"]>([^<]*)<|border-color: (#\w+)""", page[tags[i - 1].end() if i else 0:m.start()])
        calendar = (marks[-1][0] or colours.get(marks[-1][1])) if marks else None
        if src.get("own_calendar_only") and calendar != src.get("own_calendar"):
            continue
        body = page[m.end():tags[i + 1].start() if i + 1 < len(tags) else len(page)]
        times = dict((k, v) for v, k in re.findall(r'<time datetime="([^"]+)" class="fs(Start|End)Time"', body))
        _, first, after = occur.split("_")
        start = times.get("Start") or first[:10]
        if not ahead(date.fromisoformat(start[:10]), today):
            continue
        last = (date.fromisoformat(after[:10]) - timedelta(1)).isoformat()
        title = html.unescape(re.search(r'title="([^"]*)"', m.group(0)).group(1)).strip()
        place = re.search(r'<div class="fsLocation">(.*?)</div>', body, re.S)
        place = plain(place.group(1)) if place else ""
        label = re.findall(r"fsStyleSROnly'>([^<]*)<", page[tags[i - 1].end() if i else 0:m.start()])
        if not place and label and label[-1] == src.get("own_calendar"):
            place = entry["_name"]
        news = bool(NEWS.search(title))
        out.append(judged(entry, src, kind="news" if news else "event", category="school" if news else None,
                          title=title, start=start, end=times.get("End") or (last if last > start else None), all_day="Start" not in times,
                          place="" if place.lower() in ("multiple", "tbd", "tba") else place,
                          source_url=url, source_uid=occur, **({} if news else calendar_activity(title, entry))))
    return out


def read_finalsite_calendar(src, entry, today):
    first = today.replace(day=1)
    out = []
    for month in (first, (first + timedelta(days=32)).replace(day=1)):
        url = f"{src['url']}?cal_date={month}"
        out += finalsite_calendar_items(fetch(url)[1], url, entry, src, today)
    return out


def finalsite_news_items(page, url, entry, src):
    """The posts carry no dates, so each one is News from the day it is first seen."""
    out = []
    for post_id, body in re.findall(r'<article [^>]*data-post-id="(\d+)"[^>]*>(.*?)</article>', page, re.S):
        head = re.search(r'class="fsTitle[^"]*"[^>]*>(.*?)</div>', body, re.S)
        if not head:
            continue
        link = re.search(r'href="([^"]+)"', head.group(1))
        summary = re.search(r'class="fsSummary"[^>]*>(.*?)</div>', body, re.S)
        out.append(judged(entry, src, kind="news", category="school", title=plain(head.group(1)),
                          blurb=plain(summary.group(1)) if summary else None,
                          source_url=html.unescape(link.group(1)) if link else url, source_uid=post_id))
    return out


def read_finalsite_news(src, entry, today):
    return finalsite_news_items(fetch(src["url"])[1], src["url"], entry, src)


# Stearns County: CivicPlus HCMS ----------------------------------------------------------

# A crime story names a person; it waits in staging for Jesse instead of publishing.
CRIME = re.compile(r"\b(indicted|charged|arrested|sentenced|convicted|murder|homicide|assault|manslaughter)\b", re.I)
# Saint John's Outdoor University lists its programs on the county's calendar at SJU's street address,
# which the registry gives the Abbey; its own page (csbsju.edu) is closed to robots, so the county is
# how they arrive. Placed at Outdoor U, a copy lands on the listing already there (2026-11-03: eight
# wreath, print-making, Banff and owl nights doubled under the Abbey's picture).
OUTDOOR_U = re.compile(r"\bOutdoor U(?:niversity)?\b", re.I)


def hcms_token(page):
    m = re.search(r'hcmsClientToken\s*=\s*"([^"]+)"', page)
    if not m:
        raise RuntimeError("the county's page no longer carries hcmsClientToken")
    return m.group(1) if m.group(1).startswith("Bearer ") else f"Bearer {m.group(1)}"


def hcms_url(base, kind, top, orderby, where):
    return f"{base.rstrip('/')}/{kind}?" + urlencode(
        {"$top": top, "$skip": 0, "$orderby": orderby, "$filter": where}, quote_via=quote)


def field(data, name):
    value = data.get(name) or {}
    return value.get("iv", value.get("en")) if isinstance(value, dict) else None


def hcms_items(news, events, entry, src, today, town):
    out, page = [], src["token_page"]
    for x in news.get("items") or []:
        d = x["data"]
        if utc_local(field(d, "Date")).date() < today - timedelta(days=7):
            continue  # News older than 7 days leaves the Town feed anyway
        title = plain(field(d, "title"))
        out.append(judged(entry, src, kind="news", title=title, sure=not CRIME.search(title),
                          blurb=news_line(plain(field(d, "description"))), source_url=page, source_uid=x["id"]))
    for x in events.get("items") or []:
        d = x["data"]
        at, loc = field(d, "eventdate") or {}, field(d, "location") or {}
        if (loc.get("zip") or "")[:5] not in town["zips"]:
            continue  # the county's events count only in the town (ADR-019)
        start, all_day = utc_local(at["startDate"]), bool(at.get("allDay"))
        if not ahead(start.date(), today):
            continue
        title = plain(field(d, "title"))
        place = ", ".join(p for p in (loc.get("address1"), loc.get("city")) if p)
        if (loc.get("address1") or "").startswith("2850 Abbey Plaza") and OUTDOOR_U.search(plain(field(d, "description"))):
            place = "Outdoor U, SJU"
        out.append(judged(entry, src, kind="news" if NEWS.search(title) else "event", title=title, all_day=all_day,
                          start=start.date().isoformat() if all_day else start.isoformat(),
                          end=None if all_day or not at.get("endDate") else utc_local(at["endDate"]).isoformat(),
                          place=place, area="town",
                          source_url=page, source_uid=f"{x['id']}:{at['startDate']}"))
    return out


def read_hcms(src, entry, today):
    auth = {"Authorization": hcms_token(fetch(src["token_page"])[1]), "Accept": "application/json"}
    since = datetime.combine(today, time(), LOCAL).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    news = fetch(hcms_url(src["url"], "news", 20, "data/Date/iv desc",
                          f"categories/any(c:c/id eq {src['news_category']})"), headers=auth)[1]
    events = fetch(hcms_url(src["url"], "event", 100, "data/eventdate/iv/startDate asc",
                            f"categories/any(c:c/id eq {src['event_category']}) and data/eventdate/iv/endDate ge {since}"),
                   headers=auth)[1]
    return hcms_items(json.loads(news), json.loads(events), entry, src, today, TOWNS[entry["_town"]])


# High school games: the Minnesota State High School League -------------------------------

# Games are read four weeks ahead: the longest lead time a game gets (a notable one).
GAME_DAYS = 28
LEAGUE = "https://www.mshsl.org"
# Venues within 20 miles of St. Joseph as the league writes them: (town, the school whose
# building it is, by its registry name). Measured 2026-10-14 and 2026-10-15 from Google Maps
# listings. A venue not listed counts as outside and is named in the dry run: measure it and
# add it here. Left out on purpose: Eden Valley-Watkins Football Field (20.3 mi), Stone
# Creek Golf Course (Foley, 21.5), Upsala High School (20.5).
NEARBY = {
    "Albany High School": ("Albany", "Albany High School"),
    "College of Saint Benedict": ("St. Joseph", None),
    "College of St. Benedict": ("St. Joseph", None),
    "Eden Valley-Watkins High School": ("Eden Valley", "Eden Valley-Watkins High School"),
    "Holdingford High School": ("Holdingford", "Holdingford High School"),
    "Kimball Area High School": ("Kimball", "Kimball Area High School"),
    "Kimball Golf Club": ("Kimball", None),
    "Municipal Athletic Complex": ("St. Cloud", None),
    "Powder Ridge": ("Kimball", None),
    "Radio Tower Field": ("Collegeville", None),
    "River Lakes Arena": ("Richmond", None),
    "River Lakes Civic Arena": ("Richmond", None),
    "River Oaks Golf Course": ("Cold Spring", None),
    "Riverview Intermediate School": ("Sartell", "Sartell High School"),
    "ROCORI High School": ("Cold Spring", "ROCORI High School"),
    "Royalton High School": ("Royalton", "Royalton High School"),
    "Saint John's University": ("Collegeville", None),
    "Sartell High School": ("Sartell", "Sartell High School"),
    "Sauk Rapids Arena East": ("Sauk Rapids", None),
    "Sauk Rapids-Rice High School": ("Sauk Rapids", "Sauk Rapids-Rice High School"),
    "Sauk Rapids-Rice Middle School": ("Sauk Rapids", "Sauk Rapids-Rice High School"),
    "Scheels Athletic Complex": ("Sartell", None),
    "St Cloud State University": ("St. Cloud", None),
    "St John's University - Gagliardi Field and Skalicky Seasonal Dome": ("Collegeville", None),
    "St. Cloud Apollo High School": ("St. Cloud", "Apollo High School"),
    "St. Cloud Cathedral High School": ("St. Cloud", "Cathedral High School"),
    "St. Cloud Municipal Athletic Complex": ("St. Cloud", None),
    "St. Cloud Tech High School": ("St. Cloud", "Tech High School"),
    "St. John's Prep": ("Collegeville", "St. John's Prep"),
    "Sta-Fit Gym": ("St. Cloud", None),
    "Sta-Fit Sartell": ("Sartell", None),
    "The King's Academy": ("Waite Park", None),
    "Warner Lake": ("Clearwater", None),
    "Whitney Recreation Center": ("St. Cloud", None),
    "Whitney Sports Complex": ("St. Cloud", None),
}
NOT_GAMES = re.compile(r"^(music|robotics|speech|visual arts|one act play|debate|cheerleading|clay target)", re.I)
ONE_GENDER = {"Volleyball", "Gymnastics", "Softball"}
SPORT_WORDS = {"Cross Country Running": "Cross Country", "Swimming and Diving": "Swim",
               "Nordic Ski Racing": "Nordic Skiing", "Track and Field": "Track"}
# A row naming an event rather than an opponent: a meet, a tournament, an invitational. "CLC" is the Central Lakes
# Conference: "CLC Dance Team" is its dance meet, no team (BP app game-card 19).
NAMED = re.compile(r"\b(meet|tournament|tourney|invite|invitational|championships?|classic|jamboree|scrimmage|"
                   r"relays|section|conference|clc|true team|tri|triangular|quadrangular|individuals|race|festival|"
                   r"showcase|show|competition|state)\b", re.I)
PLAYOFF = re.compile(r"\b(section|state|true team|championships?|playoffs?)\b", re.I)
# The league lists varsity games; a row naming only a lower level, or a practice, is left out.
LOWER = re.compile(r"\b(jv|junior varsity|c-?squad|b-?squad|9th|freshman|practice|tryouts?)\b", re.I)
VARSITY = re.compile(r"\b(v|varsity)\b", re.I)
# A playoff row before its teams are known.
PLACEHOLDERS = {"", "vs", "tbd", "tba"}
# An opponent not decided yet: "St. Cloud Apollo OR Little Falls" (a playoff bracket).
UNDECIDED = re.compile(r"\bor\b", re.I)


def league_sports(page, today):
    """The school's own sports in season over the next four weeks, from its schedule page's
    settings: {activity id: (sport family, title words)}, e.g. 142: ("Soccer", "Girls Soccer")."""
    m = re.search(r'data-drupal-selector="drupal-settings-json">(.*?)</script>', page, re.S)
    if not m:
        raise RuntimeError("the league's page no longer carries its settings")
    s = json.loads(m.group(1))
    out = {}
    for a in s["activitiesList"]:
        season = s["activityDates"].get(str(a["id"]))
        if NOT_GAMES.match(a["name"]) or not season or not (
                season["start"] <= str(today + timedelta(GAME_DAYS)) and season["end"] >= str(today)):
            continue
        family, _, rest = a["name"].partition(", ")
        family = SPORT_WORDS.get(family, family)
        gender = rest if rest in ("Boys", "Girls") and family not in ONE_GENDER else ""
        out[a["id"]] = (family, f"{gender} {family}".strip(), season["start"], season["end"])
    return out


def short_team(name):
    """The team as neighbours say it: "Apollo", not "St. Cloud Apollo"; "Kimball", not
    "Kimball Area"; a co-op joined with a hyphen, since a title carries no slash."""
    name = re.sub(r"^St\. Cloud (Apollo|Tech|Cathedral)$", r"\1", name.strip())
    return re.sub(r"\s*/\s*", "-", re.sub(r" Area$", "", name))


def league_listings(rows, sports, entry, src, today):
    """One school's rows, every sport's whole season, as listings in the next four weeks.
    A game is numbered by which meeting of the two teams it is in that sport's season, so
    it keeps its id when it moves to another day."""
    out, met = [], {}
    team = src.get("team") or entry["_name"]
    for r in sorted(rows, key=lambda r: (datetime.strptime(r["event_date"], "%m/%d/%Y"), r["event_time"])):
        a = r["mshsl_activity_id"]
        if a not in sports:
            continue
        day = datetime.strptime(r["event_date"], "%m/%d/%Y").date()
        mine, other = (r.get("school_name") or "").strip() or team, (r.get("opponent") or "").strip()
        named = bool(NAMED.search(other))
        n = None
        if not named and not {mine.lower(), other.lower()} & PLACEHOLDERS:
            pair = (a, frozenset((mine.lower(), other.lower())))
            n = met[pair] = met.get(pair, 0) + 1
        if not today <= day <= today + timedelta(GAME_DAYS):
            continue
        family, words, *_ = sports[a]
        out.append({"lister": entry["_name"], "page": src["url"], "activity": a, "family": family,
                    "sport": words, "day": day, "time": r["event_time"].strip(), "team": mine,
                    "opponent": other, "named": named, "venue": (r.get("location") or "").strip(), "n": n})
    return out


def league_start(day, clock_text):
    """The league writes "7:00 PM"; "12:00 AM" is its no-time-yet."""
    if clock_text in ("", "12:00 AM"):
        return day.isoformat(), True
    t = datetime.strptime(clock_text, "%I:%M %p").time()
    return datetime.combine(day, t, LOCAL).isoformat(), False


def games(listings, today):
    """Every school's listings -> one judged item per game, meet or tournament day, and what
    was left out. The same game from both teams (date, sport, venue and the two teams) is one
    Event; a meet, or a day of tournament pool matches (three or more rows for one school), is
    one Event per sport, venue and day. Kept only at a venue within 20 miles (NEARBY)."""
    left = {"outside": 0, "waiting": 0, "lower": 0, "unplaced": set()}
    kept = []
    for l in listings:
        if LOWER.search(l["opponent"]) and not VARSITY.search(l["opponent"]):
            left["lower"] += 1
        elif l["venue"] not in NEARBY:
            left["outside"] += 1
            if l["venue"].lower() not in PLACEHOLDERS:
                left["unplaced"].add(l["venue"])
        elif not l["named"] and (l["n"] is None or UNDECIDED.search(l["opponent"])):
            left["waiting"] += 1  # a playoff game with no opponent yet waits until it has one
        else:
            kept.append(l)
    # A school's own team in a sport is the one in more than half its rows, its co-op's included
    # ("River Lakes" for Albany, which the league may list second, as at River Lakes Arena).
    rows = Counter((l["lister"], l["activity"]) for l in listings)
    named = Counter((l["lister"], l["activity"], n) for l in listings for n in {l["team"], l["opponent"]})
    busy = {}
    for l in kept:
        k = (l["lister"], l["day"], l["activity"], l["venue"])
        busy[k] = busy.get(k, 0) + 1
    groups = {}
    for l in kept:
        meet = l["named"] or busy[(l["lister"], l["day"], l["activity"], l["venue"])] >= 3
        key = (("meet", l["family"]) if meet else ("game", l["activity"], frozenset((l["team"], l["opponent"])))) \
            + (l["day"], l["venue"])
        groups.setdefault(key, []).append(l)

    items = []
    for key, ls in groups.items():
        town, home = NEARBY[ls[0]["venue"]]
        own = [l for l in ls if l["lister"] == home]
        first = (own or sorted(ls, key=lambda l: l["lister"]))[0]
        host = home or first["lister"]
        if key[0] == "meet":
            name = next((l["opponent"] for l in sorted(ls, key=lambda l: (not l["named"], l["lister"]))
                         if l["named"]), f"{short_team(first['team'])} {first['sport']} Tournament")
            if not re.search(rf"\b({re.escape(first['family'].split()[0])}|swim|dive|diving|ski|xc|cc)\b", name, re.I):
                name = re.sub(r"\b(Meet|Invite|Invitational)\b", lambda m: f"{first['family']} {m[1]}", name, count=1) \
                    if re.search(r"\b(Meet|Invite|Invitational)\b", name) else f"{name}: {first['sport']}"
            title, uid = name, f"mshsl:meet:{first['family'].lower()}:{first['day']}:{first['venue'].lower()}"
            game = about = None
            when = min(ls, key=lambda l: league_start(l["day"], l["time"])[::-1])  # timed first, earliest
        else:
            pair, act = (first["team"], first["opponent"]), first["activity"]
            mine = lambda lister: [n for n, t in enumerate(pair) if named[(lister, act, t)] * 2 > rows[(lister, act)]]
            # The venue's school hosts only a game it plays in, and then goes first: a section game on a
            # third school's ground has no host and keeps both teams. On ground that is no school's, the
            # host line is the lister's, and its own team may leave a long title.
            hosts = ([n for n, t in enumerate(pair) if plays_for(t, home)] or (mine(home) if own else [])) if home else []
            us, them = pair[::-1] if hosts == [1] else pair
            teams = [short_team(us), short_team(them)]
            listed = mine(first["lister"])
            ours = 0 if len(hosts) == 1 else listed[0] if not home and len(listed) == 1 else None
            title = game_title(teams, first["sport"], ours)
            about = game_about("Varsity", first["sport"], teams[0], teams[1], hosted=len(hosts) == 1)
            game = {"sport": first["sport"], "teams": teams}
            pair = "|".join(sorted(t.lower() for t in (first["team"], first["opponent"])))
            uid, when = f"mshsl:{first['activity']}:{pair}:{first['n']}", first
        start, all_day = league_start(when["day"], when["time"])
        items.append({"kind": "event", "title": title, "start": start, "end": None, "all_day": all_day,
                      "place": first["venue"], "town": town, "area": "game", "source_name": host,
                      "source_url": first["page"], "source_uid": uid, "trust": "official", "sure": True,
                      "size": "notable" if PLAYOFF.search(title) else "everyday", "interest": "watch_sports",
                      "blurb": about, **({"game": game} if game else {})})
    return sorted(items, key=lambda i: (i["start"], i["title"])), left


# The league answers most calls in half a second, but about one in six hangs or comes back 502:
# on 2026-10-25 six of twelve schools failed, from the cloud and from the Mac alike. One school
# failing keeps every school's called-off games up that morning (read_all's schedule line), so
# each call gets three more tries, a while apart. A hang is given up after 8 seconds, not
# run.py's 20: with 20, the retries made a read of the schools 11 to 18 minutes. A hanging call
# costs about two minutes with its tries (fetch's own retry doubles each), and a school makes 8 to
# 10 calls, so in prepare's timed parts a school's calls stop 150 s past the part's end and the
# school is read whole in the next part: no part passes the cloud's 10 minutes.
LEAGUE_WAITS = (3, 10, 20)
LEAGUE_TIMEOUT = 8
PART_STOP = None  # the timed part's end, set by read_all


class LeftForNextPart(Exception):
    pass


def league_fetch(url, wait=sleep):
    for pause in (*LEAGUE_WAITS, None):
        if late(PART_STOP, 150):
            raise LeftForNextPart(url)
        try:
            return fetch(url, timeout=LEAGUE_TIMEOUT)[1]
        except urllib.error.HTTPError as ex:
            if ex.code < 500 or pause is None:
                raise
        except (urllib.error.URLError, ConnectionError, TimeoutError):
            if pause is None:
                raise
        wait(pause)


def read_league(src, entry, today):
    """One school's listings: its page (for its sports and their seasons), then each sport in
    season, the whole season, so a game keeps its number. games() turns them into items."""
    sports = league_sports(league_fetch(src["url"]), today)
    rows = []
    for a, (_, _, start, end) in sports.items():
        rows += json.loads(league_fetch(f"{LEAGUE}/api/team-data/schedule/{src['league_id']}/varsity/{a}"
                                        f"?start_date={start}&end_date={end}"))
    return [{"listing": l} for l in league_listings(rows, sports, entry, src, today)]


# Bound: a school's activities calendar ---------------------------------------------------

# Bound (gobound.com) posts every activity of seven nearby schools (BP app school-activities, ticket 05).
# Its iCal export carries each event's activity in fields of its own (X-BND-ACTIVITYKEY "volleyball",
# -ACTIVITYNAME "Volleyball, Girls", -ACTIVITYLEVEL "Varsity", -ACTIVITYSEX), the venue's GEO and
# STATUS:CANCELLED; the calendar page itself 403s a headless browser (REA, 2026-10-25).
# Varsity games keep coming from the league reader; Bound adds the plays, concerts and clubs, and the
# levels a source names in `game_levels` (Kennedy's "Middle School") as games (Jesse, 2026-10-25).
# Everything else is kept for followers only (JV, C, B and middle school games, away games, banquets):
# "most of them will only be seen if people are following that exact activity" (Jesse, 2026-10-25;
# BP app school-activities 03). Each carries its school and Bound's activity name.
BOUND_ARTS = {"band", "jazzband", "choir", "orchestra", "theatre", "drama", "speech", "knowledgebowl", "robotics",
              "math", "studentcouncil"}
# An event with no activity is a school's own: kept when it is a show people go to, never a ticket pass.
BOUND_SHOW = re.compile(r"\b(play|musical|concert|orchestra|band|choir|theat(er|re)|art club|art show)\b", re.I)
BOUND_PASS = re.compile(r"\b(pass|practice|tryouts?)\b", re.I)
# The level Bound adds to a title: "(Varsity)", "(Middle School)", "(High School Choir)".
BOUND_LEVEL = re.compile(r"\s*\((varsity|jv|junior varsity|middle school|high school[^)]*|c|b)\)$", re.I)
BOUND_TEAMS = {"Kennedy Community MS": "Kennedy"}
# A lower level as its title says it: "Apollo Girls Volleyball vs Brainerd · JV". A school's second
# C team plays beside its first, same time and gym, so its title says so (2026-10-29: 14 pairs).
BOUND_LEVEL_WORDS = {"Junior Varsity": "JV", "JV": "JV", "C": "C-squad", "C2": "C2-squad", "C Team": "C-squad",
                     "B": "B-squad", "Middle School": "Middle school", "MS": "Middle school"}
# The adapted sports' divisions, not levels: the title keeps them, and a card wouldn't say what they mean.
CARD_SAYS_NO_LEVEL = {"CI", "PI"}
# A level that only says who plays ("Girls Varsity", "Boys MS"), posted where a meet's name goes.
BOUND_WHO = re.compile(r"(girls|boys)\s+(varsity|jv|ms|c|b)", re.I)
BOUND_MEET = re.compile(r"wrestl|swim|diving|cross country|track|gymnast|ski|golf|dance", re.I)
# A name that says only what kind of meet it is ("Competition", "Triangular") gets its activity in front.
BOUND_GENERIC = {"competition", "meet", "invitational", "invite", "triangular", "quad", "tri", "tournament", "scrimmage"}
# A meet's name that lacks its sport ("Section Championship"; Jesse, 2026-11-04): the sport goes before the
# word saying what kind of meet it is, else after the name.
BOUND_SAID = re.compile(r"wrestl|swim|div(e|ing)|cross country|track|gymnast|\bski|nordic|golf|dance|kick|hockey|"
                        r"basketball|soccer|football|baseball|softball|volleyball|tennis|lacrosse|bowling|trap|clay", re.I)
BOUND_KIND = re.compile(r" (invite|invitational|championships?|tournament|classic|jamboree|showcase|tri|quad|duals|"
                        r"duels|open|sprints|meet|scrimmages?|banquet|meeting)( \d{4})?$", re.I)
# Bound joins a school and its room, and the two often repeat: "ROCORI High School High School Gym".
BOUND_DOUBLED = re.compile(r"\b((?:[\w.'-]+ ){0,2}[\w.'-]+) \1\b", re.I)
HOME = (45.5647, -94.3183)  # St. Joseph


def miles(a, b):
    (la1, lo1), (la2, lo2) = [(math.radians(x), math.radians(y)) for x, y in (a, b)]
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 7918 * math.asin(math.sqrt(h))


def bound_sport(name):
    """Bound's "Soccer, Boys" as the league's words, "Boys Soccer"; a one-gender sport bare."""
    family, _, sex = name.partition(", ")
    family = SPORT_WORDS.get(family, family)
    return f"{sex} {family}" if sex in ("Boys", "Girls") and family not in ONE_GENDER else family


def bound_with_sport(name, activity):
    """A meet's own name with its sport in it. No boys or girls: a meet is often both."""
    family = re.sub(r"^(girls|boys|ms coed) ", "", activity.partition(", ")[0], flags=re.I)
    family = SPORT_WORDS.get(family, family)
    if not family or BOUND_SAID.search(name):
        return name
    kind = BOUND_KIND.search(name)
    return f"{name[:kind.start()]} {family}{kind[0]}" if kind else f"{name} {family}"


def bound_meet_title(name, activity, level):
    """A meet's title, saying its level as a game's does: "Albany Dance Invitational · JV", "Mora Wrestling
    Invitational · Girls"; varsity, a level it doesn't know and a word the name already has say nothing. Two levels of
    one meet are two cards, each saying its own (BP app loopholes 11; Jesse, 2026-11-05). Cathedral's dance levels
    name the routine first: "High Kick JV", "Jazz V"."""
    title = bound_with_sport(name, activity)
    who = BOUND_WHO.fullmatch(level.strip())
    rank = who[2] if who else re.sub(r"^(high kick|jazz) ", "", level.strip(), flags=re.I)
    rank = BOUND_LEVEL_WORDS.get(rank.upper() if len(rank) <= 2 else rank.title(), "")
    have = set(re.findall(r"[a-z0-9-]+", title.lower()))
    if {"junior", "varsity"} <= have:
        have.add("jv")
    said = [w for w in (who[1].title() if who else "", LEVEL_SHORT.get(rank, rank)) if w and w.lower() not in have]
    return f"{title} · {' '.join(said)}" if said else title


def bound_team(entry):
    """The school's row in public.teams: "Apollo High School" is apollo, "Kennedy Community School" kennedy."""
    return re.sub(r"[^a-z0-9]+", "-", re.sub(r" (High|Community) School$", "", entry["_name"]).lower()).strip("-")


def bound_items(text, entry, src, today):
    out, games, levels = [], [], set(src.get("game_levels") or ())
    for ev in parse_ics(text):
        get = lambda k: unescape(ev.get(k, ("", ""))[1])
        title, key, level = get("SUMMARY"), get("X-BND-ACTIVITYKEY"), get("X-BND-ACTIVITYLEVEL")
        title = re.sub(r"\s*\(time tba\)$", "", title, flags=re.I)  # the missing start is already missing
        geo = re.fullmatch(r"(-?[\d.]+);(-?[\d.]+)", ev.get("GEO", ("", ""))[1].strip())
        if "DTSTART" not in ev or "UID" not in ev or get("STATUS").upper() == "CANCELLED" or BOUND_PASS.search(title):
            continue
        # No venue to measure: as far as an away game.
        far = not geo or miles(HOME, (float(geo[1]), float(geo[2]))) > 20
        start, all_day = when(ev["DTSTART"])
        if not ahead(start if all_day else start.date(), today):
            continue
        uid, place = f"bound:{ev['UID'][1].strip()}", BOUND_DOUBLED.sub(r"\1", get("LOCATION"))
        name = BOUND_LEVEL.sub("", re.sub(rf"\s*\({re.escape(level)}\)$", "", title) if level else title)
        # Bound cuts a long title off mid-word: "vs South Junior High (Mid".
        name = re.sub(r"\s*\([^)]*$", "", name)
        name = name.split(": ", 1)[1].strip() if ": " in name and key else "" if key and name.endswith(":") else name
        # A show has no opponent: "Theatre: vs St. Cloud Cathedral (Winter Show)" is a show named by its level.
        if not re.sub(r"\bvs\b", "", name).strip() or (key in BOUND_ARTS and re.match(r"vs\b", name)):
            # Posted with no name ("Choir:  vs"): a show's level may be its name ("Fall Show"), else skip
            # it. A team sport's is a game with no opponent yet. A meet sport's level says only who goes:
            # a meet of many schools (Sartell's "Girls Varsity" wrestling, Dec 18-19: eight schools on
            # its Bound page; Jesse, 2026-10-29).
            who = BOUND_WHO.fullmatch(level.strip())
            if who and BOUND_MEET.search(get("X-BND-ACTIVITYNAME")):
                sport = bound_sport(get("X-BND-ACTIVITYNAME"))
                sex = "" if who[1].lower() in sport.lower() else f"{who[1].title()} "
                school = short_team(re.sub(r" (High|Community) School$", "", entry["_name"]))
                rank = BOUND_LEVEL_WORDS.get(who[2].upper() if len(who[2]) <= 2 else who[2].title())
                name = f"{school} {sex}{sport} Meet" + (f" · {LEVEL_SHORT.get(rank, rank)}" if rank else "")
            elif not level or key not in BOUND_ARTS or BOUND_LEVEL.fullmatch(f" ({level})"):
                continue
            else:
                name = level
        name = re.sub(r"^.*\bpresents:\s*", "", name, flags=re.I)  # "Apollo Theater Presents: The SpongeBob Musical"
        quoted = re.search(r'"([^"]+)"', name)
        if quoted and len(name) > 40:  # 'SRRHS Fall Musical, "Disney, The Little Mermaid"': the show's own name
            name = re.sub(r"^Disney,\s*", "", quoted[1])
        if key and name.lower() in BOUND_GENERIC and get("X-BND-ACTIVITYNAME"):
            name = f"{bound_sport(get('X-BND-ACTIVITYNAME'))} {name}"
        if key and re.search(r"\svs$", name):
            continue  # "River Lakes vs" at West Fargo (Dec 29): a tournament game whose opponent isn't named yet
        start_at = start.isoformat()
        # Bound posts a concert, a show or a club's day with no activity ("HS Fall Band Concert"): its title names it, as
        # a school calendar's does (BP app school-search 07).
        mark = dict(activity_team=bound_team(entry),
                    activity_name=get("X-BND-ACTIVITYNAME") or calendar_activity(title, entry).get("activity_name"),
                    source_url=page_url(ev, src["url"]), source_uid=uid)
        if key in BOUND_ARTS or (not key and BOUND_SHOW.search(title)):
            out.append(judged(entry, src, title=name, start=start_at, all_day=all_day, place=place,
                              followers_only=far or bool(SCHOOL_ONLY.search(title)),
                              same=(start_at, key or name, level, place[:25]), **mark))
        elif key and " vs " in name:
            if level == "Varsity" and not far:
                continue  # the league's
            # Bound names the visitors first ("Brainerd vs St. Cloud Apollo" at Apollo); a title and a game
            # card put the home team first, as the league's do.
            # Its own brackets stay out of a name: "St. Cloud Tech (Varsity) (Time TBA) vs Osseo".
            away, home = [BOUND_TEAMS.get(t, short_team(t)) for t in
                          (re.sub(r"\s*\([^)]*\)?", "", n).strip() for n in name.split(" vs ", 1))]
            if {away.lower(), home.lower()} & PLACEHOLDERS or UNDECIDED.search(name):
                continue  # an opponent not named yet
            sport = bound_sport(get("X-BND-ACTIVITYNAME"))
            words = "" if level == "Varsity" else BOUND_LEVEL_WORDS.get(level, level)
            game = judged(entry, src, title="", start=start_at, all_day=all_day, place=place,
                          area="announced" if far else "game", interest="watch_sports",
                          blurb=game_about(level and (words or "Varsity"), sport, home, away, hosted=any(
                              re.search(rf"\b{re.escape(n)}\b", place, re.I) for n in {home, *home.split("-")})),
                          followers_only=far or level not in levels,
                          game={"sport": sport, "teams": [home, away]}, same=(start_at, key, level, place[:25]), **mark)
            out.append(game)
            games.append((game, words))
        elif key:
            # A banquet, a meeting: for those following its activity or school. The school's own days
            # with no activity ("No School", "Mass", "Conferences") stay out.
            out.append(judged(entry, src, title=bound_meet_title(name, get("X-BND-ACTIVITYNAME"), level), start=start_at,
                              all_day=all_day, place=place, followers_only=True,
                              same=(start_at, key or name, level, place[:25]), **mark))
    # The school's own team, which a title too long for both leaves out: its own name, or a co-op's
    # ("St. Cloud", "River Lakes") as the one team in more than half that activity's games here.
    played = Counter(g["activity_name"] for g, _ in games)
    seen = Counter((g["activity_name"], t) for g, _ in games for t in g["game"]["teams"])
    for g, words in games:
        teams, act = g["game"]["teams"], g["activity_name"]
        ours = [n for n, t in enumerate(teams) if bound_team({"_name": t}) == bound_team(entry)] \
            or [n for n, t in enumerate(teams) if seen[(act, t)] * 2 > played[act]]
        g["title"] = game_title(teams, g["game"]["sport"], ours[0] if len(ours) == 1 else None, words)
        # The white card says only its sport, so the sport says the level (Jesse, 2026-11-05, game-card 16): five
        # games between two schools in one night read alike otherwise. private.sport_base leaves it out.
        if words and words not in CARD_SAYS_NO_LEVEL and not g["game"]["sport"].startswith("MS "):
            g["game"]["sport"] += f" · {LEVEL_SHORT.get(words, words)}"
    # The whole schedule was read: an event of this school's gone from it was called off. A schedule
    # with nothing on it is a feed that came back empty, not a school that called off everything.
    if not out:
        return out
    return out + [{"kind": "schedule", "uid_prefix": "bound:", "from": today.isoformat(),
                   "through": (today + timedelta(DAYS_AHEAD)).isoformat(), "sources": [entry["_name"]]}]


def one_each(items):
    """Bound lists a shared event on every school in it (the conference jazz festival on five), and a
    meet once per school entered: one Event each, by its id or its start, activity and venue, posted by
    the school whose venue it is."""
    keep, seen = [], {}
    for it in items:
        same = it.pop("same", None)
        if same is None:
            keep.append(it)
            continue
        same = tuple(same)  # a list once read back from a timed part's file
        k = seen.get(it["source_uid"]) or seen.get(same)
        if k is None:
            seen[it["source_uid"]] = seen[same] = len(keep)
            keep.append(it)
        elif short_team(it["source_name"].replace(" High School", "")).split()[0].lower() in it["place"].lower():
            keep[k] = it  # the school whose venue it is hosts it
    return keep


def read_bound(src, entry, today):
    # Bound's robots.txt keeps crawlers off /*/calendar*, so our fetch is refused and Firecrawl reads the
    # feed raw (run.py's read_page; Jesse, 2026-10-25: "fire crawl"). Seven a morning, of the run's 30.
    return bound_items(read_page(src["url"], "ical")[1], entry, src, today)


# The diocesan paper ----------------------------------------------------------------------

# The Central Minnesota Catholic lists parish events across the diocese (The Events Calendar's iCal, its next 30). Only
# those within 20 miles of St. Joseph come in, as the league's and Bound's games do (BP app nothing-scheduled 02): by
# the map point, else by the town the address names. Never by the title's "— Town": "Our Sacred Universe Story — Little
# Falls" is at the Franciscan Welcoming House in St. Cloud. The towns: NEARBY's, and parish towns 7 to 14 miles off.
NEAR_TOWNS = {town for town, _ in NEARBY.values()} | {"Avon", "Rockville", "Rice", "St. Stephen", "St. Augusta", "Luxemburg"}
ONLINE = re.compile(r"\b(virtual|online|zoom|webinar)\b", re.I)
# The paper ends each title with its town and its name for the venue: "Breakfast — St. Joseph, Church of St. Joseph".
PAPER_ENDING = re.compile(r"\s+—\s+([^—]*)$")
# Who puts it on, in its description: "St. Joseph • Knights of Columbus hosts breakfast", "the Poor Clares of Sauk Rapids
# invite you", "St. Anne’s Christian Women of Luxemburg (St. Wendelin’s Parish) will be hosting".
HOSTED = re.compile(r"(?:^|[.,•–—]\s+)(?:[Tt]he\s+)?([A-Z][\w'’.&-]*(?:\s+(?:(?:of|the|and|&|for)\s+)*[A-Z][\w'’.&-]*)*)"
                    r"(?:\s+\([^)]*\))?\s+(?:hosts?|is hosting|are hosting|will (?:be )?host(?:ing)?|invites?|presents?)\b")


def town_of(address):
    """The town an address names, written as NEARBY writes it: "…, St Cloud, MN, 56301" is St. Cloud; "MN" names none."""
    town = re.search(r"([^,]+),\s*(?:MN|Minnesota)\b", address)
    return town and re.sub(r"^(?:St\.?|Saint)\s+", "St. ", town[1].strip())


def venue_of(address):
    """(the venue's name, its town) for the place line. A parish's name carries its own town, truer than its mail's:
    "St. Wendelin Parish – Luxemburg, 22714 State Highway 15, St. Cloud" is St. Wendelin Parish, Luxemburg."""
    venue = address.split(",")[0].strip()
    named = re.fullmatch(r"(.+?)\s+–\s+(.+)", venue)
    town = named and town_of(f"{named[2]}, MN")
    return (named[1], town) if town in NEAR_TOWNS else (venue, town_of(address))


def diocese_items(text, entry, src, today):
    """The nearby, in-person Events, each once: a series (one page, a sitting a date) shows at its next sitting, and a
    drop-off open 4 hours or more on days a week apart or closer (Toys for Tots, weekdays 9 to 4) is one Event to its
    last day, as the campus calendar's shows are. The host is who the description says hosts it, else the paper's name
    for the venue."""
    series = {}
    for ev in parse_ics(text):
        get = lambda k: unescape(ev.get(k, ("", ""))[1])
        if "DTSTART" not in ev or "UID" not in ev:
            continue
        where, geo = get("LOCATION"), re.fullmatch(r"(-?[\d.]+);(-?[\d.]+)", ev.get("GEO", ("", ""))[1].strip())
        near = miles(HOME, (float(geo[1]), float(geo[2]))) <= 20 if geo else town_of(where) in NEAR_TOWNS
        start, all_day = when(ev["DTSTART"])
        if near and not ONLINE.search(f"{get('SUMMARY')} {where}") and ahead(start if all_day else start.date(), today):
            url = page_url(ev, src["url"])
            series.setdefault(re.sub(r"\d{4}-\d\d-\d\d/?$", "", url), []).append((start, all_day, ev, url))
    out = []
    for page, sittings in series.items():
        start, all_day, ev, url = sittings[0]
        get = lambda k: unescape(ev.get(k, ("", ""))[1])
        end = when(ev["DTEND"])[0] if "DTEND" in ev and not all_day else None
        uid = ev["UID"][1].strip()
        # A run's last day (or its first, at the feed's edge) is its one sitting in the feed: still the run's Event,
        # never a second card that day. Only a series' dated sitting takes a run's id: a one-off long day (the
        # monastery's retreat) keeps its own, since a run's id never merges into another host's copy.
        if url != page and all(not a and "DTEND" in e and when(e["DTEND"])[0] - s >= SHOW_SITTING
                               for s, a, e, _ in sittings):
            days_apart = [b[0] - a[0] for a, b in zip(sittings, sittings[1:])]
            if not days_apart or min(days_apart) <= timedelta(7):
                uid = f"run:{page}"
                end = sittings[-1][0].date() if days_apart else end
        title, about = get("SUMMARY"), said(get("DESCRIPTION"))
        ending, host = PAPER_ENDING.search(title), HOSTED.search(about or "")
        place, town = venue_of(get("LOCATION"))
        out.append(judged(entry, src, kind="news" if NEWS.search(title) else "event", title=PAPER_ENDING.sub("", title),
                          start=start.isoformat(), end=end and end.isoformat(), all_day=all_day, place=place,
                          town=town, blurb=about, source_url=url, source_uid=uid,
                          source_name=(host and host[1]) or (ending and ending[1].partition(", ")[2]) or entry["_name"]))
    return sorted(out, key=lambda i: i["start"])


def read_diocese(src, entry, today):
    return diocese_items(fetch(src["url"])[1], entry, src, today)


# Rec1: a city's registration catalog ------------------------------------------------------

REC1_KEY = re.compile(r'data-page-data="([^"]+)"')
REC1_NO_PLACE = {"location tbd", "multiple", "tbd", "tba"}
WEEKDAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]


def rec1_clock(text):
    """"7pm", "9:30am" as (hour, minute), else None."""
    m = re.fullmatch(r"(\d{1,2})(?::(\d\d))?\s*([ap])m", (text or "").strip().lower())
    if not m:
        return None
    hour = int(m.group(1)) % 12 + (12 if m.group(3) == "p" else 0)
    return hour, int(m.group(2) or 0)


def rec1_next(dates, days, today):
    """The program's next day from today: "12/11/26" is that day; "10/06-12/29" with days "Mon"
    is the next Monday in that run. None when it has no dates yet ("Open TBD") or is over."""
    one = re.fullmatch(r"(\d\d)/(\d\d)/(\d\d)", dates or "")
    if one:
        day = date(2000 + int(one.group(3)), int(one.group(1)), int(one.group(2)))
        return day if day >= today else None
    run = re.fullmatch(r"(\d\d)/(\d\d)-(\d\d)/(\d\d)", dates or "")
    if not run:
        return None
    m1, d1, m2, d2 = map(int, run.groups())
    # ponytail: a run's year is guessed from today (the catalog leaves it out); a run listed
    # more than a season ahead would read a year early.
    first = date(today.year, m1, d1)
    if first > today + timedelta(days=DAYS_AHEAD):
        first = date(today.year - 1, m1, d1)
    last = date(first.year + (1 if (m2, d2) < (m1, d1) else 0), m2, d2)
    wanted = {WEEKDAYS.index(d[:3].lower()) for d in re.split(r"[,\s/]+", days or "") if d[:3].lower() in WEEKDAYS}
    day = max(first, today)
    while day <= last:
        if not wanted or day.weekday() in wanted:
            return day
        day += timedelta(days=1)
    return None


def rec1_title(text, youth):
    """The session's own name; a youth program says so ("Volleyball" is the kids' league)."""
    title = re.sub(r"\s*\((youth|kids)\)", "", text, flags=re.I).strip()
    return f"Youth {title[0].lower()}{title[1:]}" if youth and not re.search(r"\b(youth|kids?)\b", title, re.I) else title


def rec1_items(catalog, entry, src, today):
    """`catalog`: [{section, group, description, sessions}] as read_rec1 gathers them. A program
    listed under several sections (Youth and Toddler) is one item, called youth only when every
    section listing it is Youth."""
    seen, sections = {}, {}
    for g in catalog:
        for s in g["sessions"]:
            seen.setdefault(s["id"], (g, s))
            sections.setdefault(s["id"], set()).add(g["section"].lower().startswith("youth"))
    out = []
    for sid, (g, s) in seen.items():
        if s.get("canceled"):
            continue
        f = {x["name"]: x["value"] for x in s.get("features") or []}
        day = rec1_next(f.get("dates"), f.get("days"), today)
        if not day or not ahead(day, today):
            continue
        times = [rec1_clock(t) for t in (f.get("times") or "").split("-")]
        start = times[0] and datetime.combine(day, time(*times[0]), LOCAL)
        end = start and len(times) > 1 and times[1] and datetime.combine(day, time(*times[1]), LOCAL)
        place = f.get("location") or ""
        # The fee goes in its own field (inside-cards 14); the words keep how to sign up. Only a fee of 0 is Free: no
        # fee given is unknown, and stays null.
        price = s.get("price")
        cost = "Sign up on the City's registration site."
        # A group's text is about its one program; a group of several (Senior Citizen Activities) says nothing of each.
        about = said(plain(g.get("description"))) if len(g["sessions"]) == 1 else None
        out.append(judged(entry, src, title=rec1_title(s["text"], sections[sid] == {True}),
                          start=start.isoformat() if start else day.isoformat(), end=end.isoformat() if end else None,
                          all_day=not start, place="" if place.lower() in REC1_NO_PLACE else place,
                          blurb=" ".join(p for p in (about, cost) if p), price=None if price is None else f"${price:g}" if price else "Free",
                          closed=bool(s.get("sessionFull") or s.get("registrationOver")),
                          source_url=src["url"], source_uid=f"rec1:{sid}"))
    return out


def read_rec1(src, entry, today):
    """The catalog page carries a visitor key; its programs come from the same JSON calls the
    page makes: the tabs, the all-programs tab's groups, each group's sessions."""
    base = src["url"].rstrip("/")
    root = base.rsplit("/catalog", 1)[0]
    page = REC1_KEY.search(fetch(base)[1])
    if not page:
        raise RuntimeError("the catalog page no longer carries its page data")
    key = json.loads(html.unescape(page.group(1)))["checkoutData"]["key"]
    form = {"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"}
    post = lambda path: json.loads(fetch(f"{root}/catalog/{path}", b"page=1", form)[1])
    tab = next(t["id"] for t in post(f"getTabs/{key}")["tabs"] if t["label"].lower().startswith("all"))
    catalog = []
    for section in post(f"getItems/{key}/{tab}")["sections"]:
        for g in section["groups"]:
            if g.get("type") == "activity":
                catalog.append({"section": section["name"], "group": g["name"], "description": g.get("description"),
                                "sessions": post(f"getActivitySessions/{key}/{tab}/{g['id']}")["items"]})
    return rec1_items(catalog, entry, src, today)


# The run ---------------------------------------------------------------------------------

READERS = {"ical": read_ical, "pathify": read_pathify, "cars511": read_roads,
           "finalsite-calendar": read_finalsite_calendar, "finalsite-news": read_finalsite_news,
           "csbsju-music": read_csbsju_music,
           "civicplus-hcms": read_hcms, "rec1": read_rec1, "mshsl": read_league, "gobound": read_bound,
           "diocese": read_diocese}


def reader_of(src):
    """The reader a source names, or ical for an iCal feed, which names none."""
    return src.get("reader") or ("ical" if src.get("kind") == "ical" else None)


def source_key(entry, src):
    return f"{entry['_name']}|{src['url']}"


def read_all(entries, today, readers=READERS, saved=None, stop=None):
    """Every reader source of these entries. One that fails is named in the summary and
    never stops the others. The schools' listings become games once every school is read,
    since both teams list the same game; on a morning every school was read, a schedule
    line tells the writer the list is whole, so a game missing from it was called off. A school
    whose schedule showed 0 games is left off the line: its games stay as they are.

    In a timed part, `saved` holds what each source gave in the morning's earlier parts, which
    is not read again (this part's are added to it), and no source starts after `stop`."""
    global PART_STOP
    items, summary, listings = [], [], []
    saved, PART_STOP = ({} if saved is None else saved), stop
    for e in entries:
        for s in e.get("sources") or []:
            name = reader_of(s)
            if not name:
                continue
            key = source_key(e, s)
            if key not in saved:
                if late(stop):
                    continue  # left for the next part
                try:
                    saved[key] = [readers[name](s, e, today), None]
                except LeftForNextPart:
                    continue  # its calls ran past the part: read whole next part
                except Exception as ex:  # a site down or changed is a line in the summary
                    saved[key] = [[], f"{type(ex).__name__}: {ex}"[:300]]
            got, error = saved[key]
            row = {"source": e["_name"], "reader": name, "url": s["url"], "items": len(got), "error": error}
            # A listing's day comes back from a part's file as text.
            listings += [{**g["listing"], "day": date.fromisoformat(str(g["listing"]["day"]))} for g in got if "listing" in g]
            items += [dict(g) for g in got if "listing" not in g]  # one_each changes them; the part's file keeps them whole
            if not got and not error and name in ("mshsl", "gobound"):
                row["note"] = "0 games on its schedule: its games are left as they are"
            summary.append(row)
    items = one_each(items)
    schools = [r for r in summary if r["reader"] == "mshsl"]
    if schools:
        found, left = games(listings, today)
        items += found
        read = sorted(r["source"] for r in schools if r["items"])
        if read and not any(r["error"] for r in schools):
            items.append({"kind": "schedule", "uid_prefix": "mshsl:", "from": today.isoformat(),
                          "through": (today + timedelta(GAME_DAYS)).isoformat(), "sources": read})
        summary.append({"source": "High school games", "reader": "games", "url": LEAGUE, "items": len(found),
                        "error": None, "note": f"{left['outside']} listings outside 20 miles, {left['waiting']} "
                        f"waiting for an opponent, {left['lower']} lower levels; venues outside or not yet measured: "
                        + (", ".join(sorted(left["unplaced"])) or "none")})
    return items, summary


TODAY = date(2026, 10, 14)
CITY = {"_name": "City of St. Joseph", "_town": "st-joseph-mn"}


def sample(name):
    return (SAMPLES / name).read_text()


def t_robots():
    from run import parse_robots, allowed
    kennedy = parse_robots("User-agent: sitebot\nDisallow: /\n\nUser-agent: *\nCrawl-delay: 5\nDisallow: /fs/\n"
                           "Allow: /fs/login$\n\n# Page Exclusions\nUser-agent: *\n"
                           "Disallow: /kennedy-news/kennedy-news-stories/~\n")
    assert allowed(kennedy, "/calendar?cal_date=2026-11-01") and allowed(kennedy, "/kennedy-news")
    assert not allowed(kennedy, "/kennedy-news/kennedy-news-stories/~board/x"), "the second * group counts too"
    assert not allowed(kennedy, "/fs/calendar-manager/events.ics?feed_id=1")
    assert allowed(kennedy, "/fs/login") and not allowed(kennedy, "/fs/login/x"), "$ ends the path"
    longest = parse_robots("User-agent: *\nDisallow: /a\nAllow: /a/b\nDisallow: /*.ics\n")
    assert allowed(longest, "/a/b/c") and not allowed(longest, "/a/x") and not allowed(longest, "/cal/x.ics")
    assert parse_robots("User-agent: BlockPartyBot\nDisallow: /a\n\nUser-agent: *\nDisallow: /\n") == [(False, "/a")]
    assert allowed(parse_robots("<!doctype html><html>a portal page</html>"), "/api/x"), "no rules: allowed"
    import run
    run._robots["https://down.example"], run._unreadable["https://down.example"] = run.STAY_OUT, "[Errno 104] reset"
    run._robots["https://no.example"] = run.STAY_OUT
    for url, said in (("https://down.example/x", "could not be read"), ("https://no.example/x", "disallows")):
        try:
            run.fetch(url)
            raise AssertionError(f"{url} was fetched")
        except RuntimeError as e:
            assert said in str(e), (url, str(e))


def t_closings_wait():
    """A calendar's closing goes up a week before its day (BP app town-feed 50). Titles from the live calendars."""
    days = lambda occur: finalsite_calendar_items(
        f'<a class="x" title="No School - Winter Break" data-occur-id="{occur}" href="#"></a>',
        "https://k/calendar", CITY, {"url": "https://k/calendar"}, date(2026, 11, 6))[0]
    winter = days("774605_2026-12-21T00:00:00Z_2027-01-02T00:00:00Z")
    assert (winter["start"], winter["end"], winter["shows_from"], winter["blurb"]) == (
        "2026-12-21", "2027-01-01", "2026-12-14", "Dec 21 to Jan 1"), winter
    workshop = days("774603_2026-11-25T00:00:00Z_2026-11-26T00:00:00Z")
    assert (workshop["end"], workshop["blurb"]) == (None, "Wednesday, Nov 25"), workshop
    src, say = {"url": "https://x.org"}, lambda title, **more: judged(CITY, src, kind="news", title=title, **more)
    for title in ("Holiday - City Offices Closed", "Alcuin and Clemens Library Closed", "No School - Winter Break",
                  "No Classes", "Late Start", "Two-hour Early Dismissal", "Early Release"):
        assert NEWS.search(title) and say(title, start="2026-12-21")["shows_from"] == "2026-12-14", title
    for title in ("Holiday Door Hangers for your Dorm!", "Holiday Sales at the Art and Heritage Place"):
        assert NEWS.search(title) and "shows_from" not in say(title, start="2026-11-19"), title
    assert say("Winter Break", start="2026-12-21").get("shows_from") is None, "the words have to say so"
    assert "shows_from" not in say("City Offices Closed"), "no day to wait for"
    assert "shows_from" not in say("Highway 23 closure", start="2026-12-21", category="road"), "a road report goes up"
    assert not NEWS.search("Closed Captioned Film") and "shows_from" not in judged(CITY, src, title="Closed", start="2026-12-21")
    timed = say("Late Start", start="2026-12-21T10:00:00-06:00", end="2026-12-21T15:00:00-06:00")
    assert (timed["shows_from"], timed["blurb"]) == ("2026-12-14", "Monday, Dec 21"), timed
    run = say("Library Closed", start="2026-11-25", end="2026-11-28")
    assert run["blurb"] == "Nov 25 to Nov 28", run
    assert say("Library Closed", start="2026-11-25", blurb="Back Sunday at 6pm.")["blurb"] == "Back Sunday at 6pm."


def t_ical():
    ics = ("BEGIN:VEVENT\r\nUID:7\r\nSUMMARY:Fare for All\r\nDTSTART:20261207T153000\r\n"
           "DTEND:20261207T173000\r\nLOCATION: - 610 County Rd 2  St. Joseph MN \r\n 56374\r\n"
           "DESCRIPTION:<p>Groceries\\, cheap</p>\r\nEND:VEVENT\r\n"
           "BEGIN:VEVENT\r\nUID:8\r\nSUMMARY:Holiday - City Offices Closed\r\nDTSTART;VALUE=DATE:20261126\r\nEND:VEVENT\r\n"
           "BEGIN:VEVENT\r\nUID:9\r\nSUMMARY:Film\r\nDTSTART:20261204T190000\r\n"
           "LOCATION:Saint John's University - 2850 Abbey Plaza St. Joseph MN 56374\r\nEND:VEVENT\r\n"
           "BEGIN:VEVENT\r\nUID:10\r\nSUMMARY:Old meeting\r\nDTSTART:20261005T180000\r\nEND:VEVENT\r\n")
    src = {"url": "https://www.stjosephmn.gov/common/modules/iCalendar/iCalendar.aspx?catID=25&feed=calendar"}
    fare, closed, film = ical_items(ics, CITY, src, date(2026, 10, 6))
    assert (fare["start"], fare["end"]) == ("2026-12-07T15:30:00-06:00", "2026-12-07T17:30:00-06:00"), fare
    assert fare["place"] == "610 County Rd 2 St. Joseph MN 56374" and fare["blurb"] == "Groceries, cheap"
    assert fare["source_url"] == "https://www.stjosephmn.gov/Calendar.aspx?EID=7" and fare["source_uid"] == "7"
    linked = ical_items("BEGIN:VEVENT\r\nUID:11\r\nSUMMARY:Council\r\nDTSTART:20261207T180000\r\n"
                        "DESCRIPTION:https://www.stjosephmn.gov/calendar.aspx?EID=2354\r\nEND:VEVENT\r\n",
                        CITY, src, date(2026, 10, 6))[0]
    assert linked["blurb"] is None, "a description that is only a link is none"
    assert said("See https://x.org for more") == "See https://x.org for more"
    assert (closed["kind"], closed["start"], closed["all_day"]) == ("news", "2026-11-26", True), closed
    assert (closed["shows_from"], closed["blurb"]) == ("2026-11-19", "Thursday, Nov 26"), "a closing waits and says its day"
    assert "shows_from" not in fare, "an Event doesn't wait this way"
    assert film["place"].startswith("Saint John's University"), "a St. Joseph source's event is kept wherever it is"
    assert clock(datetime(2026, 1, 1, 18, 0)) == "6 PM"
    sals = ical_items("BEGIN:VEVENT\r\nUID:12\r\nSUMMARY:Bingo Night\r\nDTSTART;TZID=UTC:20261020T183000\r\n"
                      "DTEND;TZID=UTC:20261020T200000\r\nEND:VEVENT\r\n"
                      "BEGIN:VEVENT\r\nUID:13\r\nSUMMARY:Fair week\r\nDTSTART;VALUE=DATE:20261109\r\n"
                      "DTEND;VALUE=DATE:20261115\r\nEND:VEVENT\r\n", CITY, src, date(2026, 10, 6))
    assert (sals[0]["start"], sals[0]["end"]) == ("2026-10-20T18:30:00-05:00", "2026-10-20T20:00:00-05:00"), \
        "a feed's TZID=UTC is the town's clock (Sal's page says 6:30 pm)"
    assert (sals[1]["start"], sals[1]["end"]) == ("2026-11-09", "2026-11-14"), "an all-day run keeps its last day"
    assert when((";VALUE=DATE", "20261126"))[1] and when(("", "20261020T233000Z"))[0].hour == 18


def t_diocese():
    """The diocesan paper's feed as read 2026-11-13 (15 of its 30, contacts blanked): Events within 20 miles of St.
    Joseph, by their map point, else by the town their address names; online and far ones out (BP app
    nothing-scheduled 02)."""
    paper, src = {"_name": "The Central Minnesota Catholic events"}, {"url": "https://x.org/events/?ical=1", "trust": "squishy"}
    ics, day = sample("diocese-calendar.ics"), date(2026, 11, 13)
    got = diocese_items(ics, paper, src, day)
    assert [(i["start"][:10], i["title"], i["source_name"], i["town"]) for i in got] == [
        ("2026-11-13", "Toys for Tots Collection", "Catholic Charities", "St. Cloud"),  # no map point: its address, St Cloud
        ("2026-11-17", "Our Sacred Universe Story", "Franciscan Sisters of Little Falls", "St. Cloud"),  # "— Little Falls"
        ("2026-11-22", "Holy Spirit Bouja", "Holy Spirit Church", "St. Cloud"),
        ("2026-11-22", "Breakfast", "St. Anne’s Christian Women of Luxemburg", "Luxemburg"),  # mail goes to St. Cloud
        ("2026-11-27", "Divine Mercy Chaplet", "Poor Clares of Sauk Rapids", "Sauk Rapids"),
        ("2026-12-06", "Breakfast", "Knights of Columbus", "St. Joseph"),
        ("2026-12-06", "Christmas Concert", "Church of St. Boniface", "Cold Spring")], \
        "Box of Joy (no town), Taizé and Lessons and Carols (Little Falls, 28 miles) and the virtual one stay out"
    toys, bouja = got[0], got[2]
    assert (toys["start"], toys["end"], toys["all_day"]) == ("2026-11-13T09:00:00-06:00", "2026-12-04", False), \
        "a drop-off open all day on many days is one Event to its last day"
    run = "run:https://thecentralminnesotacatholic.org/event/toys-for-tots-collection-st-cloud-catholic-charities/"
    assert toys["source_uid"] == run and toys["source_url"].endswith("/2026-11-13/"), toys
    tomorrow = diocese_items(ics, paper, src, date(2026, 11, 14))[0]
    assert (tomorrow["start"][:10], tomorrow["source_uid"]) == ("2026-11-16", run), "the same Event at its next day"
    last = diocese_items(ics, paper, src, date(2026, 12, 4))[0]
    assert (last["start"], last["end"], last["source_uid"]) == ("2026-12-04T09:00:00-06:00", "2026-12-04T16:00:00-06:00",
                                                                run), f"its last day alone is still the run's Event: {last}"
    from write_judged import plan, interest_ids
    row = plan([tomorrow], [], date(2026, 11, 14), interest_ids())["events"][0]["row"]
    stored = {**{k: row[k] for k in ("title", "event_date", "start_time", "all_day", "location", "source_name",
                                     "source_uid", "category")},
              "id": "e1", "status": "approved", "shows_from": None, "review_reason": None, "cancelled_at": None,
              "found": True, "mentions": [{"source_name": row["source_name"], "source_uid": run, "source_url": "u",
                                           "trust": "squishy", "sure": True}]}
    again = plan([last], [stored], date(2026, 12, 4), interest_ids())
    assert [g["id"] for g in again["events"]] == ["e1"] and again["outcomes"][0][0] == "merged", again["outcomes"]
    oneoff = ics.replace("toys-for-tots-collection-st-cloud-catholic-charities/2026-12-04/",
                         "toys-for-tots-collection-st-cloud-catholic-charities/")
    assert diocese_items(oneoff, paper, src, date(2026, 12, 4))[0]["source_uid"].startswith("100"), \
        "a long day that is no series' sitting (the monastery's retreat) keeps its own id, so it can merge"
    assert bouja["source_uid"] == "10009179-1795336200-1795345200@thecentralminnesotacatholic.org", \
        "a morning's fundraiser on two Sundays is one card, at its next"
    assert [i["place"] for i in got] == [
        "Catholic Charities – Emergency Services", "Franciscan Welcoming House", "Bouja Shack – St. Elizabeth Ann Seton School",
        "St. Wendelin Parish", "St. Clare Monastery", "St. Joseph Parish", "St. Boniface Parish"], \
        "the venue alone, its town on its own: the writer's place line is 'St. Wendelin Parish, Luxemburg'"
    assert "Knights of Columbus hosts" in got[5]["blurb"]
    assert (got[5]["trust"], got[5]["area"], got[5]["interest"]) == ("squishy", "announced", None)
    # Taizé's address with no map point names Little Falls; a far parish named for St. Joseph names Grey Eagle; the
    # virtual pause set at the monastery is still online.
    taize = "LOCATION:St. Francis Convent – Little Falls\\, 116 8th Ave SE"
    far = (ics.replace("GEO:45.9658516;-94.3627766\n", "")
           .replace("SUMMARY:Advent Lessons", "SUMMARY:Advent Vespers").replace(
               "LOCATION:Little Falls – Our Lady of Lourdes\\, 208 W. Broadway\\, Little Falls",
               "LOCATION:Church of St. Joseph\\, 1 Main St\\, Grey Eagle").replace("GEO:45.9777003;-94.3722855\n", "")
           .replace("LOCATION:MN\nCATEGORIES:Advent", "LOCATION:St. Benedict’s Monastery – St. Joseph\\, 104 Chapel Ln\\, "
                    "St. Joseph\\, MN\\, 56374\nGEO:45.5630238;-94.3195957\nCATEGORIES:Advent"))
    assert taize in far and "Grey Eagle" in far and far.count("GEO:45.5630238") == 1, "the fixture changed"
    assert [i["title"] for i in diocese_items(far, paper, src, day)] == [i["title"] for i in got], \
        "far ones stay out: Taizé with no map point, a St. Joseph-named parish in Grey Eagle, the virtual pause"
    # No map point: the town its address names decides alone. Taizé's convent in Little Falls (28 miles) is out; the
    # same sitting at a St. Cloud address is in.
    assert "GEO:45.9658516" not in far and "Taizé Prayer" not in {i["title"] for i in diocese_items(
        far, paper, src, day)}, "no map point and an address in a far town: out"
    in_town = far.replace("116 8th Ave SE\\, Little Falls\\, MN", "116 8th Ave SE\\, St. Cloud\\, MN")
    assert "Taizé Prayer" in {i["title"] for i in diocese_items(in_town, paper, src, day)}, \
        "no map point and an address in a nearby town: in"


def t_diocese_repeats():
    """What the paper repeats from a host Block Party reads stays that host's Event: the monastery's retreat, the City's
    Fare for All (live rows of 2026-11-13; the paper lists Fare for All at Resurrection Lutheran, 610 Co. Rd. 2)."""
    from write_judged import plan, interest_ids
    ev = lambda summary, start, end, place, url, geo="": (
        f"BEGIN:VEVENT\r\nDTSTART;TZID=America/Chicago:{start}\r\nDTEND;TZID=America/Chicago:{end}\r\nUID:{url}@x\r\n"
        f"SUMMARY:{summary}\r\nURL:https://thecentralminnesotacatholic.org/event/{url}/\r\nLOCATION:{place}\r\n{geo}END:VEVENT\r\n")
    ics = (ev("Grounding Our Emotions During Tough Times — St. Joseph\\, Spirituality Center", "20261117T090000",
              "20261117T113000", "St. Benedict’s Monastery – St. Joseph\\, 104 Chapel Ln\\, St. Joseph\\, MN\\, 56374",
              "grounding/2026-11-17", "GEO:45.5630238;-94.3195957\r\n")
           + ev("Fare for All — St. Joseph\\, Resurrection Lutheran Church", "20261207T153000", "20261207T173000",
                "Resurrection Lutheran Church\\, 610 Co. Rd. 2\\, St. Joseph\\, MN\\, 56374", "fare-for-all/2026-12-07"))
    listed = lambda title, day, at, place, host, uid, category: {
        "id": uid, "status": "approved", "title": title, "event_date": day, "start_time": at, "all_day": False,
        "location": place, "source_name": host, "source_uid": uid, "category": category, "shows_from": None,
        "review_reason": None, "cancelled_at": None, "found": True,
        "mentions": [{"source_name": host, "source_uid": uid, "source_url": "u", "trust": "official", "sure": True}]}
    have = [listed("Grounding Emotions in Tough Times", "2026-11-17", "9 AM", None, "Sisters of the Order of Saint Benedict",
                   "10000617-1794906000-1794913200@sbm.osb.org", "talks"),
            listed("Fare for All", "2026-12-07", "3:30 PM", "610 County Rd 2", "City of St. Joseph", "2336", "markets")]
    items = diocese_items(ics, {"_name": "The Central Minnesota Catholic events"}, {"url": "u", "trust": "squishy"},
                          date(2026, 11, 13))
    r = plan(items, have, date(2026, 11, 13), interest_ids())
    assert [o[0] for o in r["outcomes"]] == ["merged", "merged"], r["outcomes"]


def t_pathify():
    src = {"url": "https://my.csbsju.edu/api/v2/events/unauthenticated/?calendar=2,165,166,193,212,224"}
    got = pathify_items(json.loads(sample("csbsju-events.json")), {"_name": "CSB SJU events"}, src, TODAY)
    titles = [i["title"] for i in got]
    assert len(got) == 10 and titles.count("Free Art Prints from The Saint John's Bible") == 1, titles
    assert not any(w in t for t in titles for w in ("Barre", "Oja", "Dance Team", "Admission", "Exploration Fair")), \
        "classes, away games, halftime shows, visit days, career fairs"
    salvage = next(i for i in got if i["title"] == "Salvage")
    assert salvage["start"] == "2026-10-14T14:00:00-05:00" and salvage["town"] == "Collegeville" and salvage["interest"] is None
    rinks = pathify_items([
        {"id": 7, "title": "Saint John's University Hockey vs UW-Superior (Senior Night)", "location": "Herb Brooks National Hockey Center",
         "calendar": {"name": "SJU Athletics"}, "start_date": "2026-11-07T01:00:00Z", "all_day": False},
        {"id": 8, "title": "College of Saint Benedict Hockey vs Lake Forest", "location": "St. Cloud, Minn., Ritsche Arena",
         "calendar": {"name": "CSB Athletics"}, "start_date": "2026-11-07T01:00:00Z", "all_day": False},
        {"id": 9, "title": "Saint John's University Hockey at UW-Eau Claire", "location": "Hobbs Ice Arena - Eau Claire, Wis.",
         "calendar": {"name": "SJU Athletics"}, "start_date": "2026-11-08T01:00:00Z", "all_day": False}], {"_name": "x"}, src, TODAY)
    assert [(i["title"], i["place"], i["town"], i["start"]) for i in rinks] == [
        ("SJU Hockey vs UW-Superior: Senior Night", "St. Cloud, Minn., Herb Brooks National Hockey Center", "St. Cloud", "2026-11-06T19:00:00-06:00"),
        ("CSB Hockey vs Lake Forest", "St. Cloud, Minn., Ritsche Arena", "St. Cloud", "2026-11-06T19:00:00-06:00")], \
        "hockey's two home rinks count as home, an away rink doesn't"
    football = next(i for i in got if "Football" in i["title"])
    assert (football["town"], football["interest"], football["source_name"]) == ("Collegeville", "watch_sports", "SJU Athletics")
    homecoming = next(i for i in got if i["title"] == "Homecoming 2026")
    assert (homecoming["start"], homecoming["all_day"], homecoming["end"]) == ("2026-10-17", True, None), homecoming
    closed = next(i for i in got if "Closed" in i["title"])
    assert (closed["kind"], closed["category"], closed["start"]) == ("news", "campus", "2026-11-25"), closed
    sale = next(i for i in got if "Craft Sale" in i["title"])
    assert (sale["town"], sale["interest"], sale["source_name"]) == ("St. Cloud", "faith", "Saint Benedict's Monastery")
    home = pathify_items([{"id": 1, "title": "Rainbow Support Evening", "location": "104 Chapel Lane, Saint Joseph, MN, USA",
                           "calendar": {"name": "St. Benedict's Monastery"}, "start_date": "2026-11-13T01:00:00Z",
                           "all_day": False}], {"_name": "x"}, src, TODAY)[0]
    assert (home["place"], home["town"]) == ("Saint Benedict's Monastery", "St. Joseph"), home
    assert next(i for i in got if "Fix-It" in i["title"])["interest"] == "books"
    assert got[0]["source_url"].startswith("https://my.csbsju.edu/public/events/") and got[0]["area"] == "campus"
    mass, week = pathify_items([
        {"id": 2, "title": "9 p.m. Student Mass", "location": "Saint John's Abbey and University Church",
         "calendar": {"name": "Campus Events"}, "start_date": "2026-10-25T14:00:00Z", "end_date": "2026-10-25T15:00:00Z",
         "all_day": False},
        {"id": 3, "title": "Festival of Cultures", "location": "", "calendar": {"name": "Campus Events"},
         "start_date": "2026-11-09T06:00:00Z", "start_day": "2026-11-09", "end_date": "2026-11-14T23:59:59.999999Z",
         "all_day": True}], {"_name": "x"}, src, TODAY)
    assert (mass["start"], mass["end"]) == ("2026-10-25T21:00:00-05:00", "2026-10-25T22:00:00-05:00"), mass
    assert (week["start"], week["end"]) == ("2026-11-09", "2026-11-14"), week
    assert title_clock("Unplugged at 7", datetime(2026, 1, 1, 9), None) == (datetime(2026, 1, 1, 9), None)
    url = pathify_url(src["url"], TODAY)
    assert "calendar=2,165,166,193,212,224&in_range_after=2026-10-14T05:00:00Z&in_range_before=2027-01-12T06:00:00Z" in url, url
    assert "&field=description&" in url and "&field=ticket_url&" in url, url
    show = lambda i, day, hours, rule="FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA": {
        "id": i, "title": "Reflection: Selected Works", "location": "Benedicta Arts Center", "calendar": {"name": "Campus Events"},
        "start_date": f"{day}T16:00:00Z", "end_date": (datetime.fromisoformat(f"{day}T16:00:00+00:00") + timedelta(hours=hours)).isoformat(),
        "all_day": False, "recurrence_rule": rule}
    shown = pathify_items([show(10, "2026-11-11", 11), show(11, "2026-11-12", 11), show(12, "2026-12-14", 11),
                           dict(show(13, "2026-11-20", 2), recurrence_rule=None)], {"_name": "x"}, src, date(2026, 11, 11))
    assert [(i["start"][:10], i["end"], i["source_uid"]) for i in shown] == [
        ("2026-11-11", "2026-12-14", "run:Reflection: Selected Works"), ("2026-11-20", "2026-11-20T12:00:00-06:00", "13")], \
        "a show open for days is one Event to its last day; a one-off of its name is its own"
    play = pathify_items([dict(show(20, "2026-11-12", 2.5, "FREQ=WEEKLY;BYDAY=TH,FR,SA"), title="The Crucible"),
                          dict(show(21, "2026-11-13", 2.5, "FREQ=WEEKLY;BYDAY=TH,FR,SA"), title="The Crucible")],
                         {"_name": "x"}, src, date(2026, 11, 11))
    assert [i["source_uid"] for i in play] == ["20"], "a play's nights stay one card a night, at its next"
    retreat, talk = pathify_items([
        {"id": 4155871, "title": "Grounding Our Emotions", "location": "104 Chapel Lane, Saint Joseph, MN, USA",
         "calendar": {"name": "St. Benedict's Monastery"}, "start_date": "2026-11-03T15:00:00Z", "all_day": False,
         "ticket_url": "https://sbm.osb.org/event/grounding-our-emotions-during-tough-times/2026-11-03/"},
        {"id": 5, "title": "Salvage", "location": "Clemens Library", "calendar": {"name": "Library"},
         "start_date": "2026-11-03T20:00:00Z", "all_day": False, "ticket_url": ""}], {"_name": "x"}, src, TODAY)
    circle = pathify_items([{"id": 6, "title": "Contemplative Drumming Circle", "calendar": {"name": "Spiritual Life"},
                             "location": "14215 Fruit Farm Road, Collegeville, MN, USA", "all_day": False,
                             "start_date": "2026-12-01T23:30:00Z", "ticket_url": ""}], {"_name": "x"}, src, TODAY)[0]
    assert circle["place"] == "Episcopal House of Prayer, Collegeville", circle["place"]
    assert (retreat["source_url"], retreat["source_uid"]) == (
        "https://sbm.osb.org/event/grounding-our-emotions-during-tough-times/2026-11-03/", "4155871"), \
        "an Event with a sign-up page links to it, still known by the calendar's id"
    assert talk["source_url"] == "https://my.csbsju.edu/public/events/5", "no sign-up page: the calendar's own page"
    assert campus_blurb("<p>SJU Football vs Gustavus</p><p>Tickets: https://tickets.csbsju.edu/x</p>",
                        "SJU Athletics") is None, "a game shows no About"
    assert campus_blurb("", "Library") is None and campus_blurb(None, "Library") is None
    assert campus_blurb("<p class='a'><span>Join Purl &amp; Looped&mdash;the chillest knitting club!</span></p>\n"
                        "<p>&nbsp;</p><p>Monday, 4pm<br/>All are Welcome!</p>", "Library") \
        == "Join Purl & Looped—the chillest knitting club!\nMonday, 4pm\nAll are Welcome!", \
        "the organizer's words as plain text, a line to each paragraph"


def t_roads():
    features = json.loads(sample("511-features.json"))["features"]
    near = box(45.5647, -94.3183, 15)
    got = road_items(features + [dict(features[0], properties=dict(features[0]["properties"], active=False))],
                     {"_name": "Minnesota 511"}, {"trust": "official"}, near)
    assert [i["title"] for i in got] == ["MN 24 in both directions: Construction work near Clearwater"], \
        "Paynesville's closure is outside a 15-mile box; an ended report is dropped"
    assert got[0]["kind"] == "news" and got[0]["category"] == "road" and got[0]["start"] == "2026-08-10", got
    assert "Until November 20" in got[0]["blurb"] and "<" not in got[0]["blurb"]
    assert got[0]["source_url"] == "https://511mn.org/events/CARSx-129007" and got[0]["source_uid"] == "CARSx-129007"
    assert not road_items(features, {"_name": "Minnesota 511"}, {}, box(45.5647, -94.3183, 10))
    b = box(45.5647, -94.3183, 10)
    assert round(b["north"], 3) == 45.710 and round(b["west"], 3) == -94.525, b


def t_league_retries():
    real, calls, waits = fetch, [], []
    def flaky(answers):
        def f(u, timeout=None):
            calls.append(u)
            a = answers.pop(0)
            if isinstance(a, Exception):
                raise a
            return 200, a
        return f
    busy = urllib.error.HTTPError("u", 502, "Bad Gateway", {}, None)
    try:
        globals()["fetch"] = flaky([busy, TimeoutError("read"), busy, "ok"])
        assert league_fetch("u", waits.append) == "ok" and waits == [3, 10, 20] and len(calls) == 4
        globals()["fetch"] = flaky([busy, busy, busy, busy])
        try:
            league_fetch("u", waits.append)
            raise AssertionError("a fourth 502 is the school's failure")
        except urllib.error.HTTPError:
            pass
        calls.clear()
        globals()["fetch"] = flaky([urllib.error.HTTPError("u", 404, "Not Found", {}, None)])
        try:
            league_fetch("u", waits.append)
            raise AssertionError("a 404 is never retried")
        except urllib.error.HTTPError:
            assert len(calls) == 1
    finally:
        globals()["fetch"] = real


def t_kennedy_calendar():
    url = "https://kennedy.isd742.org/calendar?cal_date=2026-10-01"
    got = finalsite_calendar_items(sample("kennedy-calendar.html"), url, {"_name": "Kennedy Community School"},
                                   {"trust": "official", "own_calendar": "Kennedy Calendar"}, date(2026, 10, 1))
    titles = [i["title"] for i in got]
    assert titles == ["League of Women Voters School Board Candidate Forum", "Walkathon",
                      "School Board Meeting and Work Session", "PTO Meeting at the House",
                      "No School - MEA Conference", "Trunk or Treat"], titles
    forum, walk, _, pto, no_school, trunk = got
    assert (pto["followers_only"], pto["activity_team"], pto["activity_name"]) == (True, "kennedy", "PTO"), \
        "the PTO is for those following the school, and is the PTO's"
    assert not forum.get("followers_only") and not trunk.get("followers_only"), "a forum and Trunk or Treat are everyone's"
    assert "activity_team" not in forum and "activity_team" not in trunk, "an event naming no activity is none's"
    k = {"_name": "Kennedy Community School"}
    assert calendar_activity("Band/Choir/Orchestra Concert", k) == {"activity_team": "kennedy",
                                                                    "activity_name": "Band/Choir/Orchestra"}
    assert calendar_activity("Knowledge Bowl at Saint John's Prep 6-8 grades", k)["activity_name"] == "Knowledge Bowl"
    assert calendar_activity("Orchestra Solo/Ensemble", k)["activity_name"] == "Orchestra"
    assert calendar_activity("Art Club", k) == {"activity_team": "kennedy", "activity_name": "Art Club", "followers_only": True}
    assert calendar_activity("3rd Grade Concert", k) == {} and calendar_activity("Great Theatre-5th Grade", k) == {}
    assert SCHOOL_ONLY.search("Veterans Day Assembly") and SCHOOL_ONLY.search("Art Club")
    assert SCHOOL_ONLY.search("Grad Party Parent Meeting") and SCHOOL_ONLY.search("Kindergarten Signing Day")
    assert not SCHOOL_ONLY.search("School Board Meeting and Work Session") and not SCHOOL_ONLY.search("Winter Concert")
    assert (forum["start"], forum["end"], forum["place"]) == ("2026-10-06T19:00:00-05:00", "2026-10-06T20:30:00-05:00",
                                                             "District Administration Office"), forum
    assert (walk["start"], walk["all_day"]) == ("2026-10-07", True), walk
    assert (no_school["kind"], no_school["category"], no_school["start"], no_school["place"]) == ("news", "school", "2026-10-15", "")
    assert trunk["source_uid"] == "877919_2026-10-29T21:30:00Z_2026-10-29T23:00:00Z" and trunk["source_url"] == url
    assert trunk["place"] == "Kennedy Community School" and walk["place"] == "", "the school's own calendar is at the school"
    assert len(finalsite_calendar_items(sample("kennedy-calendar.html"), url, CITY, {}, TODAY)) == 2, "past days dropped"


def t_tech_calendar():
    """Tech's page shows District 742's calendar beside its own; Kennedy's gives the district's (BP app nothing-scheduled 01).
    A day box names its calendar; an all-day run only by its colour."""
    url = "https://tech.isd742.org/calendar?cal_date=2026-12-01"
    tech = {"_name": "Tech High School"}
    got = finalsite_calendar_items(sample("tech-calendar.html"), url, tech,
                                   {"trust": "official", "own_calendar": "Tech Calendar", "own_calendar_only": True},
                                   date(2026, 11, 13))
    assert [(i["start"][:10], i["title"]) for i in got] == [
        ("2026-12-05", "Snowball Dance"), ("2026-12-07", "Tech Winter Week"), ("2026-12-07", "Tech Band Concert")], got
    dance, week, band = got
    assert (band["activity_team"], band["activity_name"]) == ("tech", "Band"), "the band concert is Tech's Band's"
    assert (week["all_day"], week["end"]) == (True, "2026-12-11"), week
    every = finalsite_calendar_items(sample("tech-calendar.html"), url, tech, {"own_calendar": "Tech Calendar"}, date(2026, 11, 13))
    assert {"School Board Meeting", "No School - Winter Break"} <= {i["title"] for i in every}, "without the switch, all of it"


def t_csbsju_music():
    """The music department's season page (BP app nothing-scheduled 01): each performance on campus, its year by its
    weekday, on its ensemble's row at the college whose campus it is at."""
    url = "https://www.csbsju.edu/music/events-new/"
    music = {"_name": "CSB SJU Music"}
    got = music_items(sample("csbsju-music.html"), url, music, {"trust": "official"}, date(2026, 11, 13))
    row = lambda i: (i["start"], i["title"], i["place"], i["town"], i.get("activity_team"), i.get("activity_name"))
    assert [row(i) for i in got] == [
        ("2026-11-15T15:00:00-06:00", "An Afternoon of Organ and Voice: Greg Zelek and Emily Secor", "Abbey Church",
         "Collegeville", None, None),
        ("2026-11-16T18:00:00-06:00", "Student Piano Recital", "Great Hall", "Collegeville", None, None),
        ("2026-12-04T19:30:00-06:00", "Christmas with Saint Ben’s & Saint John’s", "The Great Hall", "Collegeville", None, None),
        ("2026-12-05T14:00:00-06:00", "Christmas with Saint Ben’s & Saint John’s", "The Great Hall", "Collegeville", None, None),
        ("2026-12-06T15:00:00-06:00", "All College Choir", "The Great Hall", "Collegeville", "saint-johns", "All-College Choir"),
        ("2026-12-08T19:30:00-06:00", "Faculty Recital: Gyehyun Jung", "Stephen B. Humphrey Auditorium", "Collegeville",
         None, None),
        ("2026-12-09T19:30:00-06:00", "Wind Ensemble Winter Concert", "Escher Auditorium", "St. Joseph",
         "saint-benedict", "Wind Ensemble"),
        ("2026-12-10T19:30:00-06:00", "Jazz Ensemble", "Colman Theatre", "St. Joseph", "saint-benedict", "Jazz Ensemble"),
        ("2026-12-11T19:30:00-06:00", "Guitar Ensemble & Studio Concert", "Gertken Organ Studio", "Collegeville",
         "saint-johns", "Guitar Ensemble")], [row(i) for i in got]
    guitar = got[-1]
    assert (guitar["area"], guitar["interest"], guitar["price"], guitar["source_url"], guitar.get("source_uid")) == (
        "campus", "live_music", "Free", url, None), guitar
    assert guitar["blurb"] == "The Guitar Ensemble and Guitar Studio perform works for guitar to finish the semester."
    assert "price" not in got[2], "Christmas is ticketed: no price the page gives"
    # Spring: a tour has no place, its home concert does; Minneapolis is off campus; past events are never read.
    spring = {i["title"]: i for i in music_items(sample("csbsju-music.html"), url, music, {}, date(2027, 2, 1))}
    assert "Orchestra at Minnesota Music Educators Association (MMEA)" not in spring and "Music and Mingling" not in spring
    home = spring["Chamber Choir Home Concert"]
    assert (home["start"], home["activity_team"], home["activity_name"]) == ("2027-02-28T19:30:00-06:00", "saint-johns",
                                                                             "Chamber Choir"), home
    assert spring["Women’s Choir Concert"]["activity_name"] == "Women's Choir", "the row's own name"
    assert not [i for i in spring.values() if i["start"] < "2027-02-01"], "the season's past is gone"
    assert "Orchestra Fall Concert" not in {i["title"] for i in music_items(sample("csbsju-music.html"), url, music, {},
                                                                           date(2026, 10, 1))}, "past events, never"
    # A run over days at one time, and a time span.
    run = ('<div class="wp-block-cover"><p class="has-text-align-center has-large-font-size">Vocal Performance Workshop</p>'
           '<p class="has-text-align-center wp-block-paragraph">Thursday, October 29 – Saturday, October 31<br>7:30 PM •<br>'
           'Colman Theatre, CSB</p></div><div class="wp-block-cover"><p class="has-large-font-size">Mingle</p>'
           '<p class="has-text-align-center">Friday, February 19, 7:00-9:00 PM •<br>Great Hall, SJU</p></div>')
    vpw, mingle = music_items(run, url, music, {}, date(2026, 10, 1)) + music_items(run, url, music, {}, date(2027, 2, 1))
    assert (vpw["start"], vpw["end"], vpw["activity_name"]) == ("2026-10-29T19:30:00-05:00", "2026-10-31",
                                                                "Vocal Performance Workshop"), vpw
    assert (mingle["start"], mingle["end"]) == ("2027-02-19T19:00:00-06:00", "2027-02-19T21:00:00-06:00"), mingle


def t_kennedy_news():
    got = finalsite_news_items(sample("kennedy-news.html"), "https://kennedy.isd742.org/kennedy-news",
                               {"_name": "Kennedy Community School"}, {"trust": "official"})
    assert [i["source_uid"] for i in got] == ["4558", "4557", "4554"], got
    assert got[0]["title"] == "Watch Recorded School Board Candidate Forum" and got[0]["blurb"] == "Watch the forum!"
    assert all(i["kind"] == "news" and i["category"] == "school" and "start" not in i for i in got)
    assert got[0]["source_url"].startswith("https://kennedy.isd742.org/kennedy-news/kennedy-news-stories/~board/")


def t_county():
    assert hcms_token(sample("stearns-home.html")) == "Bearer sample.token.not-real"
    src = {"token_page": "https://www.stearnscountymn.gov/", "trust": "official"}
    news, events = json.loads(sample("stearns-news.json")), json.loads(sample("stearns-events.json"))
    got = hcms_items(news, events, {"_name": "Stearns County"}, src, TODAY, TOWNS["st-joseph-mn"])
    assert [(i["kind"], i["title"]) for i in got] == [("news", "Offices Open October 12"),
                                                      ("event", "Park Commission Meeting")], got
    park = got[1]
    assert (park["start"], park["place"], park["area"]) == ("2026-10-14T18:00:00-05:00", "29709 Kipper Road, St Joseph", "town")
    assert got[0]["sure"] is True
    assert got[0]["blurb"] == "Monday, October 12, is Indigenous Peoples Day.", got[0]["blurb"]  # 75 characters, whole sentences
    assert news_line("Stearns County will celebrate the opening of its new Veteran Services Office in Melrose.") is None
    assert news_line("Meet in St. Joseph at the Legion for the annual pancake breakfast on Sunday morning.") is None
    assert news_line("Offices reopen at 8 a.m. Monday, Nov. 30, after the Thanksgiving holiday break.") is None
    assert news_line("Ribbon cutting Monday, Nov. 9, at noon. Drinks after.") == "Ribbon cutting Monday, Nov. 9, at noon. Drinks after."
    assert news_line("Open 8 a.m. to 4:30 p.m. Monday. A full list of observed holidays is on the county's page.") == \
        "Open 8 a.m. to 4:30 p.m. Monday."
    crime = {"items": [{"id": "x", "data": {"title": {"en": "Someone Indicted for Assault"}, "Date": {"iv": "2026-10-13T05:00:00Z"}}}]}
    assert hcms_items(crime, {}, {"_name": "Stearns County"}, src, TODAY, TOWNS["st-joseph-mn"])[0]["sure"] is False
    older = hcms_items(news, {}, {"_name": "Stearns County"}, src, date(2026, 8, 21), TOWNS["st-joseph-mn"])
    assert "Public Notice of Regional Rail Authority Board Meeting" in [i["title"] for i in older]
    # Outdoor U's programs at SJU's street address land at Outdoor U (2026-11-03); the address alone stays as read.
    def at_abbey_plaza(uid, about):
        return {"id": uid, "data": {"title": {"en": "Animal Tracking"}, "description": {"en": about},
                "eventdate": {"iv": {"startDate": "2026-10-24T18:00:00Z", "endDate": "2026-10-24T20:00:00Z"}},
                "location": {"iv": {"address1": "2850 Abbey Plaza", "city": "St Joseph", "zip": "56374"}}}}
    got = hcms_items({}, {"items": [at_abbey_plaza("u", "<p>Join Saint John&#39;s Outdoor University in the Arboretum.</p>"),
                                    at_abbey_plaza("a", "<p>Vespers in the Abbey Church.</p>")]},
                     {"_name": "Stearns County"}, src, TODAY, TOWNS["st-joseph-mn"])
    assert [i["place"] for i in got] == ["Outdoor U, SJU", "2850 Abbey Plaza, St Joseph"], got
    from write_judged import plan, interest_ids
    assert plan(got[:1], [], TODAY, interest_ids())["events"][0]["row"]["place_entry_id"] == "sju"
    url = hcms_url("https://content.civicplus.com/api/content/mn-stearnscounty/", "news", 20, "data/Date/iv desc", "a eq b")
    assert url.endswith("/mn-stearnscounty/news?%24top=20&%24skip=0&%24orderby=data%2FDate%2Fiv%20desc&%24filter=a%20eq%20b"), url


LEAGUE_DAY = date(2026, 10, 15)
SCHOOLS = {"sartell": ("Sartell High School", 504, "Sartell"), "tech": ("Tech High School", 537, "St. Cloud Tech"),
           "cathedral": ("Cathedral High School", 535, "St. Cloud Cathedral"),
           "holdingford": ("Holdingford High School", 246, "Holdingford")}


def league_sample(change=lambda school, r: r):
    """The saved schedules (read 2026-10-15) as every school's listings."""
    sports, out = league_sports(sample("mshsl-page.html"), LEAGUE_DAY), []
    for school, rows in json.loads(sample("mshsl-schedules.json")).items():
        name, league_id, team = SCHOOLS[school]
        src = {"url": f"{LEAGUE}/group/{league_id}/full-schedule", "league_id": league_id, "team": team}
        out += league_listings([change(school, dict(r)) for r in rows], sports, {"_name": name}, src, LEAGUE_DAY)
    return out


def t_league():
    sports = league_sports(sample("mshsl-page.html"), LEAGUE_DAY)
    assert sorted(sports) == [128, 133, 142, 146, 153], "in season within four weeks; baseball, boys swim, music not"
    assert [sports[a][1] for a in (142, 153, 146)] == ["Girls Soccer", "Volleyball", "Girls Swim"], sports
    got, left = games(league_sample(), LEAGUE_DAY)
    rows = {i["title"]: i for i in got}
    assert list(rows) == ["Sartell Girls Soccer vs St. Cloud", "Tech Girls Swim vs Sartell",
                          "Central Lakes Conference Diving Meet", "Central Lakes Conference Swim Meet",
                          "Section 6A Girls Swim Meet"], list(rows)
    soccer = rows["Sartell Girls Soccer vs St. Cloud"]
    assert (soccer["start"], soccer["place"], soccer["town"], soccer["source_name"], soccer["area"]) == (
        "2026-10-15T19:00:00-05:00", "Sartell High School", "Sartell", "Sartell High School", "game"), soccer
    assert soccer["source_uid"] == "mshsl:142:sartell|st. cloud:2", "the second meeting this season"
    assert soccer["source_url"] == f"{LEAGUE}/group/504/full-schedule" and soccer["interest"] == "watch_sports"
    assert rows["Tech Girls Swim vs Sartell"]["source_name"] == "Tech High School", "the home school hosts"
    # The game card's teams and sport (game-card 01), the host first, as neighbours say them.
    assert soccer["game"] == {"sport": "Girls Soccer", "teams": ["Sartell", "St. Cloud"]}, soccer
    assert rows["Tech Girls Swim vs Sartell"]["game"] == {"sport": "Girls Swim", "teams": ["Tech", "Sartell"]}
    section = rows["Section 6A Girls Swim Meet"]
    assert (section["start"], section["all_day"], section["size"]) == ("2026-11-12", True, "notable"), section
    assert "game" not in section, "a meet names no two teams"
    assert (left["lower"], left["waiting"]) == (1, 4), "the JV diving meet; a vs and three TBD playoff rows"
    assert "Robbinsdale Cooper High School" in left["unplaced"] and "Upsala High School" in left["unplaced"]
    # Read only from the visitors' schedule, the home team still goes first.
    visitors = [l for l in league_sample() if l["lister"] == "Tech High School" and l["activity"] == 142]
    only = games(visitors, LEAGUE_DAY)[0]
    assert [(i["title"], i["source_name"]) for i in only] == [("Sartell Girls Soccer vs St. Cloud", "Sartell High School")]
    assert only[0]["source_uid"] == soccer["source_uid"]


def t_league_tournament_and_moves():
    home = league_sample(lambda s, r: dict(r, location="Holdingford High School") if s == "holdingford" else r)
    day = [i for i in games(home, LEAGUE_DAY)[0] if "Volleyball" in i["title"]]
    assert [(i["title"], i["start"], i["source_name"]) for i in day] == [
        ("Upsala MEA Varsity Volleyball Tournament", "2026-10-15T09:00:00-05:00", "Holdingford High School")], day
    moved = league_sample(lambda s, r: dict(r, event_date="10/16/2026", event_time="5:00 PM")
                          if r["event_date"] == "10/15/2026" and r["mshsl_activity_id"] == 142 else r)
    soccer = next(i for i in games(moved, LEAGUE_DAY)[0] if "Soccer" in i["title"])
    assert (soccer["start"], soccer["source_uid"]) == ("2026-10-16T17:00:00-05:00", "mshsl:142:sartell|st. cloud:2"), \
        "a moved game keeps its id, so the writer moves its Event"
    assert league_start(LEAGUE_DAY, "12:00 AM") == ("2026-10-15", True)



def t_league_dance_show():
    """A dance show is one Event, not a game per team and per dance (jazz and high kick are two
    league activities): "Crush Dance Show" made four "vs" Events on 2026-10-22."""
    show = [{"lister": lister, "page": f"{LEAGUE}/group/635/full-schedule", "activity": a, "family": "Dance Team",
             "sport": "Dance Team", "day": LEAGUE_DAY, "time": "10:00 AM", "team": team,
             "opponent": "Crush Dance Show", "named": bool(NAMED.search("Crush Dance Show")),
             "venue": "St. Cloud Apollo High School", "n": 1}
            for lister, team in (("Apollo High School", "St. Cloud Apollo"), ("Tech High School", "St. Cloud Tech"))
            for a in (126, 346)]
    got = games(show, LEAGUE_DAY)[0]
    assert [(i["title"], i["source_name"]) for i in got] == [("Crush Dance Show", "Apollo High School")], got


def t_league_conference_meet():
    """"CLC Dance Team" is the Central Lakes Conference's dance meet, not a team: on 2026-11-06 the league's Dec 4
    meet at Tech was five games against it, and the writer made it a team (BP app game-card 19)."""
    sports = {126: ("Dance Team", "Dance Team", "2026-11-01", "2027-02-28")}
    rows = [{"event_date": "12/04/2026", "event_time": "7:00 PM", "mshsl_activity_id": 126, "school_name": team,
             "opponent": "CLC Dance Team", "location": "St. Cloud Tech High School"}
            for team in ("St. Cloud Tech", "St. Cloud Apollo", "Sartell", "ROCORI", "Sauk Rapids-Rice")]
    day = date(2026, 11, 10)
    listings = [l for n, r in enumerate(rows) for l in league_listings(
        [r], sports, {"_name": f"School {n}"}, {"url": f"{LEAGUE}/group/{n}/full-schedule"}, day)]
    got = games(listings, day)[0]
    assert [(i["title"], i["source_name"], "game" in i) for i in got] == [
        ("CLC Dance Team", "Tech High School", False)], got

def t_league_undecided_opponent():
    """"St. Cloud Apollo OR Little Falls" is a bracket not played out yet: the game waits, and makes
    no team (Jesse, 2026-10-26)."""
    row = {"lister": "Sartell High School", "page": f"{LEAGUE}/group/504/full-schedule", "activity": 142,
           "family": "Soccer", "sport": "Girls Soccer", "day": LEAGUE_DAY, "time": "7:00 PM", "team": "Sartell",
           "opponent": "St. Cloud Apollo OR Little Falls", "named": False, "venue": "Sartell High School", "n": 1}
    got, left = games([row], LEAGUE_DAY)
    assert got == [] and left["waiting"] == 1, (got, left)


def t_league_schedule_line():
    def school(s, e, t):
        return [{"listing": l} for l in league_sample() if l["lister"] == e["_name"]]
    def down(*_):
        raise TimeoutError("the league took too long")
    entries = [{"_name": n, "sources": [{"url": "u", "reader": "mshsl"}]} for n in ("Tech High School", "Sartell High School")]
    items, summary = read_all(entries, LEAGUE_DAY, {"mshsl": school})
    line = items[-1]
    assert line == {"kind": "schedule", "uid_prefix": "mshsl:", "from": "2026-10-15", "through": "2026-11-12",
                    "sources": ["Sartell High School", "Tech High School"]}, line
    assert [s["reader"] for s in summary] == ["mshsl", "mshsl", "games"] and "outside 20 miles" in summary[-1]["note"]
    items, _ = read_all(entries, LEAGUE_DAY, {"mshsl": lambda s, e, t: down() if e["_name"] == "Tech High School" else school(s, e, t)})
    assert not [i for i in items if i["kind"] == "schedule"], "a school not read: no game is called off this morning"
    assert any(i["title"] == "Sartell Girls Soccer vs St. Cloud" for i in items), "the other school's games still come"
    # A school whose schedule shows 0 games is left off the line, so its games stay; the others' still go.
    items, summary = read_all(entries, LEAGUE_DAY, {"mshsl": lambda s, e, t: [] if e["_name"] == "Tech High School" else school(s, e, t)})
    assert items[-1]["kind"] == "schedule" and items[-1]["sources"] == ["Sartell High School"], items[-1]
    assert "0 games" in summary[0]["note"], summary[0]
    items, _ = read_all(entries, LEAGUE_DAY, {"mshsl": lambda *_: []})
    assert not [i for i in items if i["kind"] == "schedule"], "no school showed a game: nothing is called off"


def t_parts():
    """Timed parts on a fake clock against a slow league and slow Bound calendars: each part reads
    what it can, the next reads the rest from what the last saved, each source once, and the games
    and the one jazz festival three schools list are one long read's."""
    import run
    clock, reads = type("Clock", (), {"t": 0.0, "monotonic": lambda self: self.t})(), []
    jazz = ("BEGIN:VEVENT\r\nDTSTART;TZID=America/Chicago:20261120T190000\r\nGEO:45.570271;-94.210471\r\n"
            "LOCATION:St. Cloud Tech High School Performing Arts Center\r\nSTATUS:CONFIRMED\r\n"
            "SUMMARY:Jazzband: Central Lakes Jazz Festival (Varsity)\r\nUID:j1\r\nURL:https://gobound.com/direct/comps/j1/show"
            "\r\nX-BND-ACTIVITYKEY:jazzband\r\nX-BND-ACTIVITYLEVEL:Varsity\r\nX-BND-ACTIVITYNAME:Jazz Band\r\nEND:VEVENT\r\n")

    def slow(read):
        def reader(s, e, t):
            reads.append(s["url"])
            clock.t += 100
            return read(s, e, t)
        return reader
    readers = {"mshsl": slow(lambda s, e, t: [{"listing": l} for l in league_sample() if l["lister"] == e["_name"]]),
               "gobound": slow(lambda s, e, t: bound_items(jazz, e, s, t))}
    entries = [{"_name": n, "sources": [{"url": f"{r}:{n.split()[0]}", "reader": r, "trust": "official"}]}
               for r, names in (("mshsl", ("Tech High School", "Sartell High School", "Cathedral High School")),
                                ("gobound", ("Apollo High School", "Tech High School", "Sartell High School")))
               for n in names]
    whole, was = read_all(entries, LEAGUE_DAY, readers)[0], run.time
    try:
        run.time, saved, parts = clock, {}, []
        while len(saved) < len(entries) and len(parts) < 5:
            n = len(reads)
            items, _ = read_all(entries, LEAGUE_DAY, readers, saved, deadline(2))
            parts.append(reads[n:])
            saved = json.loads(json.dumps(saved, default=str))  # the part's file
    finally:
        run.time = was
    assert parts == [["mshsl:Tech", "mshsl:Sartell"], ["mshsl:Cathedral", "gobound:Apollo"],
                     ["gobound:Tech", "gobound:Sartell"]], parts
    assert [i["source_name"] for i in items if "Jazz" in i.get("title", "")] == ["Tech High School"], "one festival, its venue's"
    assert items == whole and items[-1]["kind"] == "schedule", "the same games and schedule line as one long read"


def t_nearby_hosts_are_registry_schools():
    names = {e["_name"]: s for e in load(find_root(Path(__file__).resolve().parent))[0] for s in e.get("sources") or []
             if s.get("reader") == "mshsl"}
    hosts = {h for _, h in NEARBY.values() if h}
    assert hosts <= set(names), hosts - set(names)
    assert len(names) == 12 and all(s.get("league_id") and s.get("team") for s in names.values()), names


def t_rec1():
    """The City's rec catalog, read 2026-10-24: each dated program once, at its next date."""
    src = {"url": "https://secure.rec1.com/MN/st-joseph-mn/catalog", "trust": "official"}
    got = {i["title"]: i for i in rec1_items(json.loads(sample("rec1-catalog.json")), CITY, src, date(2026, 10, 24))}
    assert sorted(got) == ["Chanhassen Dinner Theatre Day Trip", "Fall Craft Day", "Fall Puzzle Competition",
                           "Halloween Adult Dodgeball Tournament", "Pilates Class", "Winter Paint and Sip",
                           "Youth dodgeball", "Youth volleyball"], sorted(got)
    paint, pilates = got["Winter Paint and Sip"], got["Pilates Class"]
    assert (paint["start"], paint["end"], paint["place"]) == ("2026-12-11T19:00:00-06:00", "2026-12-11T21:00:00-06:00",
                                                             "Bad Habit Brewing Co"), paint
    assert (paint["blurb"], paint["price"]) == ("Sign up on the City's registration site.", "$50") and paint["source_uid"].startswith("rec1:")
    assert pilates["start"] == "2026-10-26T10:00:00-05:00", "a weekly run is read at its next Monday"
    assert got["Fall Puzzle Competition"]["place"] == "", "Location TBD is no place"
    assert (got["Chanhassen Dinner Theatre Day Trip"]["blurb"], got["Chanhassen Dinner Theatre Day Trip"]["price"]) == \
        ("Sign up on the City's registration site.", "$91"), "a shared group text is left out; the fee is the price"
    # Only a fee of 0 says Free; a session with no price, or a null one, is unknown, and the page then shows none.
    paint_group = next(g for g in json.loads(sample("rec1-catalog.json")) if g["sessions"][0]["text"] == "Winter Paint and Sip")
    priced = lambda **price: rec1_items([{**paint_group, "sessions": [{**{k: v for k, v in paint_group["sessions"][0].items()
                                                                          if k != "price"}, **price}]}],
                                        CITY, src, date(2026, 10, 24))[0]["price"]
    assert (priced(price=0), priced(), priced(price=None), priced(price=12.5)) == ("Free", None, None, "$12.5")
    assert rec1_next("10/06-12/29", "Mon", date(2026, 12, 30)) is None and rec1_next("Open TBD", "", TODAY) is None
    assert rec1_next("12/28-01/04", "Sat", date(2026, 12, 29)) == date(2027, 1, 2), "a run over New Year"
    assert rec1_clock("9:30am") == (9, 30) and rec1_clock("12pm") == (12, 0) and rec1_clock("TBD") is None


def t_part_file():
    """main in timed parts, on a fake clock: the first reads one source and says run again, with what it read in
    the part's file; the next reads only the other, then writes every item."""
    import contextlib, io, run, sys as system, tempfile
    global load, find_root
    clock = type("Clock", (), {"t": 1000.0, "monotonic": lambda self: self.t, "time": lambda self: self.t})()
    reads = []

    def slow(s, e, t):
        reads.append(s["url"])
        clock.t += 200
        return [{"kind": "news", "title": s["url"], "source_name": e["_name"]}, {"listing": {"day": TODAY}}]  # a date, as the league's
    entries = [{"_name": n, "_town": "st-joseph-mn", "status": "active", "sources": [{"url": f"https://{n}", "reader": "slow"}]}
               for n in ("a", "b")]
    saved = load, find_root, system.argv, run.time
    READERS["slow"] = slow
    try:
        with tempfile.TemporaryDirectory() as tmp:
            part, got = Path(tmp) / "part.json", Path(tmp) / "items.jsonl"
            load, find_root, run.time = (lambda root: (entries, [])), (lambda *a: Path(tmp)), clock
            system.argv = ["read_events.py", "--part", str(part), "--items", str(got), "--minutes", "1", "--today", "2026-11-03"]
            said = [io.StringIO(), io.StringIO()]
            with contextlib.redirect_stdout(said[0]):
                main()
            kept, written = json.loads(part.read_text()), got.exists()
            with contextlib.redirect_stdout(said[1]):
                main()
            items = [json.loads(ln)["title"] for ln in got.read_text().splitlines()]
    finally:
        load, find_root, system.argv, run.time = saved
        del READERS["slow"]
    assert said[0].getvalue() == "[read] run again: 1 of 2 sources read\n" and not written, said[0].getvalue()
    assert list(kept["sources"]) == ["a|https://a"] and "robots" in kept["state"], kept
    assert reads == ["https://a", "https://b"] and items == ["https://a", "https://b"], (reads, items)


def t_failure_in_summary():
    def boom(*_):
        raise TimeoutError("the site took too long")
    entry = {"_name": "Somewhere", "sources": [{"url": "https://a", "reader": "boom"}, {"url": "https://b", "reader": "fine"},
                                               {"url": "https://c", "kind": "website", "method": "fetch"}]}
    items, summary = read_all([entry], TODAY, {"boom": boom, "fine": lambda s, e, t: [{"title": "x"}]})
    assert items == [{"title": "x"}] and len(summary) == 2, (items, summary)
    assert "TimeoutError" in summary[0]["error"] and summary[1] == dict(summary[1], items=1, error=None), summary


def t_items_fit_the_writer():
    from write_judged import plan, interest_ids
    entry = {"_name": "Kennedy Community School"}
    items = (pathify_items(json.loads(sample("csbsju-events.json")), entry, {"url": "https://my.csbsju.edu/api"}, TODAY)
             + road_items(json.loads(sample("511-features.json"))["features"], entry, {}, box(45.5647, -94.3183, 30))
             + finalsite_calendar_items(sample("kennedy-calendar.html"), "u", entry, {}, TODAY)
             + finalsite_news_items(sample("kennedy-news.html"), "u", entry, {})
             + hcms_items(json.loads(sample("stearns-news.json")), json.loads(sample("stearns-events.json")),
                          {"_name": "Stearns County"}, {"token_page": "u"}, TODAY, TOWNS["st-joseph-mn"])
             + games(league_sample(), LEAGUE_DAY)[0]
             + diocese_items(sample("diocese-calendar.ics"), entry, {"url": "u", "trust": "squishy"}, TODAY))
    r = plan(items, [], TODAY, interest_ids())
    bad = [(i["title"], o) for i, o in zip(items, r["outcomes"]) if o[0] == "skipped"]
    # "kept apart" and "place not in the registry" are reports for Jesse, not failures.
    assert not bad and not [n for n in r["notes"] if "kept apart" not in n and "not in the registry" not in n], (bad, r["notes"])
    rows = {g["row"]["title"]: g["row"] for g in r["events"]}
    assert rows["SJU Football vs Concordia: Homecoming"]["location"] == "Clemens Stadium, Collegeville"
    assert rows["Fix-It Clinic"]["location"] == "Clemens Library", "St. Joseph needs no town on its place line"
    assert rows["Christmas Craft Sale at Saint Scholastica Convent"]["location"] == "Saint Scholastica Convent, St. Cloud"
    assert rows["Tech Girls Swim vs Sartell"]["location"] == "St. Cloud Tech High School", "the venue already names its town"
    assert rows["Sartell Girls Soccer vs St. Cloud"]["category"] == "watch_sports"
    lines = {(g["row"]["title"], g["row"]["location"]) for g in r["events"] if g["row"]["source_name"] in (
        "St. Anne’s Christian Women of Luxemburg", "Knights of Columbus", "Church of St. Boniface", "Catholic Charities")}
    assert lines == {("Breakfast", "St. Wendelin Parish, Luxemburg"), ("Breakfast", "St. Joseph Parish"),
                     ("Christmas Concert", "St. Boniface Parish, Cold Spring"),
                     ("Toys for Tots Collection", "Catholic Charities – Emergency Services, St. Cloud")}, lines


def t_gobound():
    def ev(uid, summary, key="", level="", name="", geo="45.570271;-94.210471", status="CONFIRMED",
           start="20261120T190000", place="St. Cloud Apollo High School Performing Arts Center"):
        return (f"BEGIN:VEVENT\r\nDTSTART;TZID=America/Chicago:{start}\r\nGEO:{geo}\r\nLOCATION:{place}\r\n"
                f"STATUS:{status}\r\nSUMMARY:{summary}\r\nUID:{uid}\r\nURL:https://gobound.com/direct/comps/{uid}/show\r\n"
                f"X-BND-ACTIVITYKEY:{key}\r\nX-BND-ACTIVITYLEVEL:{level}\r\nX-BND-ACTIVITYNAME:{name}\r\nEND:VEVENT\r\n")
    ics = "".join([
        ev("a1", "Drama: Apollo Theater Presents: The SpongeBob Musical (Varsity)", "theatre", "Varsity", "Drama"),
        ev("a2", "Volleyball\\, Girls: Brainerd vs St. Cloud Apollo (Varsity)", "volleyball", "Varsity", "Volleyball\\, Girls"),
        ev("a3", "Apollo Boys Soccer Season Pass", "soccer", "", "Soccer\\, Boys"),
        ev("a4", "Choir: Apollo Choir Concert (Varsity)", "choir", "Varsity", "Choir", status="CANCELLED"),
        ev("a5", "Band: Detroit Lakes Band Festival (Varsity)", "band", "Varsity", "Band", geo="46.808275;-95.837446"),
        ev("a6", "Choir:  vs  (Fall Show)", "choir", "Fall Show", "Choir"),
        ev("a7", "Choir:  vs  (High School Choir)", "choir", "High School Choir", "Choir"),
        ev("a8", "Fall Play", start="20261029T190000"),
        ev("a9", "Prom", start="20270501T190000"),
        ev("a10", 'SRRHS Fall Musical\\, "Disney\\, The Little Mermaid"', start="20261112T190000"),
        ev("k1", "Soccer\\, Boys: Melrose Area vs Kennedy Community MS (Middle School)", "soccer", "Middle School",
           "Soccer\\, Boys", place="Kennedy Community School Kennedy Field"),
        ev("k2", "Volleyball\\, Girls: TBD vs Kennedy Community MS (Middle School)", "volleyball", "Middle School",
           "Volleyball\\, Girls"),
        ev("k3", "Basketball\\, Girls: Holdingford vs Kennedy Community MS (Middle Sc", "basketball", "Middle School",
           "Basketball\\, Girls", place="Kennedy Community School Kennedy Field"),
        ev("a11", "Volleyball\\, Girls: Brainerd vs St. Cloud Apollo (Junior Varsity)", "volleyball", "Junior Varsity",
           "Volleyball\\, Girls"),
        ev("a12", "Volleyball\\, Girls: St. Cloud Apollo vs Fergus Falls (Varsity)", "volleyball", "Varsity",
           "Volleyball\\, Girls", geo="46.283016;-96.077558", place="Fergus Falls High School Gold Gym"),
        ev("a13", "Volleyball\\, Girls: Volleyball Banquet (Varsity)", "volleyball", "Varsity", "Volleyball\\, Girls"),
        # Real ones from the first dry run (2026-10-26): no activity, a banquet a show word matched,
        # an empty name, a meet named only "Competition".
        ev("a14", "No School"), ev("a15", "Boys Soccer Banquet - Play Soccer"),
        ev("a16", "Wrestling:", "wrestling", "", "Wrestling"),
        ev("a17", "Robotics: Competition", "robotics", "", "Robotics"),
        # A meet sport's event posted with only who goes (Sartell's "Girls Varsity" wrestling, Dec 18-19), and a
        # team sport's, a game with no opponent yet.
        ev("a18", "Wrestling:  vs  (Girls Varsity)", "wrestling", "Girls Varsity", "Wrestling", place=""),
        ev("a19", "Wrestling:", "wrestling", "Boys MS", "Wrestling"),
        ev("a20", "Basketball\\, Girls:  vs  (Girls Varsity)", "basketball", "Girls Varsity", "Basketball\\, Girls"),
        ev("a21", "Hockey\\, Boys: River Lakes vs  (Varsity)", "hockey", "Varsity", "Boys Hockey", geo="46.867588;-96.880953"),
        ev("a22", "Art Club"),
    ])
    src = {"url": "https://www.gobound.com/mn/schools/stcloudapollo/calendar/ical", "trust": "official"}
    got = bound_items(ics, {"_name": "Apollo High School"}, src, date(2026, 10, 25))
    events = [i for i in got if i["kind"] == "event"]
    # Everyone's: the plays and concerts within 20 miles. Followers only: the band festival 170 miles off, a middle school
    # game that isn't Apollo's level, the JV game, the varsity game away, the banquet, a club (school-activities 03). The varsity game at home
    # stays the league's; the season pass and the cancelled concert stay out.
    assert [(i["title"], i["followers_only"]) for i in events] == [
        ("The SpongeBob Musical", False), ("Detroit Lakes Band Festival", True),
        ("Fall Show", False), ("Fall Play", False), ("The Little Mermaid", False),
        ("Kennedy Boys Soccer vs Melrose · MS", True), ("Kennedy Basketball vs Holdingford · MS", True),
        ("Apollo Volleyball vs Brainerd · JV", True), ("Fergus Falls Volleyball vs Apollo", True),
        ("Volleyball Banquet", True), ("Boys Soccer Banquet - Play Soccer", True),
        ("Robotics Competition", False), ("Apollo Girls Wrestling Meet", True),
        ("Apollo Boys Wrestling Meet · MS", True), ("Art Club", True)], events
    assert [(i["activity_team"], i["activity_name"]) for i in events[:2]] == [("apollo", "Drama"), ("apollo", "Band")]
    # Bound's own activity first, else the one its title names: Sauk Rapids-Rice's musical, a club (school-search 07).
    named = {i["title"]: i["activity_name"] for i in events}
    assert (named["The Little Mermaid"], named["Art Club"], named["Fall Play"]) == ("Musical", "Art Club", None), named
    assert events[8]["area"] == "announced", "an away game isn't the writer's 20-mile game"
    assert got[0]["source_uid"] == "bound:a1" and got[0]["start"] == "2026-11-20T19:00:00-06:00"
    assert got[-1] == {"kind": "schedule", "uid_prefix": "bound:", "from": "2026-10-25", "through": "2027-01-23",
                       "sources": ["Apollo High School"]}, "the schedule line: a dropped event was called off"
    # Lines read from the seven schools' calendars on 2026-11-04.
    def one(summary, key, level, name, place="Sartell High School Gym"):
        got = bound_items(ev("r1", summary, key, level, name, place=place), {"_name": "Sartell High School"}, src,
                          date(2026, 10, 25))
        return got[0] if got else None
    for summary, name, level, want in [
            ("Nordic Ski Racing\\, Boys: Section Championship (Varsity)", "Nordic Ski Racing\\, Boys", "Varsity",
             "Section Nordic Skiing Championship"),
            ("Wrestling: Pierz Tri (Varsity)", "Wrestling", "Varsity", "Pierz Wrestling Tri"),
            ("Dance: Best of the Best (Varsity)", "Dance", "Varsity", "Best of the Best Dance"),
            ("Swimming and Diving\\, Boys: StormHawk Invitational 2026 (Varsity)", "Swimming and Diving\\, Boys", "Varsity",
             "StormHawk Swim Invitational 2026"),
            ("Girls Nordic Ski: Central Lakes Nordic Championship (Varsity)", "Girls Nordic Ski", "Varsity",
             "Central Lakes Nordic Championship"),
            ("Dance: Conference Kick (Varsity)", "Dance", "Varsity", "Conference Kick"),
            ("Dance: Edina Invite (Varsity) (Time TBA)", "Dance", "Varsity", "Edina Dance Invite"),
            # Two levels of one meet say which (2026-11-05, ROCORI's and Sartell's calendars).
            ("Dance: Albany Dance Invitational (Junior Varsity)", "Dance", "Junior Varsity", "Albany Dance Invitational · JV"),
            ("Competitive Dance: Albany Dance Invitational (Varsity)", "Competitive Dance", "Varsity",
             "Albany Dance Invitational"),
            ("Wrestling: Mora Invitational (Girls Varsity)", "Wrestling", "Girls Varsity", "Mora Wrestling Invitational · Girls"),
            ("Wrestling: Girls Sectional (Girls JV)", "Wrestling", "Girls JV", "Girls Sectional Wrestling · JV"),
            ("Wrestling: Defender Invite (Middle School)", "Wrestling", "Middle School", "Defender Wrestling Invite · MS"),
            ("Dance: Conference Kick (High Kick JV)", "Dance", "High Kick JV", "Conference Kick · JV"),
            ("Dance: Conference Kick (High Kick V)", "Dance", "High Kick V", "Conference Kick"),
            ("Dance: Junior Varsity Jazz Dance (Jazz JV)", "Dance", "Jazz JV", "Junior Varsity Jazz Dance"),
            ("Wrestling: Wrestling Invitational (Girls JH)", "Wrestling", "Girls JH", "Wrestling Invitational")]:
        assert one(summary, name.split("\\")[0].split()[0].lower(), level, name)["title"] == want, summary
    game = one("Basketball\\, Boys: Osseo vs St. Cloud Tech (B) (Time TBA)", "basketball", "B", "Basketball\\, Boys")
    assert game["game"]["teams"][0] == "Tech" and "TBA" not in game["title"], game["title"]
    assert one("Nordic Ski Racing\\, Girls: (JV) (Time TBA)", "nordic", "JV", "Nordic Ski Racing\\, Girls") is None, \
        "no name and no time: nothing to show"
    assert one("Theatre: vs St. Cloud Cathedral (Winter Show)", "theatre", "Winter Show", "Theatre")["title"] == "Winter Show", \
        "a show has no opponent: its level names it"
    for raw, want in [("ROCORI High School High School Gym North Court #3", "ROCORI High School Gym North Court #3"),
                      ("St. Cloud Tech High School Gym Gym-West Court", "St. Cloud Tech High School Gym-West Court"),
                      ("Foley High School Foley High School Main Gym", "Foley High School Main Gym"),
                      ("Foley Intermediate School Foley Field House Field House - Court 1",
                       "Foley Intermediate School Foley Field House - Court 1"),
                      ("Long Prairie-Grey Eagle High School High School: Main Gym",
                       "Long Prairie-Grey Eagle High School: Main Gym"),
                      ("Paynesville Area High School Middle School Gym", "Paynesville Area High School Middle School Gym")]:
        got = one("Wrestling: Pierz Tri (Varsity)", "wrestling", "Varsity", "Wrestling", place=raw)
        assert got["place"] == want, got["place"]
    about = one("Basketball\\, Boys: Osseo vs St. Cloud Tech (B)", "basketball", "B", "Basketball\\, Boys",
                place="ROCORI High School High School Gym")["blurb"]
    assert "High School High School" not in about, about
    for empty in ("BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n", ev("p1", "Apollo Boys Soccer Season Pass", "soccer")):
        assert bound_items(empty, {"_name": "Apollo High School"}, src, date(2026, 10, 25)) == [], \
            "a schedule with nothing on it calls nothing off"
    kennedy = bound_items(ics, {"_name": "Kennedy Community School"}, {**src, "game_levels": ["Middle School"]},
                          date(2026, 10, 25))
    game = [i for i in kennedy if "game" in i]
    # The home team first, as the league's (Bound names the visitors first); too long for both, the
    # school's own team leaves the title, since the host line names it (smooth-mornings 06).
    assert [(i["title"], i["game"], i["followers_only"], i["blurb"]) for i in game if "Melrose" in i["title"]] == [
        ("Boys Soccer vs Melrose · Middle school", {"sport": "Boys Soccer · MS", "teams": ["Kennedy", "Melrose"]}, False,
         "Middle school boys soccer: Kennedy hosts Melrose.")], game
    assert "Girls Basketball vs Holdingford · MS" in [i["title"] for i in game], \
        "a title Bound cut off loses its stub"
    # A game's sport says its level, and only a level; a name keeps none of Bound's brackets (game-card 16).
    tech = one("Basketball\\, Boys: St. Cloud Tech (Junior Varsity) (Time TBA) vs Osseo (Junior Varsity)", "basketball",
               "Junior Varsity", "Basketball\\, Boys")
    assert tech["game"] == {"sport": "Boys Basketball · JV", "teams": ["Osseo", "Tech"]}, tech["game"]
    assert tech["title"] == "Osseo Boys Basketball vs Tech · JV" and "(Time TBA)" not in tech["blurb"], tech
    for name, level, want in (("Adapted Floor Hockey", "CI", "Adapted Floor Hockey"),
                              ("MS Coed Wrestling", "Middle School", "MS Coed Wrestling")):
        got = one(f"{name}: Moorhead vs St. Cloud ({level})", "x", level, name)
        assert got["game"]["sport"] == want and level.split()[0] in got["title"] + got["blurb"], got
    away = next(i for i in events if "Fergus" in i["title"])
    assert away["game"]["sport"] == "Volleyball", "varsity says no level"
    assert (away["game"]["teams"], away["blurb"]) == (["Fergus Falls", "Apollo"], "Varsity volleyball: Fergus Falls "
                                                      "hosts Apollo."), away
    assert bound_team({"_name": "Kennedy Community School"}) == "kennedy"
    assert bound_team({"_name": "Sauk Rapids-Rice High School"}) == "sauk-rapids-rice"
    # One Event for a festival every school lists, posted by the school whose venue it is.
    jazz = ev("j1", "Jazzband: Central Lakes Jazz Festival (Varsity)", "jazzband", "Varsity", "Jazz Band",
              place="St. Cloud Tech High School Performing Arts Center")
    both = [i for s in ("Apollo High School", "Tech High School")
            for i in bound_items(jazz, {"_name": s}, src, date(2026, 10, 25)) if i["kind"] == "event"]
    assert [i["source_name"] for i in one_each(both)] == ["Tech High School"]
    assert "same" not in one_each(both)[0], "the merge key never reaches the writer"



def t_league_stops_past_the_part():
    """A league that hangs on every call: once the part is 150 s past its end the school's next
    call isn't made, nothing of the school is saved, and the next part reads it whole, so no part
    passes the cloud's 10 minutes."""
    import run
    global fetch
    clock, made = type("Clock", (), {"t": 0.0, "monotonic": lambda self: self.t})(), []

    def hanging(url, timeout=None):
        made.append(url)
        clock.t += 117  # a hanging call with fetch's own retry
        raise TimeoutError("timed out")

    def school(s, e, t):
        league_fetch(s["url"], wait=lambda pause: setattr(clock, "t", clock.t + pause))
        return []
    entries = [{"_name": "Tech High School", "sources": [{"url": "mshsl:Tech", "reader": "mshsl", "trust": "official"}]}]
    was = run.time, fetch
    try:
        run.time, fetch, saved = clock, hanging, {}
        read_all(entries, LEAGUE_DAY, {"mshsl": school}, saved, deadline(2))
        cut = (len(made), clock.t, dict(saved))
        fetch = lambda url, timeout=None: (200, "page")
        read_all(entries, LEAGUE_DAY, {"mshsl": school}, saved, deadline(2))
    finally:
        run.time, fetch = was
    assert cut[2] == {} and cut[0] == 3, f"the school is left for the next part after 3 calls: {cut}"
    assert cut[1] <= 120 + 150 + 117 + 20, f"the part's league calls end in time: {cut[1]} s"
    assert list(saved.values()) == [[[], None]], "the next part reads the school whole"

def facts_only(about, *facts):
    """Every word of an About is one of its schedule's own (teams, sport, level, place, night), or one
    of the few that join them."""
    said = set(re.findall(r"[a-z0-9'#]+", " ".join(facts).lower())) | {"hosts", "and", "play", "at", "the", "jv", "c", "squad"}
    return bool(about) and set(re.findall(r"[a-z0-9'#]+", about.lower())) <= said


def t_games_complete():
    """Every game the school readers bring arrives titled in 40 characters or fewer by the
    title-and-place rules, with an About of its schedule's facts alone (smooth-mornings 06): the
    league's, the CSB/SJU Athletics calendars', and Bound's, Oct 28's long titles among them."""
    league = [i for i in games(league_sample(), LEAGUE_DAY)[0] if "game" in i]
    assert league and all(len(i["title"]) <= TITLE_MAX for i in league), [i["title"] for i in league]
    soccer = next(i for i in league if i["title"] == "Sartell Girls Soccer vs St. Cloud")
    assert soccer["blurb"] == "Varsity girls soccer: Sartell hosts St. Cloud.", soccer["blurb"]
    for i in league:
        assert facts_only(i["blurb"], "varsity", i["title"], i["place"]), i["blurb"]
    # Albany's girls play as River Lakes, which the league listed second at River Lakes Arena (Oct 29's
    # dry run): the team Albany's host line names is River Lakes, not the first.
    row = lambda them, venue, n, team="River Lakes": {
        "lister": "Albany High School", "page": f"{LEAGUE}/group/1/full-schedule", "activity": 133, "family": "Hockey",
        "sport": "Girls Hockey", "day": LEAGUE_DAY + timedelta(n), "time": "7:00 PM", "team": team, "opponent": them,
        "named": False, "venue": venue, "n": 1}
    hockey = games([row("River Lakes", "River Lakes Arena", 1, team="Detroit Lakes"), row("Fergus Falls", "Fergus Falls Ice Arena", 2),
                    row("Brainerd", "Essentia Health Sports Center", 3)], LEAGUE_DAY)[0]
    assert [(i["title"], i["blurb"]) for i in hockey] == [("Girls Hockey vs Detroit Lakes", "Varsity girls hockey: "
                                                          "Detroit Lakes and River Lakes play.")], hockey
    # A section game on a third school's ground: the venue's school plays in neither team, so nobody hosts
    # and both teams stay in the title (review of 06d3b8e0: "Eden Valley-Watkins hosts Albany" at Sartell).
    section = [dict(row("Eden Valley-Watkins", "Sartell High School", 4, team="Albany"), sport="Girls Basketball", activity=7),
               dict(row("Albany", "Sartell High School", 4, team="Eden Valley-Watkins"), sport="Girls Basketball", activity=7,
                    lister="Eden Valley-Watkins High School")]
    assert [(i["title"], i["blurb"], i["source_name"]) for i in games(section, LEAGUE_DAY)[0]] == [
        ("Albany Girls Basketball vs Eden Valley", "Varsity girls basketball: Albany and Eden Valley-Watkins play.", "Sartell High School")], games(section, LEAGUE_DAY)[0]
    campus = [i for i in pathify_items(json.loads(sample("csbsju-events.json")), {"_name": "x"},
                                       {"url": "https://my.csbsju.edu/api"}, TODAY) if "Athletics" in i["source_name"]]
    raw = {str(r["id"]): r for r in json.loads(sample("csbsju-events.json"))}
    assert [(i["title"], i["blurb"]) for i in campus] == [
        ("CSB Soccer vs Hamline: Senior Night", "Soccer: Saint Benedict hosts Hamline. Senior Night."),
        ("SJU Soccer vs UW-River Falls", "Soccer: Saint John's hosts UW-River Falls."),
        ("SJU Football vs Concordia: Homecoming",
         "Football: Saint John's hosts Concordia. Homecoming.")], campus
    for i in campus:
        r = raw[i["source_uid"]]
        assert len(i["title"]) <= TITLE_MAX and facts_only(i["blurb"], r["title"], r["location"]), i
    # A calendar the reader doesn't know yet is read, never a stop (review of 06d3b8e0).
    club = pathify_items([{"id": 9, "title": "Club Hockey vs Bemidji State", "location": "Collegeville, Minn., Sexton Arena",
                           "calendar": {"name": "Club Athletics"}, "start_date": "2026-10-20T00:00:00Z", "all_day": False}],
                         {"_name": "x"}, {"url": "https://my.csbsju.edu/api"}, TODAY)
    assert [(i["source_name"], i["title"], i["blurb"]) for i in club] == [
        ("CSB SJU Club Athletics", "Club Hockey vs Bemidji State", None)], club
    # A playoff round in the opponent's place (Oct 29's dry run): no team "TBD" hosted.
    assert [campus_game(t, "St. Joseph, Minn., CSB Stadium", "CSB Athletics")[1] for t in (
        "College of Saint Benedict Soccer vs MIAC Quarterfinals", "College of Saint Benedict Soccer vs TBD - MIAC Semifinals")] \
        == ["Soccer: Saint Benedict hosts the MIAC Quarterfinals.",
            "Soccer: Saint Benedict hosts the MIAC Semifinals."]
    # Oct 28's long game titles, as Bound's calendars give them (the visitors first). The school's own
    # team leaves a title too long for both; a co-op's ("River Lakes") is the team in most of its games.
    def ev(uid, summary, act, level, place):
        name = act.replace(",", "\\,")
        return (f"BEGIN:VEVENT\r\nDTSTART;TZID=America/Chicago:20261201T174500\r\nGEO:45.4;-94.6\r\n"
                f"LOCATION:{place}\r\nSTATUS:CONFIRMED\r\nSUMMARY:{name}: {summary} ({level})\r\n"
                f"UID:{uid}\r\nX-BND-ACTIVITYKEY:{act.split(',')[0].lower()}\r\nX-BND-ACTIVITYLEVEL:{level}\r\n"
                f"X-BND-ACTIVITYNAME:{name}\r\nEND:VEVENT\r\n")
    calendars = {
        "Sauk Rapids-Rice High School": [
            ev("s1", "North Junior High vs Sauk Rapids-Rice", "Basketball, Girls", "7th Grade", "Sauk Rapids-Rice Middle School Gym"),
            ev("s2", "St. Cloud Apollo vs Sauk Rapids-Rice", "Basketball, Boys", "C", "Sauk Rapids-Rice High School Auxiliary Gym"),
            ev("s3", "St. Cloud Apollo vs Sauk Rapids-Rice", "Basketball, Boys", "C2", "Sauk Rapids-Rice High School Auxiliary Gym")],
        "Sartell High School": [
            ev("t1", "Sauk Rapids-Rice vs Sartell", "Basketball, Boys", "8th Grade", "Sartell Middle School Gym"),
            ev("t2", "Sartell/Sauk Rapids vs Thief River Falls", "Hockey, Girls", "Junior Varsity", "Huck Olson Memorial Arena"),
            ev("t3", "Sartell/Sauk Rapids vs Willmar", "Hockey, Girls", "Junior Varsity", "Willmar Civic Center"),
            ev("t4", "Detroit Lakes vs Sartell/Sauk Rapids", "Hockey, Girls", "Junior Varsity", "Bernicks Arena")],
        "ROCORI High School": [
            ev("r1", "Prairie Centre vs River Lakes", "Hockey, Boys", "Junior Varsity", "River Lakes Civic Arena"),
            ev("r2", "River Lakes vs Hutchinson", "Hockey, Boys", "Junior Varsity", "Hutchinson Civic Arena"),
            ev("r3", "Little Falls vs ROCORI", "Basketball, Boys", "C", "ROCORI Middle School Gym")],
        # A game on a third school's ground (Whitney, Cathedral's calendar): nobody hosts.
        "Cathedral High School": [
            ev("c1", "Montevideo vs Sauk Rapids-Rice", "Basketball, Boys", "Junior Varsity", "Whitney Recreation Center Gym")]}
    got = {}
    for school, events in calendars.items():
        for i in bound_items("".join(events), {"_name": school}, {"url": "u"}, date(2026, 10, 28)):
            if "game" in i:
                got[i["source_uid"][6:]] = (i["title"], i["blurb"])
    assert {k: t for k, (t, _) in got.items()} == {
        "s1": "Girls Basketball vs North · 7th Grade", "s2": "Boys Basketball vs Apollo · C-squad",
        "s3": "Boys Basketball vs Apollo · C2-squad",
        "t1": "Boys Basketball vs Sauk Rapids · 8th", "t2": "Girls Hockey vs Thief River Falls · JV",
        "t3": "Girls Hockey vs Willmar · JV", "t4": "Girls Hockey vs Detroit Lakes · JV",
        "r1": "Boys Hockey vs Prairie Centre · JV", "r2": "Boys Hockey vs Hutchinson · JV",
        "r3": "Basketball vs Little Falls · C-squad", "c1": "Sauk Rapids Basketball vs Montevideo"}, got
    assert got["c1"][1] == ("JV boys basketball: Sauk Rapids-Rice and Montevideo play."), got["c1"]
    assert got["s1"][1] == ("7th Grade girls basketball: Sauk Rapids-Rice hosts North Junior High."), got["s1"]
    for uid, (title, about) in got.items():
        source = next(e for es in calendars.values() for e in es if f"UID:{uid}\r" in e)
        assert len(title) <= TITLE_MAX and facts_only(about, source.replace("/", "-")), (title, about)
    # Two long names on a third school's ground, the host line naming neither, still fit.
    assert game_title(["Montevideo", "Sauk Rapids-Rice"], "Boys Basketball") == "Montevideo Basketball vs Sauk Rapids"
    assert game_title(["Sartell", "Fergus Falls"], "Girls Soccer") == "Sartell Girls Soccer vs Fergus Falls", \
        "a title that fits is never touched"


TESTS = [t_closings_wait, t_games_complete, t_gobound, t_robots, t_ical, t_diocese, t_diocese_repeats, t_pathify, t_roads, t_league_retries, t_kennedy_calendar, t_tech_calendar, t_csbsju_music, t_kennedy_news, t_county, t_rec1, t_league,
         t_league_tournament_and_moves, t_league_dance_show, t_league_conference_meet, t_league_undecided_opponent, t_league_schedule_line, t_league_stops_past_the_part, t_nearby_hosts_are_registry_schools,
         t_failure_in_summary, t_items_fit_the_writer, t_parts, t_part_file]


def selftest():
    failed = 0
    for t in TESTS:
        try:
            t()
        except Exception as e:
            failed += 1
            print(f"FAIL {t.__name__}: {type(e).__name__}: {e}")
    print(f"{len(TESTS) - failed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--town", default="st-joseph-mn")
    ap.add_argument("--root", default=".")
    ap.add_argument("--items", help="write the judged items here, one per line, for write_judged.py")
    ap.add_argument("--include-proposed", action="store_true",
                    help="also read proposed entries: a dry run to look at, never a live write (ADR-008)")
    ap.add_argument("--today", help="YYYY-MM-DD; default today in Chicago")
    ap.add_argument("--reader", help="read only the sources with this reader, e.g. mshsl")
    ap.add_argument("--skip-reader", help="read every source but those with this reader")
    ap.add_argument("--part", help="a timed part (morning.py prepare): what each source gave is kept in this "
                                   "file, and --items is written once every source is read")
    ap.add_argument("--minutes", type=float, help="with --part: start no source after this many minutes")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    today = date.fromisoformat(args.today) if args.today else datetime.now(LOCAL).date()
    statuses = {"active", "proposed"} if args.include_proposed else {"active"}
    entries = [dict(e, sources=[s for s in e.get("sources") or []
                                if (not args.reader or reader_of(s) == args.reader)
                                and (not args.skip_reader or reader_of(s) != args.skip_reader)])
               for e in load(find_root(args.root))[0] if e.get("_town") == args.town and e.get("status") in statuses]
    part = Part(args.part, deadline(args.minutes), {"sources": {}, "state": {}})
    resume_part(part.saved["state"])
    items, summary = read_all(entries, today, saved=part.saved["sources"], stop=part.stop)
    if args.part:
        part.saved["state"] = part_state()
        part.save()
        every = {source_key(e, s) for e in entries for s in e["sources"] if reader_of(s)}
        left = every - set(part.saved["sources"])
        if left:
            return print(f"[read] run again: {len(every) - len(left)} of {len(every)} sources read")
    shown = [i for i in items if i["kind"] != "schedule"]
    for i in sorted(shown, key=lambda i: (i["source_name"], i.get("start") or "")):
        print(f"  {i['kind']:<5} {str(i.get('start') or '')[:16]:<16}  {i['title'][:50]:<50} | "
              f"{i['source_name'][:26]:<26} | {(i.get('place') or '')[:36]}")
    for s in summary:
        print(f"[read] {'FAILED' if s['error'] else 'ok':<6} {s['source']} ({s['reader']}): "
              + (s["error"] or f"{s['items']} items") + (f"; {s['note']}" if s.get("note") else ""))
    print(f"[read] {len(shown)} items from {sum(not s['error'] for s in summary)} of {len(summary)} sources")
    if len(shown) < len(items):
        print("[read] every school was read: games missing from their schedules will be marked cancelled")
    if args.include_proposed:
        print("[read] proposed entries included: a dry run to look at, not for a live write (ADR-008)")
    if args.items:
        Path(args.items).write_text("".join(json.dumps(i, ensure_ascii=False) + "\n" for i in items))
        print(f"[read] judged items written to {args.items}; next: write_judged.py {args.items} --existing ...")


if __name__ == "__main__":
    main()
