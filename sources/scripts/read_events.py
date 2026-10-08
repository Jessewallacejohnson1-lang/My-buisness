#!/usr/bin/env python3
"""
read_events.py: turn the registry's iCal feeds into events (ADR-013, ADR-021).

Reads every `kind: ical` source on an active entry, through run.py's fetch (robots.txt and
Crawl-delay obeyed, ADR-014), and keeps what is an event in the town in the next 90 days:

  - News is not an event (ADR-021): "City Offices Closed" and the like are counted, not kept.
    The town board takes news; nothing writes it there yet.
  - In-town only for now (ADR-021): an address with another ZIP, or naming a place the town
    file says is elsewhere (Saint John's mail goes to Collegeville, ADR-019), is skipped.

Dry-run by default (ADR-009): prints what it found. `--sql FILE` writes one upsert for
public.club_events. Found events go in as `approved` and show straight away: Jesse,
2026-10-07, "just let them run without my approval for now" (ADR-021's review is paused;
these are official calendars, one mention under ADR-001). Re-reading updates them by
(source_name, source_uid) and never changes a status the admin set. A decline stays one,
except an event declined as a misread (any review_reason but not_event): when a re-read
changes its title, date, time or place, it goes back to `pending` for another look.

  python3 sources/scripts/read_events.py [--town st-joseph-mn] [--sql out.sql]
  python3 sources/scripts/read_events.py --selftest
"""

import argparse, html, json, re, secrets, sys
from urllib.parse import urljoin, urlparse
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from run import fetch
from discover import TOWNS

DAYS_AHEAD = 90
LOCAL = ZoneInfo("America/Chicago")
NEWS = re.compile(r"\b(closed|closure|holiday)\b", re.I)


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


def outside(location, town):
    zips = set(re.findall(r"\b(5\d{4})\b", location))
    if zips and not zips & set(town["zips"]):
        return True
    return any(w.lower() in location.lower() for w in town.get("elsewhere", ()))


def bare_town(location, town):
    """A location naming only the town ("St. Joseph MN 56374") says nowhere to go: the
    card would print the town as if it were the place, so it is written as no place."""
    rest = location.lower().replace(town["label"].lower(), "")
    for z in town["zips"]:
        rest = rest.replace(z, "")
    return not re.sub(r"[\W_]+", "", rest)


def page_url(ev, feed_url):
    """A link a person can open. CivicPlus feeds (the City's) give each event a relative URL
    pointing back at the feed itself; the event's own page is Calendar.aspx?EID=<UID>."""
    url = urljoin(feed_url, unescape(ev["URL"][1])) if "URL" in ev else feed_url
    if "iCalendar.aspx" in url:
        host = urlparse(feed_url)
        return f"{host.scheme}://{host.netloc}/Calendar.aspx?EID={ev['UID'][1].strip()}"
    return url


def to_event(ev, source_name, feed_url, town, today):
    """An event row, or a reason it is not one."""
    if "DTSTART" not in ev or "UID" not in ev:
        return None, "unreadable"
    start, all_day = when(ev["DTSTART"])
    day = start if all_day else start.date()
    if not (today <= day <= today + timedelta(days=DAYS_AHEAD)):
        return None, "not in the next 90 days"
    title = unescape(ev.get("SUMMARY", ("", ""))[1])
    if NEWS.search(title):
        return None, "news"
    location = unescape(ev.get("LOCATION", ("", ""))[1])
    if outside(location, town):
        return None, "out of town"
    if bare_town(location, town):
        location = ""
    end = when(ev["DTEND"])[0] if "DTEND" in ev and not all_day else None
    return {
        "title": title,
        "event_date": day.isoformat(),
        "start_time": None if all_day else clock(start),
        "end_at": end.isoformat() if end else None,
        "all_day": all_day,
        "location": location or None,
        "description": unescape(ev.get("DESCRIPTION", ("", ""))[1])[:1000] or None,
        "source_name": source_name,
        "source_url": page_url(ev, feed_url),
        "source_uid": ev["UID"][1].strip(),
    }, None


def upsert_sql(rows):
    payload = json.dumps(rows, ensure_ascii=False)
    tag = "ev" + secrets.token_hex(8)
    assert f"${tag}$" not in payload
    cols = "title text, event_date date, start_time text, end_at timestamptz, all_day boolean, " \
           "location text, description text, source_name text, source_url text, source_uid text"
    keep = ["title", "event_date", "start_time", "end_at", "all_day", "location", "description", "source_url"]
    return (
        "insert into public.club_events (status, kind, title, event_date, start_time, end_at, all_day,\n"
        "  location, description, source_name, source_url, source_uid)\n"
        "select 'approved', 'event', x.title, x.event_date, x.start_time, x.end_at, x.all_day,\n"
        "  x.location, x.description, x.source_name, x.source_url, x.source_uid\n"
        f"from jsonb_to_recordset(${tag}${payload}${tag}$::jsonb) as x({cols})\n"
        "on conflict on constraint club_events_source_uid_key do update set\n  "
        + ", ".join(f"{c} = excluded.{c}" for c in keep) + ",\n"
        "  status = case when club_events.status = 'rejected'\n"
        "      and club_events.review_reason is distinct from 'not_event' and club_events.review_reason is not null\n"
        "      and (club_events.title, club_events.event_date, club_events.start_time, club_events.all_day, club_events.location)\n"
        "          is distinct from (excluded.title, excluded.event_date, excluded.start_time, excluded.all_day, excluded.location)\n"
        "    then 'pending' else club_events.status end;\n"
    )


def selftest():
    town = {"label": "St. Joseph MN", "zips": ["56374"], "elsewhere": ["Saint John's University"]}
    ics = ("BEGIN:VEVENT\r\nUID:7\r\nSUMMARY:Fare for All\r\nDTSTART:20261207T153000\r\n"
           "DTEND:20261207T173000\r\nLOCATION: - 610 County Rd 2  St. Joseph MN \r\n 56374\r\n"
           "DESCRIPTION:<p>Groceries\\, cheap</p>\r\nEND:VEVENT\r\n"
           "BEGIN:VEVENT\r\nUID:8\r\nSUMMARY:Holiday - City Offices Closed\r\nDTSTART;VALUE=DATE:20261126\r\nEND:VEVENT\r\n"
           "BEGIN:VEVENT\r\nUID:9\r\nSUMMARY:Film\r\nDTSTART:20261204T190000\r\n"
           "LOCATION:Saint John's University - 2850 Abbey Plaza St. Joseph MN 56374\r\nEND:VEVENT\r\n"
           "BEGIN:VEVENT\r\nUID:10\r\nSUMMARY:City Council Meeting\r\nDTSTART:20261207T180000\r\n"
           "LOCATION: - St. Joseph MN 56374\r\nEND:VEVENT\r\n")
    got = [to_event(e, "City", "feed", town, date(2026, 10, 6)) for e in parse_ics(ics)]
    row = got[0][0]
    assert row["start_time"] == "3:30 PM" and row["event_date"] == "2026-12-07", row
    assert row["location"] == "610 County Rd 2 St. Joseph MN 56374", row["location"]
    assert row["description"] == "Groceries, cheap" and row["end_at"].startswith("2026-12-07T17:30:00-06:00")
    assert got[1] == (None, "news") and got[2] == (None, "out of town"), got
    assert got[3][0]["location"] is None, got[3]
    assert clock(datetime(2026, 1, 1, 18, 0)) == "6 PM"
    assert page_url({"UID": ("", "2447"), "URL": ("", "/common/modules/iCalendar/iCalendar.aspx?feed=calendar&catID=25")},
                    "https://www.stjosephmn.gov/common/modules/iCalendar/iCalendar.aspx?catID=25&feed=calendar") \
        == "https://www.stjosephmn.gov/Calendar.aspx?EID=2447"
    print("read_events OK")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--town", default="st-joseph-mn")
    ap.add_argument("--root", default=".")
    ap.add_argument("--sql", help="write the upsert for public.club_events to this file")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    town, today = TOWNS[args.town], datetime.now(LOCAL).date()
    entries = [e for e in load(find_root(args.root))[0]
               if e.get("_town") == args.town and e.get("status") == "active"]
    rows, skipped = {}, {}
    for e in entries:
        for s in e.get("sources") or []:
            if s.get("kind") != "ical":
                continue
            _status, text = fetch(s["url"])
            for ev in parse_ics(text):
                row, why = to_event(ev, e["_name"], s["url"], town, today)
                if row:
                    rows[(row["source_name"], row["source_uid"])] = row
                else:
                    skipped[why] = skipped.get(why, 0) + 1
    rows = sorted(rows.values(), key=lambda r: (r["event_date"], r["start_time"] or ""))
    for r in rows:
        print(f"  {r['event_date']} {r['start_time'] or 'all day':>8}  {r['title'][:44]:44} | {(r['location'] or '')[:40]}")
    print(f"[events] {len(rows)} events in town in the next {DAYS_AHEAD} days; skipped {skipped}")
    if args.sql:
        Path(args.sql).write_text(upsert_sql(rows))
        print(f"[events] upsert written to {args.sql}")


if __name__ == "__main__":
    main()
