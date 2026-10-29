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
                      export sits under the robots-disallowed /fs/, so never that (Kennedy)
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
from towns import TOWNS

DAYS_AHEAD = 90
LOCAL = ZoneInfo("America/Chicago")
# Something to know rather than go to is News, even with a date (ADR-021).
NEWS = re.compile(r"\b(closed|closure|holiday|no school|no classes|late start|early (release|dismissal))\b", re.I)
SAMPLES = Path(__file__).resolve().parent / "samples"


def judged(entry, src, **kw):
    """One item in write_judged.py's contract. No model read it: it is sure, sized everyday,
    and as trusted as the registry says its source is."""
    return {"kind": "event", "all_day": False, "place": "", "town": None, "area": "announced",
            "source_name": entry["_name"], "trust": src.get("trust") or "official", "sure": True,
            "size": "everyday", "interest": None, **kw}


def plain(markup):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", markup or ""))).strip()


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
LEVEL_SHORT = {"C-squad": "C", "B-squad": "B", "Middle school": "MS"}


def game_title(teams, sport, ours=None, level=""):
    """A game's title by the title-and-place rules, "<home> <sport> vs <away>", then " · <level>"
    below varsity, in 40 characters or fewer so the poster fits without the morning's model. Too
    long, it gives up a little at a time and never cuts a word: a school's kind ("Willmar MS" is
    "Willmar"); our own team, which the host line names ("Boys Basketball vs Willmar · C-squad");
    a co-op's or district's later towns ("Sartell-Sauk Rapids" is "Sartell"); the level's short
    form ("C", "8th", "MS"); the boys or girls; then the level. The About keeps all of it. `ours`:
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
        # ponytail: the last two steps are for a game on a third school's ground, whose host line
        # names neither team (0.6% of Bound's on 2026-10-29); two names longer still stay long.
        sport = re.sub(r"^(Boys|Girls) ", "", sport)
    if len(title()) > TITLE_MAX:
        lv = ""
    return title()


def game_about(level, sport, home, away, place, hosted=True, occasion=None):
    """A game's About from its schedule alone: its level and sport, who hosts whom (or who meets
    whom, on ground that is neither's), where, and the night or playoff round the schedule names.
    Nothing here to research, so the describe layout leaves games out."""
    what = f"{level} {sport.lower()}".strip()
    who = f"{home} hosts {away}" if hosted else f"{home} and {away} meet"
    return f"{what[:1].upper()}{what[1:]}: {who}" + (f" at {place}" if place else "") + "." \
        + (f" {occasion}." if occasion else "")


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
CAMPUS_INTERESTS = {"CSB Athletics": "watch_sports", "SJU Athletics": "watch_sports",
                    "Library": "books", "St. Benedict's Monastery": "faith"}
# Campus Events also lists what only students go to: career workshops and fairs (Jesse, 2026-10-14).
STUDENT_ONLY = re.compile(r"admission event|networking workshop|charting conversations|employer tabling|"
                          r"johnnie development institute|\bJDI\b|exploration fair|study session", re.I)
HOME_GAME = re.compile(r"\b(st\.?|saint) joseph\b|collegeville", re.I)
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
    return tidy_title(title, host), game_about("", g["sport"], home, away, place, occasion=night)


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
                                             "calendar__name", "recurrence_rule", "location", "description"))
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


def pathify_items(rows, entry, src, today):
    site = urlparse(src["url"])
    out, series = [], set()
    for r in sorted(rows, key=lambda r: r["start_date"]):
        cal = (r.get("calendar") or {}).get("name") or ""
        title, place = r["title"].strip(), re.sub(r",\s*USA$", "", (r.get("location") or "").strip())
        address, home_name = CAMPUS_HOMES.get(cal, (None, None))
        if address and place.startswith(address):
            place = home_name
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
        if not ahead(date.fromisoformat(start[:10]), today):
            continue
        news = bool(NEWS.search(title))
        about = campus_blurb(r.get("description"), cal)
        if "Athletics" in cal:
            title, about = campus_game(title, place, CAMPUS_HOSTS[cal])
        out.append(judged(entry, src, kind="news" if news else "event", category="campus" if news else None,
                          title=title, start=start, end=end, all_day=bool(r.get("all_day")),
                          place=place, town=campus_town(place), area="campus",
                          blurb=about,
                          source_name=CAMPUS_HOSTS.get(cal, f"CSB SJU {cal}"), interest=CAMPUS_INTERESTS.get(cal),
                          source_url=f"{site.scheme}://{site.netloc}/public/events/{r['id']}",
                          source_uid=str(r["id"])))
    return out


def read_pathify(src, entry, today):
    return pathify_items(json.loads(fetch(pathify_url(src["url"], today))[1]), entry, src, today)


# Minnesota 511 ---------------------------------------------------------------------------

# 511mn.org moved to a new map on 2026-10-21 and its old GraphQL address now answers with the
# map's page. The new map loads every road report in the state from one address; the ones on a
# road inside the box are kept. Incidents, closures and work zones are what the old map called
# road reports (crashes came through it from 2026-10-17).


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


def finalsite_calendar_items(page, url, entry, src, today):
    """Each occurrence once (a long event repeats in every day box it spans), with the exact
    times from <time datetime>; an all-day one takes its day from the occurrence id. An event
    on the place's own calendar (`own_calendar`) with no place given is at the place."""
    out, seen = [], set()
    tags = list(OCCURRENCE.finditer(page))
    for i, m in enumerate(tags):
        occur = m.group(1)
        if occur in seen:
            continue
        seen.add(occur)
        body = page[m.end():tags[i + 1].start() if i + 1 < len(tags) else len(page)]
        times = dict((k, v) for v, k in re.findall(r'<time datetime="([^"]+)" class="fs(Start|End)Time"', body))
        start = times.get("Start") or occur.split("_")[1][:10]
        if not ahead(date.fromisoformat(start[:10]), today):
            continue
        title = html.unescape(re.search(r'title="([^"]*)"', m.group(0)).group(1)).strip()
        place = re.search(r'<div class="fsLocation">(.*?)</div>', body, re.S)
        place = plain(place.group(1)) if place else ""
        label = re.findall(r"fsStyleSROnly'>([^<]*)<", page[tags[i - 1].end() if i else 0:m.start()])
        if not place and label and label[-1] == src.get("own_calendar"):
            place = entry["_name"]
        news = bool(NEWS.search(title))
        out.append(judged(entry, src, kind="news" if news else "event", category="school" if news else None,
                          title=title, start=start, end=times.get("End"), all_day="Start" not in times,
                          place="" if place.lower() in ("multiple", "tbd", "tba") else place,
                          source_url=url, source_uid=occur))
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
                          blurb=plain(field(d, "description"))[:300] or None, source_url=page, source_uid=x["id"]))
    for x in events.get("items") or []:
        d = x["data"]
        at, loc = field(d, "eventdate") or {}, field(d, "location") or {}
        if (loc.get("zip") or "")[:5] not in town["zips"]:
            continue  # the county's events count only in the town (ADR-019)
        start, all_day = utc_local(at["startDate"]), bool(at.get("allDay"))
        if not ahead(start.date(), today):
            continue
        title = plain(field(d, "title"))
        out.append(judged(entry, src, kind="news" if NEWS.search(title) else "event", title=title, all_day=all_day,
                          start=start.date().isoformat() if all_day else start.isoformat(),
                          end=None if all_day or not at.get("endDate") else utc_local(at["endDate"]).isoformat(),
                          place=", ".join(p for p in (loc.get("address1"), loc.get("city")) if p), area="town",
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
# A row naming an event rather than an opponent: a meet, a tournament, an invitational.
NAMED = re.compile(r"\b(meet|tournament|tourney|invite|invitational|championships?|classic|jamboree|scrimmage|"
                   r"relays|section|conference|true team|tri|triangular|quadrangular|individuals|race|festival|"
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
            us, them = first["team"], first["opponent"]
            if not own and home:  # read from the visitors' schedule: the home team goes first
                us, them = them, us
            teams = [short_team(us), short_team(them)]
            # The host's own team: the home school's, or on neither's ground the lister's.
            k = (first["lister"], first["activity"])
            mine = [n for n, t in enumerate((us, them)) if named[(*k, t)] * 2 > rows[k]]
            title = game_title(teams, first["sport"], 0 if home and not own else mine[0] if len(mine) == 1 else None)
            about = game_about("Varsity", first["sport"], teams[0], teams[1], first["venue"], hosted=bool(home))
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
# A lower level as its title says it: "Apollo Girls Volleyball vs Brainerd · JV".
BOUND_LEVEL_WORDS = {"Junior Varsity": "JV", "JV": "JV", "C": "C-squad", "C2": "C-squad", "C Team": "C-squad",
                     "B": "B-squad", "Middle School": "Middle school", "9th Grade": "9th grade"}
# A name that says only what kind of meet it is ("Competition", "Triangular") gets its activity in front.
BOUND_GENERIC = {"competition", "meet", "invitational", "invite", "triangular", "quad", "tri", "tournament", "scrimmage"}
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


def bound_team(entry):
    """The school's row in public.teams: "Apollo High School" is apollo, "Kennedy Community School" kennedy."""
    return re.sub(r"[^a-z0-9]+", "-", re.sub(r" (High|Community) School$", "", entry["_name"]).lower()).strip("-")


def bound_items(text, entry, src, today):
    out, games, levels = [], [], set(src.get("game_levels") or ())
    for ev in parse_ics(text):
        get = lambda k: unescape(ev.get(k, ("", ""))[1])
        title, key, level = get("SUMMARY"), get("X-BND-ACTIVITYKEY"), get("X-BND-ACTIVITYLEVEL")
        geo = re.fullmatch(r"(-?[\d.]+);(-?[\d.]+)", ev.get("GEO", ("", ""))[1].strip())
        if "DTSTART" not in ev or "UID" not in ev or get("STATUS").upper() == "CANCELLED" or BOUND_PASS.search(title):
            continue
        # No venue to measure: as far as an away game.
        far = not geo or miles(HOME, (float(geo[1]), float(geo[2]))) > 20
        start, all_day = when(ev["DTSTART"])
        if not ahead(start if all_day else start.date(), today):
            continue
        uid, place = f"bound:{ev['UID'][1].strip()}", get("LOCATION")
        name = BOUND_LEVEL.sub("", re.sub(rf"\s*\({re.escape(level)}\)$", "", title) if level else title)
        # Bound cuts a long title off mid-word: "vs South Junior High (Mid".
        name = re.sub(r"\s*\([^)]*$", "", name)
        name = name.split(": ", 1)[1].strip() if ": " in name and key else "" if key and name.endswith(":") else name
        if not re.sub(r"\bvs\b", "", name).strip():
            # Posted with no name ("Choir:  vs"): a show's level may be its name ("Fall Show"), else skip
            # it. A sport's is a game with no opponent yet: Sartell's "Girls Varsity" wrestling, Dec 18.
            if not level or key not in BOUND_ARTS or BOUND_LEVEL.fullmatch(f" ({level})"):
                continue
            name = level
        quoted = re.search(r'"([^"]+)"', name)
        if quoted and len(name) > 40:  # 'SRRHS Fall Musical, "Disney, The Little Mermaid"': the show's own name
            name = re.sub(r"^Disney,\s*", "", quoted[1])
        if key and name.lower() in BOUND_GENERIC and get("X-BND-ACTIVITYNAME"):
            name = f"{bound_sport(get('X-BND-ACTIVITYNAME'))} {name}"
        start_at = start.isoformat()
        mark = dict(activity_team=bound_team(entry), activity_name=get("X-BND-ACTIVITYNAME") or None,
                    source_url=page_url(ev, src["url"]), source_uid=uid)
        if key in BOUND_ARTS or (not key and BOUND_SHOW.search(title)):
            out.append(judged(entry, src, title=name, start=start_at, all_day=all_day, place=place,
                              followers_only=far or "banquet" in title.lower(),
                              same=(start_at, key or name, level, place[:25]), **mark))
        elif key and " vs " in name:
            if level == "Varsity" and not far:
                continue  # the league's
            # Bound names the visitors first ("Brainerd vs St. Cloud Apollo" at Apollo); a title and a game
            # card put the home team first, as the league's do.
            away, home = [BOUND_TEAMS.get(t.strip(), short_team(t)) for t in name.split(" vs ", 1)]
            if {away.lower(), home.lower()} & PLACEHOLDERS or UNDECIDED.search(name):
                continue  # an opponent not named yet
            sport = bound_sport(get("X-BND-ACTIVITYNAME"))
            words = "" if level == "Varsity" else BOUND_LEVEL_WORDS.get(level, level)
            game = judged(entry, src, title="", start=start_at, all_day=all_day, place=place,
                          area="announced" if far else "game", interest="watch_sports",
                          blurb=game_about(level and (words or "Varsity"), sport, home, away, place),
                          followers_only=far or level not in levels,
                          game={"sport": sport, "teams": [home, away]}, same=(start_at, key, level, place[:25]), **mark)
            out.append(game)
            games.append((game, words))
        elif key:
            # A banquet, a meeting: for those following its activity or school. The school's own days
            # with no activity ("No School", "Mass", "Conferences") stay out.
            out.append(judged(entry, src, title=name, start=start_at, all_day=all_day, place=place,
                              followers_only=True, same=(start_at, key or name, level, place[:25]), **mark))
    # The school's own team, which a title too long for both leaves out: its own name, or a co-op's
    # ("St. Cloud", "River Lakes") as the one team in more than half that activity's games here.
    played = Counter(g["activity_name"] for g, _ in games)
    seen = Counter((g["activity_name"], t) for g, _ in games for t in g["game"]["teams"])
    for g, words in games:
        teams, act = g["game"]["teams"], g["activity_name"]
        ours = [n for n, t in enumerate(teams) if bound_team({"_name": t}) == bound_team(entry)] \
            or [n for n, t in enumerate(teams) if seen[(act, t)] * 2 > played[act]]
        g["title"] = game_title(teams, g["game"]["sport"], ours[0] if len(ours) == 1 else None, words)
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
        price = s.get("price") or 0
        cost = f"${price:g}; sign up on the City's registration site." if price else "Free; sign up on the City's registration site."
        # A group's text is about its one program; a group of several (Senior Citizen Activities) says nothing of each.
        about = said(plain(g.get("description"))) if len(g["sessions"]) == 1 else None
        out.append(judged(entry, src, title=rec1_title(s["text"], sections[sid] == {True}),
                          start=start.isoformat() if start else day.isoformat(), end=end.isoformat() if end else None,
                          all_day=not start, place="" if place.lower() in REC1_NO_PLACE else place,
                          blurb=" ".join(p for p in (about, cost) if p),
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
           "civicplus-hcms": read_hcms, "rec1": read_rec1, "mshsl": read_league, "gobound": read_bound}


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


def t_pathify():
    src = {"url": "https://my.csbsju.edu/api/v2/events/unauthenticated/?calendar=2,165,166,193,212,224"}
    got = pathify_items(json.loads(sample("csbsju-events.json")), {"_name": "CSB SJU events"}, src, TODAY)
    titles = [i["title"] for i in got]
    assert len(got) == 10 and titles.count("Free Art Prints from The Saint John's Bible") == 1, titles
    assert not any(w in t for t in titles for w in ("Barre", "Oja", "Dance Team", "Admission", "Exploration Fair")), \
        "classes, away games, halftime shows, visit days, career fairs"
    salvage = next(i for i in got if i["title"] == "Salvage")
    assert salvage["start"] == "2026-10-14T14:00:00-05:00" and salvage["town"] == "Collegeville" and salvage["interest"] is None
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
    assert "&field=description&" in url, url
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
    forum, walk, _, _, no_school, trunk = got
    assert (forum["start"], forum["end"], forum["place"]) == ("2026-10-06T19:00:00-05:00", "2026-10-06T20:30:00-05:00",
                                                             "District Administration Office"), forum
    assert (walk["start"], walk["all_day"]) == ("2026-10-07", True), walk
    assert (no_school["kind"], no_school["category"], no_school["start"], no_school["place"]) == ("news", "school", "2026-10-15", "")
    assert trunk["source_uid"] == "877919_2026-10-29T21:30:00Z_2026-10-29T23:00:00Z" and trunk["source_url"] == url
    assert trunk["place"] == "Kennedy Community School" and walk["place"] == "", "the school's own calendar is at the school"
    assert len(finalsite_calendar_items(sample("kennedy-calendar.html"), url, CITY, {}, TODAY)) == 2, "past days dropped"


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
    crime = {"items": [{"id": "x", "data": {"title": {"en": "Someone Indicted for Assault"}, "Date": {"iv": "2026-10-13T05:00:00Z"}}}]}
    assert hcms_items(crime, {}, {"_name": "Stearns County"}, src, TODAY, TOWNS["st-joseph-mn"])[0]["sure"] is False
    older = hcms_items(news, {}, {"_name": "Stearns County"}, src, date(2026, 8, 21), TOWNS["st-joseph-mn"])
    assert "Public Notice of Regional Rail Authority Board Meeting" in [i["title"] for i in older]
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
    assert paint["blurb"] == "$50; sign up on the City's registration site." and paint["source_uid"].startswith("rec1:")
    assert pilates["start"] == "2026-10-26T10:00:00-05:00", "a weekly run is read at its next Monday"
    assert got["Fall Puzzle Competition"]["place"] == "", "Location TBD is no place"
    assert got["Chanhassen Dinner Theatre Day Trip"]["blurb"].startswith("$91"), "a shared group text is left out"
    assert rec1_next("10/06-12/29", "Mon", date(2026, 12, 30)) is None and rec1_next("Open TBD", "", TODAY) is None
    assert rec1_next("12/28-01/04", "Sat", date(2026, 12, 29)) == date(2027, 1, 2), "a run over New Year"
    assert rec1_clock("9:30am") == (9, 30) and rec1_clock("12pm") == (12, 0) and rec1_clock("TBD") is None


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
             + games(league_sample(), LEAGUE_DAY)[0])
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
        # A sport's event with no name, its level standing in: Sartell's "Girls Varsity" wrestling, Dec 18.
        ev("a18", "Wrestling:  vs  (Girls Varsity)", "wrestling", "Girls Varsity", "Wrestling"),
    ])
    src = {"url": "https://www.gobound.com/mn/schools/stcloudapollo/calendar/ical", "trust": "official"}
    got = bound_items(ics, {"_name": "Apollo High School"}, src, date(2026, 10, 25))
    events = [i for i in got if i["kind"] == "event"]
    # Everyone's: the plays, concerts and clubs within 20 miles. Followers only: the band festival 170 miles
    # off, a middle school game that isn't Apollo's level, the JV game, the varsity game away, the banquet (school-activities 03). The varsity game at home
    # stays the league's; the season pass and the cancelled concert stay out.
    assert [(i["title"], i["followers_only"]) for i in events] == [
        ("Apollo Theater Presents: The SpongeBob Musical", False), ("Detroit Lakes Band Festival", True),
        ("Fall Show", False), ("Fall Play", False), ("The Little Mermaid", False),
        ("Kennedy Boys Soccer vs Melrose · MS", True), ("Kennedy Basketball vs Holdingford · MS", True),
        ("Apollo Volleyball vs Brainerd · JV", True), ("Fergus Falls Volleyball vs Apollo", True),
        ("Volleyball Banquet", True), ("Boys Soccer Banquet - Play Soccer", True),
        ("Robotics Competition", False)], events
    assert [(i["activity_team"], i["activity_name"]) for i in events[:2]] == [("apollo", "Drama"), ("apollo", "Band")]
    assert events[8]["area"] == "announced", "an away game isn't the writer's 20-mile game"
    assert got[0]["source_uid"] == "bound:a1" and got[0]["start"] == "2026-11-20T19:00:00-06:00"
    assert got[-1] == {"kind": "schedule", "uid_prefix": "bound:", "from": "2026-10-25", "through": "2027-01-23",
                       "sources": ["Apollo High School"]}, "the schedule line: a dropped event was called off"
    for empty in ("BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n", ev("p1", "Apollo Boys Soccer Season Pass", "soccer")):
        assert bound_items(empty, {"_name": "Apollo High School"}, src, date(2026, 10, 25)) == [], \
            "a schedule with nothing on it calls nothing off"
    kennedy = bound_items(ics, {"_name": "Kennedy Community School"}, {**src, "game_levels": ["Middle School"]},
                          date(2026, 10, 25))
    game = [i for i in kennedy if "game" in i]
    # The home team first, as the league's (Bound names the visitors first); too long for both, the
    # school's own team leaves the title, since the host line names it (smooth-mornings 06).
    assert [(i["title"], i["game"], i["followers_only"], i["blurb"]) for i in game if "Melrose" in i["title"]] == [
        ("Boys Soccer vs Melrose · Middle school", {"sport": "Boys Soccer", "teams": ["Kennedy", "Melrose"]}, False,
         "Middle school boys soccer: Kennedy hosts Melrose at Kennedy Community School Kennedy Field.")], game
    assert "Girls Basketball vs Holdingford · MS" in [i["title"] for i in game], \
        "a title Bound cut off loses its stub"
    away = next(i for i in events if "Fergus" in i["title"])
    assert (away["game"]["teams"], away["blurb"]) == (["Fergus Falls", "Apollo"], "Varsity volleyball: Fergus Falls "
                                                      "hosts Apollo at Fergus Falls High School Gold Gym."), away
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
    said = set(re.findall(r"[a-z0-9'#]+", " ".join(facts).lower())) | {"hosts", "and", "meet", "at", "jv", "c", "squad"}
    return bool(about) and set(re.findall(r"[a-z0-9'#]+", about.lower())) <= said


def t_games_complete():
    """Every game the school readers bring arrives titled in 40 characters or fewer by the
    title-and-place rules, with an About of its schedule's facts alone (smooth-mornings 06): the
    league's, the CSB/SJU Athletics calendars', and Bound's, Oct 28's long titles among them."""
    league = [i for i in games(league_sample(), LEAGUE_DAY)[0] if "game" in i]
    assert league and all(len(i["title"]) <= TITLE_MAX for i in league), [i["title"] for i in league]
    soccer = next(i for i in league if i["title"] == "Sartell Girls Soccer vs St. Cloud")
    assert soccer["blurb"] == "Varsity girls soccer: Sartell hosts St. Cloud at Sartell High School.", soccer["blurb"]
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
                                                          "Detroit Lakes and River Lakes meet at River Lakes Arena.")], hockey
    campus = [i for i in pathify_items(json.loads(sample("csbsju-events.json")), {"_name": "x"},
                                       {"url": "https://my.csbsju.edu/api"}, TODAY) if "Athletics" in i["source_name"]]
    raw = {str(r["id"]): r for r in json.loads(sample("csbsju-events.json"))}
    assert [(i["title"], i["blurb"]) for i in campus] == [
        ("CSB Soccer vs Hamline: Senior Night", "Soccer: Saint Benedict hosts Hamline at CSB Stadium. Senior Night."),
        ("SJU Soccer vs UW-River Falls", "Soccer: Saint John's hosts UW-River Falls at Haws Field, Collegeville."),
        ("SJU Football vs Concordia: Homecoming",
         "Football: Saint John's hosts Concordia at Clemens Stadium, Collegeville. Homecoming.")], campus
    for i in campus:
        r = raw[i["source_uid"]]
        assert len(i["title"]) <= TITLE_MAX and facts_only(i["blurb"], r["title"], r["location"]), i
    # A playoff round in the opponent's place (Oct 29's dry run): no team "TBD" hosted.
    assert [campus_game(t, "St. Joseph, Minn., CSB Stadium", "CSB Athletics")[1] for t in (
        "College of Saint Benedict Soccer vs MIAC Quarterfinals", "College of Saint Benedict Soccer vs TBD - MIAC Semifinals")] \
        == ["Soccer: Saint Benedict hosts the MIAC Quarterfinals at CSB Stadium.",
            "Soccer: Saint Benedict hosts the MIAC Semifinals at CSB Stadium."]
    # Oct 28's long game titles, as Bound's calendars give them (the visitors first). The school's own
    # team leaves a title too long for both; a co-op's ("River Lakes") is the team in most of its games.
    def ev(uid, summary, act, level, place):
        return (f"BEGIN:VEVENT\r\nDTSTART;TZID=America/Chicago:20261201T174500\r\nGEO:45.4;-94.6\r\n"
                f"LOCATION:{place}\r\nSTATUS:CONFIRMED\r\nSUMMARY:{act.replace(',', '\\,')}: {summary} ({level})\r\n"
                f"UID:{uid}\r\nX-BND-ACTIVITYKEY:{act.split(',')[0].lower()}\r\nX-BND-ACTIVITYLEVEL:{level}\r\n"
                f"X-BND-ACTIVITYNAME:{act.replace(',', '\\,')}\r\nEND:VEVENT\r\n")
    calendars = {
        "Sauk Rapids-Rice High School": [
            ev("s1", "North Junior High vs Sauk Rapids-Rice", "Basketball, Girls", "7th Grade", "Sauk Rapids-Rice Middle School Gym"),
            ev("s2", "St. Cloud Apollo vs Sauk Rapids-Rice", "Basketball, Boys", "C", "Sauk Rapids-Rice High School Auxiliary Gym")],
        "Sartell High School": [
            ev("t1", "Sauk Rapids-Rice vs Sartell", "Basketball, Boys", "8th Grade", "Sartell Middle School Gym"),
            ev("t2", "Sartell/Sauk Rapids vs Thief River Falls", "Hockey, Girls", "Junior Varsity", "Huck Olson Memorial Arena"),
            ev("t3", "Sartell/Sauk Rapids vs Willmar", "Hockey, Girls", "Junior Varsity", "Willmar Civic Center"),
            ev("t4", "Detroit Lakes vs Sartell/Sauk Rapids", "Hockey, Girls", "Junior Varsity", "Bernicks Arena")],
        "ROCORI High School": [
            ev("r1", "Prairie Centre vs River Lakes", "Hockey, Boys", "Junior Varsity", "River Lakes Civic Arena"),
            ev("r2", "River Lakes vs Hutchinson", "Hockey, Boys", "Junior Varsity", "Hutchinson Civic Arena"),
            ev("r3", "Little Falls vs ROCORI", "Basketball, Boys", "C", "ROCORI Middle School Gym")]}
    got = {}
    for school, events in calendars.items():
        for i in bound_items("".join(events), {"_name": school}, {"url": "u"}, date(2026, 10, 28)):
            if "game" in i:
                got[i["source_uid"][6:]] = (i["title"], i["blurb"])
    assert {k: t for k, (t, _) in got.items()} == {
        "s1": "Girls Basketball vs North · 7th Grade", "s2": "Boys Basketball vs Apollo · C-squad",
        "t1": "Boys Basketball vs Sauk Rapids · 8th", "t2": "Girls Hockey vs Thief River Falls · JV",
        "t3": "Girls Hockey vs Willmar · JV", "t4": "Girls Hockey vs Detroit Lakes · JV",
        "r1": "Boys Hockey vs Prairie Centre · JV", "r2": "Boys Hockey vs Hutchinson · JV",
        "r3": "Boys Basketball vs Little Falls · C"}, got
    assert got["s1"][1] == ("7th Grade girls basketball: Sauk Rapids-Rice hosts North Junior High at "
                            "Sauk Rapids-Rice Middle School Gym."), got["s1"]
    for uid, (title, about) in got.items():
        source = next(e for es in calendars.values() for e in es if f"UID:{uid}\r" in e)
        assert len(title) <= TITLE_MAX and facts_only(about, source.replace("/", "-")), (title, about)
    # Two long names on a third school's ground, the host line naming neither, still fit.
    assert game_title(["Montevideo", "Sauk Rapids-Rice"], "Boys Basketball") == "Montevideo Basketball vs Sauk Rapids"
    assert game_title(["Sartell", "Fergus Falls"], "Girls Soccer") == "Sartell Girls Soccer vs Fergus Falls", \
        "a title that fits is never touched"


TESTS = [t_games_complete, t_gobound, t_robots, t_ical, t_pathify, t_roads, t_league_retries, t_kennedy_calendar, t_kennedy_news, t_county, t_rec1, t_league,
         t_league_tournament_and_moves, t_league_dance_show, t_league_undecided_opponent, t_league_schedule_line, t_league_stops_past_the_part, t_nearby_hosts_are_registry_schools,
         t_failure_in_summary, t_items_fit_the_writer, t_parts]


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
    part = Path(args.part) if args.part else None
    saved = json.loads(part.read_text()) if part and part.exists() else {"sources": {}, "state": {}}
    resume_part(saved["state"])
    items, summary = read_all(entries, today, saved=saved["sources"], stop=deadline(args.minutes))
    if part:
        part.write_text(json.dumps({"sources": saved["sources"], "state": part_state()}, default=str))
        every = {source_key(e, s) for e in entries for s in e["sources"] if reader_of(s)}
        left = every - set(saved["sources"])
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
