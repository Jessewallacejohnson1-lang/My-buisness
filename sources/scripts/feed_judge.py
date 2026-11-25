#!/usr/bin/env python3
"""
feed_judge.py: two judges read what an Apify check put in the Town feed, beside its own posts (BP app
watch-every-place 52; Jesse, 2026-11-24: "have a agents judge job be to finish clearing data for apify solving the
hiccups we have found"). What both say is done, where they differ is one line in the morning report.

  python3 sources/scripts/feed_judge.py prepare          the check's new and changed Events and News, and the Events this
                                                         morning's [check] lines named, in .runs/morning/feed-judge/batch-N.json
  python3 sources/scripts/feed_judge.py keep [--dry-run]  both judges' lines (a.jsonl, b.jsonl there): what they agree on is
                                                         written by public.feed_judge, and every verdict kept
  python3 sources/scripts/feed_judge.py --selftest

An item is judged once: feed_judgments keeps the fingerprint of what was read, so only a changed one comes back. Nothing is
written past MOST of a check's items (a judge gone wrong): those wait, named. Never a game, a neighbour's Event or a Group's.
"""

import argparse, hashlib, json, re, shutil, sys
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root
from read_events import LOCAL
from run import Supabase
from db import DbError
import write_judged
from write_judged import words

DAYS = 2            # a row a check wrote this lately and no judge has read; a check that failed is picked up by the next
PER_JUDGE = 20      # items in one judge's batch
ALSO = 15           # of a host's other live items, shown beside each
MOST = 0.25         # of a check's items two judges may change; FEW always may
FEW = 4
SOCIAL = "or=(source_url.ilike.*facebook.com*,source_url.ilike.*instagram.com*)"
EVENT = ("id,title,event_date,start_time,end_at,all_day,location,description,price,ages,source_name,source_url,moved_at,"
         "moved_from,place_entry_id,sport,team_ids,submitted_by,club_id")
NEWS = "id,title,blurb,category,source_name,source_url,post_words,posted_at,ends_on,starts_at,created_at,published_at,status"
REASONS = {"copy": "other", "over": "other", "not open": "not_event", "not an event or news": "not_event"}
CHECK = re.compile(r"^\[check\] (.+) \((\d{4}-\d\d-\d\d)\): (.+)$", re.M)


def chicago(stamp):
    return f"{(d := datetime.fromisoformat(stamp).astimezone(LOCAL)):%a %Y-%m-%d %-I:%M %p}" if stamp else None


def in_list(values):
    return quote("(" + ",".join('"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"' for v in sorted(values)) + ")")


def showing(events, today):
    """Found Events still to come or running, games aside."""
    last = lambda e: max(date.fromisoformat(e["event_date"]), datetime.fromisoformat(e["end_at"]).astimezone(LOCAL).date()
                         if e.get("end_at") else date.min)
    return [e for e in events if not e.get("submitted_by") and not e.get("club_id") and not e.get("sport")
            and not write_judged.is_game(e) and last(e) >= today]


LIVE = "status=eq.approved&kind=eq.event&cancelled_at=is.null"


def to_judge(db, now):
    """([(kind, row, its posts, its [check] note)], the rows of the same hosts also live)."""
    today, since = now.astimezone(LOCAL).date(), quote((now - timedelta(days=DAYS)).isoformat())
    fresh = {m["event_id"] for m in db.rest("GET", f"event_mentions?select=event_id&last_seen=gte.{since}&{SOCIAL}") or []}
    report = db.rest("GET", f"morning_reports?select=report&day=eq.{today}") or []
    checks = {(t, d): c for t, d, c in CHECK.findall(report[0]["report"] if report else "")}
    events = db.rest("GET", f"club_events?select={EVENT}&{LIVE}&id=in.{in_list(fresh)}") or [] if fresh else []
    if checks:
        named = db.rest("GET", f"club_events?select={EVENT}&{LIVE}&title=in.{in_list({t for t, _ in checks})}"
                               f"&event_date=in.{in_list({d for _, d in checks})}") or []
        have = {e["id"] for e in events}
        events += [e for e in named if e["id"] not in have and (e["title"], e["event_date"]) in checks]
    events = showing(events, today)
    news = [n for n in db.rest("GET", f"board_items?select={NEWS}&status=eq.published&created_at=gte.{since}&{SOCIAL}") or []
            if now < write_judged.news_lasts_until(n)]
    ids = [e["id"] for e in events]
    posts = {}
    for m in (db.rest("GET", "event_mentions?select=event_id,source_name,source_url,host_words,first_seen"
                             f"&event_id=in.{in_list(ids)}&order=first_seen") or [] if ids else []):
        posts.setdefault(m["event_id"], []).append({"by": m["source_name"], "link": m["source_url"], "words": m["host_words"]})
    out = [("Event", e, posts.get(e["id"], []), checks.get((e["title"], e["event_date"]))) for e in events]
    out += [("News", n, [{"by": n["source_name"], "link": n["source_url"], "words": n["post_words"]}], None) for n in news]
    hosts = {r["source_name"] for _, r, _, _ in out}
    also = []
    if hosts:
        also += [("Event", e) for e in showing(db.rest("GET", f"club_events?select={EVENT}&{LIVE}&source_name=in.{in_list(hosts)}"
                 f"&or={quote(f'(event_date.gte.{today},end_at.gte.{today})')}&order=event_date&limit=1000") or [], today)]
        also += [("News", n) for n in db.rest("GET", f"board_items?select={NEWS}&status=eq.published&source_name=in.{in_list(hosts)}"
                 f"&published_at=gte.{quote((now - timedelta(days=30)).isoformat())}") or [] if now < write_judged.news_lasts_until(n)]
    return out, also


def shown(kind, r):
    """What the app shows of an item, as its judges read it."""
    if kind == "News":
        it = {"about": r["blurb"], "shows_until": r["ends_on"], "starts": chicago(r["starts_at"]), "link": r["source_url"],
              "posted": chicago(r["posted_at"]), "category": r["category"]}
    else:
        was = r.get("moved_from") or {}
        it = {"day": r["event_date"], "start": r["start_time"], "all_day": r["all_day"] or None, "end": chicago(r["end_at"]),
              "place": r["location"], "about": r["description"], "price": r["price"], "ages": r["ages"], "link": r["source_url"],
              "card_says_moved_from": {k: was.get(k) for k in ("event_date", "start_time", "location")} if was else None}
    it = {"kind": kind, "title": r["title"], "host": r["source_name"], **it}
    return {k: v for k, v in it.items() if v not in (None, "", [])}


def read_as(it, posts, check):
    return hashlib.md5(json.dumps([it, [p["words"] for p in posts], check], sort_keys=True).encode()).hexdigest()


def judged_before(db, rows):
    """{(id, fingerprint)} already judged."""
    out = set()
    for col, kind in (("event_id", "Event"), ("news_id", "News")):
        ids = [r["id"] for k, r, _, _ in rows if k == kind]
        if ids:
            out |= {(j[col], j["read_as"]) for j in db.rest("GET", f"feed_judgments?select={col},read_as&{col}=in.{in_list(ids)}") or []}
    return out


def prepare(out, now=None, db=None, grab=None, page=None):
    import morning, social
    # Our own storage, so no site's crawl delay to keep: the polite fetch took over 5 minutes for 30 pictures.
    grab, db, now = grab or social.fetch_picture, db or Supabase(), now or datetime.now(timezone.utc)
    folder = out / "feed-judge"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    rows, also = to_judge(db, now)
    before, new = judged_before(db, rows), []
    for kind, r, posts, check in rows:
        it = shown(kind, r)
        if (r["id"], read_as(it, posts, check)) not in before:
            new.append((kind, r, posts, check, it))
    ids = {k: [r["id"] for kind, r, *_ in new if kind == k] for k in ("Event", "News")}
    photos = {}
    for col, k in (("event_id", "Event"), ("news_id", "News")):
        for p in (db.rest("GET", f"place_photos?select=url,{col}&status=eq.live&{col}=in.{in_list(ids[k])}&order=position") or [] if ids[k] else []):
            photos.setdefault(p[col], []).append(p["url"])
    new.sort(key=lambda x: (x[1]["source_name"], x[0], x[1]["title"]))  # a host's items sit together, so a repeat is seen
    alias = {r["id"]: f"i{n:03d}" for n, (_, r, *_) in enumerate(new, 1)}
    others = [(k, r) for k, r in also if r["id"] not in alias]
    alias.update({r["id"]: f"o{n:03d}" for n, (_, r) in enumerate(others, 1)})
    line = lambda k, r: (f"{alias[r['id']]} {k}: {r['title']}" + (f" ({r['event_date']} {r['start_time'] or ''})".replace(" )", ")")
                         if k == "Event" else f": {r['blurb'] or ''}".rstrip(": ")))
    laid, items, failed = {}, [], []
    for kind, r, posts, check, it in new:
        key = alias[r["id"]]
        words_ = [{k: v for k, v in p.items() if v} for p in posts]
        if check:  # a website's Event: its own page, read the polite way; a post's words are already here
            own = [{"title": r["title"], "link": r["source_url"]}]
            morning.own_pages(own, page)
            it = {**it, "a_helper_said": check, **({"its_page_says": own[0]["page"]} if own[0]["page"] else {})}
        pics = []
        for n, url in enumerate(photos.get(r["id"], [])[:2]):
            try:
                grab(url, folder / f"{key}-{n}.jpg")
                pics.append(str(folder / f"{key}-{n}.jpg"))
            except Exception as e:
                failed.append(f"[feed judge]   {key}: a picture would not download ({' '.join(str(e).split())[:80]})")
        if not (pics or check or any(p.get("words") for p in posts)):
            continue  # nothing to hold it against
        mates = [line(k, o) for k, o in [(k, o) for k, o, *_ in new] + others if o["source_name"] == r["source_name"] and o["id"] != r["id"]]
        items.append({"item": key, **it, "what_was_posted": words_, **({"pictures": pics} if pics else {}),
                      **({"also_live_from_this_host": mates[:ALSO]} if mates else {})})
        laid[key] = {"id": r["id"], "kind": kind, "title": r["title"], "host": r["source_name"], "read_as": read_as(shown(kind, r), posts, check),
                     "shown": it, "said": " ".join(p.get("words") or "" for p in posts) + " " + str(it.get("its_page_says") or ""),
                     "posted": r.get("posted_at")}
    keeps = {a: {"id": i} for i, a in alias.items()}
    (folder / "laid.json").write_text(json.dumps({"items": laid, "names": keeps}, indent=1, ensure_ascii=False))
    for n, i in enumerate(range(0, len(items), PER_JUDGE), 1):
        (folder / f"batch-{n}.json").write_text(json.dumps(items[i:i + PER_JUDGE], indent=1, ensure_ascii=False) + "\n")
    print("\n".join([f"[feed judge] laid out {len(items)} items in {-(-len(items) // PER_JUDGE)} batches" if items
                     else "[feed judge] nothing to judge"] + failed))


def answers(path, laid):
    got = {}
    for ln in path.read_text().splitlines() if path.exists() else []:
        try:
            a = json.loads(ln.strip().strip(",")) if ln.strip().startswith("{") else None
        except ValueError:
            continue
        if isinstance(a, dict) and a.get("item") in laid and a.get("verdict") in ("fine", "fix", "take out", "unsure"):
            got.setdefault(a["item"], a)
    return got


def clock_of(text):
    t = write_judged.parse_clock(str(text or ""))
    return t and write_judged.clock(datetime.combine(date(2026, 1, 1), t))


def changes(it, kind, fix):
    """A judge's `fix` as the columns it changes, or None when any of it can't be read."""
    out, day = {}, None
    if not isinstance(fix, dict) or not fix or len(fix) > 3:
        return None
    text = {"title": "title", "about": "description" if kind == "Event" else "blurb"}
    for k, v in fix.items():
        v = " ".join(str(v or "").split())
        if k in text and v:
            out[text[k]] = v
        elif kind == "News" and k == "shows_until":
            try:
                out["ends_on"] = date.fromisoformat(v).isoformat()
            except ValueError:
                return None
        elif kind == "News":
            return None
        elif k == "day":
            try:
                day = out["event_date"] = date.fromisoformat(v).isoformat()
            except ValueError:
                return None
        elif k == "start" and clock_of(v):
            out["start_time"] = clock_of(v)
        elif k == "place" and v:
            out["location"] = v
        elif k == "price":
            out["price"] = v if v != "none" else ""
        elif k == "ages" and (v == "none" or write_judged.ages_of(v)):
            out["ages"] = write_judged.ages_of(v) or ""
        elif k == "moved" and v == "no":
            out["moved_at"] = None
        elif k != "end":
            return None
    if "end" in fix:
        v = " ".join(str(fix["end"] or "").split())
        m = re.fullmatch(r"(?:\w{3} )?(?:(\d{4}-\d\d-\d\d) )?(.+)", v)
        if v == "none":
            out["end_at"] = None
        elif m and clock_of(m[2]):
            on, t = date.fromisoformat(m[1] or day or it["day"]), write_judged.parse_clock(m[2])
            start = write_judged.parse_clock(out.get("start_time") or it.get("start") or "")
            on += timedelta(days=1) if not m[1] and start and t <= start else timedelta(0)  # ends past midnight
            out["end_at"] = datetime.combine(on, t, LOCAL).isoformat()
        else:
            return None
    elif day and it.get("end"):  # another day, the same hours
        end = datetime.strptime(it["end"], "%a %Y-%m-%d %I:%M %p").replace(tzinfo=LOCAL)
        out["end_at"] = (end + (date.fromisoformat(day) - date.fromisoformat(it["day"]))).isoformat()
    return out


NUMBER = re.compile(r"\d+")


def same_fix(it, a, b):
    """What both fixes change, or None: the same fields, each to the same thing. A title or an About in other words is the
    same when both judges quote the same words; every number in it must be in the post's words, the quotes or the item."""
    x, y = (changes(it["shown"], it["kind"], j.get("fix")) for j in (a, b))
    if not x or not y or set(x) != set(y):
        return None
    quotes = [words(j.get("quote")) for j in (a, b)]
    near = quotes[0] and quotes[1] and len(quotes[0] & quotes[1]) >= 2 / 3 * min(len(q) for q in quotes)
    known = set(NUMBER.findall(" ".join([it["said"], json.dumps(it["shown"]), str(a.get("quote")), str(b.get("quote"))])))
    out = {}
    for k, v in x.items():
        w = y[k]
        if v == w:
            out[k] = v
        elif k in ("title", "description", "blurb") and near and set(NUMBER.findall(v)) <= known:
            out[k] = v
        elif k in ("location", "price") and (words(v) <= words(w) or words(w) <= words(v)) and words(v) and words(w):
            out[k] = max(v, w, key=len)
        else:
            return None
    title = out.get("title")
    if title and (len(title) > write_judged.TITLE_MAX if it["kind"] == "Event" else not write_judged.headline_fits(title)):
        return None
    if "location" in out:
        place = write_judged.tidy_place(out["location"])
        out["location"], out["place_entry_id"] = place, write_judged.place_of(place, it["host"])[0]
    return out


def said_by(j):
    what = {"fine": "fine", "unsure": "unsure", "take out": f"take out ({j.get('reason')})",
            "fix": "fix " + ", ".join(f"{k} to {v!r}" for k, v in j["fix"].items()) if isinstance(j.get("fix"), dict) else "fix"}[j["verdict"]]
    return f"{what}: {j['why']}" if j.get("why") else what


def decide(it, a, b, names):
    """(outcome, why, the fix or None, the take-out's reason or None, the id of the copy kept or None)."""
    both = a["verdict"] if a["verdict"] == b["verdict"] else None
    why = " ".join(str(a.get("why") or b.get("why") or "").split())[:280]
    if both == "fine":
        return "fine", None, None, None, None
    if both == "take out" and a.get("reason") == b.get("reason") and a.get("reason") in REASONS:
        keep = names.get(a.get("keep"), {}).get("id") if a.get("keep") == b.get("keep") else None
        if a["reason"] != "copy" or keep and keep != it["id"]:
            return "taken out", why, None, REASONS[a["reason"]], keep if a["reason"] == "copy" else None
    if both == "fix" and (fix := same_fix(it, a, b)):
        return "fixed", why, fix, None, None
    if both == "unsure":
        return "unsure", why, None, None, None
    return "differ", f"one judge: {said_by(a)[:280]} | the other: {said_by(b)[:280]}", None, None, None


def change_words(it, fix):
    was = it["shown"]
    old = {"title": it["title"], "event_date": was.get("day"), "start_time": was.get("start"), "end_at": was.get("end"), "location": was.get("place")}
    said = {"event_date": "day", "start_time": "start", "end_at": "end", "location": "place", "description": "About", "blurb": "line",
            "moved_at": "moved mark", "ends_on": "shows until"}
    return "; ".join(f"{said.get(k, k)} " + ("off" if k == "moved_at" else "rewritten" if k in ("description", "blurb") else
                     f"{old[k]} to {chicago(v) if k == 'end_at' else v}" if old.get(k) else f"to {v or 'none'}")
                     for k, v in fix.items() if k != "place_entry_id")


def keep(out, dry_run=False, db=None):
    folder = out / "feed-judge"
    kept = json.loads((folder / "laid.json").read_text()) if (folder / "laid.json").exists() else {"items": {}, "names": {}}
    laid, names = kept["items"], kept["names"]
    a, b = answers(folder / "a.jsonl", laid), answers(folder / "b.jsonl", laid)
    both = [k for k in laid if k in a and k in b]
    say = {k: decide(laid[k], a[k], b[k], names) for k in both}
    gone = {laid[k]["id"] for k, d in say.items() if d[0] == "taken out"}
    for k, d in say.items():  # two copies each taken out for the other: neither
        if d[4] in gone:
            say[k] = ("differ", f"a copy of one taken out too: {d[1]}", None, None, None)
    acts = [k for k, d in say.items() if d[0] in ("fixed", "taken out")]
    held = len(acts) > max(FEW, MOST * len(both))
    db, n, told = db or (None if dry_run else Supabase()), Counter(), []
    for k in both:
        outcome, why, fix, reason, _ = say[k]
        it = laid[k]
        if held and k in acts:
            n["held"] += 1
            told.append(f"[feed judge]   held, too many at once: {it['title']} ({it['host']}): {outcome}, {why}")
            continue  # not kept, so the next check's judges read it again
        line = f"{change_words(it, fix)}: {why}" if fix else why
        row = {"event_id" if it["kind"] == "Event" else "news_id": it["id"], "title": it["title"], "read_as": it["read_as"],
               "outcome": outcome, "why": line, **({"fix": fix} if fix else {}), **({"reason": reason} if reason else {})}
        if not dry_run:
            try:
                outcome = db.rest("POST", "rpc/feed_judge", {"p_row": row})
            except DbError as e:
                told.append(f"[feed judge]   not saved: {it['title']}: {' '.join(str(e).split())[:200]}")
                continue
        n[outcome] += 1
        if outcome != "fine":
            told.append(f"[feed judge]   {outcome}: {it['title']} ({it['host']}): {line}")
    lines = [f"[feed judge] {len(both)} of {len(laid)} items judged: " + (", ".join(f"{v} {w}" for w, v in n.most_common()) or "none")
             + (f"; {len(laid) - len(both)} wait for the next check" if len(both) < len(laid) else "")
             + (" (dry run: nothing written)" if dry_run else "")] + told
    print("\n".join(lines))
    return lines


def report_lines(db, today):
    """The morning report's: every verdict but the fine ones since the last report, what was done first (morning.py finish)."""
    last = db.rest("GET", f"morning_reports?select=saved_at&day=lt.{today}&order=day.desc&limit=1") or []
    since = last[0]["saved_at"] if last else datetime.combine(today, datetime.min.time(), LOCAL).isoformat()
    rows = db.rest("GET", f"feed_judgments?select=title,outcome,why&judged_at=gt.{quote(since)}&order=judged_at") or []
    if not rows:
        return []
    n = Counter(r["outcome"] for r in rows)
    order = ["taken out", "fixed", "left", "differ", "unsure"]
    return [f"[feed judge] {len(rows)} items judged since the last report: " + ", ".join(f"{n[o]} {o}" for o in ["fine", *order] if n[o])] + [
        f"[feed judge]   {r['outcome']}: {r['title']}: {r['why']}" for o in order for r in rows if r["outcome"] == o]


def selftest():
    import contextlib, io, tempfile
    from morning_run import FakeDb
    failed = []

    def check(ok, what):
        print(("ok    " if ok else "FAIL  ") + what)
        if not ok:
            failed.append(what)
    now = datetime(2026, 11, 25, 22, tzinfo=timezone.utc)
    ev = lambda i, title, **kw: {"id": f"e{i}", "title": title, "event_date": "2026-12-08", "start_time": "6 PM", "end_at": None,
                                 "all_day": False, "location": "Rock Ridge Intermediate, Sartell", "description": "A concert.", "price": None,
                                 "ages": None, "source_name": "Sartell Schools", "source_url": f"https://www.facebook.com/events/{i}", "moved_at": None,
                                 "moved_from": None, "place_entry_id": None, "sport": None, "team_ids": None, "submitted_by": None,
                                 "club_id": None, **kw}
    nw = lambda i, title, **kw: {"id": f"n{i}", "title": title, "blurb": "Deals.", "category": "business", "source_name": "KPower Yoga",
                                 "source_url": f"https://www.instagram.com/p/{i}/", "post_words": "Deals this week", "posted_at": None, "ends_on": None,
                                 "starts_at": None, "created_at": "2026-11-25T12:00:00+00:00", "published_at": "2026-11-25T12:00:00+00:00",
                                 "status": "published", **kw}
    events = [ev(1, "Grade 5 Band"), ev(2, "Sartell Volleyball vs ROCORI", sport="Volleyball"), ev(3, "A neighbour's sale", submitted_by="u"),
              ev(4, "Old Concert", event_date="2026-11-01"), ev(5, "Read before"), ev(6, "Chapel Anniversary", source_url="https://sbm.example/a")]
    news = [nw(1, "Holla for a Dolla"), nw(2, "Black Friday deals"), nw(3, "Gone by", published_at="2026-10-01T12:00:00+00:00", created_at="2026-10-01T12:00:00+00:00")]
    five = read_as(shown("Event", events[4]), [{"by": "Sartell Schools", "link": "x", "words": "Bring a lawn chair"}], None)
    db = FakeDb(answers={
        "event_mentions?select=event_id&last_seen": [{"event_id": e["id"]} for e in events[:5]],
        "event_mentions?select=event_id,source_name": [{"event_id": "e1", "source_name": "Sartell Schools", "source_url": "x", "host_words": "RIS band, 6 to 7 PM", "first_seen": ""},
                                                       {"event_id": "e5", "source_name": "Sartell Schools", "source_url": "x", "host_words": "Bring a lawn chair", "first_seen": ""}],
        "morning_reports?select=report": [{"report": "Morning watch\n[check] Chapel Anniversary (2026-12-08): Starts at 7:30, not 6.\n"}],
        "club_events": lambda m, p, b: ([events[5]] if "title=in." in p else events if "source_name=in." in p else events[:5]),
        "board_items": lambda m, p, b: news, "place_photos": lambda m, p, b: [{"url": "https://x/p.webp", "news_id": "n1"}] if "news_id" in p else [],
        "feed_judgments?select=event_id": [{"event_id": "e5", "read_as": five}], "rpc/feed_judge": lambda m, p, b: b["p_row"]["outcome"]})
    with tempfile.TemporaryDirectory() as tmp:
        out, said = Path(tmp), io.StringIO()
        with contextlib.redirect_stdout(said):
            prepare(out, now, db, grab=lambda url, dest: dest.write_text("x"), page=lambda url: (200, "<p>Chapel Anniversary begins at 7:30 PM</p>"))
        batch = json.loads((out / "feed-judge" / "batch-1.json").read_text())
        by = {i["title"]: i for i in batch}
        check(sorted(by) == ["Black Friday deals", "Chapel Anniversary", "Grade 5 Band", "Holla for a Dolla"]
              and "laid out 4 items in 1 batches" in said.getvalue(),
              f"laid out: new and changed items only; no game, neighbour's, past or already judged one ({sorted(by)})")
        check(by["Chapel Anniversary"].get("a_helper_said") == "Starts at 7:30, not 6." and "7:30" in by["Chapel Anniversary"].get("its_page_says", ""),
              "a [check] line's Event comes with the line and its own page")
        check(by["Grade 5 Band"]["what_was_posted"] == [{"by": "Sartell Schools", "link": "x", "words": "RIS band, 6 to 7 PM"}]
              and len(by["Holla for a Dolla"].get("pictures", [])) == 1
              and any(x.endswith("News: Black Friday deals: Deals.") for x in by["Holla for a Dolla"]["also_live_from_this_host"])
              and any("Read before" in x for x in by["Grade 5 Band"]["also_live_from_this_host"]),
              "each item beside its post's words, its pictures and its host's other live ones")
        laid = json.loads((out / "feed-judge" / "laid.json").read_text())["items"]
        key = {v["title"]: k for k, v in laid.items()}
        place = {"item": key["Grade 5 Band"], "verdict": "fix", "fix": {"place": "Riverview Intermediate School, Sartell", "end": "7 PM"},
                 "quote": "RIS band, 6 to 7 PM", "why": "RIS is Riverview"}
        copy = {"item": key["Holla for a Dolla"], "verdict": "take out", "reason": "copy", "keep": key["Black Friday deals"], "why": "A teaser"}
        fine = lambda t: {"item": key[t], "verdict": "fine"}

        def run(a, b, dry=False):
            for name, rows in (("a", a), ("b", b)):
                (out / "feed-judge" / f"{name}.jsonl").write_text("prose\n" + "\n".join(json.dumps(r) for r in rows))
            db.calls.clear()
            with contextlib.redirect_stdout(io.StringIO()):
                lines = keep(out, dry, db)
            return lines, [b["p_row"] for m, p, b in db.calls if p == "rpc/feed_judge"]
        lines, rows = run([place, copy, fine("Black Friday deals"), fine("Chapel Anniversary")],
                          [{**place, "fix": {"end": "7:00 PM", "place": "Riverview Intermediate School"}}, copy, fine("Black Friday deals"),
                           {"item": key["Chapel Anniversary"], "verdict": "fix", "fix": {"start": "7:30 PM"}, "why": "The page"}])
        got = {r["title"]: r for r in rows}
        check(got["Grade 5 Band"]["outcome"] == "fixed" and got["Grade 5 Band"]["fix"]["location"] == "Riverview Intermediate School, Sartell"
              and got["Grade 5 Band"]["fix"]["end_at"] == "2026-12-08T19:00:00-06:00" and "place_entry_id" in got["Grade 5 Band"]["fix"],
              f"both fix the place and the end alike: written, the fuller place line kept ({got['Grade 5 Band']})")
        check((got["Holla for a Dolla"]["outcome"], got["Holla for a Dolla"]["reason"]) == ("taken out", "other") and got["Holla for a Dolla"]["news_id"] == "n1"
              and got["Black Friday deals"]["outcome"] == "fine", "both name the same copy to keep: taken out, the copy kept")
        check(got["Chapel Anniversary"]["outcome"] == "differ" and "fix" not in got["Chapel Anniversary"]
              and any("differ: Chapel Anniversary" in x and "start to '7:30 PM'" in x for x in lines), "where they differ nothing is written, and the line says both")
        out_of = lambda j, **kw: {**copy, **kw}
        lines, rows = run([copy, {**copy, "item": key["Black Friday deals"], "keep": key["Holla for a Dolla"]}],
                          [copy, {**copy, "item": key["Black Friday deals"], "keep": key["Holla for a Dolla"]}])
        check([r["outcome"] for r in rows] == ["differ", "differ"] and "2 wait for the next check" in lines[0],
              "two copies taken out for each other: neither goes; an item one judge left out waits")
        lines, rows = run([copy], [out_of(copy, keep="o999")])
        check(rows[0]["outcome"] == "differ", "two copies named: differ")
        lines, rows = run([copy], [copy], dry=True)
        check(not rows and "dry run" in lines[0], "a dry run writes nothing")
        # A judge gone wrong: five of five changed is held, and read again next time.
        global FEW
        few, FEW = FEW, 1
        lines, rows = run([place, copy], [place, copy])
        FEW = few
        check(not rows and sum("held, too many at once" in x for x in lines) == 2, "too many at once: held, none written")
    it = {"id": "e1", "kind": "Event", "host": "SJU", "title": "Weckström MIAC Goalie of Week", "said": "named the MIAC Defensive Player of the Week. He stopped 54 of 55 shots",
          "shown": {"day": "2027-04-06", "start": "6 PM", "end": "Tue 2027-04-06 7:30 PM", "title": "x"}}
    f = lambda q="MIAC Defensive Player of the Week", **kw: {"fix": kw, "quote": q}
    check(same_fix({**it, "kind": "News"}, f(title="Weckström: Defensive Player"), f(q="named the MIAC Defensive Player of the Week", title="Weckström: MIAC Defensive Player"))
          == {"title": "Weckström: Defensive Player"}, "a title in other words, the same words quoted: the first's")
    check(same_fix(it, f(title="Weckström Player"), f(q="He stopped 54 of 55 shots", title="Weckström saves")) is None, "other words quoted: not the same")
    check(same_fix(it, f(about="He stopped 99 shots."), f(about="He stopped 54.")) is None, "a number nothing gave is never written")
    check(same_fix({**it, "kind": "News"}, *[f(title="Weckström MIAC Defensive Player of Week")] * 2) is None, "a title too long for its card is never written")
    check(same_fix(it, f(start="5 PM", end="6:30 PM"), f(end="2027-04-06 6:30 PM", start="5:00 pm"))
          == {"start_time": "5 PM", "end_at": "2027-04-06T18:30:00-05:00"}, "Kindergarten Signing Day: the clock after March, in summer's offset")
    check(same_fix(it, f(day="2027-04-07"), f(day="2027-04-07")) == {"event_date": "2027-04-07", "end_at": "2027-04-07T19:30:00-05:00"}, "another day keeps its hours")
    check(changes(it["shown"], "Event", {"start": "9 PM", "end": "1 AM"})["end_at"] == "2027-04-07T01:00:00-05:00", "an end past midnight is the next day")
    check(same_fix(it, f(moved="no"), f(moved="no")) == {"moved_at": None} and changes(it["shown"], "Event", {"colour": "red"}) is None
          and changes(it["shown"], "Event", {"start": "noonish"}) is None, "a moved mark comes off; a field or a time it can't read is no fix")
    db = FakeDb(answers={"morning_reports": [{"saved_at": "2026-11-25T12:00:00+00:00"}], "feed_judgments": [
        {"title": "A", "outcome": "fine", "why": None}, {"title": "B", "outcome": "unsure", "why": "two places"}, {"title": "C", "outcome": "fixed", "why": "start 6 PM to 5 PM: the post"}]})
    check(report_lines(db, date(2026, 11, 26)) == ["[feed judge] 3 items judged since the last report: 1 fine, 1 fixed, 1 unsure",
                                                   "[feed judge]   fixed: C: start 6 PM to 5 PM: the post", "[feed judge]   unsure: B: two places"],
          "the report names each fix and take-out first, then what is for Jesse")
    print(f"{len(failed)} failed" if failed else "all passed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", nargs="?", choices=["prepare", "keep"])
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    out = find_root() / ".runs" / "morning"
    if a.step == "prepare":
        prepare(out)
    elif a.step == "keep":
        keep(out, a.dry_run)
    else:
        ap.error("prepare or keep")


if __name__ == "__main__":
    main()
