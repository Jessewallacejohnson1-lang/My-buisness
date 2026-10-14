#!/usr/bin/env python3
"""
read_events.py: the registry's sources that need no model, read exactly and handed to
write_judged.py as judged items (ADR-013, ADR-021; BP app docs/plans/watch-every-place,
ticket 10).

Calendar feeds, and sites whose pages are built by JavaScript (a plain fetch of the page
reads almost nothing), are read from the data itself by a small reader per kind of site:
exact dates, no model. A source is read when its entry is active and it names a `reader:`
(an iCal feed needs none):

  ical                an iCal feed (the City's)
  pathify             a Pathify campus portal's public events JSON (CSB/SJU's my.csbsju.edu);
                      the calendars to read are in the source's own url
  cars511             Minnesota 511's road reports within `miles` of `around` (its GraphQL)
  finalsite-calendar  a Finalsite calendar page, this month and next (?cal_date=). Its iCal
                      export sits under the robots-disallowed /fs/, so never that (Kennedy)
  finalsite-news      a Finalsite news page: titles only, dated the day first seen; the story
                      pages are robots-disallowed (Kennedy)
  civicplus-hcms      CivicPlus's content service: news, notices and events, read with the
                      read-only token the county's own page gives every visitor, taken fresh
                      each run and never stored (Stearns County; Jesse, 2026-10-14)

Every request goes through run.py's fetch, so robots rules and Crawl-delay are obeyed on
every run, not only on the day a reader was written (ADR-014). A source that fails is named
in the summary and the others carry on.

What the readers keep (Jesse, 2026-10-14): events in the next 90 days, and News. Each is one
sure mention at its source's trust, sized everyday (it shows two weeks ahead), with an
interest only where the calendar says what it is: games Sports & leagues, the library
Library & books, the Monastery Faith. CSB/SJU: the public calendars named in the registry,
home games only (no away games, rec-center classes or halftime shows), and a repeating
event once, at its next date. 511: road work as News. Stearns County: news and notices from
the last 7 days, and events only in the town (ADR-019). Every St. Joseph source's events
are kept wherever they happen (the spec's Area rule, amending ADR-021's in-town-only rule).

Dry-run by default (ADR-009): prints what each reader found. `--items FILE` writes the
judged items, one per line, for the writer, which merges them with what is already listed
and writes the SQL; it sets each event's show-from day too:

  python3 sources/scripts/read_events.py --items items.jsonl [--include-proposed]
  python3 sources/scripts/write_judged.py items.jsonl --existing existing.json --sql out.sql
  python3 sources/scripts/read_events.py --selftest
"""

import argparse, html, json, math, re, sys
from urllib.parse import quote, urlencode, urljoin, urlparse
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from run import fetch, to_text
from discover import TOWNS

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


def utc_local(stamp):
    return datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone(LOCAL)


def ahead(day, today):
    return today <= day <= today + timedelta(days=DAYS_AHEAD)


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
    return dt.replace(tzinfo=ZoneInfo(tz.group(1)) if tz else LOCAL), False


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
        end = when(ev["DTEND"])[0] if "DTEND" in ev and not all_day else None
        out.append(judged(entry, src, kind="news" if NEWS.search(title) else "event", title=title,
                          start=start.isoformat(), end=end and end.isoformat(), all_day=all_day,
                          # "St. Joseph MN 56374" alone is no place; the writer drops it.
                          place=unescape(ev.get("LOCATION", ("", ""))[1]),
                          blurb=unescape(ev.get("DESCRIPTION", ("", ""))[1]) or None,
                          source_url=page_url(ev, src["url"]), source_uid=ev["UID"][1].strip()))
    return out


def read_ical(src, entry, today):
    return ical_items(fetch(src["url"])[1], entry, src, today)


# CSB/SJU: Pathify ------------------------------------------------------------------------

# Each campus calendar names who is hosting, because the card shows it as the host.
CAMPUS_HOSTS = {"Campus Events": "CSB/SJU Campus Events", "CSB Athletics": "CSB Athletics",
                "SJU Athletics": "SJU Athletics", "Library": "CSB/SJU Libraries",
                "St. Benedict's Monastery": "Saint Benedict's Monastery",
                "School of Theology": "Saint John's School of Theology"}
CAMPUS_INTERESTS = {"CSB Athletics": "sports_leagues", "SJU Athletics": "sports_leagues",
                    "Library": "books", "St. Benedict's Monastery": "faith"}
HOME_GAME = re.compile(r"\b(st\.?|saint) joseph\b|collegeville", re.I)
# ponytail: SJU's own building names, for a place with no town in it. A building not listed
# reads as St. Joseph; add it here when one shows up wrong.
SJU = re.compile(r"collegeville|\bsju\b|saint john'?s|st\.? john'?s|alcuin|learning commons|\bquad\b|sexton|"
                 r"clemens stadium|haws field|palaestra|guild hall|luke hall|pengl|simons|abbey", re.I)


def campus_town(place):
    m = re.search(r"([A-Z][A-Za-z.' ]+?),\s*(?:MN|Minn\.)", place)
    town = m.group(1).strip() if m else "Collegeville" if SJU.search(place) else "St. Joseph"
    return "St. Joseph" if re.fullmatch(r"(st\.?|saint) joseph", town, re.I) else town


def pathify_url(url, today):
    after, before = (datetime.combine(d, time(), LOCAL).astimezone(timezone.utc)
                     for d in (today, today + timedelta(days=DAYS_AHEAD)))
    fields = "".join(f"&field={f}" for f in ("id", "title", "start_date", "end_date", "all_day", "start_day",
                                             "calendar__name", "recurrence_rule", "location"))
    return (f"{url}{'&' if '?' in url else '?'}in_range_after={after:%Y-%m-%dT%H:%M:%SZ}"
            f"&in_range_before={before:%Y-%m-%dT%H:%M:%SZ}{fields}&paginate=false&published=true")


def pathify_items(rows, entry, src, today):
    site = urlparse(src["url"])
    out, series = [], set()
    for r in sorted(rows, key=lambda r: r["start_date"]):
        cal = (r.get("calendar") or {}).get("name") or ""
        title, place = r["title"].strip(), re.sub(r",\s*USA$", "", (r.get("location") or "").strip())
        if "Athletics" in cal and ("group exercise" in place.lower() or "dance team" in title.lower()
                                   or not HOME_GAME.search(place)):
            continue  # a rec-center class, a halftime show or an away game
        if "admission event" in title.lower():
            continue  # a visit day for students thinking of coming
        if r.get("recurrence_rule"):
            if (cal, title) in series:
                continue  # a repeating event shows once, at its next date
            series.add((cal, title))
        if r.get("all_day"):
            start, end = r.get("start_day") or r["start_date"][:10], None
        else:
            start = utc_local(r["start_date"]).isoformat()
            end = r.get("end_date") and utc_local(r["end_date"]).isoformat()
        if not ahead(date.fromisoformat(start[:10]), today):
            continue
        news = bool(NEWS.search(title))
        out.append(judged(entry, src, kind="news" if news else "event", category="campus" if news else None,
                          title=title, start=start, end=end, all_day=bool(r.get("all_day")),
                          place=place, town=campus_town(place), area="campus",
                          source_name=CAMPUS_HOSTS.get(cal, f"CSB/SJU {cal}"), interest=CAMPUS_INTERESTS.get(cal),
                          source_url=f"{site.scheme}://{site.netloc}/public/events/{r['id']}",
                          source_uid=str(r["id"])))
    return out


def read_pathify(src, entry, today):
    return pathify_items(json.loads(fetch(pathify_url(src["url"], today))[1]), entry, src, today)


# Minnesota 511 ---------------------------------------------------------------------------

ROADS_MAP = """query MapFeatures($input: MapFeaturesArgs!) { mapFeaturesQuery(input: $input) {
  mapFeatures { uri title __typename } error { message type } } }"""
ROAD_EVENT = """query Event($layerSlugs: [String!]!, $eventId: ID!) {
  eventQuery(eventId: $eventId, layerSlugs: $layerSlugs) {
    event { uri title description beginTime { timestamp } active } error { type } } }"""


def box(lat, lon, miles):
    dlat, dlon = miles / 69.0, miles / (69.0 * math.cos(math.radians(lat)))
    return {"north": lat + dlat, "south": lat - dlat, "east": lon + dlon, "west": lon - dlon}


def graphql(url, query, variables):
    body = json.dumps({"query": query, "variables": variables}).encode()
    answer = json.loads(fetch(url, data=body, headers={"Content-Type": "application/json",
                                                       "Accept": "application/json"})[1])
    if answer.get("errors"):
        raise RuntimeError(f"GraphQL: {answer['errors'][0].get('message')}")
    return answer["data"]


def road_items(events, entry, src):
    out = []
    for e in events:
        if not e or e.get("active") is False:
            continue
        about = re.sub(r"\s+", " ", to_text(e.get("description") or "").split("Comment:")[0]).strip()
        near = re.search(r"\((?:near )?([^)]+)\)", about)
        out.append(judged(entry, src, kind="news", category="road", all_day=True,
                          title=e["title"].strip().rstrip(".") + (f" near {near.group(1)}" if near else ""),
                          start=datetime.fromtimestamp(e["beginTime"]["timestamp"] / 1000, LOCAL).date().isoformat(),
                          blurb=about or None, source_url=f"https://511mn.org/{e['uri']}",
                          source_uid=e["uri"].rsplit("/", 1)[-1]))
    return out


def read_roads(src, entry, today):
    lat, lon = src["around"]
    found = graphql(src["url"], ROADS_MAP, {"input": dict(box(lat, lon, src.get("miles", 10)), zoom=14,
                                                          layerSlugs=["roadReports"])})["mapFeaturesQuery"]
    if found.get("error"):
        raise RuntimeError(f"511: {found['error']}")
    events = []
    for f in found["mapFeatures"]:
        if f["__typename"] == "Cluster":
            raise RuntimeError("511 grouped road reports into a cluster: ask at a higher zoom")
        if f["__typename"] == "Event":
            events.append(graphql(src["url"], ROAD_EVENT, {"layerSlugs": ["roadReports"],
                                                           "eventId": f["uri"].rsplit("/", 1)[-1]})["eventQuery"]["event"])
    return road_items(events, entry, src)


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


# The run ---------------------------------------------------------------------------------

READERS = {"ical": read_ical, "pathify": read_pathify, "cars511": read_roads,
           "finalsite-calendar": read_finalsite_calendar, "finalsite-news": read_finalsite_news,
           "civicplus-hcms": read_hcms}


def read_all(entries, today, readers=READERS):
    """Every reader source of these entries. One that fails is named in the summary and
    never stops the others."""
    items, summary = [], []
    for e in entries:
        for s in e.get("sources") or []:
            name = s.get("reader") or ("ical" if s.get("kind") == "ical" else None)
            if not name:
                continue
            row = {"source": e["_name"], "reader": name, "url": s["url"], "items": 0, "error": None}
            try:
                got = readers[name](s, e, today)
                items += got
                row["items"] = len(got)
            except Exception as ex:  # a site down or changed is a line in the summary
                row["error"] = f"{type(ex).__name__}: {ex}"[:300]
            summary.append(row)
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
    assert (closed["kind"], closed["start"], closed["all_day"]) == ("news", "2026-11-26", True), closed
    assert film["place"].startswith("Saint John's University"), "a St. Joseph source's event is kept wherever it is"
    assert clock(datetime(2026, 1, 1, 18, 0)) == "6 PM"


def t_pathify():
    src = {"url": "https://my.csbsju.edu/api/v2/events/unauthenticated/?calendar=2,165,166,193,212,224"}
    got = pathify_items(json.loads(sample("csbsju-events.json")), {"_name": "CSB/SJU events"}, src, TODAY)
    titles = [i["title"] for i in got]
    assert len(got) == 11 and titles.count("Free Art Prints from The Saint John's Bible") == 1, titles
    assert not any(w in t for t in titles for w in ("Barre", "Oja", "Dance Team", "Admission")), \
        "classes, away games, halftime shows, visit days"
    fair = next(i for i in got if i["title"] == "Academic Exploration Fair")
    assert fair["start"] == "2026-10-14T14:00:00-05:00" and fair["town"] == "St. Joseph" and fair["interest"] is None
    football = next(i for i in got if "Football" in i["title"])
    assert (football["town"], football["interest"], football["source_name"]) == ("Collegeville", "sports_leagues", "SJU Athletics")
    homecoming = next(i for i in got if i["title"] == "Homecoming 2026")
    assert (homecoming["start"], homecoming["all_day"], homecoming["end"]) == ("2026-10-17", True, None), homecoming
    closed = next(i for i in got if "Closed" in i["title"])
    assert (closed["kind"], closed["category"], closed["start"]) == ("news", "campus", "2026-11-25"), closed
    sale = next(i for i in got if "Craft Sale" in i["title"])
    assert (sale["town"], sale["interest"], sale["source_name"]) == ("St. Cloud", "faith", "Saint Benedict's Monastery")
    assert next(i for i in got if "Fix-It" in i["title"])["interest"] == "books"
    assert got[0]["source_url"].startswith("https://my.csbsju.edu/public/events/") and got[0]["area"] == "campus"
    url = pathify_url(src["url"], TODAY)
    assert "calendar=2,165,166,193,212,224&in_range_after=2026-10-14T05:00:00Z&in_range_before=2027-01-12T06:00:00Z" in url, url


def t_roads():
    events = [r["data"]["eventQuery"]["event"] for r in json.loads(sample("511-events.json")).values()]
    got = road_items(events + [dict(events[0], active=False)], {"_name": "Minnesota 511"}, {"trust": "official"})
    assert [i["title"] for i in got] == ["I-94 eastbound: Construction work near Clearwater",
                                         "MN 55 in both directions: Road closed near Paynesville"], got
    assert all(i["kind"] == "news" and i["category"] == "road" for i in got)
    assert got[0]["start"] == "2026-10-13" and "Left lane closed" in got[0]["blurb"] and "Comment" not in got[0]["blurb"]
    assert got[0]["source_url"] == "https://511mn.org/event/CARSx-149782"
    b = box(45.5647, -94.3183, 10)
    assert round(b["north"], 3) == 45.710 and round(b["west"], 3) == -94.525, b
    assert [f["uri"] for f in json.loads(sample("511-mapfeatures.json"))["data"]["mapFeaturesQuery"]["mapFeatures"]] \
        == ["event/CARSx-149782", "event/CARSx-142773"]


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
             + road_items([r["data"]["eventQuery"]["event"] for r in json.loads(sample("511-events.json")).values()], entry, {})
             + finalsite_calendar_items(sample("kennedy-calendar.html"), "u", entry, {}, TODAY)
             + finalsite_news_items(sample("kennedy-news.html"), "u", entry, {})
             + hcms_items(json.loads(sample("stearns-news.json")), json.loads(sample("stearns-events.json")),
                          {"_name": "Stearns County"}, {"token_page": "u"}, TODAY, TOWNS["st-joseph-mn"]))
    r = plan(items, [], TODAY, interest_ids())
    bad = [(i["title"], o) for i, o in zip(items, r["outcomes"]) if o[0] == "skipped"]
    assert not bad and not r["notes"], (bad, r["notes"])
    rows = {g["row"]["title"]: g["row"] for g in r["events"]}
    assert rows["Saint John's University Football vs Concordia (Homecoming)"]["location"] == "Collegeville, Minn., Clemens Stadium"
    assert rows["Fix-It Clinic"]["location"] == "Clemens Library", "St. Joseph needs no town on its place line"
    assert rows["Christmas Craft Sale at Saint Scholastica Convent"]["location"].endswith("St. Cloud, MN")


TESTS = [t_robots, t_ical, t_pathify, t_roads, t_kennedy_calendar, t_kennedy_news, t_county, t_failure_in_summary,
         t_items_fit_the_writer]


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
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    today = date.fromisoformat(args.today) if args.today else datetime.now(LOCAL).date()
    statuses = {"active", "proposed"} if args.include_proposed else {"active"}
    entries = [e for e in load(find_root(args.root))[0]
               if e.get("_town") == args.town and e.get("status") in statuses]
    items, summary = read_all(entries, today)
    for i in sorted(items, key=lambda i: (i["source_name"], i.get("start") or "")):
        print(f"  {i['kind']:<5} {str(i.get('start') or '')[:16]:<16}  {i['title'][:50]:<50} | "
              f"{i['source_name'][:26]:<26} | {(i.get('place') or '')[:36]}")
    for s in summary:
        print(f"[read] {'FAILED' if s['error'] else 'ok':<6} {s['source']} ({s['reader']}): "
              + (s["error"] or f"{s['items']} items"))
    print(f"[read] {len(items)} items from {sum(not s['error'] for s in summary)} of {len(summary)} sources")
    if args.include_proposed:
        print("[read] proposed entries included: a dry run to look at, not for a live write (ADR-008)")
    if args.items:
        Path(args.items).write_text("".join(json.dumps(i, ensure_ascii=False) + "\n" for i in items))
        print(f"[read] judged items written to {args.items}; next: write_judged.py {args.items} --existing ...")


if __name__ == "__main__":
    main()
