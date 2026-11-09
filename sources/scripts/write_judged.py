#!/usr/bin/env python3
"""
write_judged.py: the judge's items for one morning become Events and News (BP app
docs/plans/watch-every-place, ticket 03; registry ADR-001 trust tiers, ADR-021 found events,
and the spec's Area rule, which amends ADR-019 and ADR-021's in-town rule).

The part of the morning job that needs no model: saved pages in, Events and News out, and
this is everything after the judge. Dry-run by default (ADR-009): prints what each item
becomes. How the writes land lives in the database, in public.apply_judged (the newest
supabase/migrations/*.sql that makes it): `--apply` calls it with this morning's writes over the
routine's key (SUPABASE_URL and a key in the environment: db.py), `--sql FILE`
writes the same call as SQL to run by hand. Besides its counts, it answers which items it added
(`added`: their places in the Events and News sent; every other Event was merged into one already
listed, every other News a repeat; BP app smooth-mornings 05), and morning.py save counts from that.

  python3 sources/scripts/write_judged.py judged.jsonl --existing existing.json [--sql out.sql]
  python3 sources/scripts/write_judged.py judged.jsonl --existing db --apply
  python3 sources/scripts/write_judged.py --selftest

THE JUDGED ITEM: the contract the judge (ticket 05) produces, one JSON object per line.
  kind         "event" | "news"
  title        the event's own name, the way a neighbour would say it (.claude/skills/title-and-place)
  start        ISO 8601 with offset ("2026-10-24T16:00:00-05:00"), or a date ("2026-11-09")
               when all_day. Required for an event; optional for news (the day it is about).
  end          optional, the same form; a run over days, timed or all day, gives its last day
               alone ("2026-10-25"), and lasts until the midnight after it. A News with none takes it from
               a dated phrase in its title or blurb ("through Nov 29"; news_end), and the Town feed shows
               it until then, up to 30 days (BP app town-feed 49)
  shows_from   news, optional: the day a calendar's closing goes up, a week before its day. read_events.py sets
               it (BP app town-feed 50); a judge never does. With none, a News goes up as it's written
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
  size         events: "everyday" | "notable" | "big" (sources/CONTEXT.md, Event size); when
               unsure, the smaller size. Anything else is sized everyday and named.
  signup_by    events, optional: the date sign-ups or tickets close
  closed       events, optional: true when nobody can still go (sign-ups or tickets closed, sold
               out, registration full, members or invitation only)
  interest     one id from Interests.all (BlockParty/Backend/Interests.swift), or null when none
               fits (a council meeting, a road closure); News matches neighbours by it (town-feed 35)
  category     news: "announcement" (default) | "road" | "school" | "campus" | "business"
  blurb        one line; an Event's says what it is and what to expect, never its date, time, place or price
  price        events, optional: what it costs, as words ("Free", "$10 at the door"); the Event page's own line
               (BP app inside-cards 14)
  game         events, optional: a game between two teams, {"sport": "Girls Soccer", "teams": ["Sartell",
               "St. Cloud"]}, the host's team first, as neighbours say them (read_events.py, the league's
               games). CSB and SJU Athletics games need none: the writer reads them off the title.
  followers_only events, optional: true when only people following its activity or school see it (a JV
               game, an away game, a banquet; read_events.py's Bound reader, BP app school-activities 03)
  activity_team, activity_name
               events, optional: the school's team id and its activity as Bound names it ("apollo",
               "Choir"), so an Event that isn't a game lands on its activity's row

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
  Goes live: every kept item is published (events `approved`, news `published`), official or
    secondhand, on its first mention (Jesse, 2026-10-26: "only hold back if its the exact same").
    Nothing waits for review; the only thing kept out is a repeat.
  News repeats, decided here before anything is sent (BP app codebase-health-2 04): one News is one
    link (smooth-mornings 05). News from the same source with the same link of its own (a post's
    address, a feed item's link; own_link) as a published News of the last 7 days is a repeat
    however its title is worded. This morning's News from one post fold into the first one, whose
    blurb names the others ("Also: ..."). Links compare without tracking, a trailing slash, or
    Facebook's and Instagram's m. (clean_link). A site's home page or a page the registry or the social watch reads is no link
    of its own, since every News read from it shares it. And News from the same place in the last
    7 days (as long as the Town feed shows it) with much the same title (one title's words all in
    the other's, or two shared words at least and two thirds of the shorter title's; a plural or
    "pre-" is the same word; the place's own name, weekdays, free and new not counted) is a repeat
    and is not added (repeat_of).
  Merging: same place (or two names for one registry place), start within an hour (all-day ones: a day apart; one with no time: the
    same day), shared title words = one
    Event; a hyphen inside a word doesn't count ("Boo-tique" is "Bootique"). Shared means
    one title's words all sit inside the other's, with the same team words (JV, varsity,
    girls...); a source's own two ids are always two events. With no place on either, the
    same date and start time to the minute and shared title words are one Event (Jesse,
    2026-10-19: the City's calendar feed and its web page both listed six meetings, no place). With no place on one, one
    host's listings at the very same start under shared title words are one Event too. Checked against the events
    already in the list and this morning's items; every mention is kept (event_mentions) and
    counts toward the two-mention rule. A pair short of that stays two events, and one on the
    same day at the same place or under the same title is named for Jesse to settle: a
    duplicate stays visible, a wrong merge hides a real event (ADR-021). One source's own two ids
    join only when posted twice (the very same listing) or listed twice (listed_twice: one host, one
    start, one place, one name inside the other, in the Town feed).
  Two hosts (BP app smooth-mornings 08, two_hosts): copies from two hosts on the same day are one
    Event when they are at one place (a registry place both lines name, an address naming the
    shops in its building, or a spot the registry doesn't know on the host's own grounds, where
    only the very same name counts), their names match once filler and the other host's name are
    out, and their times agree (an all-day copy agrees with a timed one). A copy joins that way
    only when it matches every copy already in the Event (joins). The same day, a place both lines name and the time, with names
    sharing only a word, are named for Jesse ("kept apart", the morning report's "Maybe the same"), and both stay.
  One Facebook event (one_facebook_event): the same host's same event number on the same day, at agreeing times, is one
    Event whatever its titles.
  Which copy is kept: an event already listed stays the Event and every new copy is its Mention.
    Among new copies, the official one, then its place's own host's (not a town calendar's), then
    a timed one, then one with a place; kept all day, it takes the time another copy gives that day.
  Filled in (Jesse, 2026-10-27): a listed event with no time takes the time another source gives
    it later, keeping its own source, uid and title; a mention with no time joins a shown, timed
    listing before a hidden copy, and leaves its time alone (Jesse, 2026-11-06).
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
from itertools import groupby
from pathlib import Path
from urllib.parse import parse_qsl, quote, urlencode, urlsplit, urlunsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from read_events import BOUND_GENERIC, LOCAL, SCHOOL_KIND, clock
from run import Supabase
from towns import TOWNS, DEFAULT, lookup
import registry

LEAD = {"everyday": 14, "notable": 28, "big": 56}
AREAS = {"town", "campus", "game", "announced", "outside"}
# The registry's trust words (ADR-001); "secondhand" is the spec's word for squishy.
TRUST = {"official": "official", "secondhand": "squishy", "squishy": "squishy"}
NEWS_CATEGORIES = {"announcement", "road", "school", "campus", "business"}
STOP = set("a an and at by for from in of on the to with".split())
# Words that tell two games at one place apart; both titles must carry the same ones.
# A lower level's title carries it: "· C-squad", "· 9th grade", "· Middle school" (school-activities 03).
TEAM = set("jv varsity junior reserve freshman sophomore boys girls men women mens womens squad grade 9th middle "
           "ms 6th 7th 8th csquad bsquad".split())  # words() reads "C-squad" as "csquad"
# Words that name the town or a kind of spot rather than which place: "Centennial Park
# shelter" and "Millstream Park shelter" are two places, and so are "St. Cloud Apollo High
# School" and "St. Cloud Tech High School".
PLACE_STOP = STOP | set("st saint joseph collegeville mn minnesota united states usa county road rd street "
                        "ave avenue east west north south suite park shelter hall center centre building "
                        "room gym lot parking map theater theatre high middle intermediate elementary school".split())
# Meetings whose listing names no room, and where the host's agendas say they always meet: each
# town file's meets_at, keyed by the town's label (the `home` the writer passes around).
MEETS_AT = {t["label"]: [(m["host"], re.compile(m["titles"]), m["place"]) for m in t.get("meets_at") or []]
            for t in TOWNS.values()}
HOME = TOWNS[DEFAULT]["label"]
INTERESTS_SWIFT = Path(__file__).resolve().parents[2] / "BlockParty" / "Backend" / "Interests.swift"
MIGRATIONS = Path(__file__).resolve().parents[2] / "supabase" / "migrations"


def whole_repo(path):
    """A file outside sources/: a copy of sources/ alone (git archive ... sources) doesn't have it,
    and the morning's scripts loaded but couldn't run (2026-10-26). Say so instead of crashing."""
    if not path.exists():
        raise FileNotFoundError(f"{path} is missing: run from a whole checkout, not a copy of sources/ alone")
    return path


def writes():
    """The newest migration that makes public.apply_judged: the self-tests read the SQL the database
    runs today, whatever the file is called."""
    return max(p for p in whole_repo(MIGRATIONS).glob("*.sql")
               if re.search(r"create\s+(or\s+replace\s+)?function\s+public\.apply_judged\s*\(", p.read_text(), re.I))


def interest_ids(swift=INTERESTS_SWIFT):
    """The shared interest list lives in the app (Interests.all); read it, never copy it."""
    return re.findall(r'Interest\(id: "([a-z_]+)"', whole_repo(swift).read_text())


def words(text, stop=STOP):
    text = (text or "").lower().replace("'", "").replace("’", "")
    text = re.sub(r"(?<=[a-z])-(?=[a-z])", "", text)  # "Boo-tique" is "Bootique", "pre-orders" "preorders"
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
    if a["at"] is None and b["at"] is None:
        # Two all-day listings a day apart are one: White Peony's site started Bootique Week on
        # Sunday, its Instagram on Monday (2026-10-26).
        return abs(a["day"] - b["day"]) <= timedelta(1)
    if a["at"] is None or b["at"] is None:
        # A post that gives no time is the same day's timed listing of it: Milk & Honey's
        # "Yoga, Sauna & Cider" and its site's 6:30 PM "Sauna, Yoga, Ice Bath, Cider"
        # (Jesse, 2026-10-27: "merge events that have minimal info on specific time").
        return a["day"] == b["day"]
    return abs(a["at"] - b["at"]) <= timedelta(hours=1)


def same_event(a, b):
    if not a["place"] and not b["place"] and a["at"] is not None:
        return a["at"] == b["at"] and same_title(a["title"], b["title"])
    if not (a["place"] and b["place"]):
        # One gives no place: the same registry place (where()) and the very same start, or the
        # same day with one or both giving no time. Or one host's own two listings of one start: no place
        # reads as the poster's own, so the City's "Youth Dodgeball" with none missed its "Youth dodgeball"
        # at Kennedy (2026-11-04).
        same_start = a["at"] == b["at"] or a["at"] is None or b["at"] is None
        one_host = a["at"] is not None and a["at"] == b["at"] and a["poster"] == b["poster"]
        return (bool(a["entry"]) and a["entry"] == b["entry"] or one_host) and a["day"] == b["day"] and same_start \
            and same_title(a["title"], b["title"])
    # One registry place under two names ("City Hall", "75 Callaway St E") is one place (2026-10-27:
    # the City's Planning Commission was listed twice).
    return within_hour(a, b) and (same_place(a["place"], b["place"]) or bool(a["entry"]) and a["entry"] == b["entry"]) \
        and same_title(a["title"], b["title"])


def real_uid(uid):
    """The source's own id. "page:" is made up here from the start and title; "board:" is the
    town board row an event was moved from (ticket 01), not anything its source gave it."""
    return bool(uid) and not str(uid).startswith(("page:", "board:"))


def posted_twice(a, b):
    """One listing a source posted twice under two ids: the very same title, day, start and place.
    The campus calendar posted the winter's games again on 2026-10-28, and each showed twice in
    the Town feed and lost its live score. Two levels of one game differ in their titles ("C-squad",
    "C2-squad"), and a doubleheader in its start.
    ponytail: two activities at one meet under one title become one, its first activity's; compare
    activity_name once listed_for_writer returns it, if such pairs show up."""
    return a["title"] == b["title"] and a["day"] == b["day"] and a["at"] == b["at"] and same_event(a, b)


def listed_twice(a, b):
    """One host's Event under two of its own ids and two wordings (BP app loopholes 11; Jesse, 2026-11-05): the same
    host, start to the minute and place, one name inside the other with the same team words (same_event). Cathedral's
    calendar listed its Knowledge Bowl meet three times, each with its own id and a longer name, and all three showed
    in the Town feed. Never a game or a followers-only listing: a school's meets look alike and aren't, as Sartell's
    "Mora Invite" (boys, Welia Center) and "Mora Invitational" (girls, main gym)."""
    return a["poster"] == b["poster"] and a["at"] is not None and a["at"] == b["at"] \
        and not (a["game"] or b["game"] or a["followers"] or b["followers"]) and same_event(a, b)


def two_hosts(a, b):
    """One Event from two hosts (BP app smooth-mornings 08): "one" when two copies fall on the same day,
    at one place, under the same name at agreeing times; "maybe" when the day, a place both lines
    name and the times match and the names only share a word (Sunny Mary Meadow's "Indoor Farmers
    Market" and "Holiday Market"), for Jesse to settle while both stay; else None. A word in common
    keeps a game and a lecture at one campus that evening from being asked about.
    - One place: the same place line (same_place), a registry place both lines name (spots: "25 First
      Ave NW" is both shops in that building, a venue is its place's), or a line the registry doesn't
      know from a host the other copy names, on its own grounds (the sisters' Monastic Cemetery and the
      campus calendar's Saint Benedict's Monastery). A pair with no place on one merges only by same_event;
      here it is "maybe" at one registry place (where(): no place is the poster's own) under names sharing a
      word (smooth-mornings 13: Sal's "Puzzle Mania" and the City's "Fall Adult Puzzle Competition" at Sal's).
    - The same name: same_title on the words left once filler and the other copy's host's name are
      taken out ("Free Twinkle & Toast at White Peony Friday" from W|R Home is "Twinkle & Toast", inside
      "Twinkle & Toast: Holiday Launch"). Only the other host's name comes out: a host's name in its own
      title can be a team's, so CSB Athletics' "CSB Soccer vs Hamline" and SJU Athletics' "SJU Soccer vs
      Hamline" stay two. On the host's grounds alone, the names must be the very same (the procession):
      most unknown spots are away games, and Apollo's "Girls JV" at Rush City is not Upsala at Apollo.
    - Agreeing times: within an hour, or one all day (within_hour); the Event keeps the time (plan)."""
    if a["day"] != b["day"] or not within_hour(a, b):
        return None
    mine, theirs = ({w for w in f["title"] if w not in host and w.removesuffix("s") not in host}
                    - FILLER - {"annual", "event", "vs"} for f, host in ((a, b["names"]), (b, a["names"])))
    if not (a["place"] and b["place"]):
        return "maybe" if a["entry"] and a["entry"] == b["entry"] and mine & theirs else None
    named = bool(a["spots"] & b["spots"]) or same_place(a["place"], b["place"])
    # ponytail: an unknown spot is taken for its host's own grounds, so a school's away game reads as at the
    # school, and only the very same name merges on it. Use coordinates if that ever merges wrong.
    grounds = not a["spots"] and a["host"] in b["spots"] or not b["spots"] and b["host"] in a["spots"]
    if not (named or grounds):
        return None
    if same_title(mine, theirs) and (named or mine == theirs):
        return "one"
    return "maybe" if named and mine & theirs else None


def joins(g, f):
    """A copy joins a group by same_event with its first copy, or by two_hosts with every copy in it: a
    shared address is all its shops, so JoeTown's "Holiday Open House" at 25 First Ave NW must not make
    White Peony's and W|R Home's, each at its own shop, one."""
    return same_event(g["facts"], f) or all(same_event(x, f) or two_hosts(x, f) == "one" or renamed(x, f)
                                            for x in [g["facts"], *(ev["facts"] for _, ev in g["items"])])


def renamed(a, b):
    """One host's Event under two names (smooth-mornings 08): Sartell High School's calendar listed "Fall Play"
    and its Instagram "The Crucible", at its Performing Arts Center at 7 PM on Oct 29 and 30 and 2 PM on Oct 31.
    The same poster, start to the minute and place line, one copy a listing with its own id and the other a
    post, neither a game, and names with no word in common: a calendar's plain name and the show's own. Names
    sharing a word are two of a kind, as the City's "City Council Meeting" and "City Council Work Session" at
    6 PM. Two listings with their own ids stay two (own_ids_differ), and so do two posts: one post can be two
    things at once ("Trunk or Treat and chili cook-off at 5")."""
    return (a["names"] == b["names"] and a["own_id"] != b["own_id"] and a["at"] is not None and a["at"] == b["at"]
            and bool(a["place"]) and a["place"] == b["place"] and not (a["game"] or b["game"])
            and not (a["title"] - a["names"]) & (b["title"] - b["names"]))


def facebook_event(url):
    """A Facebook event's own number, from its link. A post's link doesn't count: one post can be two things."""
    found = re.search(r"facebook\.com/events/(\d+)", url or "")
    return found and found[1]


def one_facebook_event(g, row, facts):
    """One host's one Facebook event under a new name: the same event number on the same day, at agreeing times,
    whatever the titles (Jesse, 2026-11-05). The judge words a title anew on each read, and two names that don't fit
    inside each other showed as two Events: Stone Road's "Stone Road Live" and "Stone Road at The La Playette".
    A host under two spellings is one host (Jeanne B's Tours, and Tours & Shoppe). Times must agree because one
    event page can list a matinee and an evening show. Another host's listing of it stays a question for the review."""
    number = facebook_event(row["source_url"])
    return bool(number) and g["facts"]["day"] == facts["day"] and within_hour(g["facts"], facts) and any(
        facebook_event(m.get("source_url")) == number
        and same_title(words(m.get("source_name")), words(row["source_name"])) for m in g["mentions"])


def spots(place):
    """Every registry place a place line names (registry.names_index): the line whole, or else the longest
    name inside it and in each of its parts ("White Peony and WR Home" names both shops)."""
    key = registry.place_key(place)
    if key in names():
        return set(names()[key])
    out = set()
    for part in [place or "", *re.split(r"\s+(?:and|&)\s+", place or "")]:
        k = registry.place_key(part)
        inside = [n for n in names() if len(n) >= 8 and n in k]
        out.update(names().get(k) or (names()[max(inside, key=len)] if inside else ()))
    return out


def own_host(f):
    """Posted by the place's own host: one its line names, or a line naming no registry place (its grounds)."""
    return f["host"] is not None and f["host"] in (f["spots"] or {f["host"]})


def place_facts(place, poster):
    """What two_hosts reads of where an event is and who posted it."""
    return {"spots": spots(place), "host": places().get(registry.place_key(poster)), "names": words(poster)}


def own_ids_differ(g, source, uid, facts):
    """The source itself gave the two their own ids: two events, however alike, unless posted or listed twice."""
    seen = ([g["old"]] if g["old"] else []) + g["mentions"]
    return real_uid(uid) and any(m["source_name"] == source and real_uid(m.get("source_uid"))
                                 and m["source_uid"] != uid for m in seen) \
        and not posted_twice(g["facts"], facts) and not listed_twice(g["facts"], facts)


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
# A News title gets its card's 2 lines (BP app inside-cards 13; Jesse, 2026-11-07: measured, on his 402 pt phone):
# BP Event Heading at 19 pt in 234 pt, once News has its heart (402 - 32 column - 16 - 56 logo - 14 - 16 - 34 heart).
# Each character's width at 19 pt was read once from the font (BP app docs/plans/inside-cards/assets/13-news-titles);
# wrapped at spaces, they agree with the phone's wrap on 345 of 346 News titles and never call a long one short.
# ponytail: a new heading font or card width means reading these again with that folder's wrap.py.
HEADLINE_ROOM, HEADLINE_LINES = 234, 2
HEADLINE_WIDTHS = dict(zip(
    " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~é—’“”",
    (4.09, 5.07, 10.22, 16.43, 10.57, 16.89, 14.95, 4.88, 6.73, 6.56, 7.39, 11.34, 5.07, 7.87, 4.9, 10.34, 14.63, 7.03,
     13.53, 13.7, 14.63, 13.85, 14, 12.29, 14.16, 14, 5.24, 5.24, 11.1, 11.1, 11.1, 13.15, 16.93, 17.37, 14.31, 16.07,
     14.95, 13.01, 12.54, 16.23, 14.46, 4.83, 13.98, 15.11, 12.22, 18.32, 14.8, 16.97, 14.31, 16.97, 14.63, 14.46, 14.31,
     14.31, 17.14, 23.66, 16.8, 16.8, 14.63, 5.28, 5.28, 5.28, 8.92, 10.57, 6.33, 13.24, 14.38, 13.89, 14.38, 13.74, 9.96,
     14.55, 13.24, 4.71, 6.69, 13.57, 4.88, 21.43, 13.41, 14.42, 14.74, 14.59, 11.76, 13.09, 10.09, 13.76, 15.41, 21.57,
     15.09, 15.26, 13.41, 6.35, 4.94, 6.35, 11.1, 10.57, 19, 4.88, 10.22, 10.22)))
NEWS_TITLE_MAX = 30  # what the morning job's model shortens a News title to: every one since July at 30 or fewer fits


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
    # The colleges' own meet: the Athletics calendar writes the hosts as the opponent, "College of
    # Saint Benedict Track and Field vs CSB/SJU" (2026-10-25), which read "CSB Track and Field vs CSB SJU".
    t = re.sub(r"^(CSB|SJU) (.+?) vs\.? CSB SJU$", r"\1 \2 Meet", t)
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
# What can't be a new team's name: what a schedule writes before it knows the team, and what no school's name has.
NOT_A_NAME = re.compile(r"\b(tbd|tba|winner|loser|seed|section|pool|bracket|consolation|semi-?finals?|quarter-?finals?|"
                        r"finals?|playoffs?|opponent|bye|alumni|varsity|jv)\b|[\d#,&()/:@]", re.I)
DIRECTIONS = {"north", "south", "east", "west", "central"}  # "West Junior High": alone, a direction names no school
SHORT_MAX = 20  # characters: what the white card's 112 pt column holds at 13 pt, shrunk to 80%


def team_id(name):
    """A team's row in public.teams: its name as the schedules write it, as a slug."""
    return re.sub(r"[^a-z0-9]+", "-", name.lower().replace("'", "")).strip("-")


def team_name(name):
    """A team's name with no ranking ("#21 ") and nothing in brackets at its end, even a bracket a feed
    cut off ("Kennedy Community MS (Mid")."""
    return re.sub(r"(?:\s*\([^)]*\)?)+\s*$", "", re.sub(r"^#\d+\s+", "", name.strip()))


def team_key(name):
    """A team name as a lookup key."""
    return team_id(team_name(name))


def known_teams(db=None):
    """Every name a team goes by -> its id (public.teams: id, name, short name, aliases). A team's own id and
    name come first: a co-op's short name ("Brainerd") never takes the name of a team that has it."""
    rows = (db or Supabase()).rest("GET", "teams?select=id,name,short_name,aliases") or []
    known = {team_key(n): r["id"] for r in rows for n in (r["id"], r["name"]) if n}
    for r in rows:
        # A co-op's short name is often its first school's ("Centennial"), which isn't the co-op.
        short = [] if "-" in r["name"] else [r.get("short_name")]
        for n in (*short, *(r.get("aliases") or [])):
            if n:
                known.setdefault(team_key(n), r["id"])
    return known


def could_be_a_team(name):
    """Whether a name no team goes by can be a new team (not a placeholder or a kind of event)."""
    return 3 <= len(name) <= 60 and name[0].isupper() and name.lower() not in BOUND_GENERIC \
        and not NOT_A_TEAM.search(name) and not NOT_A_NAME.search(name)


def team_short(name):
    """A new team's short name: whole if it fits, else a co-op's first school, else cut at a word."""
    if len(name) <= SHORT_MAX:
        return name
    name = re.sub(r"^Minneapolis ", "Mpls ", name)
    if len(name) <= SHORT_MAX:
        return name
    first = name.split("-")[0].strip()
    return first if len(first) <= SHORT_MAX else name[:SHORT_MAX + 1].rsplit(" ", 1)[0]


def team_of(name, teams, may_make, made):
    """The team a schedule's name means, as (id, name, is it new), or None. A new team goes by its name with its
    school's kind off ("Breck School" is Breck), so the next spelling finds it. `made` holds this run's new teams,
    so every game's row carries one name for each, and public.apply_judged makes the team with the first row kept
    (Jesse, 2026-11-05: "create the teams profile and card whenever theres a new one that comes up", replacing
    2026-10-26's no reader makes a team)."""
    clean = team_name(name)
    bare = SCHOOL_KIND.sub("", clean)
    for known in (clean, bare):
        if team_id(known) in teams:
            i = teams[team_id(known)]
            return i, made.get(i, known), False
    if not may_make or not could_be_a_team(clean):
        return None
    new = clean if bare.lower() in DIRECTIONS else bare
    i = team_id(new)
    teams[i] = teams[team_id(clean)] = i
    made[i] = new
    return i, new, True


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


# A title in the readers' game form: "Sartell Girls Soccer vs St. Cloud", "Boys Basketball vs Willmar · C-squad",
# "CSB Soccer vs Hamline: Senior Night".
GAME_TITLE = re.compile(r"^\S.*? vs\.? (?P<them>.+?)(?: · .+?)?(?:: .+)?$")


def is_game(e):
    """What a game is (BP app smooth-mornings 06), read the same from a judged item or a listed row,
    for the describe layout: two teams playing a sport. A `game` that names a sport and two teams says so, and so does the
    sport the writer gave a row; else Watch sports and a title in the readers' form, a team after
    its "vs" (or one still to come), not a meet. A game's About is its reader's (read_events.game_about),
    so there is nothing to research. Not the game card's rule (place_photos.game_card), on purpose: a game whose
    other team isn't in `teams` is a game here and a plain card there (codebase-health-2 07)."""
    if not isinstance(e, dict):
        return False
    if e.get("sport") or isinstance(e.get("game"), dict) and game_of(e, ""):
        return True
    m = GAME_TITLE.match(str(e.get("title") or ""))
    return bool(m) and e.get("interest", e.get("category")) == "watch_sports" and not NOT_A_TEAM.search(m["them"])


def headline_fits(title):
    """Whether a News title fits its card's 2 lines, wrapped at spaces as the phone wraps it. A character the
    font table lacks counts as an M, and a word wider than a line never fits."""
    lines, line, space = 1, 0.0, HEADLINE_WIDTHS[" "]
    for word in title.split():
        w = sum(HEADLINE_WIDTHS.get(c, HEADLINE_WIDTHS["M"]) for c in word)
        if w > HEADLINE_ROOM:
            return False
        if line and line + space + w > HEADLINE_ROOM:
            lines, line = lines + 1, w
        else:
            line += (space if line else 0) + w
    return lines <= HEADLINE_LINES


def long_headlines(items, listed=()):
    """News titles past their card's 2 lines once tidied (headline_fits), for the morning job's model to shorten
    to NEWS_TITLE_MAX in the source's own words (BP app inside-cards 13). `listed`: the News already in the app
    (news_titles_in_db). One there under its long title keeps it, so its re-read lands on its own row (apply_judged
    knows a News by title, source and day) and not on a new one: on 2026-11-08 eight of Kennedy's posts from
    Oct 14 to 29, read again every morning, went up again under short titles (BP app smooth-mornings 14)."""
    have = {(r.get("source_name"), (r.get("title") or "").lower()) for r in listed}
    out = []
    for it in items:
        if isinstance(it, dict) and it.get("kind") == "news" and isinstance(it.get("title"), str):
            source = str(it.get("source_name") or "").strip()
            t = tidy_title(it["title"], source, event=False)
            if not headline_fits(t) and t not in out and (source, t.lower()) not in have:
                out.append(t)
    return out


def long_titles(items, existing=()):
    """Event titles still over TITLE_MAX once tidied, for the morning job's model to shorten by
    the title-and-place skill, never cut mid-word (Jesse, 2026-10-21: three lines don't fit the
    Town's Event of the day poster). A game's reader writes it short (read_events.game_title), so
    one over 40 is the judge's or a calendar's, and is shortened like any other. An event already
    listed with a short title keeps it (plan), so it isn't asked again."""
    short = {(r.get("source_name"), r.get("source_uid")) for r in existing
             if r.get("source_uid") and len(r.get("title") or "") <= TITLE_MAX}
    out = []
    for it in items:
        if not isinstance(it, dict) or it.get("kind") != "event" or not isinstance(it.get("title"), str):
            continue
        source = str(it.get("source_name") or "").strip()
        t = tidy_title(it["title"], source)
        if len(t) > TITLE_MAX and t not in out \
                and (source, str(it.get("source_uid") or "").strip()) not in short:
            out.append(t)
    return out


def tidy_place(place, home=HOME):
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
    left = trailing.sub("", p)
    return p if re.search(r"\b(?:of|in|at)$", left, re.I) else left or p  # "Church of Saint Joseph" keeps its name


def without_town_start(place, town):
    """A social flag starts its place with the town the post shows, so the judge sees it (social.md): "#duluthmn: The
    Harbor Lofts", "Sartell: Oak Ridge". The judge copies it, and it stays off the card. A reader's "School: Main Gym" stays."""
    start, colon, rest = (place or "").partition(":")
    return rest.strip() if colon and (start.startswith("#") or town_key(start) == town_key(town)) else place


def meets_at(place, host, title, home=HOME):
    """A meeting its host lists with no room is where it always meets (MEETS_AT)."""
    if words(place, PLACE_STOP):
        return place
    return next((p for h, what, p in MEETS_AT.get(home, []) if host.strip() == h and what.search(title)), place)


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


def listed_facts(row, home=HOME):
    day = date.fromisoformat(str(row["event_date"])[:10])
    t = None if row.get("all_day") else parse_clock(row.get("start_time"))
    poster = row.get("source_name") or ""
    place = meets_at(tidy_place(row.get("location"), home), poster, tidy_title(row["title"], poster), home)
    return {"day": day, "at": t and datetime.combine(day, t), "place": words(place, PLACE_STOP),
            "entry": where(place, poster), "title": words(tidy_title(row["title"], poster)), **place_facts(place, poster),
            "own_id": real_uid(row.get("source_uid")), "game": is_game(row), "poster": poster.strip(),
            "followers": row.get("followers_only") is True}


def show_from(day, size, signup_by):
    """The event-lead-time rule (sources/CONTEXT.md, Lead time)."""
    shown = day - timedelta(LEAD[size])
    if signup_by and shown > signup_by - timedelta(7):
        bigger = [day - timedelta(n) for n in sorted(LEAD.values()) if n > LEAD[size]]
        shown = next((d for d in bigger if d <= signup_by - timedelta(7)), signup_by - timedelta(7))
    return shown


# A title that names nothing (smooth-mornings 12): Apollo's Bound schedule gave a nameless Willmar JV meet as "Time TBA".
PLACEHOLDER = re.compile(r"\s*(?:(?:time|date|place|event)\s+)?(?:tba|tbd|to be (?:announced|determined))\W*", re.I)


def skip_reason(it, town):
    """Why an item can't be used, or None. Items are model output: one bad item is skipped,
    never the whole morning."""
    if not isinstance(it, dict):
        return "invalid: not a JSON object"
    for k in ("title", "source_name", "source_url"):
        if not isinstance(it.get(k), str) or not it[k].strip():
            return f"invalid: no {k}"
    if PLACEHOLDER.fullmatch(it["title"]):
        return f"invalid: the title {it['title'].strip()!r} names nothing"
    for k in ("kind", "trust", "area", "start", "end", "place", "town", "blurb", "size",
              "signup_by", "interest", "category", "activity_team", "activity_name", "shows_from"):
        if it.get(k) is not None and not isinstance(it[k], str):
            return f"invalid: {k} must be text"
    for k in ("closed", "followers_only"):
        if it.get(k) not in (None, True, False):
            return f"invalid: {k} must be true or false"
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


_NAMES = _PLACES = None


def names():
    """The registry's place names, read once: each name -> every entry answering to it."""
    global _NAMES
    if _NAMES is None:
        _NAMES = registry.names_index(registry.load(Path(__file__).resolve().parents[2])[0])
    return _NAMES


def places():
    """Each place name -> its entry (the first answering to it): every event is tagged with where it happens."""
    global _PLACES
    if _PLACES is None:
        _PLACES = {key: ids[0] for key, ids in names().items()}
    return _PLACES


def event_of(it, today, interests, home, notes, titles=None, teams=None, made=None):
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
    place = without_town_start(it.get("place"), it.get("town") or home)
    title, place = tidy_title(it["title"], it["source_name"]), tidy_place(place, home)
    title = (titles or {}).get(title, title)
    place = meets_at(place, it["source_name"], title, home)
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
           "description": clip(it.get("blurb"), 1000) or None, "price": clip(it.get("price"), 60) or None,
           "source_name": it["source_name"].strip(), "source_url": it["source_url"].strip(),
           "source_uid": uid, "category": interest, "shows_from": shows.isoformat(),
           "place_entry_id": entry, "sport": None, "team_ids": None, "team_names": None, "team_shorts": None,
           "occasion": None, "followers_only": it.get("followers_only") is True, "activity_team": it.get("activity_team"),
           "activity_name": it.get("activity_name")}
    game = game_of(it, title)
    if game:
        # A name from a schedule can make a team; the judge's stays a normal card until someone adds it.
        may_make = str(it.get("source_uid") or "").startswith(("mshsl:", "bound:")) or row["source_name"] in CAMPUS_TEAMS
        found = [(team_id(t), t, False) if teams is None else team_of(t, teams, may_make, made) for t in game["teams"]]
        for t, f in zip(game["teams"], found):
            if not f:
                notes.append(f"who is this: {t!r} ({title!r}) is no team's name, so a normal card until it's added")
            elif f[2]:
                notes.append(f"new team: {f[1]!r} ({title!r})")
        if all(found):
            row.update(sport=game["sport"], team_ids=[f[0] for f in found], team_names=[f[1] for f in found],
                       team_shorts=[team_short(f[1]) for f in found], occasion=game["occasion"])
    facts = {"day": day, "at": at, "place": words(place, PLACE_STOP), "entry": where(place, it["source_name"]),
             "title": words(title), **place_facts(place, it["source_name"]), "own_id": real_uid(uid),
             "game": bool(game) or is_game(row), "poster": it["source_name"].strip(),
             "followers": it.get("followers_only") is True}
    return {"row": row, "facts": facts}, None


# How long the Town feed shows a News (town_feed.sql's `news`): a week, or to its date, up to a month.
NEWS_DAYS, NEWS_MOST = 7, 30
_MONTHS = "january february march april may june july august september october november december".split()
_MONTH = r"(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?"
_TO = r"\b(through|thru|until|till|ends?|ending|expires?|by|before)\s+(?:\w+day,?\s+)?(?:the\s+)?"
_ON_A_DAY = re.compile(_TO + _MONTH + r"\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4}))?", re.I)
_DAY_TO_DAY = re.compile(r"\b" + _MONTH + r"\s+\d{1,2}(?:st|nd|rd|th)?\s*(?:to|-|–|—)\s*" + _MONTH + r"\s+(\d{1,2})\b", re.I)
_ON_NUMBERS = re.compile(_TO + r"(\d{1,2})/(\d{1,2})\b(?:/(\d{2,4}))?", re.I)
_A_MONTH = re.compile(r"\b(?:(?:through|thru|until|till)(?: the end of)?|all(?: of)?|(?:by|before) the end of)\s+(" + "|".join(_MONTHS) + r")\b(?!\.?\s+\d)", re.I)
_YEAR_END = re.compile(r"\b(?:end of (?:the |this )?year|year[- ]end)\b", re.I)
_MONTH_END = re.compile(r"\b(?:end of (?:the |this )?month|all month)\b", re.I)


def _nearest(month, day, today):
    """A day the words give with no year: the one closest to today, so "through Jan 5" in November is next year's
    and "through Oct 31" read in November is over."""
    days = []
    for year in (today.year - 1, today.year, today.year + 1):
        try:
            days.append(date(year, month, day))
        except ValueError:
            pass
    return min(days, key=lambda d: abs(d - today)) if days else None


def _month_end(year, month):
    return (date(year + (month == 12), month % 12 + 1, 1)) - timedelta(1)


def news_end(it, today):
    """The last day a News is true: the judge's `end`, else a dated phrase in its title or blurb ("through Nov 29",
    "all November", "through the end of the year"; BP app town-feed 49). Words that give no date ("Tuesday through
    Thursday", "preschool through fifth-grade", "until the season ends") give none, and the story has its week."""
    if isinstance(it.get("end"), str):
        try:
            return when(it["end"], it.get("all_day"))[0]
        except ValueError:
            pass
    words = f"{it.get('title') or ''}. {it.get('blurb') or ''}"
    if m := _ON_A_DAY.search(words):
        month = next(i + 1 for i, name in enumerate(_MONTHS) if name.startswith(m[2].lower()[:3]))
        day = _nearest(month, int(m[3]), today if not m[4] else date(int(m[4]), 7, 1))
        return day and (day - timedelta(1) if m[1].lower() == "before" else day)
    if m := _DAY_TO_DAY.search(words):
        return _nearest(next(i + 1 for i, name in enumerate(_MONTHS) if name.startswith(m[2].lower()[:3])), int(m[3]), today)
    if m := _ON_NUMBERS.search(words):
        day = _nearest(int(m[2]), int(m[3]), today) if 1 <= int(m[2]) <= 12 else None
        return day and (day - timedelta(1) if m[1].lower() == "before" else day)
    if m := _A_MONTH.search(words):
        if m[1] != "may":  # "all may come"; "all May" is the month
            month = _MONTHS.index(m[1].lower()) + 1
            return _month_end(today.year + (month < today.month - 6), month)
    if _YEAR_END.search(words):
        return date(today.year, 12, 31)
    if _MONTH_END.search(words):
        return _month_end(today.year, today.month)
    return None


def news_lasts_until(old):
    """How long a News in the app makes a new one its repeat: while the Town feed can still show it, and at least its
    week. "Winter gymnastics registration opens Nov 16" went up three times from Oct 24, a week apart (2026-11-06)."""
    made = local(old.get("published_at") or old["created_at"])  # a closing that waits counts from when it goes up
    last = date.fromisoformat(old["ends_on"][:10]) if old.get("ends_on") else None
    if not last and old.get("starts_at"):
        day = local(old["starts_at"]).date()
        last = day if day >= made.date() else None
    week = made + timedelta(NEWS_DAYS)
    return max(week, min(made + timedelta(NEWS_MOST), datetime.combine(last + timedelta(1), time(), LOCAL))) if last else week


def news_of(it, interests, notes, today, titles=None):
    start = it.get("start")
    try:
        day, at = when(start, it.get("all_day")) if start else (None, None)
        shows = when(it["shows_from"], True)[0] if it.get("shows_from") else None
    except ValueError as e:
        return None, f"invalid: unreadable date ({e})"
    end = news_end(it, today)
    if shows and day and end and end < day:  # a closing's words saying "by Nov 20" can't end it before its day
        end = None
    interest = it.get("interest")
    if interest is not None and interest not in interests:
        notes.append(f"interest {interest!r} is not on the list ({it['title']!r}): left empty")
        interest = None
    url = clean_link(it["source_url"])
    title = tidy_title(it["title"], it["source_name"], event=False)
    short = (titles or {}).get(title)
    # A short title keeps the long one's numbers, initials and dates, so tomorrow's read of the same story, long
    # again, is still its repeat (repeat_of tells "SJU Athlete of the Week" from "CSB Athlete of the Week" by them).
    if short and marks(short, title) != marks(title, short):
        notes.append(f"short title {short!r} drops a number, initials or a date of {title!r}: kept as written")
        short = None
    return {"title": short or title, "blurb": (it.get("blurb") or "").strip() or None,
            "category": it.get("category") if it.get("category") in NEWS_CATEGORIES else "announcement",
            "source_name": it["source_name"].strip(), "source_url": url,
            # The board's tiers as the old curator wrote them: 1 the City, 1.5 Newsleaders.
            "tier": 1 if it["trust"] == "official" else 1.5, "status": None,
            "starts_at": day and (at or datetime.combine(day, time())).replace(tzinfo=LOCAL).isoformat(),
            "ends_on": end and end.isoformat(),
            "shows_from": shows and datetime.combine(shows, time()).replace(tzinfo=LOCAL).isoformat(),
            # Who it matches in the Town feed, and the place whose logo it shows (town-feed 35).
            "interests": [interest] if interest else None, "place_entry_id": where(None, it["source_name"])}, None


TRACKING = re.compile(r"igsh|img_index|utm_.*|fbclid", re.I)


def clean_link(url):
    """A News link as it is saved and compared: without tracking (?igsh=, &img_index=, utm_...) and with
    Facebook's and Instagram's m. site as www., so one post shared two ways is one link."""
    u = urlsplit((url or "").strip())
    host = re.sub(r"^m\.(?=(facebook|instagram)\.com$)", "www.", u.netloc.lower())
    query = urlencode([(k, v) for k, v in parse_qsl(u.query, keep_blank_values=True) if not TRACKING.fullmatch(k)])
    return urlunsplit((u.scheme, host, u.path, query, u.fragment))


def same_link(a, b):
    return clean_link(a).rstrip("/") == clean_link(b).rstrip("/")


def link_key(url):
    """A link without its scheme, www. or m., query, fragment or trailing slash: "stjosephmn.gov/calendar.aspx"."""
    u = urlsplit((url or "").strip().lower())
    return (re.sub(r"^(www|m)\.", "", u.netloc) + u.path).rstrip("/")


_PAGES = None


def own_link(url):
    """Whether a News item's link is its own (a post's address, a feed item's link), so the same link
    from the same source again is a repeat (repeat_of). A site's home page, or a page the registry
    or the social watch reads, is the link of every News read from it: Stearns County gives its home
    page for all its news, Kennedy its calendar's ?cal_date=2026-11-01 for each day off in November.
    Those keep the title rule alone."""
    global _PAGES
    if _PAGES is None:
        root = Path(__file__).resolve().parents[2]
        social = [p["url"] for f in (root / "sources" / "social").glob("*.json") for p in json.loads(f.read_text())]
        _PAGES = {link_key(v) for e in registry.load(root)[0] for s in e.get("sources") or []
                  for v in s.values() if isinstance(v, str) and v.startswith("http")} | {link_key(u) for u in social}
    key = link_key(url)
    return "/" in key and key not in _PAGES


def mention(it, uid):
    return {"source_name": it["source_name"].strip(), "source_url": it["source_url"].strip(),
            "source_uid": uid, "trust": TRUST[it["trust"]], "sure": it.get("sure") is not False, "new": True}


def news_day(row):
    return row.get("starts_at") and local(row["starts_at"]).date()


def another_closing(n, old, now):
    """A closing on another day is another closing, however alike the titles: every "Holiday: City Offices Closed" has
    its own day, and "No School: Winter Break" was never written while it read as "No School: Thanksgiving Break"'s
    repeat (BP app town-feed 50). And one still waiting to go up can't swallow a post about another day."""
    waiting = old.get("shows_from") or (old.get("published_at") and local(old["published_at"]) > now)
    return (n.get("shows_from") or waiting) and news_day(n) != news_day(old)


def repeat_of(n, recent):
    """News already in the app from the same source this week with the same link of its own (own_link), whatever
    its title says: The North Table's brunch post (instagram.com/p/De3AnqRDaIV) was written twice on Oct 23 and
    24 under two wordings. Only a published one the Town feed can still show counts (news_lasts_until, Chicago's
    now): a landing page (legion.org/sweepstakes) can carry a different News next month, and this morning's News
    from one post fold into one instead (plan).
    Or News already in the app from the same place this week, under much the same title
    (Flour & Flower's Thanksgiving orders went up three times in three days, 2026-10-26).
    The place's own name doesn't count, and two shared words at least: "Flavor of the Week:
    Malt Amore" is not last week's "Flavor of the Week: Pumpkin Pie". Or one title's words all
    inside the other's: The North Table's "Brunch Saturdays and Sundays" is its "Weekend brunch,
    gluten-free" (Oct 30); over Oct 14 to Nov 3 this joined only News Jesse took out. A different number or
    initials say it's another one: "I-94 eastbound: Crash" and "MN 23 westbound: Crash", "SJU
    Athlete of the Week" and "CSB Athlete of the Week". A date only one title gives doesn't:
    "Cloudy collection launches Oct 25" is the "Comfort With a Chance of Cloudy collection"
    launching that Sunday; two different dates ("Closed Oct 24", "Closed Oct 31") do. Capitals and
    hyphens don't either: White Peony's "Build-your-own boo basket", "Build-your-own BOO baskets" and
    "Build Your Own Boo Baskets" were one offer posted three times (Oct 26 and 27). Weekdays and words
    like free and new say nothing of which offer: "FREE coffee Friday" is not "Free cookie Friday"."""
    stop = STOP | FILLER
    now, linked = datetime.now(LOCAL), own_link(n["source_url"])
    for old in recent:
        if another_closing(n, old, now):
            continue
        if (linked and old["source_name"] == n["source_name"] and same_link(old.get("source_url"), n["source_url"])
                and old.get("status") == "published" and old.get("created_at") and now < news_lasts_until(old)):
            return old
        if (old.get("place_entry_id") or old["source_name"]) != (n["place_entry_id"] or n["source_name"]):
            continue
        (theirs_marks, their_days), (my_marks, my_days) = marks(old["title"], n["title"]), marks(n["title"], old["title"])
        if theirs_marks != my_marks or (their_days and my_days and their_days != my_days):
            continue
        mine, theirs = word_forms(words(DAY.sub(" ", joined(n["title"], old["title"])), stop) - words(n["source_name"]),
                                  words(DAY.sub(" ", joined(old["title"], n["title"])), stop) - words(old["source_name"]))
        shared = mine & theirs
        if mine and theirs and (mine <= theirs or theirs <= mine
                                or len(shared) >= 2 and len(shared) >= 2 / 3 * min(len(mine), len(theirs))):
            return old
    return None


def word_forms(a, b):
    """Two titles' words with plurals as one ("hours" is "hour") and "pre" off a word the other title has
    without it: Flour & Flower's "Thanksgiving pre-orders" is its "Thanksgiving orders open" (Nov 2)."""
    a, b = ({w[:-1] if len(w) > 3 and w.endswith("s") and not w.endswith("ss") else w for w in s} for s in (a, b))
    return ({w[3:] if w.startswith("pre") and w[3:] in other else w for w in s} for s, other in ((a, b), (b, a)))


FILLER = set("is are our your its this now free new".split()) | {
    d + s for d in "monday tuesday wednesday thursday friday saturday sunday".split() for s in ("", "s")}
DAY = re.compile(r"\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.? \d{1,2}(?:st|nd|rd|th)?\b", re.I)


def marks(title, other=""):
    """A title's numbers and initials ("94", "SJU"), the words that tell one from another,
    and apart from them the dates it names ("Oct 25"). A word in capitals that `other` has too, in any
    letters, is the same word shouted, not initials: "BOO baskets" and "Boo Baskets". "MN" tells nothing:
    "Central MN" is only where, and a road keeps its number ("MN 23")."""
    days = {d.lower().replace(".", "") for d in DAY.findall(title or "")}
    theirs = set(re.findall(r"[a-z]+", (other or "").lower()))
    return {m for m in re.findall(r"\b(?:\d+|[A-Z]{2,})\b", DAY.sub(" ", title or ""))
            if m != "MN" and not (m.isalpha() and m.lower() in theirs)}, days


HYPHENED = re.compile(r"[A-Za-z]+(?:-[A-Za-z]+)+")


def joined(title, other):
    """Words a hyphen joins in either title are one word in both: "Build Your Own" is "Build-your-own"
    (words() already makes that "buildyourown"). Words joined in neither stay apart, so "Two-for-one apps"
    and "Two-for-one drinks" share one word, not three."""
    for compound in HYPHENED.findall(title or "") + HYPHENED.findall(other or ""):
        parts = compound.split("-")
        title = re.sub(r"\b" + r"[\s-]+".join(map(re.escape, parts)) + r"\b", "".join(parts), title, flags=re.I)
    return title


def group(old=None, facts=None, home=HOME):
    return {"id": old and old["id"], "old": old, "facts": facts or listed_facts(old, home), "items": [],
            "row": None, "mentions": [dict(m) for m in (old or {}).get("mentions") or []]}


def plan(items, existing, today, interests, town=TOWNS[DEFAULT], titles=None, teams=None, recent_news=()):
    """Judged items + the events already listed -> what to write, and each item's outcome.
    `recent_news`: this week's News already in the app (news_in_db), so a repeat isn't added.
    `titles`: this morning's shorter titles for long ones, {tidied title: short} (long_titles, long_headlines).
    `teams`: known_teams(); without it a game's names become ids, which apply() refuses."""
    home = town["label"]
    out = {"events": [], "news": [], "outcomes": [None] * len(items), "notes": [], "cancelled": [], "restored": [],
           "teams_checked": teams is not None}
    made = {}  # this run's new teams, by id: their one name
    schedules = []
    groups, by_uid, news, also = [group(row, home=home) for row in existing], {}, {}, {}
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
            n, why = news_of(it, interests, out["notes"], today, titles)
        elif not why:
            ev, why = event_of(it, today, interests, home, out["notes"], titles, teams, made)
        if why:
            out["outcomes"][i] = ("skipped", why)
        elif it["kind"] == "news":
            # The title as read too, when the morning gave it a short one: News written before it was short.
            read = tidy_title(it["title"], it["source_name"], event=False)
            old = (repeat_of(n, [*recent_news, *news.values()])
                   or read != n["title"] and repeat_of({**n, "title": read}, [*recent_news, *news.values()]))
            if old:
                out["outcomes"][i] = ("repeat", f"of {old['title']!r} (already in the app)")
                continue
            # One post is one News (smooth-mornings 05): a second News from the same post joins the first's
            # blurb by its title (Well & Company's one post was three News on Oct 23).
            post = own_link(n["source_url"]) and next((m for m in news.values() if m["source_name"] == n["source_name"]
                                                       and same_link(m["source_url"], n["source_url"])), None)
            if post:
                also.setdefault(id(post), (post, []))[1].append(n["title"])
                out["outcomes"][i] = ("folded", f"{n['title']!r} into {post['title']!r}, the News of the post they share")
                continue
            n["status"] = "published"
            news[(n["title"].lower(), n["source_name"], n["starts_at"])] = n
            out["outcomes"][i] = ("news", "")
        else:
            key = (ev["row"]["source_name"], ev["row"]["source_uid"])
            # A shown, timed listing first: a no-time mention joins it, not a hidden copy.
            g = by_uid.get(key) or min((g for g in groups if (joins(g, ev["facts"])
                                                              or one_facebook_event(g, ev["row"], ev["facts"]))
                                        and not own_ids_differ(g, *key, ev["facts"])),
                                       key=lambda g: ((g["old"] or {}).get("status") == "rejected",
                                                      g["facts"]["at"] is None), default=None)
            if g is None:
                # Two of one source's own ids are two events; nothing for Jesse to settle.
                near = [g for g in groups if g["facts"]["day"] == ev["facts"]["day"] and (
                    same_place(g["facts"]["place"], ev["facts"]["place"])
                    or same_title(g["facts"]["title"], ev["facts"]["title"])
                    or two_hosts(g["facts"], ev["facts"]) == "maybe") and not own_ids_differ(g, *key, ev["facts"])]
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
    for post, titles in also.values():
        post["blurb"] = " ".join(x for x in (post["blurb"], f"Also: {'; '.join(titles)}.") if x)
    out["news"] = list(news.values())

    for g in groups:
        if not g["items"]:
            continue
        old = g["old"]
        if old:
            # The listed row's own source re-reading it: by the same uid, by the second id it posted the
            # row under (posted_twice; the campus calendar lists only the new one), or (no ids on that
            # source) the same event a little reworded or retimed. It keeps its uid.
            # A read that gives no time says nothing of a timed Event's time or end: a Mention only (Jesse, 2026-11-06).
            # A listing with its own id speaks for itself when it drops its time, and a run over days changes the Event.
            mine = [(i, ev) for i, ev in g["items"] if ev["row"]["source_name"] == old["source_name"]
                    and not (g["facts"]["at"] and ev["facts"]["at"] is None and not ev["row"]["end_at"]
                             and not real_uid(ev["row"]["source_uid"]))]
            uid = old.get("source_uid")
            primary = next(((i, ev) for i, ev in mine if ev["row"]["source_uid"] == uid),
                           next(((i, ev) for i, ev in mine if real_uid(ev["row"]["source_uid"]) == real_uid(uid)
                                 and uid), None))
            filled = False
            if primary is None and g["facts"]["at"] is None:
                # Another source gives the time this one left out: the listed event takes it, under
                # its own source and title (Jesse, 2026-10-27: "always be looking for updates").
                primary = next(((i, ev) for i, ev in g["items"] if ev["facts"]["at"]), None)
                filled = primary is not None
            g["status"] = old["status"]
            # Every kept item goes live; only a repeat stays out (Jesse, 2026-10-26).
            if old["status"] == "pending" and old.get("review_reason") is None and old.get("found", True):
                g["status"] = "approved"
        else:
            # The copy kept (smooth-mornings 08): official, then the place's own host's, then a timed one,
            # then one with a place; the rest are its Mentions, and a timed one gives it its time.
            primary = min(g["items"], key=lambda e: (items[e[0]]["trust"] != "official", not own_host(e[1]["facts"]),
                                                     e[1]["facts"]["at"] is None, not e[1]["facts"]["place"]))
            # Only a time from the kept copy's own day: Nov 1's all-day copy never reads "Nov 1, 4 PM".
            timed = next((ev for _, ev in g["items"]
                          if ev["facts"]["at"] and ev["facts"]["day"] == primary[1]["facts"]["day"]), None)
            g["status"] = "approved"
        if old and primary and len(primary[1]["row"]["title"]) > TITLE_MAX >= len(old.get("title") or ""):
            # A title the morning job or Jesse shortened stays when its source sends the long one
            # again (title-and-place: 40 at most). ponytail: a source that renames an event to
            # another long title keeps the old short one; compare words if renames show up.
            primary[1]["row"]["title"] = old["title"]
        if (old and primary and old["status"] == "rejected" and old.get("review_reason") not in (None, "not_event")
                and any(primary[1]["row"].get(k) != old.get(k)
                        for k in ("title", "event_date", "start_time", "all_day", "location"))):
            g["status"] = "pending"  # a misread its source changed gets another look, as in read_events
        if primary:
            row = dict(primary[1]["row"], status="approved")
            # Everyone's when any mention this morning is (a school's own page and Bound's followers-only copy).
            row["followers_only"] = all(ev["row"]["followers_only"] for _, ev in g["items"])
            # Its activity from whichever mention names one (Bound's), so a public page's row still lands on it.
            named = next((ev["row"] for _, ev in g["items"] if ev["row"]["activity_team"]), row)
            row["activity_team"], row["activity_name"] = named["activity_team"], named["activity_name"]
            if old:
                row["source_uid"] = old["source_uid"]
                if filled:
                    row["source_name"], row["title"] = old["source_name"], old["title"]
                if old.get("shows_from") and str(old["event_date"])[:10] == row["event_date"]:
                    row["shows_from"] = str(old["shows_from"])[:10]
                row["category"] = old.get("category") or row["category"]
            if not old and timed and row["all_day"] and not row["end_at"]:
                row.update({k: timed["row"][k] for k in ("start_time", "all_day", "end_at")})
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
                out["outcomes"][i] = ("published", "")
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
        if not old.get("cancelled_at") and old.get("status") != "rejected" and any(
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


def apply(result, db=None):
    """The live write, over the service role key: one call, all or nothing."""
    if not result.get("teams_checked"):
        sys.exit("[judged] refused: the plan didn't look its games' teams up (plan(..., teams=known_teams()))")
    return (db or Supabase()).rest("POST", "rpc/apply_judged", payloads(result))


def listed_in_db(db=None):
    return (db or Supabase()).rest("POST", "rpc/listed_for_writer", {})


def news_titles_in_db(db=None):
    """Every News's title and source, whatever its age or status, for long_headlines."""
    return (db or Supabase()).rest("GET", "board_items?select=title,source_name") or []


def news_in_db(now=None, db=None):
    """The News already in the app that the Town feed can still show (Chicago's now), with each one's link, status,
    created time and dates, for repeat_of."""
    now = now or datetime.now(LOCAL)
    since = (now - timedelta(NEWS_MOST)).replace(microsecond=0).isoformat()
    rows = (db or Supabase()).rest("GET", "board_items?select=title,source_name,place_entry_id,source_url,status,created_at,published_at,starts_at,ends_on"
                                   f"&status=eq.published&published_at=gte.{quote(since, safe=':')}") or []
    return [r for r in rows if now < news_lasts_until(r)]


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
        if g["row"] and len(g["row"]["title"]) > TITLE_MAX:
            print(f"[long title] {g['row']['title']!r}: over {TITLE_MAX}; give it a shorter one (title-and-place)")
    for n in r["news"]:
        if not headline_fits(n["title"]):
            print(f"[long title] {n['title']!r}: over its 2 lines; give it a shorter one (title-and-place)")


INTERESTS = ["live_music", "families_kids", "bars", "markets", "art_theater", "watch_sports"]
TODAY = date(2026, 10, 14)


def t_long_titles_shortened_and_kept():
    chapel = item(title="Anniversary of the Dedication of Sacred Heart Chapel", source_uid="sisters:1")
    hockey = item(title="Sartell-Sauk Rapids Girls Hockey vs Fergus Falls", source_uid="mshsl:9",
                  game={"sport": "Girls Hockey", "teams": ["Sartell-Sauk Rapids", "Fergus Falls"]})
    assert long_titles([chapel, hockey, item()]) == [chapel["title"], hockey["title"]], \
        "every title over 40 is listed, a game's too: its reader writes it short, so this one is the judge's"
    # One rule for a judged item and a listed row: a row whose teams nobody has added has no sport.
    row = lambda title, category="watch_sports", sport=None: {"title": title, "category": category, "sport": sport}
    assert [is_game(row(t)) for t in ("Boys Basketball vs Willmar · C-squad", "CSB Soccer vs Hamline: Senior Night",
                                      "SJU Wrestling vs North Country Open", "SJU Soccer vs TBD: MIAC Quarterfinals",
                                      "Central Lakes Conference Swim Meet")] == [True, True, False, True, False]
    assert not is_game(row("Vikings vs Colts Game Day", "dining")) and is_game(row("Apollo game", sport="Volleyball"))
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


def t_news_titles_fit_their_two_lines():
    # Real titles, wrapped on the phone in 234 pt (BP app inside-cards 13): 38 characters filling both lines to 0.2 pt
    # of the edge, and 36 needing 1.3 pt more for its last word. A count of characters can't tell them apart.
    at, over = "Johnnies football home opener, Sept. 5", "Pumpkin Crafted Cold Brew at Caribou"
    assert headline_fits(at) and not headline_fits(over), "measured, not counted"
    assert headline_fits("Kennedy Community School") and not headline_fits("St. Joseph Community Food Shelf")
    assert not headline_fits("Supercalifragilisticexpialidocious"), "a word wider than a line never fits"
    news = lambda t: item(kind="news", title=t, start=None, category="business")
    assert long_headlines([news(over), news(at), news(over), item(title=over)]) == [over], \
        "each News past its 2 lines once; an Event keeps its 40 characters (long_titles)"
    listed = [{"title": over.upper(), "source_name": news(over)["source_name"]}]
    assert long_headlines([news(over)], listed) == [], "one in the app under its long title is re-read into its row"
    assert long_headlines([news(over)], [dict(listed[0], source_name="Someone Else")]) == [over], "another source's isn't"
    short = {over: "Pumpkin Cold Brew at Caribou"}
    assert len(short[over]) <= NEWS_TITLE_MAX and headline_fits(short[over])
    assert plan([news(over)], [], TODAY, INTERESTS, titles=short)["news"][0]["title"] == short[over]
    assert run([news(over)])["news"][0]["title"] == over, "no short one given: as written"
    # A short one is still its story's repeat (review of inside-cards 13): a home page's News is told by its title alone.
    county = lambda t: item(kind="news", title=t, start=None, category="road", source_name="Stearns County",
                            source_url="https://www.stearnscountymn.gov/")
    road, athlete = "County Road 75 closed 2 weeks for bridge repair", "SJU Athlete of the Week: Jane Doe, Cross Country"
    shorts = {road: "CR 75 closed for bridge work", athlete: "Athlete of the Week: Jane Doe"}
    r = plan([county(road), county(athlete)], [], TODAY, INTERESTS, titles=shorts)
    assert [n["title"] for n in r["news"]] == [road, athlete] and len(r["notes"]) == 2, \
        "a short title that drops a number or initials isn't taken"
    stored = lambda t: {"title": t, "source_name": "Stearns County", "place_entry_id": "stearns-county"}
    for before, now in (([stored(athlete)], {athlete: "SJU Athlete of the Week: Jane Doe"}),     # written long
                        ([stored("SJU Athlete of the Week: Jane Doe")], {athlete: "SJU Athlete: Jane Doe"}),
                        ([stored("SJU Athlete of the Week: Jane Doe")], {})):                   # no short one today
        r = plan([county(athlete)], [], TODAY, INTERESTS, titles=now, recent_news=before)
        assert outcome(r, 0) == "repeat", (before, now, r["outcomes"])
    import contextlib, io
    said = io.StringIO()
    with contextlib.redirect_stdout(said):
        report([news(over), news(at)], run([news(over), news(at)]))
    longs = [ln for ln in said.getvalue().splitlines() if ln.startswith("[long title]")]
    assert longs == [f"[long title] {over!r}: over its 2 lines; give it a shorter one (title-and-place)"], longs


def t_short_levels_kept_apart():
    """A lower level in its short form ("· MS", "· 8th", "· C-squad", as read_events writes a long
    game) is never that day's varsity game at the same place an hour on (smooth-mornings 06 review)."""
    at = dict(place="Kennedy Community School", area="game", interest="watch_sports", size="everyday")
    for varsity, lower in [("Girls Basketball vs Holdingford", "Girls Basketball vs Holdingford · MS"),
                           ("Boys Basketball vs Apollo", "Boys Basketball vs Apollo · C-squad"),
                           ("Girls Basketball vs Willmar", "Girls Basketball vs Willmar · 8th")]:
        two = [item(title=varsity, start="2026-10-23T19:00:00-05:00", source_name="Kennedy Community School", **at),
               item(title=lower, start="2026-10-23T18:00:00-05:00", source_name="Holdingford High School", **at)]
        assert len(run(two)["events"]) == 2, lower


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


def t_everything_kept_goes_live():
    """Jesse, 2026-10-26: "only hold back if its the exact same". Secondhand or unsure, it publishes."""
    one = item(source_name="Newsleaders", trust="secondhand", source_url="https://thenewsleaders.com/a")
    r = run([one, item(kind="news", title="Shop hours change", start=None, trust="secondhand", sure=False)])
    assert r["events"][0]["status"] == "approved" and outcome(r, 0) == "published", r["outcomes"]
    assert r["news"][0]["status"] == "published" and outcome(r, 1) == "news", r["outcomes"]
    assert run([dict(one, trust="squishy")])["events"][0]["mentions"][0]["trust"] == "squishy"
    # One left waiting from before goes live on its next mention.
    waiting = listed(status="pending", title="Plant Bingo", event_date="2026-10-24", start_time="4 PM",
                     location="Milk & Honey Ciders", source_name="Newsleaders", source_uid="page:x",
                     mentions=[{"source_name": "Newsleaders", "source_uid": "page:x", "trust": "secondhand", "sure": True}])
    r = run([item(title="Plant Bingo night", start="2026-10-24T16:30:00-05:00")], [waiting])
    g = r["events"][0]
    assert g["id"] == waiting["id"] and g["status"] == "approved", g
    assert outcome(r, 0) == "merged" and "publishes" in r["outcomes"][0][1], r["outcomes"]


def t_news_repeat_left_out():
    """The week of 2026-10-22: Thanksgiving orders three times, the Cloudy collection twice."""
    flour = dict(kind="news", start=None, category="business", source_name="Flour & Flower Bakery",
                 source_url="https://facebook.com/flourandflowerbakery")
    recent = [{"title": "Thanksgiving pre-orders are open", "source_name": "Flour & Flower Bakery",
               "place_entry_id": "flour-and-flower"},
              {"title": "Comfort With a Chance of Cloudy collection", "source_name": "White Peony Boutique",
               "place_entry_id": "boutique-peony-white"},
              {"title": "Flavor of the Week: Pumpkin Pie", "source_name": "The Wandering Cow",
               "place_entry_id": "cow-wandering"}]
    r = plan([item(title="Thanksgiving orders open at Flour & Flower", **flour),
              item(title="Thanksgiving orders open", **flour),
              item(title="Cloudy collection is back", **dict(flour, source_name="White Peony Boutique")),
              item(title="Flavor of the Week: Malt Amore", **dict(flour, source_name="The Wandering Cow")),
              item(title="No pizza Monday", **flour),
              item(title="Thanksgiving orders open", **dict(flour, source_name="Milk & Honey Ciders")),
              item(title="CSB Athlete of the Week", **flour), item(title="SJU Athlete of the Week", **flour),
              item(title="Cloudy collection launches Oct 25", **dict(flour, source_name="White Peony Boutique")),
              item(title="Closed Saturday Oct 24", **flour), item(title="Closed Saturday Oct 31", **flour)],
             [], TODAY, INTERESTS, recent_news=recent)
    assert [outcome(r, i) for i in range(11)] == ["repeat", "repeat", "repeat", "news", "news", "news", "news", "news",
                                                  "repeat", "news", "news"], r["outcomes"]
    assert "Thanksgiving pre-orders are open" in r["outcomes"][0][1]


def t_closings_wait():
    """A calendar's closing says when it goes up, and each day's is its own (BP app town-feed 50)."""
    ahead = lambda days: (TODAY + timedelta(days)).isoformat()
    city = dict(kind="news", category="announcement", source_name="City of St. Joseph", all_day=True,
                source_url="https://www.stjosephmn.gov/Calendar.aspx", title="Holiday: City Offices Closed")
    closing = lambda days, **more: item(**{**city, "start": ahead(days), "shows_from": ahead(days - 7),
                                           "source_url": f"{city['source_url']}?EID={days}", **more})
    r = plan([closing(20), closing(21), closing(20), item(**{**city, "start": None, "title": "City Offices Closed"})],
             [], TODAY, INTERESTS)
    assert [outcome(r, i) for i in range(4)] == ["news", "news", "repeat", "news"], r["outcomes"]
    held = r["news"][0]
    assert held["shows_from"] == datetime.combine(TODAY + timedelta(13), time()).replace(tzinfo=LOCAL).isoformat(), held
    assert r["news"][2]["shows_from"] is None, "other News goes up as it's written"
    # Another morning: one waiting in the app, read as the database gives it back.
    now = datetime.now(LOCAL)
    stamp = lambda days: (now + timedelta(days)).isoformat()
    waiting = {"title": "Holiday: City Offices Closed", "source_name": "City of St. Joseph", "status": "published",
               "place_entry_id": held["place_entry_id"], "source_url": city["source_url"],
               "created_at": stamp(-60), "published_at": stamp(13), "starts_at": held["starts_at"]}
    assert news_lasts_until(waiting) > now + timedelta(13), "it catches its repeats until it has gone up and left"
    again = lambda **more: outcome(plan([item(**{**city, **more})], [], TODAY, INTERESTS, recent_news=[waiting]), 0)
    assert again(start=ahead(20), shows_from=ahead(13)) == "repeat", "the same day, read again"
    assert again(start=ahead(20)) == "repeat", "the City's post about that day"
    assert again(start=ahead(21), shows_from=ahead(14)) == "news", "the next day's closing"
    assert again(start=None, title="City Offices Closed") == "news", "a snow day it can't swallow"
    assert again(start=ahead(3), title="City Offices Closed") == "news", "a post about another day"
    # Words can't end a closing before its day; an end the calendar gives stands.
    ends = lambda **more: plan([closing(20, **more)], [], TODAY, INTERESTS)["news"][0]["ends_on"]
    assert ends(blurb=f"Sign up by {TODAY + timedelta(5):%b} {(TODAY + timedelta(5)).day}.") is None
    assert ends(end=ahead(23)) == ahead(23)
    assert outcome(plan([closing(20, shows_from="soon")], [], TODAY, INTERESTS), 0) == "skipped", "an unreadable day"


def t_news_state_initials_tell_nothing():
    """Kidstop's "Boys & Girls Clubs get CLA Foundation funding" came back the next morning as "Boys & Girls Clubs of
    Central MN get CLA Foundation funding" (2026-11-05). "MN" is only where; a road's number still tells two apart."""
    def news(source, title):
        return item(kind="news", start=None, category="announcement", source_name=source, title=title,
                    source_url="https://www.bgcmn.org/news/")
    first = {"title": "Boys & Girls Clubs get CLA Foundation funding", "source_name": "Kidstop",
             "place_entry_id": where(None, "Kidstop")}
    road = {"title": "MN 23 westbound: Crash near Saint Cloud", "source_name": "Minnesota 511",
            "place_entry_id": where(None, "Minnesota 511")}
    r = plan([news("Kidstop", "Boys & Girls Clubs of Central MN get CLA Foundation funding"),
              news("Minnesota 511", "MN 15 westbound: Crash near Saint Cloud"),
              news("Minnesota 511", "I-94 westbound: Crash near Saint Cloud")],
             [], TODAY, INTERESTS, recent_news=[first, road])
    assert [outcome(r, i) for i in range(3)] == ["repeat", "news", "news"], r["outcomes"]


def t_one_host_no_place_is_one():
    """The City's catalog has "Youth dodgeball" at Kennedy and its board "Youth volleyball and dodgeball" at the gym;
    its flyer gave each night no place (2026-11-04). One host, the very same start, shared title words: one Event.
    A later start, another host or other words stay apart."""
    def listing(title, clock, location, uid):
        return listed(title=title, event_date="2026-11-12", start_time=clock, location=location,
                      source_name="City of St. Joseph", source_uid=uid)
    dodge = listing("Youth dodgeball", "7 PM", "Kennedy Community School", "rec1:4429103")
    both = listing("Youth volleyball and dodgeball", "6 PM", "Kennedy Community School gym", "board:abc")
    flyer = item(title="Youth Dodgeball", start="2026-11-12T19:00:00-06:00", end=None, place="",
                 source_name="City of St. Joseph", source_url="https://secure.rec1.com/MN/st-joseph-mn/catalog")
    assert run([flyer], [dodge])["events"][0]["id"] == dodge["id"]
    assert run([dict(flyer, title="Youth Volleyball", start="2026-11-12T18:00:00-06:00")], [both])["events"][0]["id"] == both["id"]
    for other in (dict(flyer, start="2026-11-12T20:00:00-06:00"), dict(flyer, source_name="Sal's Bar and Grill"),
                  dict(flyer, title="Adult Dodgeball")):
        assert run([other], [dodge])["events"][0]["id"] is None, other


def t_news_shouted_or_hyphened_is_one():
    """White Peony's boo baskets: one offer posted three times on Oct 26 and 27, as "Build-your-own boo
    basket", "Build-your-own BOO baskets" and "Build Your Own Boo Baskets at White Peony". Capitals and
    hyphens don't make it another News (smooth-mornings 05). Different specials from one place stay apart."""
    def posts(source, titles):  # each its own post, as they were
        return [item(kind="news", start=None, category="business", source_name=source, title=t,
                     source_url="https://www.instagram.com/p/" + re.sub(r"\W", "", t) + "/") for t in titles]
    first = {"title": "Build-your-own boo basket", "source_name": "White Peony Boutique",
             "place_entry_id": where(None, "White Peony Boutique")}
    r = plan(posts("White Peony Boutique", ["Build-your-own BOO baskets", "Build Your Own Boo Baskets at White Peony"]),
             [], TODAY, INTERESTS, recent_news=[first])
    assert [outcome(r, i) for i in range(2)] == ["repeat", "repeat"], r["outcomes"]
    week = [{"title": t, "source_name": "The House Food & Tap", "place_entry_id": where(None, "The House Food & Tap")}
            for t in ("Half-price wings Tuesday", "Two-for-one apps", "Wing NIGHT", "Free cookie Friday", "New winter menu",
                      "BOO Basket")]
    # Weekdays, free and new are filler: "FREE coffee Friday" shares nothing with "Free cookie Friday" that names it.
    titles = ["Half price burgers Thursday", "Two-for-one drinks", "Taco night", "$10 Pour of the Week", "Half-price taps",
              "FREE coffee Friday", "NEW fall menu", "BOO Bash"]
    r = plan(posts("The House Food & Tap", titles), [], TODAY, INTERESTS, recent_news=week)
    assert [outcome(r, i) for i in range(len(titles))] == ["news"] * len(titles), list(zip(titles, r["outcomes"]))


def t_all_day_a_day_apart_is_one():
    """White Peony's site started Bootique Week on Sunday, its Instagram ("Boo-tique") on Monday."""
    peony = dict(start="2026-10-26", end="2026-10-30", all_day=True, place="White Peony Boutique",
                 source_name="White Peony Boutique", interest=None)
    site = listed(title="Bootique Week", event_date="2026-10-25", start_time=None, all_day=True,
                  location="White Peony Boutique", source_name="White Peony Boutique", source_uid="page:a")
    r = run([item(title="Boo-tique Week", source_url="https://instagram.com/p/1", **peony)], [site])
    assert r["events"][0]["id"] == site["id"] and outcome(r, 0) == "merged", r["outcomes"]
    apart = run([item(title="Garage sale", **dict(peony, start="2026-10-26", end=None)),
                 item(title="Garage sale", **dict(peony, start="2026-10-28", end=None, source_name="City"))])
    assert len(apart["events"]) == 2, "two days apart stay two"


def t_no_time_joins_the_timed_one():
    """Milk & Honey's Instagram gave no time; its site said 6:30 PM (2026-10-27)."""
    site = listed(title="Sauna, Yoga, Ice Bath, Cider", event_date="2026-11-12", start_time="6:30 PM",
                  location="Milk & Honey Ciders", source_name="Milk & Honey Ciders", source_uid="page:a")
    post = dict(start="2026-11-12", end=None, all_day=True, source_name="Milk & Honey Ciders", interest=None)
    r = run([item(title="Yoga, Sauna & Cider", place="Milk & Honey Ciders", **post)], [site])
    assert r["events"][0]["id"] == site["id"] and outcome(r, 0) == "merged", r["outcomes"]
    r = run([item(title="Yoga, Sauna & Cider", place="", **post)], [site])
    assert r["events"][0]["id"] == site["id"], "with no place either, it is still the poster's own"
    r = run([item(title="Yoga, Sauna & Cider", place="Milk & Honey Ciders", **dict(post, start="2026-11-13"))], [site])
    assert r["events"][0]["id"] is None, "the next day stays apart"


def t_later_read_fills_the_time():
    """The Instagram post came first with no time; the site's 6:30 PM listing came a day later."""
    post = listed(title="Yoga, Sauna & Cider", event_date="2026-11-12", start_time=None, all_day=True,
                  location="Milk & Honey Ciders", source_name="Milk & Honey Ciders Instagram", source_uid="page:p")
    site = item(title="Sauna, Yoga, Ice Bath, Cider", start="2026-11-12T18:30:00-06:00", end=None,
                place="Milk & Honey Ciders", source_name="Milk & Honey Ciders", interest=None)
    g = run([site], [post])["events"][0]
    assert g["id"] == post["id"] and g["row"]["start_time"] == "6:30 PM" and not g["row"]["all_day"], g["row"]
    assert (g["row"]["source_name"], g["row"]["source_uid"], g["row"]["title"]) == \
        (post["source_name"], "page:p", "Yoga, Sauna & Cider"), "it updates the listed row, not a new one"
    hidden = dict(post, id="22222222-2222-2222-2222-222222222222", status="rejected", title="Yoga Sauna")
    shown = listed(title="Sauna, Yoga, Ice Bath, Cider", event_date="2026-11-12", start_time="6:30 PM",
                   location="Milk & Honey Ciders", source_name="Milk & Honey Ciders", source_uid="page:s")
    again = item(title="Yoga, Sauna & Cider", start="2026-11-12", end=None, all_day=True,
                 place="Milk & Honey Ciders", source_name="Somebody", interest=None)
    assert run([again], [hidden, shown])["events"][0]["id"] == shown["id"], "a shown, timed listing first"


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
    assert r["events"][0]["id"] is None and outcome(r, 0) == "published", "work session and meeting are two events"
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
    one_source = [item(source_uid="a1"), item(source_uid="a2", title="Plant Bingo night", start="2026-10-24T17:00:00-05:00")]
    assert len(run(one_source)["events"]) == 2, "a source's own two ids at two starts are two events"
    board = listed(title="School Board meeting", event_date="2026-10-21", start_time="6:30 PM",
                   location="Colman Theatre, Benedicta Arts Center", source_name="Kennedy", source_uid="board:532f")
    feed = item(title="School Board Meeting", start="2026-10-21T18:30:00-05:00", place="Colman Theater",
                source_name="Kennedy", source_uid="877641_2026-10-21")
    r2 = run([feed], [board])
    assert r2["events"][0]["id"] == board["id"] and outcome(r2, 0) == "merged", "a board copy is not the source's own id"
    assert any("kept apart" in n and "City Council Work Session" in n for n in r["notes"]), r["notes"]


def t_posted_twice():
    """One listing a source posted twice under two ids is one Event (watch-every-place 14); two
    levels of one game, or a doubleheader, stay two."""
    game = dict(title="SJU Basketball vs St. Cloud State", place="Sexton Arena, Collegeville", source_name="SJU Athletics",
                source_url="https://my.csbsju.edu/public/events/4852614", start="2026-10-29T18:00:00-05:00", end=None,
                area="game", interest="watch_sports", size="everyday")
    old = listed(title=game["title"], event_date="2026-10-29", start_time="6 PM", location=game["place"],
                 source_name="SJU Athletics", source_uid="4168764")
    r = run([item(source_uid="4852614", **game)], [old])
    assert len(r["events"]) == 1 and r["events"][0]["id"] == old["id"] and outcome(r, 0) == "merged", r["outcomes"]
    assert len(run([item(source_uid="4168764", **game), item(source_uid="4852614", **game)])["events"]) == 1, \
        "both new the same morning"
    # The calendar now lists only the new id: the listed row takes its changes, under its own uid.
    twin = dict(old, mentions=[{"source_name": "SJU Athletics", "source_url": game["source_url"], "source_uid": "4852614"}])
    moved = run([item(source_uid="4852614", **dict(game, start="2026-10-29T19:00:00-05:00"))], [twin])["events"][0]
    assert moved["id"] == old["id"] and moved["row"]["start_time"] == "7 PM" and moved["row"]["source_uid"] == "4168764", moved
    at = dict(game, title="", place="Sartell High School Gym, Auxiliary", source_name="Sartell High School")
    levels = [item(source_uid="bound:c", **dict(at, title="Apollo Boys Basketball vs Sartell · C-squad")),
              item(source_uid="bound:c2", **dict(at, title="Apollo Boys Basketball vs Sartell · C2-squad"))]
    assert len(run(levels)["events"]) == 2, "a school's C and C2 games are two"
    later = [item(source_uid="a1", **game), item(source_uid="a2", **dict(game, start="2026-10-29T18:45:00-05:00"))]
    assert len(run(later)["events"]) == 2, "two starts, even 45 minutes apart, are two"
    meet = dict(title="Section 6A Girls Swim Meet", place="St. Cloud Tech High School", source_name="Tech High School",
                all_day=True, end=None, area="game", interest="watch_sports", size="everyday")
    days = [item(source_uid="mshsl:12", start="2026-11-12", **meet), item(source_uid="mshsl:13", start="2026-11-13", **meet)]
    assert len(run(days)["events"]) == 2, "a meet's two days are two"


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
    assert "on conflict on constraint club_events_source_uid_key do update" in writes().read_text()


def t_misread_comes_back():
    """Like read_events: a decline for a misread goes back to Review when the source changes it."""
    base = dict(title="Plant Bingo", event_date="2026-10-23", start_time="4 PM", location="Milk & Honey Ciders",
                source_name="Milk & Honey Ciders", source_uid="page:2026-10-24T1600:bingo-plant")
    moved = run([item()], [listed(status="rejected", review_reason="wrong_when", **base)])
    assert moved["events"][0]["status"] == "pending", moved["events"][0]["status"]
    not_event = run([item()], [listed(status="rejected", review_reason="not_event", **base)])
    assert not_event["events"][0]["status"] == "rejected", "not an event stays declined"
    sql = writes().read_text()
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
                  dict(game, cancelled_at="2026-10-15T11:00:00Z"), dict(game, status="rejected")):
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
    db = " ".join(writes().read_text().split())
    assert "cancelled_at = null, shows_from" in db, "a re-read by its own source restores it"
    assert "set cancelled_at = now() " in db and "set cancelled_at = null " in db, "only the mark changes"
    assert "'Cancelled: ' ||" not in db, "the title stays as written: the app shows the tag (ticket 12)"
    assert not re.search(r"\bdelete\s+from\b", db, re.I), "never deleted"


def t_admin_status_kept():
    same = run([item()])["events"][0]["row"]  # the source re-reads it unchanged
    for st, reason in (("rejected", "wrong_when"), ("approved", None), ("pending", "wrong_place")):
        old = listed(status=st, review_reason=reason, **{k: same[k] for k in (
            "title", "event_date", "start_time", "all_day", "location", "source_name", "source_uid")})
        r = run([item()], [old])
        assert r["events"][0]["status"] == st, (st, r["events"][0]["status"])
    sql = writes().read_text().split("-- 1. New found events")[1]
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
    assert "place_entry_id = coalesce(excluded.place_entry_id" in writes().read_text(), "the database keeps it"


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
           item(kind="news", start="next Friday"), item(size=["big"]), item(title="Time TBA"), item(title="TBD")]
    r = run(bad + [item(), item(title="Trivia: Theme TBA")])
    assert [o[0] for o in r["outcomes"]] == ["skipped"] * len(bad) + ["published"] * 2, r["outcomes"]
    news = run([item(kind="news", title="No school", start="2026-10-15")])["news"][0]
    assert news["starts_at"] == "2026-10-15T00:00:00-05:00", news


def t_one_news_one_link():
    """One News is one link (smooth-mornings 05): a post's address or a feed item's link is its own, so
    repeat_of takes it again from the same source as a repeat. A home page, or a page the registry
    or the social watch reads, is shared by every News read from it, so it keeps the title rule alone."""
    own = [own_link(u) for u in ("https://www.instagram.com/p/DeBoo/",
                                 "https://thenewsleaders.com/where-do-i-vote-on-election-day-nov-3/",
                                 "https://www.facebook.com/permalink.php?story_fbid=pfbid0u6&id=6156",
                                 "https://www.stearnscountymn.gov/", "http://www.2ndavecuts.com",
                                 "https://kennedy.isd742.org/calendar?cal_date=2026-11-01",
                                 "https://www.facebook.com/BoDiddleysDeli/")]
    assert own == [True, True, True, False, False, False, False], own
    # Saved and compared clean: no tracking, m. as www.; Facebook's m. site of a page is still a page.
    assert clean_link("https://www.instagram.com/p/DeBoo/?igsh=MW1&img_index=2") == "https://www.instagram.com/p/DeBoo/"
    assert clean_link("https://m.facebook.com/story.php?story_fbid=1&id=2&utm_source=ig") == \
        "https://www.facebook.com/story.php?story_fbid=1&id=2"
    assert not own_link("https://m.facebook.com/BoDiddleysDeli")
    assert same_link("https://www.instagram.com/p/DeBoo", "https://m.instagram.com/p/DeBoo/?igsh=MW1")
    r = run([item(kind="news", title="Boo baskets", start=None, source_url="https://m.instagram.com/p/DeBoo/?igsh=MW1")])
    assert [n["source_url"] for n in payloads(r)["p_news"]] == ["https://www.instagram.com/p/DeBoo/"]


def t_news_same_link_this_week():
    """The plan decides the link rule (codebase-health-2 04; it was apply_judged's): The North Table's brunch post,
    written again under another title, is a repeat while a published News of the last 7 days from the same source
    has it. Older than 7 days, archived, or from another source, it is not. The same title under another link is
    a repeat by title, and an item with no link of its own (a home page) keeps the title rule alone."""
    post, home = "https://www.instagram.com/p/De3AnqRDaIV/", "https://www.thenorthtable.com/"
    table = dict(kind="news", start=None, category="business", source_name="The North Table", source_url=post)

    def live(url=post, days=2, status="published", source="The North Table"):
        return {"title": "Sunday brunch is back", "source_name": source, "place_entry_id": where(None, source),
                "source_url": url, "status": status, "created_at": (datetime.now(LOCAL) - timedelta(days)).isoformat()}

    def outcome_of(title, old, url=post):
        r = plan([item(title=title, **dict(table, source_url=url))], [], TODAY, INTERESTS, recent_news=[old])
        return r["outcomes"][0][0]

    reworded = "Bottomless mimosas with brunch"
    assert outcome_of(reworded, live()) == "repeat"
    assert outcome_of(reworded, live(), "https://m.instagram.com/p/De3AnqRDaIV?igsh=MW1") == "repeat", "one link shared two ways"
    assert outcome_of(reworded, live(days=8)) == "news", "older than the Town feed's week"
    assert outcome_of(reworded, live(status="archived")) == "news"
    assert outcome_of(reworded, live(source="Newsleaders")) == "news", "only the same source's"
    assert outcome_of("Sunday brunch is back", live(), "https://www.instagram.com/p/DfOther/") == "repeat", "by title"
    assert outcome_of(reworded, live(url=home), home) == "news", "a home page is no link of its own"
    assert outcome_of("Sunday brunch is back", live(url=home), home) == "repeat", "the title rule still holds"


def t_one_post_is_one_news():
    """Well & Company's one post was three News on Oct 23. The second and third fold into the first,
    whose blurb names them, and the report names each one folded. A link shared two ways (a trailing
    slash, m.) is one post; a home page several News share is no post of its own, so they stay."""
    well = dict(kind="news", start=None, category="business", source_name="Well & Company",
                source_url="https://www.instagram.com/p/DeujfJRqwLr/", blurb="Molly joins the team.")
    stearns = dict(well, source_name="Stearns County", source_url="https://www.stearnscountymn.gov/", blurb=None)
    r = run([item(title="Molly now at Well & Company in St. Joe", **well),
             item(title="Microneedling $275 at Well & Company", **dict(well, source_url="https://m.instagram.com/p/DeujfJRqwLr")),
             item(title="Wrinkle-Free Wednesdays", **well),
             item(title="Early Voting", **stearns), item(title="County Road 134 closed", **stearns)])
    assert [outcome(r, i) for i in range(5)] == ["news", "folded", "folded", "news", "news"], r["outcomes"]
    assert r["news"][0]["blurb"] == "Molly joins the team. Also: Microneedling $275 at Well & Company; Wrinkle-Free Wednesdays."
    assert "'Wrinkle-Free Wednesdays' into 'Molly now at Well & Company in St. Joe'" in r["outcomes"][2][1]


def t_news_look_back_is_the_feeds_week():
    """Both rules look back over as long as the Town feed can show a News (smooth-mornings 05, town-feed 49),
    counted from Chicago's now rather than a midnight, and the link rule needs each one's link. A story with no date
    counts for its 7 days, not 6, and one with a date until that date."""
    now = datetime(2026, 10, 29, 21, 40, 12, 5, tzinfo=LOCAL)
    made = lambda days: (now - timedelta(days)).isoformat()
    rows = [{"title": "Plain, 6 days", "created_at": made(6)}, {"title": "Plain, 8 days", "created_at": made(8)},
            {"title": "Ends in 3 days, 20 old", "created_at": made(20), "ends_on": "2026-11-01"},
            {"title": "Ended, 20 old", "created_at": made(20), "ends_on": "2026-10-20"},
            {"title": "About a day ahead, 10 old", "created_at": made(10), "starts_at": "2026-11-16T00:00:00-06:00"},
            {"title": "Ends far off, 31 old", "created_at": made(31), "ends_on": "2027-04-30"}]
    global Supabase
    asked, saved = [], Supabase
    Supabase = lambda: type("Db", (), {"rest": lambda self, method, path: asked.append(path) or rows})()
    try:
        kept = [r["title"] for r in news_in_db(now)]
    finally:
        Supabase = saved
    assert asked[0].endswith("&published_at=gte.2026-09-29T21:40:12-05:00"), asked
    assert "select=title,source_name,place_entry_id,source_url,status,created_at,published_at,starts_at,ends_on&" in asked[0], asked
    assert kept == ["Plain, 6 days", "Ends in 3 days, 20 old", "About a day ahead, 10 old"], kept


def t_news_says_when_it_ends():
    """A News keeps the last day it is true, so the Town feed shows it until then (Jesse, 2026-11-06; town-feed 49).
    The phrases are live stories' own, and so are the ones that give no date."""
    today = date(2026, 11, 6)
    end = lambda blurb, **more: news_end({"title": "A story", "blurb": blurb, **more}, today)
    for blurb, want in (("Open Fri-Sun 11-5 through Nov 29 with Haralson.", "2026-11-29"),
                        ("Through Nov. 16: $1.79 egg rolls", "2026-11-16"),
                        ("Offer through November 30.", "2026-11-30"),
                        ("Through November 22, bring a food item", "2026-11-22"),
                        ("Drop off food before November 23", "2026-11-22"),
                        ("Tickets $35 until December 31st", "2026-12-31"),
                        ("through Saturday, Nov. 7", "2026-11-07"),
                        ("through 11/29", "2026-11-29"),
                        ("Sunny Mary Meadow Nov 3 to Dec 22", "2026-12-22"),
                        ("From Oct 1 to Apr 30 members", "2027-04-30"),
                        ("Pass runs through March 31", "2027-03-31"),
                        ("through Jan 5, 2028", "2028-01-05"),
                        ("All November: Birthday Menu", "2026-11-30"),
                        ("all of December", "2026-12-31"),
                        ("through October, the rest of the deal", "2026-10-31"),
                        ("$50 off through the end of the year.", "2026-12-31"),
                        ("on sale all month", "2026-11-30")):
        assert str(end(blurb)) == want, (blurb, end(blurb))
    for blurb in ("All 30 taps are half off Tuesday through Thursday, 7pm to close.",
                  "every preschool through fifth-grade student", "on until the season ends", "this Halloween weekend",
                  "all may come", "book through the link in stories", "Rotate through the case.",
                  "through Nov 45", None):
        assert end(blurb) is None, (blurb, end(blurb))
    assert str(end("through Oct 31")) == "2026-10-31", "over already: the nearest one, not next year's"
    assert str(end("through Nov 29", end="2026-12-01")) == "2026-12-01", "the judge's end wins"
    assert str(end("through Nov 29", end="soon")) == "2026-11-29", "an end that can't be read leaves the words"
    r = run([item(kind="news", title="Orchard open", start=None, end=None, blurb=f"Fri-Sun through {TODAY:%b} {TODAY.day}.")])["news"][0]
    assert r["ends_on"] == TODAY.isoformat() and r["starts_at"] is None, r
    assert run([item(kind="news", title="Orchard open", start=None, end=None, blurb="Fri-Sun.")])["news"][0]["ends_on"] is None
    assert "ends_on = coalesce(excluded.ends_on, board_items.ends_on)" in writes().read_text(), "a re-read with no date keeps the date"


def t_a_dated_news_blocks_its_repeat_until_its_day():
    made = (datetime.now(LOCAL) - timedelta(10)).isoformat()
    ahead = (datetime.now(LOCAL) + timedelta(5)).date().isoformat()
    gym = dict(kind="news", start=None, category="business", source_name="Granite City Gymnastics")
    old = {"title": "Winter gymnastics registration opens Nov 16", "source_name": "Granite City Gymnastics",
           "place_entry_id": where(None, "Granite City Gymnastics"), "source_url": "https://www.facebook.com/x/posts/1",
           "status": "published", "created_at": made}
    again = item(title="Next post", source_url=old["source_url"], **gym)
    assert plan([again], [], TODAY, INTERESTS, recent_news=[dict(old, ends_on=ahead)])["outcomes"][0][0] == "repeat"
    assert plan([again], [], TODAY, INTERESTS, recent_news=[old])["outcomes"][0][0] == "news", "no date: its week"


def t_writes_are_one_safe_call():
    r = run([item(blurb="$$ drop table x; $$"), item(kind="news", title="Closed Monday", start=None)])
    p = payloads(r)
    assert [len(p[k]) for k in KEYS] == [1, 1, 0, 1, 0, 0], p
    assert p["p_events"][0]["description"] == "$$ drop table x; $$", "the payload carries text as data"
    sql = to_sql(r, TODAY)
    assert sql.lstrip().startswith("--") and "select public.apply_judged(" in sql and sql.count("::jsonb") == 6, sql[:200]
    db = writes().read_text()
    assert "insert into public.event_mentions" in db and "insert into public.board_items" in db
    assert "on conflict (lower(title), source_name, coalesce(starts_at, '-infinity'::timestamptz))" in db
    assert "from public, anon, authenticated" in db and "to service_role" in db, "only the service role may write"


def t_interest_list_is_the_apps():
    ids = interest_ids()
    assert {"live_music", "families_kids", "outdoors", "volunteering"} <= set(ids), ids


WORDING = [  # (title, host, place) as read on 2026-10-14 -> (title, place) on the card
    ("College of Saint Benedict Soccer vs Hamline - Senior Night", "CSB Athletics", "St. Joseph, Minn., CSB Stadium",
     "CSB Soccer vs Hamline: Senior Night", "CSB Stadium"),
    ("College of Saint Benedict Track and Field vs CSB/SJU", "CSB Athletics", "Collegeville, Minn., The Donald McNeely Spectrum",
     "CSB Track and Field Meet", "The Donald McNeely Spectrum, Collegeville"),
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
    ("Christmas Treasure Sale", "Church of Saint Joseph", "Church of Saint Joseph", "Christmas Treasure Sale",
     "Church of Saint Joseph"),
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
    for place, town, want in (("#duluthmn #superiorwi: The Harbor Lofts", "St. Joseph", "The Harbor Lofts"),
                              ("St. Joseph, MN: Clemens Library", "St. Joseph", "Clemens Library"),
                              ("Sartell: Oak Ridge Early Learning Center", "Sartell", "Oak Ridge Early Learning Center"),
                              ("#duluthmn:", "St. Joseph", ""),
                              ("Long Prairie-Grey Eagle High School: Main Gym", "Long Prairie",
                               "Long Prairie-Grey Eagle High School: Main Gym"),
                              ("15 E Minnesota St #107", "St. Joseph", "15 E Minnesota St #107"), (None, "St. Joseph", None)):
        assert without_town_start(place, town) == want, place
    tagged = run([item(place="#duluthmn #superiorwi: The Harbor Lofts"), item(title="Fair", town=None, place="St. Joseph Mn: Clemens Library")])
    assert [g["row"]["location"] for g in tagged["events"]] == ["The Harbor Lofts", "Clemens Library"], "a flag's town start stays off the card"
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
    sql = writes().read_text()
    assert "sport = excluded.sport, team_ids = excluded.team_ids" in sql, "a game read wrong once clears"
    assert "insert into public.teams (id, name, short_name)" in sql, "a new opponent gets its row"


def t_followers_only():
    """A Bound Event for followers only keeps its mark and activity; one a public page lists too is
    everyone's; a level in the title keeps a JV game apart from varsity (school-activities 03)."""
    game = dict(place="Apollo High School", town="St. Cloud", area="game", source_name="Apollo High School",
                interest="watch_sports", start="2026-10-23T19:00:00-05:00")
    jv = item(title="Brainerd Volleyball vs Apollo · JV", source_url="https://gobound.com/a11", source_uid="bound:a11",
              followers_only=True, activity_team="apollo", activity_name="Volleyball, Girls", **game)
    varsity = item(title="Brainerd Volleyball vs Apollo", source_url="https://www.mshsl.org/x", **game)
    rows = [g["row"] for g in run([jv, varsity])["events"]]
    assert [(r["title"], r["followers_only"], r["activity_team"], r["activity_name"]) for r in rows] == [
        ("Brainerd Volleyball vs Apollo · JV", True, "apollo", "Volleyball, Girls"),
        ("Brainerd Volleyball vs Apollo", False, None, None)], rows
    concert = dict(title="Fall Choir Concert", place="Apollo High School", town="St. Cloud", area="announced",
                   start="2026-10-23T19:00:00-05:00", interest=None)
    both = run([item(source_name="Apollo High School", source_url="https://gobound.com/c1", source_uid="bound:c1",
                     followers_only=True, activity_team="apollo", activity_name="Choir", **concert),
                item(source_name="St. Cloud Area School District", source_url="https://isd742.org/x", **concert)])
    assert [(g["row"]["followers_only"], g["row"]["activity_name"]) for g in both["events"]] == [(False, "Choir")], \
        "everyone's, and still the choir's whichever page's row it is"
    assert run([item(followers_only="yes")])["outcomes"][0] == ("skipped", "invalid: followers_only must be true or false")
    sql = writes().read_text()
    assert "followers_only = club_events.followers_only and excluded.followers_only" in sql, "once public, stays public"


def t_teams_from_their_names():
    """A game's two names are looked up in the teams' names. A name no team goes by makes a team when a schedule
    wrote it, once, and is reported (Jesse, 2026-11-05), and a cut-off or placeholder name makes none."""
    teams = {"kennedy": "kennedy", "kennedy-community-ms": "kennedy", "stride-academy": "stride-academy",
             "saint-johns": "saint-johns", "carleton": "carleton", "willmar": "willmar",
             "north-junior-high": "north-junior-high"}
    g = lambda title, names, uid="": item(
        title=title, place="Kennedy Community School", area="game", source_name="Kennedy Community School",
        source_uid=uid, interest="watch_sports", game={"sport": "Girls Basketball", "teams": names})
    r = plan([g("Kennedy Girls Basketball vs Stride Academy", ["Kennedy Community MS (Middle", "Stride Academy"]),
              g("Kennedy Girls Basketball vs Holdingford", ["Kennedy", "Holdingford"]),
              g("Kennedy Girls Basketball vs Breck", ["Kennedy", "Breck School"], "bound:a"),
              g("Stride Girls Basketball vs Breck", ["Stride Academy", "Breck"], "mshsl:1:b"),
              g("Stride Girls Basketball vs Breck School", ["Stride Academy", "Breck School"], "bound:b2"),
              g("Kennedy Girls Basketball vs Willmar", ["Kennedy", "Willmar MS"], "bound:c"),
              g("Kennedy Girls Basketball vs North", ["Kennedy", "North Junior High"], "bound:d"),
              g("Kennedy Girls Basketball vs West", ["Kennedy", "West Junior High"], "bound:e"),
              g("Kennedy Girls Basketball vs Heritage", ["Kennedy", "Heritage Christian Academy Maple Grove"], "bound:f"),
              g("Kennedy Girls Basketball vs Litchfield", ["Kennedy", "Litchfield-Dassel-Cokato"], "bound:g"),
              *[g(f"Kennedy Girls Basketball vs {n}", ["Kennedy", n], f"bound:no{i}") for i, n in enumerate(
                  ("TBD", "Winner of Game 3", "Section 6AA #2", "Tournament", "Quad", "Girls Varsity", "Pool A"))],
              item(title="SJU Soccer vs #21 Carleton", place="Clemens Stadium", town="Collegeville", area="campus",
                   source_name="SJU Athletics", interest="watch_sports")], [], TODAY, INTERESTS, teams=teams)
    rows = {e["row"]["title"]: e["row"] for e in r["events"]}
    assert rows["Kennedy Girls Basketball vs Stride Academy"]["team_ids"] == ["kennedy", "stride-academy"], "a cut-off alias"
    assert rows["SJU Soccer vs #21 Carleton"]["team_ids"] == ["saint-johns", "carleton"]
    judge = rows["Kennedy Girls Basketball vs Holdingford"]
    assert judge["team_ids"] is None and judge["sport"] is None, "the judge's name makes no team"
    assert [n for n in r["notes"] if n.startswith("who is this: 'Holdingford'")], r["notes"]
    breck = rows["Kennedy Girls Basketball vs Breck"]
    assert breck["team_ids"] == ["kennedy", "breck"] and breck["team_names"] == ["Kennedy", "Breck"], "its kind off"
    assert rows["Stride Girls Basketball vs Breck"]["team_ids"] == ["stride-academy", "breck"], "the next spelling finds it"
    assert rows["Stride Girls Basketball vs Breck School"]["team_names"] == ["Stride Academy", "Breck"], "one name each run"
    assert sum(n.startswith("new team: 'Breck'") for n in r["notes"]) == 1, "reported once"
    assert rows["Kennedy Girls Basketball vs Willmar"]["team_ids"] == ["kennedy", "willmar"], "a school's kind folds"
    assert rows["Kennedy Girls Basketball vs North"]["team_ids"] == ["kennedy", "north-junior-high"], "its own name wins"
    assert rows["Kennedy Girls Basketball vs West"]["team_ids"] == ["kennedy", "west-junior-high"], "a direction keeps its kind"
    assert rows["Kennedy Girls Basketball vs Heritage"]["team_shorts"][1] == "Heritage Christian", "cut at a word"
    assert rows["Kennedy Girls Basketball vs Litchfield"]["team_shorts"][1] == "Litchfield", "a co-op's first school"
    assert team_short("Minneapolis Southwest") == "Mpls Southwest" and team_short("Minneapolis North") == "Minneapolis North"
    for n in ("TBD", "Winner of Game 3", "Section 6AA #2", "Tournament", "Quad", "Girls Varsity", "Pool A"):
        assert rows[f"Kennedy Girls Basketball vs {n}"]["team_ids"] is None, n
        assert [x for x in r["notes"] if x.startswith(f"who is this: {n!r}")], n
    assert could_be_a_team("Tri-City United") and could_be_a_team("St. Paul Johnson") and could_be_a_team("Paynesville Area-EVW")
    assert r["teams_checked"] and not run([])["teams_checked"]
    assert team_key("#21 Saint John's") == "saint-johns" and team_key("Kennedy Community MS (Mid") == "kennedy-community-ms"
    assert team_key("St. Cloud Tech (Varsity) (Time TBA)") == "st-cloud-tech"

    class Db:
        rest = staticmethod(lambda *_: [
            {"id": "brainerd-little-falls", "name": "Brainerd-Little Falls", "short_name": "Brainerd", "aliases": []},
            {"id": "brainerd", "name": "Brainerd", "short_name": "Brainerd", "aliases": ["Forestview MS"]},
            {"id": "centennial-spring-lake-park", "name": "Centennial-Spring Lake Park", "short_name": "Centennial", "aliases": []},
            {"id": "gustavus-adolphus", "name": "Gustavus Adolphus", "short_name": "Gustavus", "aliases": []}])
    known = known_teams(Db)
    assert known["brainerd"] == "brainerd" and known["brainerd-little-falls"] == "brainerd-little-falls", known
    assert known["forestview-ms"] == "brainerd", "an alias still counts"
    assert "centennial" not in known and known["gustavus"] == "gustavus-adolphus", "a co-op's short name isn't looked up"


def t_one_place_two_names():
    old = listed_facts({"event_date": "2026-11-09", "start_time": "6 PM", "location": "75 Callaway St E",
                        "source_name": "City of St. Joseph", "title": "Planning Commission"})
    new = listed_facts({"event_date": "2026-11-09", "start_time": "6 PM", "location": "City Hall",
                        "source_name": "City of St. Joseph", "title": "Planning Commission"})
    assert old["entry"] and same_event(old, new), (old, new)


# Smooth-mornings 08's real cases: one Event from two hosts.
SISTERS = dict(title="All Hallows' Eve Procession", start="2026-10-31", end=None, all_day=True, place="Monastic Cemetery",
               source_name="Sisters of the Order of Saint Benedict", source_url="https://sbm.osb.org/events/",
               interest=None, size="everyday")
CAMPUS = dict(SISTERS, title="All Hallow's Eve Procession", start="2026-10-31T16:30:00-05:00", all_day=False,
              place="Saint Benedict's Monastery", source_name="Saint Benedict's Monastery",
              source_url="https://my.csbsju.edu/public/events/4852763", source_uid="4852763")
TOAST = dict(start="2026-11-06T18:00:00-06:00", end=None, interest=None, size="everyday")
JOETOWN = item(title="Twinkle & Toast", place="25 First Ave NW", source_name="JoeTown",
               source_url="https://www.joetown.org/events", **TOAST)
WR_HOME = item(title="Twinkle & Toast", place="WR Home & Clothing Co.", source_name="W|R Home Company",
               source_url="https://wrhomecompany.com/pages/events", **dict(TOAST, start="2026-11-06", all_day=True))
PEONY = item(title="Twinkle & Toast: Holiday Launch", place="White Peony and WR Home", source_name="White Peony Boutique",
             source_url="https://whitepeonyboutique.com/pages/events", **TOAST)


def t_two_hosts_one_place_inside_another():
    """The procession (Oct 28): the sisters' site all day at Monastic Cemetery, the campus calendar 4:30 PM at
    Saint Benedict's Monastery. A place the registry doesn't know, from the host the other copy names, is on
    that host's grounds: one Event at 4:30 PM, the other copy its Mention."""
    r = run([item(**SISTERS), item(**CAMPUS)])
    assert len(r["events"]) == 1 and [o[0] for o in r["outcomes"]] == ["merged", "published"], r["outcomes"]
    g = r["events"][0]
    assert (g["row"]["start_time"], g["row"]["all_day"], g["row"]["location"]) == ("4:30 PM", False, "Saint Benedict's Monastery")
    assert len(payloads(r)["p_mentions"]) == 2, payloads(r)["p_mentions"]
    listed_first = listed(title="All Hallow's Eve Procession", event_date="2026-10-31", start_time=None, all_day=True,
                          location="Monastery cemetery", source_name=SISTERS["source_name"], source_uid="page:x")
    g = run([item(**CAMPUS)], [listed_first])["events"][0]
    assert g["id"] == listed_first["id"] and g["row"]["start_time"] == "4:30 PM", "listed all day, it takes the time"


def t_two_hosts_an_address_names_its_shops():
    """Twinkle & Toast (Nov 6), from three hosts: JoeTown at "25 First Ave NW", W|R Home all day at its shop,
    White Peony at "White Peony and WR Home". The address is both shops' building and the line names both
    shops: one Event, whichever copy comes first."""
    r = run([JOETOWN, WR_HOME, PEONY])
    assert len(r["events"]) == 1 and len(r["events"][0]["mentions"]) == 3, [g["row"]["title"] for g in r["events"]]
    assert len(run([PEONY, WR_HOME])["events"]) == 1, "White Peony's line names W|R Home's shop too"
    # The other host's name and a weekday say nothing of which event it is.
    named = run([PEONY, dict(WR_HOME, title="Free Twinkle & Toast at White Peony Friday")])
    assert len(named["events"]) == 1, named["outcomes"]


def t_two_hosts_copy_kept():
    """The copy kept: the place's own host's over JoeTown's calendar, then a timed one; Jesse kept White Peony's
    (Oct 29). Kept all day, the Event still takes the time another copy gives."""
    row = run([JOETOWN, WR_HOME, PEONY])["events"][0]["row"]
    assert (row["title"], row["source_name"], row["start_time"]) == ("Twinkle & Toast: Holiday Launch", PEONY["source_name"], "6 PM")
    row = run([JOETOWN, WR_HOME])["events"][0]["row"]
    assert (row["source_name"], row["start_time"], row["all_day"]) == ("W|R Home Company", "6 PM", False), row
    # Only its own day's time: an official all-day copy a day later (one by the all-day rule) stays all day.
    days = [item(source_name="Newsleaders", trust="secondhand", start="2026-10-31", end=None, all_day=True),
            item(start="2026-11-01", end=None, all_day=True),
            item(source_name="City of St. Joseph", trust="secondhand", start="2026-10-31T16:00:00-05:00", end=None)]
    g = run(days)["events"]
    assert len(g) == 1 and (g[0]["row"]["event_date"], g[0]["row"]["all_day"]) == ("2026-11-01", True), g[0]["row"]


def t_two_hosts_maybe_the_same():
    """Sunny Mary Meadow's Nov 3 market as "Indoor Farmers Market" in The Bloom Room (its event room) and "Holiday
    Market": the day, place and time match but the names only share a word, so both stay and Jesse is asked.
    Splintered Harmony at Krewe (Oct 26) shares its name's words with Flour & Flower's Paint & Sip, not all of
    them, an hour and a half later: both stay, under "Maybe the same"."""
    market = dict(start="2026-11-03T15:00:00-06:00", end=None, source_name="Sunny Mary Meadow", interest=None,
                  source_url="https://sunnymarymeadow.com/events/")
    r = run([item(title="Indoor Farmers Market", place="The Bloom Room", **market),
             item(title="Holiday Market", place="Sunny Mary Meadow", **market)])
    assert len(r["events"]) == 2 and any("kept apart: 'Holiday Market' and 'Indoor Farmers Market'" in n
                                         for n in r["notes"]), r["notes"]
    r = run([item(title="Splintered Harmony Release Party", place="Krewe", source_name="Krewe",
                  start="2026-10-26T17:00:00-05:00", end=None, source_url="https://krewemn.com/saint-joseph-krewe-restaurant-events"),
             item(title="Paint & Sip: Court of Splintered Harmony", place="Krewe Restaurant", source_name="Flour & Flower Bakery",
                  start="2026-10-26T18:30:00-05:00", end=None, source_url="https://www.instagram.com/p/splintered/")])
    assert len(r["events"]) == 2 and any("Splintered Harmony" in n for n in r["notes"] if n.startswith("kept apart")), r["notes"]


def t_one_facebook_event_is_one():
    """The judge words a title anew on each read, so one Facebook event came back under two names that don't fit
    inside each other, and both showed: Stone Road's "Stone Road Live" and "Stone Road at The La Playette", Grey
    Face's "Fresh Skin Tattoos Fundraiser" and "Grey Face Flash Tattoos & Raffle" (2026-11-05)."""
    link = "https://www.facebook.com/events/1401297332070761/"
    show = dict(start="2026-11-07T20:30:00-06:00", end=None, place="The La Playette", source_name="Stone Road",
                source_url=link)
    seen = {"source_name": "Stone Road", "source_url": link, "source_uid": "page:2026-11-07T2030:live-road-stone",
            "trust": "official", "sure": True}
    old = listed(title="Stone Road Live", event_date="2026-11-07", start_time="8:30 PM", location="The La Playette",
                 source_name="Stone Road", source_uid=seen["source_uid"], mentions=[seen])

    r = run([item(title="Stone Road at The La Playette", **show)], [old])
    assert outcome(r, 0) == "merged" and [g["id"] for g in r["events"]] == [old["id"]], r["outcomes"]
    assert not any(n.startswith("kept apart") for n in r["notes"]), r["notes"]

    # Its link written another way is the same event.
    r = run([item(title="Stone Road at The La Playette", **dict(show, source_url=link.rstrip("/") + "?ref=newsfeed"))], [old])
    assert outcome(r, 0) == "merged", r["outcomes"]

    # A copy with no time takes the read's: Grey Face's Oct 29 copy had none, its Nov 5 read said 2 PM.
    r = run([item(title="Stone Road at The La Playette", **show)], [dict(old, start_time=None, all_day=True)])
    assert outcome(r, 0) == "merged" and r["events"][0]["row"]["start_time"] == "8:30 PM", r["events"][0]["row"]

    # Jeanne B's Tours and Jeanne B's Tours & Shoppe: one host under two spellings.
    r = run([item(title="Some Other Name", **dict(show, source_name="Stone Road & Friends"))], [old])
    assert outcome(r, 0) == "merged" and r["events"][0]["id"] == old["id"], r["outcomes"]

    # The shown copy takes it, not one taken out: Stone Road's second copy is rejected and stays so.
    gone = dict(old, id="22222222-2222-2222-2222-222222222222", status="rejected", review_reason="other",
                title="Stone Road at The La Playette", source_uid="page:2026-11-07T2030:la-playette-road-stone",
                mentions=[dict(seen, source_uid="page:2026-11-07T2030:la-playette-road-stone")])
    r = run([item(title="Stone Road Tonight", **show)], [gone, old])
    assert [g["id"] for g in r["events"]] == [old["id"]], r["events"]

    # Two reads in one run are one Event.
    r = run([item(title="Stone Road Live", **show), item(title="Stone Road at The La Playette", **show)])
    assert len(r["events"]) == 1 and outcome(r, 1) == "merged", r["outcomes"]

    # Still two: one event page's matinee and evening show,
    r = run([item(title="The Curious Incident, matinee", **dict(show, start="2026-11-07T14:00:00-06:00")),
             item(title="The Curious Incident, evening", **dict(show, start="2026-11-07T19:00:00-06:00"))])
    assert len(r["events"]) == 2, r["events"]
    # its other days,
    r = run([item(title="Stone Road Encore", **dict(show, start="2026-11-08T20:30:00-06:00"))], [old])
    assert r["events"][0]["id"] is None, r["events"]
    # another host's listing, which stays a question for the morning review,
    r = run([item(title="Stone Road at The La Playette", **dict(show, source_name="JoeTown"))], [old])
    assert r["events"][0]["id"] is None and any(n.startswith("kept apart") for n in r["notes"]), r["notes"]
    # and two things from one post: a post's link can carry both.
    post = "https://www.facebook.com/stoneroad/posts/1"
    seen_post = dict(seen, source_url=post)
    r = run([item(title="Stone Road at The La Playette", **dict(show, source_url=post))], [dict(old, mentions=[seen_post])])
    assert r["events"][0]["id"] is None, r["events"]


def t_read_with_no_time_keeps_the_listed_time():
    """A host's post that gives no time says nothing of its Event's time. It used to overwrite the time with all day,
    and the end with nothing: 11:30 AM read as all day (2026-11-05). Now it is a Mention only (Jesse, 2026-11-06)."""
    old = listed(title="Holiday Porch Pot Workshop", event_date="2026-11-22", start_time="11:30 AM",
                 location="Northern Hallow Winery, Foley", source_name="Holistic Flower Farm",
                 source_uid="page:2026-11-22T1130:holiday-porch-pot-workshop")
    post = item(title="Holiday Porch Pot Workshop", start="2026-11-22", end=None, all_day=True,
                place="Northern Hallow Winery, Foley", town="Foley", area="announced",
                source_name="Holistic Flower Farm", source_url="https://www.facebook.com/holistic/posts/9")
    r = run([post], [old])
    g = r["events"][0]
    assert outcome(r, 0) == "merged" and g["id"] == old["id"] and g["row"] is None, (r["outcomes"], g["row"])
    assert any(m["source_url"] == post["source_url"] and m.get("new") for m in g["mentions"]), g["mentions"]

    # A copy taken out stays out: no time read is no change to send back to Review.
    g = run([post], [dict(old, status="rejected", review_reason="other")])["events"][0]
    assert g["status"] == "rejected" and g["row"] is None, g["status"]

    # Still updates: a read that gives a time,
    g = run([dict(post, start="2026-11-22T13:00:00-06:00", all_day=False)], [old])["events"][0]
    assert g["row"]["start_time"] == "1 PM" and not g["row"]["all_day"], g["row"]
    # a listing with its own id, which speaks for itself when it drops its time,
    own = dict(old, source_uid="4168764")
    g = run([dict(post, source_uid="4168764")], [own])["events"][0]
    assert g["id"] == own["id"] and g["row"]["all_day"], g["row"]
    # and a read that makes it a run over days.
    g = run([dict(post, end="2026-11-24")], [old])["events"][0]
    assert g["id"] == old["id"] and g["row"]["all_day"] and g["row"]["end_at"], g["row"]


def t_two_hosts_no_place_asked():
    """Sal's page gave "Puzzle Mania" no place; the City listed its "Fall Adult Puzzle Competition" at Sal's the
    same day and hour (smooth-mornings 13, 2026-11-03). The names share a word: both stay, and Jesse is asked."""
    city = listed(title="Fall Adult Puzzle Competition", event_date="2026-11-22", start_time="11 AM",
                  location="Sal's Bar and Grill", source_name="City of St. Joseph", source_uid="1753692979231258")
    sals = item(title="Puzzle Mania", start="2026-11-22T11:00:00-06:00", end=None, place="",
                source_name="Sal's Bar and Grill", source_url="https://salsbarstjoe.com/event/puzzle-mania/")
    r = run([sals], [city])
    assert r["events"][0]["id"] is None and any(
        "kept apart: 'Puzzle Mania' and 'Fall Adult Puzzle Competition'" in n for n in r["notes"]), r["notes"]
    bingo = run([dict(sals, title="Bingo Night")], [city])
    assert not any(n.startswith("kept apart") for n in bingo["notes"]), "no word in common, nothing to ask"


def t_two_hosts_kept_apart():
    """No two different things at one place on one day become one: Dec 3's two Detroit Mountain Invite races (9 AM
    and 10:30 AM), two Clemens Library events one evening, two colleges' games under their own names, away games,
    and two shops' own events in one building."""
    race = dict(title="Detroit Mountain Invite", place="Detroit Mountain", area="game", interest="watch_sports", end=None,
                size="everyday")
    races = [item(start="2026-12-03T09:00:00-06:00", source_name="Cathedral High School",
                  source_url="https://www.gobound.com/mn/schools/cathedral", **race),
             item(start="2026-12-03T10:30:00-06:00", source_name="Sartell High School",
                  source_url="https://www.gobound.com/mn/schools/sartell", **race)]
    assert len(run(races)["events"]) == 2, "times that don't agree"
    library = dict(place="Clemens Library", start="2026-10-27T17:00:00-05:00", end=None, area="campus", interest=None)
    evening = [item(title="Fix-It Clinic: Halloween Edition!", source_name="CSB SJU Libraries",
                    source_url="https://my.csbsju.edu/public/events/4842668", **library),
               item(title="Spooky Halloween Diamond Dotz", source_name="CSB SJU Campus Events",
                    source_url="https://my.csbsju.edu/public/events/4523238", **library)]
    assert len(run(evening)["events"]) == 2, "one shared word is no name"
    games = [item(title="CSB Soccer vs Hamline", place="Clemens Stadium", source_name="CSB Athletics", area="campus"),
             item(title="SJU Soccer vs Hamline", place="Clemens Stadium", source_name="SJU Athletics", area="campus")]
    assert len(run(games)["events"]) == 2, "a host's own name stays in its title: two teams"
    # On a host's grounds alone (an away game's gym the registry doesn't know), only the very same name merges:
    # Apollo's "Girls JV" at Rush City (Dec 17) and Upsala at Apollo; Sartell's varsity at Brainerd and Tech at Sartell.
    away = dict(area="game", interest="watch_sports", end=None, size="everyday")
    for there, home in [(item(title="Girls JV", place="Rush City High School Main Gym", source_name="Apollo High School",
                              start="2026-12-17T17:00:00-06:00", **away),
                         item(title="Upsala Girls Basketball vs St. Cloud · JV", place="St. Cloud Apollo High School Gym",
                              source_name="Tech High School", start="2026-12-17T17:45:00-06:00", **away)),
                        (item(title="Boys Varsity", place="Brainerd High School Main Gym", source_name="Sartell High School",
                              start="2027-01-19T19:15:00-06:00", **away),
                         item(title="Tech Boys Basketball vs Sartell · Varsity", place="Sartell High School Gym, Main",
                              source_name="Tech High School", start="2027-01-19T19:00:00-06:00", **away))]:
        assert len(run([there, home])["events"]) == 2, there["title"]
    # A shared address is all its shops, but a copy there joins only an Event every copy of which it matches: JoeTown's
    # open house at 25 First Ave NW doesn't make White Peony's and W|R Home's, each at its own shop, one.
    house = dict(title="Holiday Open House", end=None, interest=None, size="everyday")
    shops = [item(place="25 First Ave NW", source_name="JoeTown", start="2026-11-07", all_day=True, **house),
             item(place="White Peony Boutique", source_name="White Peony Boutique", start="2026-11-07T09:00:00-06:00", **house),
             item(place="W|R Home Company", source_name="W|R Home Company", start="2026-11-07T08:00:00-06:00", **house)]
    assert len(run(shops)["events"]) == 2, [o for o in run(shops)["outcomes"]]


def t_one_host_two_names():
    """Sartell High School's calendar (Bound) listed "Fall Play" and its Instagram "The Crucible", each at its
    Performing Arts Center at 7 PM on Oct 29 (2026-10-29): one Event, whichever came first. Two listings with
    their own ids, two posts, a game, or another start stay two."""
    stage = dict(place="Sartell High School Performing Arts Center", source_name="Sartell High School", interest=None,
                 start="2026-10-29T19:00:00-05:00", end=None, size="everyday", area="announced")
    bound = item(title="Fall Play", source_url="https://gobound.com/direct/noncomps/h1/h", source_uid="bound:h1", **stage)
    post = item(title="The Crucible", source_url="https://www.instagram.com/p/De1v7gmE6RA/", **stage)
    r = run([bound, post])
    assert len(r["events"]) == 1 and len(r["events"][0]["mentions"]) == 2, r["outcomes"]
    as_listed = dict(location=stage["place"], source_name=stage["source_name"], event_date="2026-10-29", start_time="7 PM")
    for first, then in ((listed(title="Fall Play", source_uid="bound:h1", **as_listed), post),
                        (listed(title="The Crucible", source_uid="page:2026-10-29T1900:crucible", **as_listed), bound)):
        g = run([then], [first])["events"]
        assert len(g) == 1 and g[0]["id"] == first["id"], (first["title"], g)
    apart = [[bound, dict(bound, title="Senior Recital", source_uid="bound:h2")],
             [post, dict(post, title="Art Show Opening", source_url="https://www.instagram.com/p/other/")],
             [post, dict(bound, title="Sartell Volleyball vs Brainerd", interest="watch_sports")],
             [post, dict(bound, start="2026-10-29T19:30:00-05:00")]]
    for pair in apart:
        assert len(run(pair)["events"]) == 2, [i["title"] for i in pair]


def t_one_host_listed_twice():
    """Cathedral's Knowledge Bowl meet, Nov 10 at 4 PM, listed three times with three ids and a longer name each time
    (2026-11-05): one Event, new or already listed. Another level, start, place or word, a game, or a followers-only
    listing stays two."""
    meet = dict(place="St. Cloud Cathedral High School Commons", source_name="Cathedral High School", interest=None,
                start="2026-11-10T16:00:00-06:00", end=None, size="everyday", area="announced")
    one, two, three = (item(title=t, source_uid=f"bound:h{n}", source_url=f"https://gobound.com/direct/comps/h{n}/show", **meet)
                       for n, t in enumerate(("Cathedral Knowledge Bowl Meet", "Cathedral Knowledge Bowl",
                                              "St. Cloud Cathedral Knowledge Bowl Meet")))
    r = run([one, two, three])
    assert len(r["events"]) == 1 and len(r["events"][0]["mentions"]) == 3, r["outcomes"]
    kept = listed(title="Cathedral Knowledge Bowl Meet", source_uid="bound:h0", location=meet["place"],
                  source_name=meet["source_name"], event_date="2026-11-10", start_time="4 PM",
                  mentions=[{"source_name": meet["source_name"], "source_url": one["source_url"], "source_uid": "bound:h0",
                             "trust": "official", "sure": True}])
    g = run([two], [kept])["events"]
    assert len(g) == 1 and g[0]["id"] == kept["id"], g
    for other in (dict(two, title="Knowledge Bowl Meet · JV"), dict(two, start="2026-11-10T17:00:00-06:00"),
                  dict(two, place="Sartell High School Commons"), dict(two, title="Cathedral Science Bowl Meet"),
                  dict(two, title="Cathedral Knowledge Bowl vs Sartell", interest="watch_sports")):
        assert len(run([one, other])["events"]) == 2, other["title"]
    hidden = dict(followers_only=True, activity_team="sartell", activity_name="Wrestling")
    assert len(run([dict(one, **hidden), dict(two, **hidden)])["events"]) == 2, "a school's meets look alike and aren't"


COPIES = Path(__file__).resolve().parents[1] / "evals" / "copies" / "copies.json"


def copy_item(row):
    """A copy's live row as the judged item it came from: its place line's town split off ("Neighbors, Albertville")."""
    place, _, town = (row["location"] or "").rpartition(", ")
    if registry.place_key(town) not in registry.TOWN_KEYS:
        place, town = row["location"] or "", "St. Joseph"
    at = None if row["all_day"] else parse_clock(row["start_time"])
    start = row["event_date"] if at is None else \
        datetime.combine(date.fromisoformat(row["event_date"]), at).replace(tzinfo=LOCAL).isoformat()
    return item(title=row["title"], start=start, end=None, all_day=at is None, place=place, town=town, area="announced",
                source_name=row["source_name"], source_url=row["source_url"], interest=None, size="everyday",
                source_uid=row["source_uid"] if real_uid(row["source_uid"]) else "",
                trust="secondhand" if row["trust"] == "squishy" else "official")


def t_real_copies():
    """Every copy taken out of the Town feed from Oct 17 to Nov 3 (sources/evals/copies, BP app watch-every-place 15),
    replayed morning by morning as it was written: each Event's later copies are merged, or named under "Maybe the
    same" for the morning's review when their names differ; each News's later copies are repeats."""
    fx = json.loads(COPIES.read_text())
    missed = []
    for g in fx["events"]:
        rows, shown = [], 0
        for _, batch in groupby(g["rows"], key=lambda r: r["created_at"][:13]):  # one run writes within the hour
            batch = list(batch)
            r = plan([copy_item(x) for x in batch], list(rows), date.fromisoformat(batch[0]["created_at"][:10]), INTERESTS)
            for x, (kind, why) in zip(batch, r["outcomes"]):
                assert kind in ("published", "merged"), (g["name"], x["title"], kind, why)
                if kind == "published":
                    asked = f"kept apart: {tidy_title(x['title'], x['source_name'])!r} and "
                    shown += not any(n.startswith(asked) for n in r["notes"])
                    rows.append(listed(**{k: x[k] for k in ("id", "title", "event_date", "start_time", "all_day",
                                                            "location", "source_name", "source_uid")},
                                       shows_from=None, mentions=[{"source_name": x["source_name"], "source_url": x["source_url"],
                                                                   "source_uid": x["source_uid"], "trust": x["trust"], "sure": True}]))
        if shown != 1:
            missed.append(f"{g['name']}: {shown} shown")
    for g in fx["news"]:
        recent, shown = [], 0
        for x in g["rows"]:
            at = datetime.fromisoformat(x["created_at"])
            recent = [n for n in recent if at - n["at"] <= timedelta(7)]  # the Town feed's week
            it = item(kind="news", title=x["title"], source_name=x["source_name"], source_url=x["source_url"],
                      start=None, end=None, place="", interest=None, category="business",
                      trust="official" if x["tier"] == 1 else "secondhand")
            r = plan([it], [], at.date(), INTERESTS, recent_news=list(recent))
            if r["outcomes"][0][0] == "news":
                shown += 1
                recent.append({**r["news"][0], "status": "published", "created_at": x["created_at"], "at": at})
        if shown != 1 and not g.get("known_miss"):
            missed.append(f"{g['name']}: {shown} shown")
    assert not missed, missed


TESTS = [t_read_with_no_time_keeps_the_listed_time, t_one_facebook_event_is_one, t_news_state_initials_tell_nothing, t_one_host_no_place_is_one, t_real_copies, t_one_host_two_names, t_two_hosts_one_place_inside_another, t_two_hosts_an_address_names_its_shops, t_two_hosts_copy_kept,
         t_two_hosts_maybe_the_same, t_two_hosts_no_place_asked, t_two_hosts_kept_apart, t_one_place_two_names, t_followers_only, t_place_entry, t_wording, t_interest_list_is_the_apps, t_event_or_news, t_official_one_mention, t_everything_kept_goes_live, t_news_repeat_left_out,
         t_one_news_one_link, t_news_same_link_this_week, t_news_says_when_it_ends, t_closings_wait, t_a_dated_news_blocks_its_repeat_until_its_day, t_one_post_is_one_news, t_news_look_back_is_the_feeds_week, t_news_shouted_or_hyphened_is_one,
         t_all_day_a_day_apart_is_one, t_no_time_joins_the_timed_one, t_later_read_fills_the_time, t_merge_true_pair,
         t_merge_near_miss_kept_apart, t_posted_twice, t_same_time_no_place, t_no_place_is_its_posters_own, t_reread_updates, t_admin_status_kept, t_misread_comes_back, t_cancelled, t_show_from_by_size, t_kept_out_when_nobody_can_go,
         t_interest_checked, t_area, t_past_and_invalid_skipped, t_writes_are_one_safe_call,
         t_description_cut_at_a_word, t_city_meeting_end_and_place, t_game, t_teams_from_their_names, t_all_day_run_keeps_its_last_day,
         t_long_titles_shortened_and_kept, t_news_titles_fit_their_two_lines, t_short_levels_kept_apart, t_one_host_listed_twice]


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
    ap.add_argument("--news", help="'db', or a JSON file of this week's News already in the app (with --apply, db by default)")
    ap.add_argument("--today", help="YYYY-MM-DD; default today in Chicago")
    ap.add_argument("--town", default=DEFAULT)
    ap.add_argument("--sql", help="write the live write as SQL to this file")
    ap.add_argument("--apply", action="store_true", help="write to the database (service role key in the environment)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.items or not args.existing:
        ap.error("needs the judged items and --existing (the merge rule checks the list)")
    town = lookup(args.town)
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
    # A live write always checks this week's News: the database no longer drops a link it already has.
    news_from = args.news or ("db" if args.apply else None)
    news = [] if not news_from else news_in_db() if news_from == "db" else json.loads(Path(news_from).read_text())
    r = plan(items, existing, today, interests, town, teams=known_teams() if args.apply else None,
             recent_news=news)
    report(items, r)
    if args.sql:
        Path(args.sql).write_text(to_sql(r, today))
        print(f"[judged] SQL for the live write: {args.sql} (not run)")
    if args.apply:
        print(f"[judged] written: {json.dumps(apply(r))}")


if __name__ == "__main__":
    main()
