#!/usr/bin/env python3
"""
write_judged.py: the judge's items for one morning become Events and News (BP app
docs/plans/watch-every-place, ticket 03; registry ADR-001 trust tiers, ADR-021 found events,
and the spec's Area rule, which amends ADR-019 and ADR-021's in-town rule).

The part of the morning job that needs no model: saved pages in, Events and News out, and
this is everything after the judge. Dry-run by default (ADR-009): prints what each item
becomes. How the writes land lives in the database, in public.apply_judged
(supabase/migrations/20261016090200_apply_judged_title_kept.sql): `--apply` calls it with this
morning's writes over the service role key (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in
the environment), `--sql FILE` writes the same call as SQL to run by hand.

  python3 sources/scripts/write_judged.py judged.jsonl --existing existing.json [--sql out.sql]
  python3 sources/scripts/write_judged.py judged.jsonl --existing db --apply
  python3 sources/scripts/write_judged.py --selftest

THE JUDGED ITEM: the contract the judge (ticket 05) produces, one JSON object per line.
  kind         "event" | "news"
  title        the event's own name, the way a neighbour would say it (.claude/skills/title-and-place)
  start        ISO 8601 with offset ("2026-10-24T16:00:00-05:00"), or a date ("2026-11-09")
               when all_day. Required for an event; optional for news (the day it is about).
  end          optional, the same form; a run over days, timed or all day, gives its last day
               alone ("2026-10-25"), and lasts until the midnight after it
  all_day      true | false (default false)
  place        the venue's name ("Clemens Stadium"), an address only when nothing names the place,
               "Online" for a webinar; "" if not said (.claude/skills/title-and-place)
  town         the town it happens in ("St. Joseph", "Collegeville", "St. Cloud")
  area         "town" (St. Joseph's ZIP codes) | "campus" (any CSB/SJU event, Collegeville and
               athletics included) | "game" (a high school game played within 20 miles of St.
               Joseph) | "announced" (posted by a St. Joseph source: the City, its schools and
               colleges, or an approved place, wherever it happens; Jesse, 2026-10-14) |
               "outside" (anything else; skipped)
  source_name  the registry entry's name ("Milk & Honey Ciders")
  source_url   a link a person can open: the event's own page when it has one, else the page read
  source_uid   the source's own id for it when it has one (an iCal UID, the City's EID)
  trust        "official": the city, county, 511, the schools, the colleges, a place's own
               site or own social page | "secondhand": anyone else (Newsleaders, a town group).
               The registry's word for secondhand, "squishy", works too; mentions store that.
  sure         true | false: false when the judge doubts the date, the place, or that it is real
  size         events: "everyday" | "notable" | "big" (sources/CONTEXT.md, Event size); when
               unsure, the smaller size. Anything else is sized everyday and named.
  signup_by    events, optional: the date sign-ups or tickets close
  closed       events, optional: true when nobody can still go (sign-ups or tickets closed, sold
               out, registration full, members or invitation only)
  interest     one id from Interests.all (BlockParty/Backend/Interests.swift), or null when none
               fits (a council meeting, a road closure); News matches neighbours by it (town-feed 35)
  category     news: "announcement" (default) | "road" | "school" | "campus" | "business"
  blurb        one line
  game         events, optional: a game between two teams, {"sport": "Girls Soccer", "teams": ["Sartell",
               "St. Cloud"]}, the host's team first, as neighbours say them (read_events.py, the league's
               games). CSB and SJU Athletics games need none: the writer reads them off the title.

THE SCHEDULE LINE: a reader that has some sources' whole schedules adds one more line, only on a
morning every one of those sources was read (read_events.py, the league's high school games):
  {"kind": "schedule", "uid_prefix": "mshsl:", "from": "2026-10-15", "through": "2026-11-12",
   "sources": ["Sartell High School", ...]}
  A found event listed from one of those sources, with an id starting uid_prefix and a date from
  `from` to `through`, that no item this morning matches has been called off.

THE RULES
  Place (Jesse, 2026-10-16): every event row carries place_entry_id, the registry entry it happens
    at, so its card shows that place's photo or logo: the place line matched to a name, `aka`,
    `venues` or address (registry.place_for), else the entry that posted it. A place line the
    registry doesn't know is named in the summary.
  Wording: every title and place is tidied (tidy_title, tidy_place) to the title-and-place
    skill's rules before anything else, so a card reads the same whichever source found it.
  Event or News: an Event becomes a found event in public.club_events; News goes to
    public.board_items, the town board's store, with a publish time.
  Trust: published (events `approved`, news `published`) on one sure official mention, or on
    sure mentions from two different secondhand sources. Otherwise an event waits as `pending`
    in the Review queue and news stays in `staging`; both are named in the summary.
  Merging: same place, start within an hour, shared title words = one Event. Shared means
    one title's words all sit inside the other's, with the same team words (JV, varsity,
    girls...); a source's own two ids are always two events. With no place on either, the
    same date and start time to the minute and shared title words are one Event (Jesse,
    2026-10-19: the City's calendar feed and its web page both listed six meetings, no place). Checked against the events
    already in the list and this morning's items; every mention is kept (event_mentions) and
    counts toward the two-mention rule. A pair short of that stays two events, and one on the
    same day at the same place or under the same title is named for Jesse to settle: a
    duplicate stays visible, a wrong merge hides a real event (ADR-021).
  Re-read: an item with the same source and uid (its own, or "page:<start>:<title words>" when
    the source has none) updates its event instead of adding it twice. Status only ever goes
    pending -> approved on a found event the writer left pending; an admin's approve or
    decline stands, except a decline for a misread (any review_reason but not_event): when
    the source changes its title, date, time or place, it goes back to pending for another
    look, the same rule as read_events (Jesse, 2026-10-14).
  Show-from day (the event-lead-time rule, moved here from the skill): the event date minus
    14 days (everyday), 28 (notable) or 56 (big). With sign-ups closing, it lands at least a
    week before they close: size up if that does it, else the deadline minus 7 days. A re-read
    keeps a day already set unless the date moved. Kept out (Jesse, 2026-10-17: "if your not
    able ot signup or go dont recommend it"): an event marked closed, or whose sign-ups closed
    before today, shows from the day after it ends, so the Town feed never shows it.
  Interest: checked against Interests.all; one not on the list is dropped and named.
  Cancelled (Jesse, 2026-10-15): an event its schedule dropped (THE SCHEDULE LINE) is kept and
    marked cancelled, never deleted; its title stays as written (the app shows a Canceled tag,
    ticket 12), and the Town feed leaves it out unless someone Hearted it. Back on the schedule,
    it is restored.
  Area: town, campus, game and announced are kept; outside is skipped, and so is "town" when the item's
    own town or ZIP says otherwise. Outside St. Joseph, the place line carries its town
    ("Saint John's Abbey Arboretum, Collegeville"). Past events and unreadable items are
    skipped one by one, with the reason in the summary.

EXISTING (--existing): the events already in the list, from yesterday on (cancelled ones
  included, with cancelled_at), with their mentions: `db` reads them over the service role key; a file holds the JSON that
  `select public.listed_for_writer()` returns.
"""

import argparse, json, re, secrets, sys
from datetime import date, datetime, time, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from read_events import LOCAL, clock
from run import Supabase
from discover import TOWNS
import registry

LEAD = {"everyday": 14, "notable": 28, "big": 56}
AREAS = {"town", "campus", "game", "announced", "outside"}
# The registry's trust words (ADR-001); "secondhand" is the spec's word for squishy.
TRUST = {"official": "official", "secondhand": "squishy", "squishy": "squishy"}
NEWS_CATEGORIES = {"announcement", "road", "school", "campus", "business"}
STOP = set("a an and at by for from in of on the to with".split())
# Words that tell two games at one place apart; both titles must carry the same ones.
TEAM = set("jv varsity junior reserve freshman sophomore boys girls men women mens womens".split())
# Words that name the town or a kind of spot rather than which place: "Centennial Park
# shelter" and "Millstream Park shelter" are two places, and so are "St. Cloud Apollo High
# School" and "St. Cloud Tech High School".
PLACE_STOP = STOP | set("st saint joseph collegeville mn minnesota united states usa county road rd street "
                        "ave avenue east west north south suite park shelter hall center centre building "
                        "room gym lot parking map theater theatre high middle intermediate elementary school".split())
# Meetings whose listing names no room, and where the host's agendas say they always meet
# (read 2026-10-20). The Park Board moves between City Hall and the parks, so it stays blank.
MEETS_AT = [("City of St. Joseph", re.compile(r"\b(City Council|Economic Development Authority)\b"), "City Hall")]
INTERESTS_SWIFT = Path(__file__).resolve().parents[2] / "BlockParty" / "Backend" / "Interests.swift"
# The newest migration that makes public.apply_judged: the self-tests read the SQL the database
# runs today, whatever the file is called.
WRITES = max(p for p in (Path(__file__).resolve().parents[2] / "supabase" / "migrations").glob("*.sql")
             if re.search(r"create\s+(or\s+replace\s+)?function\s+public\.apply_judged\s*\(", p.read_text(), re.I))


def interest_ids(swift=INTERESTS_SWIFT):
    """The shared interest list lives in the app (Interests.all); read it, never copy it."""
    return re.findall(r'Interest\(id: "([a-z_]+)"', swift.read_text())


def words(text, stop=STOP):
    text = (text or "").lower().replace("'", "").replace("’", "")
    return {w for w in re.findall(r"[a-z0-9]+", text)
            if len(w) > 1 and w not in stop and not re.fullmatch(r"5\d{4}", w)}


def same_title(a, b):
    """One title's words all inside the other's ("Plant Bingo" in "Plant Bingo night"), and
    the same team words: "football" vs "volleyball", "JV" vs none, stay two events."""
    return bool(a and b) and (a <= b or b <= a) and a & TEAM == b & TEAM


def same_place(a, b):
    # ponytail: word overlap, not geocoding. A place named on one page and only its street
    # address on another stays two events; add coordinates if those duplicates pile up.
    return bool(a and b) and len(a & b) / min(len(a), len(b)) > 0.5


def within_hour(a, b):
    if a["at"] is None or b["at"] is None:
        return a["at"] is None and b["at"] is None and a["day"] == b["day"]
    return abs(a["at"] - b["at"]) <= timedelta(hours=1)


def same_event(a, b):
    if not a["place"] and not b["place"] and a["at"] is not None:
        return a["at"] == b["at"] and same_title(a["title"], b["title"])
    if not (a["place"] and b["place"]):
        # One gives no place: the same registry place (where()) and the very same start, or the
        # same day with both all day.
        return bool(a["entry"]) and a["entry"] == b["entry"] and (a["day"], a["at"]) == (b["day"], b["at"]) \
            and same_title(a["title"], b["title"])
    return within_hour(a, b) and same_place(a["place"], b["place"]) and same_title(a["title"], b["title"])


def real_uid(uid):
    """The source's own id. "page:" is made up here from the start and title; "board:" is the
    town board row an event was moved from (ticket 01), not anything its source gave it."""
    return bool(uid) and not str(uid).startswith(("page:", "board:"))


def own_ids_differ(g, source, uid):
    """The source itself gave the two their own ids: two events, however alike."""
    seen = ([g["old"]] if g["old"] else []) + g["mentions"]
    return real_uid(uid) and any(m["source_name"] == source and real_uid(m.get("source_uid"))
                                 and m["source_uid"] != uid for m in seen)


def town_key(name):
    t = re.sub(r"[^a-z ]", "", (name or "").lower().replace("saint", "st"))
    return " ".join(w for w in t.split() if w not in ("mn", "minnesota"))


# Title and place wording (.claude/skills/title-and-place). Every posting passes through here,
# from the readers and the judge alike, so a card reads the same whoever found it.
COLLEGES = ((re.compile(r"\bCollege of (?:Saint|St\.?) Benedict(?:'s)?\b"), "CSB"),
            (re.compile(r"\b(?:Saint|St\.?) John'?s University\b"), "SJU"))
# Both colleges at once are "CSB SJU": no slash, no "and" (Jesse, 2026-10-14).
BOTH = re.compile(r"\bCSB\s*(?:/|\+|&|\band\b)\s*SJU\b", re.I)
ONLINE = re.compile(r"\b(virtual|webinar|zoom)\b", re.I)
STREET = re.compile(r"^\d|\b(avenue|ave|street|st|road|rd|drive|dr|lane|ln|plaza|boulevard|blvd|way|highway|hwy|"
                    r"court|ct|parkway|pkwy)\.?(\s+(north|south|east|west|[nsew]|[ns][ew]|(north|south)(east|west)))?$", re.I)
WEEKDAYS = r"(mon|tues|wednes|thurs|fri|satur|sun)days?"
TITLE_MAX = 40


def caps(text):
    """ALL CAPS reads as shouting: a text written all in capitals gets ordinary capitals."""
    if text.upper() != text or not re.search(r"[A-Z]{4}", text):
        return text
    return " ".join(w.capitalize() if len(w) >= 4 else w for w in text.split(" "))


def clip(text, n):
    """At most n characters, cut at a word with "…" when it runs over: an Event page's About
    never stops mid-word."""
    text = (text or "").strip()
    return text if len(text) <= n else text[:n - 1].rsplit(None, 1)[0] + "…"


def tidy_title(title, host="", event=True):
    """The card's title, short and plain (the skill's rules); tidying it twice changes nothing.
    A News title keeps its subtitle: there it is often the news itself."""
    t = title.strip()
    if len(t) > 2 and t[0] in '"“' and t[-1] in '"”' and not re.search(r'["“”]', t[1:-1]):
        t = t[1:-1]
    t = caps(t)
    for college, short in COLLEGES:
        t = college.sub(short, t)
    t = BOTH.sub("CSB SJU", t)
    if "CSB" in host and "SJU" in host:
        t = re.sub(r"^CSB SJU\s+", "", t)  # the host line already names both colleges
    t = re.sub(r"\bbenefiting\b", "for", t, flags=re.I)
    t = re.sub(r"\s*\((?:\$|as needed\b|virtual\b|online\b)[^)]*\)", "", t, flags=re.I)  # price, a note
    t = re.sub(r"\s*\([A-Z]{2,6}\)", "", t)                                       # "(FOC)"
    t = re.sub(rf"\s*\([^)]*\b(?:through|until|{WEEKDAYS})\b[^)]*\)", "", t, flags=re.I)  # the schedule
    t = re.sub(r"\s+\(([^()]+)\)$", r" - \1", t)                                     # "(Homecoming)"
    t = re.sub(r"\s*[•·\-–—]\s*(?:virtual|online)$", "", t, flags=re.I)
    t = re.sub(r"^(?:19|20)\d\d\s+|\s+(?:19|20)\d\d$", "", t)                       # the card shows the date
    head, *rest = re.split(r"(?<!\d)\s+[-–—]\s+(?!\d)", t)                            # one colon, then commas
    t = head + (": " + ", ".join(rest) if rest else "")
    t = re.sub(r"\s*@\s*(?:The\b)?", lambda m: " at the" if "The" in m[0] else " at ", t)
    t = re.sub(r"\s*[/+]\s*", " ", t)                                                # no slash in a title
    t = re.sub(r"\s+:", ":", re.sub(r"\s{2,}", " ", t)).strip(" :,-–")
    if event and len(t) > TITLE_MAX and ": " in t and len(t.split(": ", 1)[0]) >= 12:
        t = t.split(": ", 1)[0]  # the name, not its subtitle
    return t or title.strip()


# The game card (game-card 01): a game's sport, two teams and special night, for its card. CSB's
# and SJU's Athletics calendars write games the title-and-place way, "SJU Football vs Concordia:
# Homecoming"; the host's team is the college whose calendar it is.
CAMPUS_TEAMS = {"SJU Athletics": ("SJU", "Saint John's"), "CSB Athletics": ("CSB", "Saint Benedict")}
CAMPUS_GAME = re.compile(r"^(?P<host>CSB|SJU) (?P<sport>.+?) vs\.? (?P<them>.+?)(?:: (?P<night>.+))?$")
# An opponent that names an event, not a team: a meet, a finale, a championship.
NOT_A_TEAM = re.compile(r"\b(meet|finale|invitational|invite|championships?|tournament|classic|relays|open)\b", re.I)


def team_id(name):
    """A team's row in public.teams: its name as the schedules write it, as a slug."""
    return re.sub(r"[^a-z0-9]+", "-", name.lower().replace("'", "")).strip("-")


def game_of(it, title):
    """{"sport", "teams", "occasion"} for a game between two teams, else None."""
    if "game" in it:
        # From a reader, or the judge: whole or nothing, so one bad line never costs the morning.
        g = it["game"] if isinstance(it["game"], dict) else {}
        teams = g.get("teams")
        ok = isinstance(g.get("sport"), str) and g["sport"].strip() and isinstance(teams, list) and len(teams) == 2 \
            and all(isinstance(t, str) and t.strip() for t in teams)
        occasion = g.get("occasion") if isinstance(g.get("occasion"), str) else None
        return {"sport": g["sport"].strip(), "teams": [t.strip() for t in teams], "occasion": occasion} if ok else None
    host = CAMPUS_TEAMS.get(it["source_name"].strip())
    m = CAMPUS_GAME.match(title)
    if not host or not m or m["host"] != host[0] or NOT_A_TEAM.search(m["them"]):
        return None
    them = re.sub(r"^#\d+\s+", "", m["them"])  # "#21 Carleton": a ranking, not the team's name
    return {"sport": m["sport"], "teams": [host[1], them], "occasion": m["night"]}


def long_titles(items, existing=()):
    """Event titles still over TITLE_MAX once tidied, for the morning job's model to shorten by
    the title-and-place skill, never cut mid-word (Jesse, 2026-10-21: three lines don't fit the
    Town's Event of the day poster). Games aside: two team names stay whole. An event already
    listed with a short title keeps it (plan), so it isn't asked again."""
    short = {(r.get("source_name"), r.get("source_uid")) for r in existing
             if r.get("source_uid") and len(r.get("title") or "") <= TITLE_MAX}
    out = []
    for it in items:
        if not isinstance(it, dict) or it.get("kind") != "event" or not isinstance(it.get("title"), str):
            continue
        source = str(it.get("source_name") or "").strip()
        t = tidy_title(it["title"], source)
        if len(t) > TITLE_MAX and not game_of(dict(it, source_name=source), t) and t not in out \
                and (source, str(it.get("source_uid") or "").strip()) not in short:
            out.append(t)
    return out


def tidy_place(place, home="St. Joseph MN"):
    """The place line's venue: a named place before its street, no state or ZIP, and no town
    inside the home town (place_line adds any other town)."""
    p = ", ".join(caps(s.strip()) for s in (place or "").split(","))
    for college, short in COLLEGES:
        p = college.sub(short, p)
    p = re.sub(r"\s+at the (CSB|SJU)\b", "", p)
    p = re.sub(r"\s+-\s+", ", ", p)
    games = re.fullmatch(r"([A-Z][\w.' ]*?),\s*Minn\.?(?:\s*[,/]\s*(.+))?", p)  # "St. Joseph, Minn., CSB Stadium"
    if games:
        p = f"{games[2]}, {games[1]}" if games[2] else games[1]
    p = re.sub(r"[\s,]+(?:USA|United States)$", "", p)
    p = re.sub(r"[\s,]+(?:MN|Minn\.?|Minnesota)(?:\s+\d{5}(?:-\d{4})?)?$", "", p)
    p = re.sub(r"[\s,]+\d{5}(?:-\d{4})?$", "", p)
    parts = [s.strip() for s in p.split(",") if s.strip()]
    if parts and not parts[0][0].isdigit():
        parts = parts[:1] + [s for s in parts[1:] if not STREET.search(s)]
    name = re.sub(r"\s+MN$", "", home)
    rest = re.sub(r"^(?:St\.?|Saint)\s+", "", name)
    lead = r"(?:St\.?|Saint)\s+" if rest != name else ""
    trailing = re.compile(r"[\s,]+" + lead + re.escape(rest) + "$", re.I)
    p = ", ".join(parts)
    return trailing.sub("", p) or p


def meets_at(place, host, title):
    """A meeting its host lists with no room is where it always meets (MEETS_AT)."""
    if words(place, PLACE_STOP):
        return place
    return next((p for h, what, p in MEETS_AT if host.strip() == h and what.search(title)), place)


def place_line(place, town, home):
    loc = place.strip() if words(place, PLACE_STOP) else ""
    if town_key(town) != town_key(home) and town_key(town) not in town_key(loc):
        loc = f"{loc}, {town}" if loc else town
    return loc or None


def parse_clock(text):
    # ponytail: reads "7 PM", "6:30 pm", "12 PM". A listed start like "7-9 PM" or "noon" reads
    # as no time, so that event merges only with all-day items; add forms if they show up.
    m = re.fullmatch(r"\s*(\d{1,2})(?::(\d\d))?\s*([AP])\.?M\.?\s*", text or "", re.I)
    return m and time(int(m[1]) % 12 + (12 if m[3].upper() == "P" else 0), int(m[2] or 0))


def where(place, poster):
    """The registry place an event is at. A listing with no place is at its poster's own: the
    sisters' calendar names none, the campus calendar says Saint Benedict's Monastery, one of
    their names (2026-10-21). A place the registry doesn't know gives None."""
    entry, found = registry.place_for(place, poster, places())
    return entry if found or not words(place, PLACE_STOP) else None


def listed_facts(row, home="St. Joseph MN"):
    day = date.fromisoformat(str(row["event_date"])[:10])
    t = None if row.get("all_day") else parse_clock(row.get("start_time"))
    poster = row.get("source_name") or ""
    place = meets_at(tidy_place(row.get("location"), home), poster, tidy_title(row["title"], poster))
    return {"day": day, "at": t and datetime.combine(day, t), "place": words(place, PLACE_STOP),
            "entry": where(place, poster), "title": words(tidy_title(row["title"], poster))}


def show_from(day, size, signup_by):
    """The event-lead-time rule (sources/CONTEXT.md, Lead time)."""
    shown = day - timedelta(LEAD[size])
    if signup_by and shown > signup_by - timedelta(7):
        bigger = [day - timedelta(n) for n in sorted(LEAD.values()) if n > LEAD[size]]
        shown = next((d for d in bigger if d <= signup_by - timedelta(7)), signup_by - timedelta(7))
    return shown


def skip_reason(it, town):
    """Why an item can't be used, or None. Items are model output: one bad item is skipped,
    never the whole morning."""
    if not isinstance(it, dict):
        return "invalid: not a JSON object"
    for k in ("title", "source_name", "source_url"):
        if not isinstance(it.get(k), str) or not it[k].strip():
            return f"invalid: no {k}"
    for k in ("kind", "trust", "area", "start", "end", "place", "town", "blurb", "size",
              "signup_by", "interest", "category"):
        if it.get(k) is not None and not isinstance(it[k], str):
            return f"invalid: {k} must be text"
    if it.get("closed") not in (None, True, False):
        return "invalid: closed must be true or false"
    if it.get("kind") not in ("event", "news"):
        return "invalid: kind must be event or news"
    if it.get("trust") not in TRUST:
        return "invalid: trust must be official or secondhand"
    if it.get("area") not in AREAS:
        return "invalid: area must be town, campus, game, announced or outside"
    # ponytail: "campus" and "game" are the reader's or judge's word; nothing here checks
    # CSB/SJU or the 20 miles. read_events.py's NEARBY venues decide the league's games.
    if it["area"] == "outside":
        return f"outside the area ({it.get('town') or 'no town'})"
    zips = set(re.findall(r"\b(5\d{4})\b", it.get("place") or ""))
    if it["area"] == "town" and (it.get("town") and town_key(it["town"]) != town_key(town["label"])
                                 or zips and not zips & set(town["zips"])):
        return f"outside the area (marked town, but in {it.get('town')} {' '.join(sorted(zips))})".replace(" )", ")")
    return None


def when(start, all_day=False):
    """(local day, local naive datetime or None for all day) from the contract's start."""
    if all_day or re.fullmatch(r"\d{4}-\d\d-\d\d", start):
        return date.fromisoformat(start[:10]), None
    return local(start).date(), local(start).replace(tzinfo=None)


def local(stamp):
    dt = datetime.fromisoformat(stamp)
    if dt.tzinfo is None:
        raise ValueError(f"{stamp!r} needs an offset")
    return dt.astimezone(LOCAL)


_PLACES = None


def places():
    """The registry's place names, read once: every event is tagged with where it happens."""
    global _PLACES
    if _PLACES is None:
        _PLACES = registry.place_index(registry.load(Path(__file__).resolve().parents[2])[0])
    return _PLACES


def event_of(it, today, interests, home, notes, titles=None):
    try:
        day, at = when(it.get("start") or "", it.get("all_day"))
        until = it.get("end") or ""
        if re.fullmatch(r"\d{4}-\d\d-\d\d", until):
            # A run over days gives its last day (the kiln, Oct 16 to 25; Festival of Cultures,
            # Nov 9 to 14): it lasts until the midnight after, so the Town feed keeps it that long.
            last = date.fromisoformat(until)
            end = datetime.combine(last + timedelta(1), time(), LOCAL) if last > day else None
        else:
            end = None if at is None or not until else local(until)
            if end and end.time() == time(23, 59):
                end = None  # a calendar's "until 11:59 PM" is how it says no end time
        signup = it.get("signup_by") and date.fromisoformat(it["signup_by"])
    except ValueError as e:
        return None, f"invalid: unreadable date ({e})"
    if day < today:
        return None, "past"
    size = it.get("size")
    if size not in LEAD:
        notes.append(f"size {size!r} unknown for {it['title']!r}: sized everyday")
        size = "everyday"
    interest = it.get("interest")
    if interest is not None and interest not in interests:
        notes.append(f"interest {interest!r} is not on the list ({it['title']!r}): left empty")
        interest = None
    title, place = tidy_title(it["title"], it["source_name"]), tidy_place(it.get("place"), home)
    title = (titles or {}).get(title, title)
    place = meets_at(place, it["source_name"], title)
    # ponytail: kept out only as it is first listed. A listed event whose sign-ups close later
    # keeps its day (apply_judged keeps a day already set); the event-lead-time skill's pass
    # takes it out. Make a kept-out day win in apply_judged if that pass keeps finding them.
    if it.get("closed") is True or (signup and signup < today):
        shows = (end.date() if end and end.date() > day else day) + timedelta(1)
        notes.append(f"kept out of the Town feed, nobody can still go: {title!r} {day}")
    else:
        shows = show_from(day, size, signup)
    online = ONLINE.search(it["title"]) or place.lower() in ("online", "virtual")
    # ponytail: a source with no ids of its own gets one from the start and title, so when its
    # page moves an event to another day the moved one is added and the old one stays. Fix
    # by reading a whole page's events as a set when sources like that start moving dates.
    # The id comes from the title as the source wrote it, so rewording never orphans a row.
    entry, found = registry.place_for(place, it["source_name"], places())
    if place and not found and not online:
        notes.append(f"place not in the registry: {place!r} ({it['source_name']}'s picture stands in)")
    uid = str(it.get("source_uid") or "").strip() or \
        f"page:{day}{at.strftime('T%H%M') if at else ''}:{'-'.join(sorted(words(it['title'])))}"
    row = {"status": None, "title": title, "event_date": day.isoformat(),
           "start_time": at and clock(at), "end_at": end and end.isoformat(), "all_day": at is None,
           "location": "Online" if online else place_line(place, it.get("town") or home, home),
           "description": clip(it.get("blurb"), 1000) or None,
           "source_name": it["source_name"].strip(), "source_url": it["source_url"].strip(),
           "source_uid": uid, "category": interest, "shows_from": shows.isoformat(),
           "place_entry_id": entry, "sport": None, "team_ids": None, "team_names": None, "occasion": None}
    game = game_of(it, title)
    if game:
        row.update(sport=game["sport"], team_ids=[team_id(t) for t in game["teams"]], team_names=game["teams"],
                   occasion=game["occasion"])
    facts = {"day": day, "at": at, "place": words(place, PLACE_STOP), "entry": where(place, it["source_name"]),
             "title": words(title)}
    return {"row": row, "facts": facts}, None


def news_of(it, interests, notes):
    start = it.get("start")
    try:
        day, at = when(start, it.get("all_day")) if start else (None, None)
    except ValueError as e:
        return None, f"invalid: unreadable date ({e})"
    interest = it.get("interest")
    if interest is not None and interest not in interests:
        notes.append(f"interest {interest!r} is not on the list ({it['title']!r}): left empty")
        interest = None
    return {"title": tidy_title(it["title"], it["source_name"], event=False), "blurb": (it.get("blurb") or "").strip() or None,
            "category": it.get("category") if it.get("category") in NEWS_CATEGORIES else "announcement",
            "source_name": it["source_name"].strip(), "source_url": it["source_url"].strip(),
            # The board's tiers as the old curator wrote them: 1 the City, 1.5 Newsleaders.
            "tier": 1 if it["trust"] == "official" else 1.5, "status": None,
            "starts_at": day and (at or datetime.combine(day, time())).replace(tzinfo=LOCAL).isoformat(),
            # Who it matches in the Town feed, and the place whose logo it shows (town-feed 35).
            "interests": [interest] if interest else None, "place_entry_id": where(None, it["source_name"])}, None


def mention(it, uid):
    return {"source_name": it["source_name"].strip(), "source_url": it["source_url"].strip(),
            "source_uid": uid, "trust": TRUST[it["trust"]], "sure": it.get("sure") is True, "new": True}


def trusted(mentions):
    """ADR-001: one sure official mention, or sure mentions from two secondhand sources."""
    sure = [m for m in mentions if m.get("sure")]
    if any(m["trust"] == "official" for m in sure) or len({m["source_name"] for m in sure}) >= 2:
        return True, ""
    return False, "secondhand, one mention" if sure else "unsure"


def group(old=None, facts=None, home="St. Joseph MN"):
    return {"id": old and old["id"], "old": old, "facts": facts or listed_facts(old, home), "items": [],
            "row": None, "mentions": [dict(m) for m in (old or {}).get("mentions") or []]}


def plan(items, existing, today, interests, town=TOWNS["st-joseph-mn"], titles=None):
    """Judged items + the events already listed -> what to write, and each item's outcome.
    `titles`: this morning's shorter titles for long ones, {tidied title: short} (long_titles)."""
    home = town["label"]
    out = {"events": [], "news": [], "outcomes": [None] * len(items), "notes": [], "cancelled": [], "restored": []}
    schedules = []
    groups, by_uid, news = [group(row, home=home) for row in existing], {}, {}
    for g in groups:
        for m in [g["old"]] + g["mentions"]:
            if m.get("source_uid"):
                by_uid[(m["source_name"], m["source_uid"])] = g
    for i, it in enumerate(items):
        if isinstance(it, dict) and it.get("kind") == "schedule":
            schedules.append(it)
            out["outcomes"][i] = ("schedule", f"{len(it.get('sources') or [])} schedules read whole, "
                                              f"{it.get('from')} to {it.get('through')}")
            continue
        why = skip_reason(it, town)
        if not why and it["kind"] == "news":
            n, why = news_of(it, interests, out["notes"])
        elif not why:
            ev, why = event_of(it, today, interests, home, out["notes"], titles)
        if why:
            out["outcomes"][i] = ("skipped", why)
        elif it["kind"] == "news":
            ok, why = trusted([mention(it, None)])
            n["status"] = "published" if ok else "staging"
            # ponytail: secondhand News waits in staging for Jesse; publishing it on a second
            # mention needs News mentions kept too. Add with the Town feed's news card.
            news[(n["title"].lower(), n["source_name"], n["starts_at"])] = n
            out["outcomes"][i] = ("news", "") if ok else ("news held", why)
        else:
            key = (ev["row"]["source_name"], ev["row"]["source_uid"])
            g = by_uid.get(key) or next((g for g in groups if same_event(g["facts"], ev["facts"])
                                         and not own_ids_differ(g, *key)), None)
            if g is None:
                # Two of one source's own ids are two events; nothing for Jesse to settle.
                near = [g for g in groups if g["facts"]["day"] == ev["facts"]["day"] and (
                    same_place(g["facts"]["place"], ev["facts"]["place"])
                    or same_title(g["facts"]["title"], ev["facts"]["title"])) and not own_ids_differ(g, *key)]
                for o in near:
                    other = o["old"]["title"] if o["old"] else o["items"][0][1]["row"]["title"]
                    out["notes"].append(f"kept apart: {ev['row']['title']!r} and {other!r} on "
                                        f"{ev['row']['event_date']}; if they are one event, Jesse settles it")
                g = group(facts=ev["facts"])
                groups.append(g)
            by_uid[key] = g
            g["items"].append((i, ev))
            m = mention(it, key[1])
            g["mentions"] = [x for x in g["mentions"]
                             if (x["source_name"], x.get("source_url")) != (m["source_name"], m["source_url"])] + [m]
    out["news"] = list(news.values())

    for g in groups:
        if not g["items"]:
            continue
        ok, why = trusted(g["mentions"])
        old = g["old"]
        if old:
            # The listed row's own source re-reading it: by the same uid, or (no ids on that
            # source) the same event a little reworded or retimed. It keeps its uid.
            mine = [(i, ev) for i, ev in g["items"] if ev["row"]["source_name"] == old["source_name"]]
            primary = next(((i, ev) for i, ev in mine if ev["row"]["source_uid"] == old.get("source_uid")),
                           next(((i, ev) for i, ev in mine if not real_uid(ev["row"]["source_uid"])
                                 and not real_uid(old.get("source_uid")) and old.get("source_uid")), None))
            g["status"] = old["status"]
            if ok and old["status"] == "pending" and old.get("review_reason") is None and old.get("found", True):
                g["status"] = "approved"
        else:
            primary = min(g["items"], key=lambda e: (not items[e[0]].get("sure") is True,
                                                     items[e[0]]["trust"] != "official"))
            g["status"] = "approved" if ok else "pending"
        if old and primary and len(primary[1]["row"]["title"]) > TITLE_MAX >= len(old.get("title") or "") \
                and not primary[1]["row"]["sport"]:
            # A title the morning job or Jesse shortened stays when its source sends the long one
            # again (title-and-place: 40 at most). ponytail: a source that renames an event to
            # another long title keeps the old short one; compare words if renames show up.
            primary[1]["row"]["title"] = old["title"]
        if (old and primary and old["status"] == "rejected" and old.get("review_reason") not in (None, "not_event")
                and any(primary[1]["row"].get(k) != old.get(k)
                        for k in ("title", "event_date", "start_time", "all_day", "location"))):
            g["status"] = "pending"  # a misread its source changed gets another look, as in read_events
        if primary:
            row = dict(primary[1]["row"], status="approved" if ok else "pending")
            if old:
                row["source_uid"] = old["source_uid"]
                if old.get("shows_from") and str(old["event_date"])[:10] == row["event_date"]:
                    row["shows_from"] = str(old["shows_from"])[:10]
                row["category"] = old.get("category") or row["category"]
            g["row"] = row
        for i, ev in g["items"]:
            if old:
                detail = f"into {old['title']!r} {str(old['event_date'])[:10]} (already listed" + \
                         (", same source)" if (i, ev) == primary else ")")
                if g["status"] != old["status"]:
                    detail += "; this mention publishes it"
                elif g["status"] != "approved":
                    detail += f"; stays {g['status']}"
                out["outcomes"][i] = ("merged", detail)
            elif (i, ev) == primary:
                out["outcomes"][i] = ("published", "") if ok else ("held", why)
            else:
                out["outcomes"][i] = ("merged", f"with #{primary[0] + 1} {primary[1]['row']['title']!r}")
        out["events"].append(g)

    for g in groups:
        old = g["old"]
        if not old or not old.get("found", True):
            continue
        if g["items"]:
            if old.get("cancelled_at"):
                out["restored"].append(old)
            continue
        day, uid = str(old["event_date"])[:10], str(old.get("source_uid") or "")
        if not old.get("cancelled_at") and any(
                uid.startswith(s.get("uid_prefix") or "\0") and old["source_name"] in (s.get("sources") or ())
                and str(s.get("from")) <= day <= str(s.get("through")) for s in schedules):
            out["cancelled"].append(old)
    return out


def payloads(result):
    """This morning's writes, as public.apply_judged takes them."""
    events = [g["row"] for g in result["events"] if g["row"]]
    mentions = [dict({k: v for k, v in m.items() if k != "new"},
                     **({"event_id": g["id"]} if g["id"] else
                        {"event_source_name": g["row"]["source_name"], "event_source_uid": g["row"]["source_uid"]}))
                for g in result["events"] for m in g["mentions"] if m.get("new")]
    upgrades = [g["id"] for g in result["events"]
                if g["old"] and not g["row"] and g["status"] != g["old"]["status"]]
    return json.loads(json.dumps({"p_events": events, "p_mentions": mentions, "p_upgrades": upgrades,
                                  "p_news": result["news"],
                                  "p_cancelled": [o["id"] for o in result.get("cancelled", [])],
                                  "p_restored": [o["id"] for o in result.get("restored", [])]},
                                 ensure_ascii=False, default=str))


KEYS = ("p_events", "p_mentions", "p_upgrades", "p_news", "p_cancelled", "p_restored")


def to_sql(result, today):
    """The same writes as one call to run by hand, every payload dollar-quoted."""
    p = payloads(result)
    texts = [json.dumps(p[k], ensure_ascii=False) for k in KEYS]
    tag = "j" + secrets.token_hex(8)
    assert not any(f"${tag}$" in t for t in texts)
    args = ",\n  ".join(f"${tag}${t}${tag}$::jsonb" for t in texts)
    return (f"-- write_judged.py, {today}: {len(p['p_events'])} events, {len(p['p_mentions'])} mentions, "
            f"{len(p['p_upgrades'])} published by a new mention, {len(p['p_news'])} news, "
            f"{len(p['p_cancelled'])} cancelled, {len(p['p_restored'])} back on.\n"
            "-- Run only after Jesse's yes. The rules live in public.apply_judged.\n"
            f"select public.apply_judged(\n  {args});\n")


def apply(result):
    """The live write, over the service role key: one call, all or nothing."""
    return Supabase().call("POST", "rpc/apply_judged", payloads(result))


def listed_in_db():
    return Supabase().call("POST", "rpc/listed_for_writer", {})


def report(items, r):
    for i, (it, (what, detail)) in enumerate(zip(items, r["outcomes"])):
        it = it if isinstance(it, dict) else {}
        print(f"  {i + 1:>2} {what:<10} {str(it.get('start') or '')[:10]:<10}  "
              f"{str(it.get('title') or it.get('kind'))[:46]:<46} {detail}")
    counts = {}
    for what, _ in r["outcomes"]:
        counts[what] = counts.get(what, 0) + 1
    print(f"[judged] {len(items)} items: " + ", ".join(f"{n} {w}" for w, n in sorted(counts.items())))
    new = sum(1 for g in r["events"] if not g["old"])
    reread = sum(1 for g in r["events"] if g["old"] and g["row"])
    print(f"[judged] the SQL would add {new} events, update {reread} already listed, "
          f"add mentions to {len(r['events']) - new - reread} more, and write {len(r['news'])} news")
    for o in r["cancelled"]:
        print(f"[cancelled] {str(o['event_date'])[:10]} {o['title']!r}: gone from its schedule")
    for o in r["restored"]:
        print(f"[back on] {str(o['event_date'])[:10]} {o['title']!r}")
    for n in r["notes"]:
        print(f"[note] {n}")
    for g in r["events"]:
        if g["row"] and len(g["row"]["title"]) > TITLE_MAX and not g["row"]["sport"]:
            print(f"[long title] {g['row']['title']!r}: over {TITLE_MAX}; give it a shorter one (title-and-place)")


INTERESTS = ["live_music", "families_kids", "bars", "markets", "art_theater", "watch_sports"]
TODAY = date(2026, 10, 14)


def t_long_titles_shortened_and_kept():
    chapel = item(title="Anniversary of the Dedication of Sacred Heart Chapel", source_uid="sisters:1")
    hockey = item(title="Sartell-Sauk Rapids Girls Hockey vs Fergus Falls", source_uid="mshsl:9",
                  game={"sport": "Girls Hockey", "teams": ["Sartell-Sauk Rapids", "Fergus Falls"]})
    assert long_titles([chapel, hockey, item()]) == [chapel["title"]], "a game's team names stay whole"
    short = {chapel["title"]: "Sacred Heart Chapel Anniversary"}
    assert run([chapel])["events"][0]["row"]["title"] == chapel["title"], "no short one given: as written"
    got = plan([chapel], [], TODAY, INTERESTS, titles=short)["events"][0]["row"]["title"]
    assert got == "Sacred Heart Chapel Anniversary", got
    # Listed short already: not asked again, and its source's long title doesn't undo it.
    old = listed(title="Sacred Heart Chapel Anniversary", event_date="2026-10-24", start_time="4 PM",
                 location="Milk & Honey Ciders", source_name="Milk & Honey Ciders", source_uid="sisters:1")
    assert long_titles([chapel], [old]) == []
    assert run([chapel], [old])["events"][0]["row"]["title"] == "Sacred Heart Chapel Anniversary"
    long_old = dict(old, title="Sartell-Sauk Rapids Girls Hockey vs Fergus Falls", source_uid="mshsl:9")
    assert run([hockey], [long_old])["events"][0]["row"]["title"] == hockey["title"]


def t_description_cut_at_a_word():
    long = "word " * 300
    got = run([item(blurb=long)])["events"][0]["row"]["description"]
    assert len(got) <= 1000 and got.endswith("word…"), got[-20:]
    assert run([item(blurb="  Bring a chair.\n")])["events"][0]["row"]["description"] == "Bring a chair."
    assert run([item(blurb=None)])["events"][0]["row"]["description"] is None


def t_all_day_run_keeps_its_last_day():
    week = item(start="2026-11-09", end="2026-11-14", all_day=True, title="Festival of Cultures")
    row = run([week])["events"][0]["row"]
    assert row["all_day"] and row["end_at"] == "2026-11-15T00:00:00-06:00", row
    assert run([dict(week, end="2026-11-09")])["events"][0]["row"]["end_at"] is None, "one day is no run"
    kiln = run([item(title="Kiln Firing", start="2026-10-16T16:00:00-05:00", end="2026-10-25")])["events"][0]["row"]
    assert kiln["end_at"] == "2026-10-26T00:00:00-05:00" and kiln["start_time"] == "4 PM", "a timed run ends after its last day"


def t_city_meeting_end_and_place():
    meeting = item(title="City Council Meeting", start="2026-11-02T18:00:00-06:00", end="2026-11-02T23:59:00-06:00",
                   place="St. Joseph, MN 56374", source_name="City of St. Joseph", interest=None)
    row = run([meeting])["events"][0]["row"]
    assert row["end_at"] is None and row["location"] == "City Hall", row
    assert run([dict(meeting, title="Park Board Meeting")])["events"][0]["row"]["location"] is None
    assert run([item(place="")])["events"][0]["row"]["location"] is None, "only the city's own meetings"


def item(**kw):
    base = {"kind": "event", "title": "Plant Bingo", "start": "2026-10-24T16:00:00-05:00",
            "end": "2026-10-24T18:30:00-05:00", "all_day": False,
            "place": "Milk & Honey Ciders, 11738 County Road 51", "town": "St. Joseph", "area": "town",
            "source_name": "Milk & Honey Ciders", "source_url": "https://www.milkandhoneyciders.com/events",
            "trust": "official", "sure": True, "size": "notable", "interest": "bars",
            "blurb": "Plant bingo for Angel Reins Stable, $30."}
    base.update(kw)
    return base


def listed(**kw):
    base = {"id": "11111111-1111-1111-1111-111111111111", "status": "approved", "title": "Banff Mountain Film Festival",
            "event_date": "2026-12-04", "start_time": "7 PM", "all_day": False, "location": "Saint John's University",
            "source_name": "CSB SJU Outdoor U", "source_uid": "board:f2c7", "shows_from": "2026-11-06",
            "review_reason": None, "found": True}
    base.update(kw)
    return base


def run(items, existing=()):
    return plan(items, list(existing), TODAY, INTERESTS)


def outcome(r, i):
    return r["outcomes"][i][0]


def t_event_or_news():
    r = run([item(), item(kind="news", title="St. Joseph office closed", start=None, category="business")])
    assert [g["row"]["title"] for g in r["events"]] == ["Plant Bingo"], r["events"]
    assert [n["title"] for n in r["news"]] == ["St. Joseph office closed"], r["news"]
    assert r["news"][0]["category"] == "business" and r["news"][0]["status"] == "published"
    assert outcome(r, 0) == "published" and outcome(r, 1) == "news"
    # News matches neighbours by its interest and shows its place's logo (town-feed 35).
    assert r["news"][0]["interests"] == ["bars"] and r["news"][0]["place_entry_id"] == "milk-and-honey-ciders", r["news"]
    r = run([item(kind="news", title="Pumpkin latte", start=None, category="business", interest="lattes")])
    assert r["news"][0]["interests"] is None and "'lattes' is not on the list" in r["notes"][0], r


def t_official_one_mention():
    r = run([item()])
    g = r["events"][0]
    assert g["status"] == "approved" and len(g["mentions"]) == 1, g
    row = g["row"]
    assert (row["event_date"], row["start_time"], row["all_day"]) == ("2026-10-24", "4 PM", False), row
    assert row["end_at"] == "2026-10-24T18:30:00-05:00" and row["source_uid"].startswith("page:2026-10-24"), row


def t_secondhand_needs_two():
    one = item(source_name="Newsleaders", trust="secondhand", source_url="https://thenewsleaders.com/a")
    r = run([one])
    assert r["events"][0]["status"] == "pending" and outcome(r, 0) == "held", r["outcomes"]
    assert "one mention" in r["outcomes"][0][1]
    assert run([dict(one, trust="squishy")])["events"][0]["mentions"][0]["trust"] == "squishy"
    same_source_twice = run([one, dict(one, source_url="https://thenewsleaders.com/b")])
    assert same_source_twice["events"][0]["status"] == "pending", "one source twice is not two mentions"
    two = item(source_name="Joetown town group", trust="secondhand", source_url="https://facebook.com/x",
               title="Plant Bingo night", start="2026-10-24T16:30:00-05:00")
    r = run([one, two])
    assert len(r["events"]) == 1 and r["events"][0]["status"] == "approved", r["events"]
    assert len(r["events"][0]["mentions"]) == 2 and outcome(r, 1) == "merged"
    # A second secondhand mention on a later morning publishes the one already waiting.
    waiting = listed(status="pending", title="Plant Bingo", event_date="2026-10-24", start_time="4 PM",
                     location="Milk & Honey Ciders", source_name="Newsleaders", source_uid="page:x",
                     mentions=[{"source_name": "Newsleaders", "source_uid": "page:x", "trust": "secondhand", "sure": True}])
    r = run([two], [waiting])
    g = r["events"][0]
    assert g["id"] == waiting["id"] and g["status"] == "approved" and g["row"] is None, g
    assert outcome(r, 0) == "merged" and "publishes" in r["outcomes"][0][1], r["outcomes"]


def t_unsure_held():
    r = run([item(sure=False), item(kind="news", title="Shop hours change", start=None, sure=False)])
    assert r["events"][0]["status"] == "pending" and outcome(r, 0) == "held"
    assert r["news"][0]["status"] == "staging" and outcome(r, 1) == "news held", r["outcomes"]
    assert "unsure" in r["outcomes"][1][1]


def t_merge_true_pair():
    a = item(source_name="City of St. Joseph", title="Print Making Workshop (native plants)",
             start="2026-11-20T10:00:00-06:00", end=None, place="Saint John's University, 2850 Abbey Plaza, Collegeville",
             town="Collegeville", area="campus", source_uid="2443")
    old = listed(id="22222222-2222-2222-2222-222222222222", title="Print making with native plants",
                 event_date="2026-11-20", start_time="10 AM", location="Outdoor U, Saint John's University",
                 source_uid="board:e74e")
    r = run([a], [old])
    assert len(r["events"]) == 1 and r["events"][0]["id"] == old["id"], r["events"]
    assert outcome(r, 0) == "merged" and "Print making with native plants" in r["outcomes"][0][1]


def t_merge_near_miss_kept_apart():
    work = listed(title="City Council Work Session", event_date="2026-10-19", start_time="5 PM",
                  location="St. Joseph City Hall", source_name="City of St. Joseph", source_uid="2354")
    meeting = item(source_name="Newsleaders", trust="secondhand", title="City Council Meeting",
                   start="2026-10-19T18:00:00-05:00", end=None, place="St. Joseph City Hall", interest=None, size="everyday")
    r = run([meeting], [work])
    assert r["events"][0]["id"] is None and outcome(r, 0) == "held", "work session and meeting are two events"
    other_park = [item(place="Centennial Park shelter"), item(place="Millstream Park shelter", source_name="City")]
    assert len(run(other_park)["events"]) == 2, "two parks are two places"
    later = [item(), item(source_name="City", start="2026-10-24T18:00:00-05:00")]
    assert len(run(later)["events"]) == 2, "two hours apart"
    no_place = [item(), item(source_name="City", place="")]
    assert len(run(no_place)["events"]) == 2, "an unknown place is not the same place"
    game = dict(place="Sartell High School", town="Sartell", area="game", start="2026-10-23T19:00:00-05:00")
    two_sports = [item(title="Sartell vs Tech football", **game), item(title="Sartell vs Tech volleyball", source_name="SRT", **game)]
    assert len(run(two_sports)["events"]) == 2, "football and volleyball are two games"
    levels = [item(title="Sartell vs Tech football", **game),
              item(title="Sartell vs Tech JV football", source_name="SRT", **dict(game, start="2026-10-23T18:00:00-05:00"))]
    assert len(run(levels)["events"]) == 2, "JV and varsity are two games"
    one_source = [item(source_uid="a1"), item(source_uid="a2", title="Plant Bingo night")]
    assert len(run(one_source)["events"]) == 2, "a source's own two ids are two events"
    board = listed(title="School Board meeting", event_date="2026-10-21", start_time="6:30 PM",
                   location="Colman Theatre, Benedicta Arts Center", source_name="Kennedy", source_uid="board:532f")
    feed = item(title="School Board Meeting", start="2026-10-21T18:30:00-05:00", place="Colman Theater",
                source_name="Kennedy", source_uid="877641_2026-10-21")
    r2 = run([feed], [board])
    assert r2["events"][0]["id"] == board["id"] and outcome(r2, 0) == "merged", "a board copy is not the source's own id"
    assert any("kept apart" in n and "City Council Work Session" in n for n in r["notes"]), r["notes"]


def t_same_time_no_place():
    feed = listed(id="33333333-3333-3333-3333-333333333333", title="City Council Meeting", event_date="2026-10-19",
                  start_time="6 PM", location=None, source_name="City of St. Joseph", source_uid="2310")
    page = item(title="City Council Meeting", start="2026-10-19T18:00:00-05:00", end=None, place="",
                source_name="City of St. Joseph", interest=None, size="everyday")
    r = run([page], [feed])
    assert len(r["events"]) == 1 and r["events"][0]["id"] == feed["id"], "the page's copy of a feed meeting is one Event"
    work = dict(page, title="City Council Work Session")
    assert run([work], [feed])["events"][0]["id"] is None, "another title at the same time stays apart"
    park = dict(feed, title="Park Board Meeting")  # a council meeting has City Hall to go on (MEETS_AT)
    later = dict(page, title="Park Board Meeting", start="2026-10-19T18:30:00-05:00")
    assert run([later], [park])["events"][0]["id"] is None, "half an hour later, with no place to go on, stays apart"


def t_no_place_is_its_posters_own():
    """The sisters' calendar names no place; the campus calendar lists the same evening at
    Saint Benedict's Monastery, one of their names. That is one Event (Jesse, 2026-10-21)."""
    campus = listed(title="Anniversary of the Dedication of Sacred Heart Chapel", event_date="2026-10-23",
                    start_time="7 PM", location="Saint Benedict's Monastery",
                    source_name="Saint Benedict's Monastery", source_uid="4770133")
    sisters = item(title="Anniversary of the Dedication of Sacred Heart Chapel", start="2026-10-23T19:00:00-05:00",
                   end=None, place="", source_name="Sisters of the Order of Saint Benedict",
                   source_uid="10000638-1792782000-1792785600@sbm.osb.org", interest=None, size="everyday")
    r = run([sisters], [campus])
    assert len(r["events"]) == 1 and r["events"][0]["id"] == campus["id"], r["events"]
    all_day = run([dict(sisters, start="2026-10-24", all_day=True)],
                  [dict(campus, event_date="2026-10-24", start_time=None, all_day=True)])
    assert all_day["events"][0]["id"] == campus["id"], "both all day, the same day"
    later = dict(sisters, start="2026-10-23T19:30:00-05:00")
    assert run([later], [campus])["events"][0]["id"] is None, "with no place, only the very same start"
    city = dict(sisters, source_name="City of St. Joseph", source_url="https://www.stjosephmn.gov/")
    assert run([city], [campus])["events"][0]["id"] is None, "the City's own place is not the monastery"
    unknown = dict(campus, location="Lakeside Bandshell")
    assert run([sisters], [unknown])["events"][0]["id"] is None, "a place not in the registry tells nothing"


def t_reread_updates():
    old = listed(title="Fare for All", event_date="2026-12-07", start_time="3:30 PM", location="610 County Rd 2",
                 source_name="City of St. Joseph", source_uid="2336", shows_from="2026-11-23")
    moved = item(source_name="City of St. Joseph", source_uid="2336", title="Fare for All",
                 start="2026-12-14T15:30:00-06:00", end=None, place="610 County Rd 2", size="everyday", interest=None)
    r = run([moved], [old])
    g = r["events"][0]
    assert len(r["events"]) == 1 and g["id"] == old["id"] and g["row"]["source_uid"] == "2336", g
    assert g["row"]["event_date"] == "2026-12-14" and g["row"]["shows_from"] == "2026-11-30", g["row"]
    assert outcome(r, 0) == "merged" and "same source" in r["outcomes"][0][1]
    mine = listed(title="Plant Bingo", event_date="2026-10-24", start_time="4 PM", location="Milk & Honey Ciders",
                  source_name="Milk & Honey Ciders", source_uid="page:2026-10-24T1600:bingo-plant")
    r2 = run([item(title="Plant Bingo for Angel Reins", start="2026-10-24T16:30:00-05:00")], [mine])
    g = r2["events"][0]
    assert g["id"] == mine["id"] and g["row"]["source_uid"] == mine["source_uid"], g
    assert g["row"]["start_time"] == "4:30 PM" and "same source" in r2["outcomes"][0][1], (g["row"], r2["outcomes"])
    # The same page read twice the same morning, no uid: one event.
    assert len(run([item(), item()])["events"]) == 1
    assert "on conflict on constraint club_events_source_uid_key do update" in WRITES.read_text()


def t_misread_comes_back():
    """Like read_events: a decline for a misread goes back to Review when the source changes it."""
    base = dict(title="Plant Bingo", event_date="2026-10-23", start_time="4 PM", location="Milk & Honey Ciders",
                source_name="Milk & Honey Ciders", source_uid="page:2026-10-24T1600:bingo-plant")
    moved = run([item()], [listed(status="rejected", review_reason="wrong_when", **base)])
    assert moved["events"][0]["status"] == "pending", moved["events"][0]["status"]
    not_event = run([item()], [listed(status="rejected", review_reason="not_event", **base)])
    assert not_event["events"][0]["status"] == "rejected", "not an event stays declined"
    sql = WRITES.read_text()
    assert "review_reason is distinct from 'not_event'" in sql and "then 'pending'" in sql, "the database does the same"


def t_cancelled():
    """A found event its schedule dropped is kept and marked cancelled; back on the schedule, it
    is restored (Jesse, 2026-10-15)."""
    game = dict(title="Sartell Volleyball vs ROCORI", event_date="2026-10-20", start_time="7 PM",
                location="ROCORI High School, Cold Spring", source_name="ROCORI High School",
                source_uid="mshsl:153:rocori|sartell:1")
    line = {"kind": "schedule", "uid_prefix": "mshsl:", "from": "2026-10-14", "through": "2026-11-11",
            "sources": ["ROCORI High School", "Sartell High School"]}
    gone = listed(**game)
    r = run([line], [gone])
    assert [o["id"] for o in r["cancelled"]] == [gone["id"]] and outcome(r, 0) == "schedule", r
    assert payloads(r)["p_cancelled"] == [gone["id"]] and not r["events"], "kept: nothing written but the mark"
    for other in (dict(game, source_uid="2336"), dict(game, source_name="City of St. Joseph"),
                  dict(game, event_date="2026-11-20"), dict(game, found=False),
                  dict(game, cancelled_at="2026-10-15T11:00:00Z")):
        assert not run([line], [listed(**other)])["cancelled"], other
    assert not run([], [gone])["cancelled"], "no schedule line, a school not read: nothing called off"
    back = listed(**dict(game, cancelled_at="2026-10-15T11:00:00Z"))
    seen = item(title="Sartell Volleyball vs ROCORI", start="2026-10-20T19:00:00-05:00", end=None, place="ROCORI High School",
                town="Cold Spring", area="game", source_name="ROCORI High School", source_uid=game["source_uid"],
                interest="watch_sports", size="everyday")
    r = run([seen, line], [back])
    assert not r["cancelled"] and [o["id"] for o in r["restored"]] == [back["id"]], r
    g = r["events"][0]
    assert g["id"] == back["id"] and g["row"]["title"] == "Sartell Volleyball vs ROCORI", g
    merged = listed(**dict(back, source_name="Sartell High School"))  # back on, under the other school's name
    r = run([seen, line], [merged])
    assert r["events"][0]["id"] == merged["id"] and r["restored"] == [merged], "a cancelled one still merges"
    db = WRITES.read_text()
    assert "cancelled_at = null,\n    shows_from" in db, "a re-read by its own source restores it"
    assert "set cancelled_at = now()\n" in db and "set cancelled_at = null\n" in db, "only the mark changes"
    assert "'Cancelled: ' ||" not in db, "the title stays as written: the app shows the tag (ticket 12)"
    assert not re.search(r"\bdelete\s+from\b", db, re.I), "never deleted"


def t_admin_status_kept():
    same = run([item()])["events"][0]["row"]  # the source re-reads it unchanged
    for st, reason in (("rejected", "wrong_when"), ("approved", None), ("pending", "wrong_place")):
        old = listed(status=st, review_reason=reason, **{k: same[k] for k in (
            "title", "event_date", "start_time", "all_day", "location", "source_name", "source_uid")})
        r = run([item()], [old])
        assert r["events"][0]["status"] == st, (st, r["events"][0]["status"])
    sql = WRITES.read_text().split("-- 1. New found events")[1]
    assert "when club_events.status = 'pending' and club_events.review_reason is null" in sql
    assert "status = 'approved'" not in sql.split("on conflict")[0], "insert never forces approved over a row"


def t_show_from_by_size():
    for size, day in (("everyday", "2026-10-10"), ("notable", "2026-09-26"), ("big", "2026-08-29")):
        r = run([item(size=size)])
        assert r["events"][0]["row"]["shows_from"] == day, (size, r["events"][0]["row"]["shows_from"])
    # Run in August, so these sign-ups are still open.
    r = plan([item(size="notable", signup_by="2026-09-30")], [], date(2026, 8, 1), INTERESTS)
    assert r["events"][0]["row"]["shows_from"] == "2026-08-29", "sized up to big to land a week before sign-up closes"
    r = plan([item(size="notable", signup_by="2026-08-30")], [], date(2026, 8, 1), INTERESTS)
    assert r["events"][0]["row"]["shows_from"] == "2026-08-23", "even big misses it: the deadline minus a week"
    r = run([item(size="huge")])
    assert r["events"][0]["row"]["shows_from"] == "2026-10-10" and "size" in " ".join(r["notes"])


def t_kept_out_when_nobody_can_go():
    r = run([item(closed=True)])
    assert r["events"][0]["row"]["shows_from"] == "2026-10-25" and "kept out" in " ".join(r["notes"])
    r = run([item(signup_by="2026-10-13")])
    assert r["events"][0]["row"]["shows_from"] == "2026-10-25", "sign-ups closed yesterday"
    r = run([item(signup_by="2026-10-14")])
    assert r["events"][0]["row"]["shows_from"] == "2026-09-26", "sign-ups close today: still open"
    r = run([item(closed=True, end="2026-10-26T12:00:00-05:00")])
    assert r["events"][0]["row"]["shows_from"] == "2026-10-27", "a multi-day event: the day after it ends"
    assert run([item(closed="yes")])["outcomes"][0] == ("skipped", "invalid: closed must be true or false")


def t_interest_checked():
    r = run([item(interest="live_music"), item(interest="music_arts", title="Stitch and Sip", start="2026-10-28T18:00:00-05:00")])
    rows = [g["row"] for g in r["events"]]
    assert rows[0]["category"] == "live_music" and rows[1]["category"] is None, rows
    assert any("music_arts" in n for n in r["notes"]), r["notes"]


def t_place_entry():
    arena = item(title="SJU Hockey vs Augsburg", place="Sexton Arena", town="Collegeville", area="campus",
                 source_name="SJU Athletics", interest="watch_sports")
    shelter = item(title="Picnic in the Park", place="Centennial Park shelter", source_name="City of St. Joseph",
                   source_url="https://www.stjosephmn.gov/")
    zoo = item(title="Family Zoo Day", place="Hemker Park & Zoo", town="Freeport", area="announced",
               source_name="City of St. Joseph", source_url="https://www.stjosephmn.gov/")
    band = item(title="Band in the Park", place="Lakeside Bandshell", source_name="City of St. Joseph",
                source_url="https://www.stjosephmn.gov/", start="2026-10-25T18:00:00-05:00")
    r = run([item(), arena, shelter, zoo, band])
    ids = {g["row"]["title"]: g["row"]["place_entry_id"] for g in r["events"]}
    assert ids == {"Plant Bingo": "milk-and-honey-ciders", "SJU Hockey vs Augsburg": "sju",
                   "Picnic in the Park": "centennial-park", "Family Zoo Day": "hemker-park-zoo",
                   "Band in the Park": "city-of-st-joseph"}, ids
    assert [n for n in r["notes"] if "not in the registry" in n] == [
        "place not in the registry: 'Lakeside Bandshell' (City of St. Joseph's picture stands in)"], r["notes"]
    assert "place_entry_id = coalesce(excluded.place_entry_id" in WRITES.read_text(), "the database keeps it"


def t_area():
    campus = item(title="Animal Tracking", start="2027-01-09T13:00:00-06:00", place="Saint John's Abbey Arboretum",
                  town="Collegeville", area="campus", source_name="City of St. Joseph")
    game = item(title="Cathedral vs Sartell football", start="2026-10-23T19:00:00-05:00", place="Cathedral High School",
                town="St. Cloud", area="game", source_name="Sartell-St. Stephen Schools", interest="watch_sports")
    away = item(title="Waite Park fair", area="outside", town="Waite Park")
    zoo = item(title="Family Zoo Day", start="2026-10-17T10:00:00-05:00", place="Hemker Park & Zoo",
               town="Freeport", area="announced", source_name="City of St. Joseph")
    r = run([campus, game, away, zoo])
    locs = [g["row"]["location"] for g in r["events"]]
    assert locs == ["Saint John's Abbey Arboretum, Collegeville", "Cathedral High School, St. Cloud",
                    "Hemker Park & Zoo, Freeport"], locs
    named = run([dict(game, place="Sartell High School", town="Sartell")])
    assert named["events"][0]["row"]["location"] == "Sartell High School", "already names its town"
    assert outcome(r, 2) == "skipped" and "outside" in r["outcomes"][2][1]
    r = run([item(town="St. Cloud"), item(place="Cool Spot, 101 Division St, St. Cloud, MN 56301")])
    assert [o[0] for o in r["outcomes"]] == ["skipped", "skipped"], r["outcomes"]
    bare = run([item(place="St. Joseph, MN 56374")])
    assert bare["events"][0]["row"]["location"] is None, "a place naming only the town is no place"


def t_past_and_invalid_skipped():
    bad = [item(start="2026-10-13T19:00:00-05:00"), item(trust="maybe"), item(start="next Friday"),
           item(end="2026-10-24T18:30:00"), item(area=["town"]), item(place=7), "not an object",
           item(kind="news", start="next Friday"), item(size=["big"])]
    r = run(bad + [item()])
    assert [o[0] for o in r["outcomes"]] == ["skipped"] * len(bad) + ["published"], r["outcomes"]
    news = run([item(kind="news", title="No school", start="2026-10-15")])["news"][0]
    assert news["starts_at"] == "2026-10-15T00:00:00-05:00", news


def t_writes_are_one_safe_call():
    r = run([item(blurb="$$ drop table x; $$"), item(kind="news", title="Closed Monday", start=None)])
    p = payloads(r)
    assert [len(p[k]) for k in KEYS] == [1, 1, 0, 1, 0, 0], p
    assert p["p_events"][0]["description"] == "$$ drop table x; $$", "the payload carries text as data"
    sql = to_sql(r, TODAY)
    assert sql.lstrip().startswith("--") and "select public.apply_judged(" in sql and sql.count("::jsonb") == 6, sql[:200]
    db = WRITES.read_text()
    assert "insert into public.event_mentions" in db and "insert into public.board_items" in db
    assert "on conflict (lower(title), source_name, coalesce(starts_at, '-infinity'::timestamptz))" in db
    assert "from public, anon, authenticated" in db and "to service_role" in db, "only the service role may write"


def t_interest_list_is_the_apps():
    ids = interest_ids()
    assert {"live_music", "families_kids", "outdoors", "volunteering"} <= set(ids), ids


WORDING = [  # (title, host, place) as read on 2026-10-14 -> (title, place) on the card
    ("College of Saint Benedict Soccer vs Hamline - Senior Night", "CSB Athletics", "St. Joseph, Minn., CSB Stadium",
     "CSB Soccer vs Hamline: Senior Night", "CSB Stadium"),
    ("Saint John's University Football vs Concordia (Homecoming)", "SJU Athletics", "Collegeville, Minn., Clemens Stadium",
     "SJU Football vs Concordia: Homecoming", "Clemens Stadium, Collegeville"),
    ("Saint John's University Rugby vs North Dakota State - SJU Red", "SJU Athletics", "Collegeville, Minn. / Radio Towers",
     "SJU Rugby vs North Dakota State: SJU Red", "Radio Towers, Collegeville"),
    ("Saint John's University Basketball vs St. Cloud State (Exhibition)", "SJU Athletics", "Collegeville, Minn., Sexton Arena",
     "SJU Basketball vs St. Cloud State", "Sexton Arena, Collegeville"),
    ("CSB+SJU Jazz Ensemble", "CSB SJU", "Colman Theatre, Benedicta Arts Center",
     "Jazz Ensemble", "Colman Theatre, Benedicta Arts Center"),
    ("CSB/SJU Jazz Ensemble", "City of St. Joseph", "", "CSB SJU Jazz Ensemble", ""),
    ("CSB and SJU Choir", "City of St. Joseph", "", "CSB SJU Choir", ""),
    ("Homecoming 2026", "CSB SJU Campus Events", "", "Homecoming", ""),
    ("2026 Clemens Lecture", "CSB SJU Campus Events", "Benedicta Arts Center, College Avenue South, Saint Joseph, MN",
     "Clemens Lecture", "Benedicta Arts Center"),
    ("Plant Bingo benefiting Angel Reins Stable ($30)", "Milk & Honey Ciders", "Milk & Honey Ciders, 11738 County Road 51",
     "Plant Bingo for Angel Reins Stable", "Milk & Honey Ciders"),
    ("Joint Planning Board (as needed)", "City of St. Joseph", "75 Callaway Street East St. Joseph MN 56374",
     "Joint Planning Board", "75 Callaway Street East"),
    ("Festival of Cultures (FOC)", "CSB SJU Campus Events", "", "Festival of Cultures", ""),
    ("No School - Teacher Workshop (Half Day - Morning)", "Kennedy Community School", "",
     "No School: Teacher Workshop, Half Day, Morning", ""),
    ("Farmers' Market final day (Fridays through Oct 16)", "St. Joseph Farmers' Market", "", "Farmers' Market final day", ""),
    ("“The Ladder of Divine Graces”", "Saint Benedict's Monastery", "", "The Ladder of Divine Graces", ""),
    ("Advent Sacred Pause • Virtual", "Saint Benedict's Monastery", "", "Advent Sacred Pause", ""),
    ("Popcorn Fridays @ The Learning Commons", "CSB SJU Libraries", "Learning Commons", "Popcorn Fridays at the Learning Commons",
     "Learning Commons"),
    ("Biology/Biochemistry Exploration Fair", "CSB SJU Campus Events", "", "Biology Biochemistry Exploration Fair", ""),
    ("What it Means to Be a Two-Spirit Influencer: A Story of Social Media and Community", "CSB SJU Campus Events",
     "Gorecki Center at the College of Saint Benedict, College Avenue South, Saint Joseph, MN",
     "What it Means to Be a Two-Spirit Influencer", "Gorecki Center"),
    ("CSB Figure Skating Club Performance", "CSB SJU Campus Events", "MUNICIPAL ATHLETIC COMPLEX, Veterans Drive, St. Cloud, MN",
     "CSB Figure Skating Club Performance", "Municipal Athletic Complex, St. Cloud"),
    ("Free Art Prints from The Saint John's Bible", "CSB SJU Campus Events", "Liturgical Press, Saint John's Road, Collegeville, MN, USA",
     "Free Art Prints from The Saint John's Bible", "Liturgical Press, Collegeville"),
    ("Park Commission Meeting", "Stearns County", "29709 Kipper Road, St Joseph", "Park Commission Meeting", "29709 Kipper Road"),
    ("Fare for All", "City of St. Joseph", "610 County Rd 2 St. Joseph MN 56374", "Fare for All", "610 County Rd 2"),
    ("The Nolan Lecture", "Saint John's School of Theology", "Saint John's University, Abbey Plaza, Collegeville, MN",
     "The Nolan Lecture", "SJU, Collegeville"),
]


def t_wording():
    for title, host, place, want_title, want_place in WORDING:
        got = (tidy_title(title, host), tidy_place(place))
        assert got == (want_title, want_place), (title, got)
        assert (tidy_title(got[0], host), tidy_place(got[1])) == got, f"tidying twice changes {title!r}"
        assert "/" not in got[0], got
    r = run([item(title="Advent Sacred Pause • Virtual", place="104 Chapel Lane, Saint Joseph, MN"),
             item(title="College of Saint Benedict Soccer vs Hamline", place="St. Joseph, Minn., CSB Stadium",
                  start="2026-10-25T16:00:00-05:00", source_name="CSB Athletics")])
    assert [(g["row"]["title"], g["row"]["location"]) for g in r["events"]] == [
        ("Advent Sacred Pause", "Online"), ("CSB Soccer vs Hamline", "CSB Stadium")], r["events"]
    assert r["events"][0]["row"]["source_uid"].endswith(":advent-pause-sacred-virtual"), "the id keeps the source's words"
    news = run([item(kind="news", title="Farmers' Market — National Farmers Market Week, every stall open", start=None)])
    assert news["news"][0]["title"] == "Farmers' Market: National Farmers Market Week, every stall open", news["news"]
    reworded = listed(title="College of Saint Benedict Soccer vs Hamline", event_date="2026-10-25", start_time="4 PM",
                      location="St. Joseph, Minn., CSB Stadium", source_name="CSB SJU", source_uid="board:x")
    assert run([item(title="CSB Soccer vs Hamline", start="2026-10-25T16:00:00-05:00", place="CSB Stadium",
                     source_name="CSB Athletics", source_uid="9")], [reworded])["events"][0]["id"] == reworded["id"], \
        "a reworded copy still merges with the source's own words"


def t_game():
    """A game's sport, teams and special night, from the league's reader or a campus title (real
    titles, 2026-10-20); a meet or a finale is no game."""
    league = item(title="Sartell Girls Soccer vs Sauk Rapids-Rice", place="Sartell High School", town="Sartell",
                  area="game", source_name="Sartell High School", source_url="https://www.mshsl.org/group/504/full-schedule",
                  interest="watch_sports", game={"sport": "Girls Soccer", "teams": ["Sartell", "Sauk Rapids-Rice"]})
    campus = lambda title, host="SJU Athletics": item(title=title, place="Clemens Stadium", town="Collegeville",
                                                      area="campus", source_name=host, interest="watch_sports")
    rows = {g["row"]["title"]: g["row"] for g in run([
        league,
        campus("Saint John's University Football vs Concordia (Homecoming)"),
        campus("College of Saint Benedict Soccer vs Hamline - Senior Night", "CSB Athletics"),
        campus("SJU Rugby vs North Dakota State: SJU Red"),
        campus("CSB Swim and Dive vs Macalester", "CSB Athletics"),
        campus("CSB Cross Country vs Fall Finale", "CSB Athletics"),
        campus("SJU Cross Country vs Saint John's Fall Finale"),
        campus("SJU Soccer vs #21 Carleton"),
        item(title="Bad game line", game={"sport": "Soccer", "teams": ["Sartell"]}),
        item(title="Pumpkin Carving", start="2026-10-25T12:00:00-05:00", game="Soccer"),
        item()])["events"]}
    game = lambda t: tuple(rows[t][k] for k in ("sport", "team_ids", "team_names", "occasion"))
    assert game("Sartell Girls Soccer vs Sauk Rapids-Rice") == (
        "Girls Soccer", ["sartell", "sauk-rapids-rice"], ["Sartell", "Sauk Rapids-Rice"], None)
    assert game("SJU Football vs Concordia: Homecoming") == (
        "Football", ["saint-johns", "concordia"], ["Saint John's", "Concordia"], "Homecoming")
    assert game("CSB Soccer vs Hamline: Senior Night") == (
        "Soccer", ["saint-benedict", "hamline"], ["Saint Benedict", "Hamline"], "Senior Night")
    assert game("SJU Rugby vs North Dakota State: SJU Red")[1:] == (
        ["saint-johns", "north-dakota-state"], ["Saint John's", "North Dakota State"], "SJU Red")
    assert game("CSB Swim and Dive vs Macalester")[0] == "Swim and Dive", "a dual meet is two teams"
    assert game("SJU Soccer vs #21 Carleton")[1] == ["saint-johns", "carleton"], "a ranking is not the name"
    for meet in ("CSB Cross Country vs Fall Finale", "SJU Cross Country vs Saint John's Fall Finale", "Plant Bingo",
                 "Bad game line", "Pumpkin Carving"):
        assert game(meet) == (None, None, None, None), meet
    assert team_id("UW-River Falls") == "uw-river-falls" and team_id("St. Cloud State") == "st-cloud-state"
    sql = WRITES.read_text()
    assert "sport = excluded.sport, team_ids = excluded.team_ids" in sql, "a game read wrong once clears"
    assert "insert into public.teams (id, name, short_name)" in sql, "a new opponent gets its row"


TESTS = [t_place_entry, t_wording, t_interest_list_is_the_apps, t_event_or_news, t_official_one_mention, t_secondhand_needs_two, t_unsure_held, t_merge_true_pair,
         t_merge_near_miss_kept_apart, t_same_time_no_place, t_no_place_is_its_posters_own, t_reread_updates, t_admin_status_kept, t_misread_comes_back, t_cancelled, t_show_from_by_size, t_kept_out_when_nobody_can_go,
         t_interest_checked, t_area, t_past_and_invalid_skipped, t_writes_are_one_safe_call,
         t_description_cut_at_a_word, t_city_meeting_end_and_place, t_game, t_all_day_run_keeps_its_last_day,
         t_long_titles_shortened_and_kept]


def selftest():
    failed = 0
    for t in TESTS:
        try:
            t()
        except Exception as e:  # a failing rule, or one not built yet
            failed += 1
            print(f"FAIL {t.__name__}: {type(e).__name__}: {e}")
    print(f"{len(TESTS) - failed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("items", nargs="?", help="the judged items, one JSON object per line")
    ap.add_argument("--existing", help="'db', or a JSON file of the events already in the list")
    ap.add_argument("--today", help="YYYY-MM-DD; default today in Chicago")
    ap.add_argument("--town", default="st-joseph-mn")
    ap.add_argument("--sql", help="write the live write as SQL to this file")
    ap.add_argument("--apply", action="store_true", help="write to the database (service role key in the environment)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.items or not args.existing:
        ap.error("needs the judged items and --existing (the merge rule checks the list)")
    items = []
    for ln in Path(args.items).read_text().splitlines():
        try:
            items.append(json.loads(ln)) if ln.strip() else None
        except ValueError:
            items.append(f"unreadable line: {ln[:60]}")
    existing = listed_in_db() if args.existing == "db" else json.loads(Path(args.existing).read_text())
    interests = interest_ids()
    if not interests:
        sys.exit(f"no interests read from {INTERESTS_SWIFT}: has Interests.all changed shape?")
    today = date.fromisoformat(args.today) if args.today else datetime.now(LOCAL).date()
    r = plan(items, existing, today, interests, TOWNS[args.town])
    report(items, r)
    if args.sql:
        Path(args.sql).write_text(to_sql(r, today))
        print(f"[judged] SQL for the live write: {args.sql} (not run)")
    if args.apply:
        print(f"[judged] written: {json.dumps(apply(r))}")


if __name__ == "__main__":
    main()
