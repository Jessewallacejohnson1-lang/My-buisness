#!/usr/bin/env python3
"""
event_photos.py: every new Event that isn't a game gets a photo of its own (BP app docs/plans/event-photos
09; Jesse, 2026-10-30: "for each event when the event is found or when you bring it to me they should all
have a photo of event. dont worry about games for now"). A step of the morning job and of the social watch
(sources/models/morning.md, social.md):

  python3 sources/scripts/event_photos.py prepare          new Events not yet looked at: their pictures on sheets
  python3 sources/scripts/event_photos.py keep [--dry-run] the helpers' picks saved as each Event's photo
  python3 sources/scripts/event_photos.py --selftest

The pictures are the ones each Event came with, so nothing paid starts and no new page is read but its own:
- a Facebook or Instagram post: its own pictures, full size, from the social watch's Apify runs of the last
  LOOKBACK days, read again (reading a finished run is free); with them, up to PLACE_MORE photos from the
  same page's other posts, for an Event whose own post is only a flyer; a post that shares a link to a story
  also offers that story's share picture (og:image), since Facebook hands over only a 139 px preview of it
- a CSB SJU campus listing: its banner picture, one call to the campus calendar for every listing
- any other page: its share picture (og:image), read politely
Each is downloaded once, at least MIN_WIDTH wide, and drawn numbered on .runs/morning/photos/sheet-N.png; a
helper on the cheap model picks one per Event by sources/models/event-photo.md: a real photo, else the Event's own
flyer from its own post or page (Jesse, 2026-11-02: Pizza night's flyer over the bakery's pastry photo), or none.
`keep` saves each pick the one way every picture is saved (place_photos.save_picture): to the places bucket as a
place_photos row of kind 'event' for that Event ('flyer' for a flyer, which the card shows only when no scene fits)
(one row per Event when one post names several), credited to its place (a post) or its site (a page). It marks
every Event laid out as looked at (club_events.photo_checked_at), found or not, so none is looked at twice. A game,
a meet or any sport has no photo of its own for now (place_photos.is_sport, the skill's review page's rule too), and a
sport's card shows the scene pool (event-photos 07).

A News found in a Facebook or Instagram post gets the same look (BP app town-feed 53; Jesse, 2026-11-08: "yes" to News
showing its post's own photo): its own post's pictures only, never its place's other posts, down to NEWS_MIN_WIDTH, a
real photo first, else its own flyer (Jesse, 2026-11-08: "never a flyer" allow). `keep` saves the pick as a place_photos row of kind 'news' tied to the News, and marks every
News laid out as looked at (board_items.photo_checked_at).

Before any of that, a photo a person kept for an Event's title at its place (a publish sheet Jesse said yes to, not this
step's own pick, and a photo, not a flyer) follows to that title's new dates: a show or class listed one day at a time gets its kept photo, not
whatever its listing came with (BP app docs/plans/dig-deeper 20; Reflection and Bréagán, 2026-11-04 to 07). Those
Events are not laid out; `keep` gives each a row of the same picture and marks it looked at.
"""
import argparse, json, re, sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import quote, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, place_key  # noqa: E402
import social, write_judged  # noqa: E402
from read_events import LOCAL  # noqa: E402
from run import Supabase, fetch  # noqa: E402
from morning_run import Part  # noqa: E402
from db import DbError  # noqa: E402
from morning import read_items  # noqa: E402
from towns import TOWNS, DEFAULT, lookup  # noqa: E402

LOOKBACK = timedelta(days=8)   # the weekly read is Thursday's: a Friday morning still finds its posts
NEW = timedelta(days=3)        # an Event found longer ago than this was there before this step
PLACE_MORE = 6                 # the same page's other photos offered beside a post's own pictures
MIN_WIDTH = 1000               # as scenes.py: the card is width-bound and asks for 1200 px
# A News's own picture: Jesse took JoeTown's 720 px group shot of its new merch over the post's sharp portrait
# ("the other ones get attention of users more", 2026-11-08, town-feed 53).
NEWS_MIN_WIDTH = 720
PER_SHEET = 4                  # Events on one sheet, so a helper sees each picture big enough
TILE = 300
TOWN = TOWNS[DEFAULT]["photo_slug"]  # the photo store's folder and place_photos.town; --town sets it
CAMPUS_API = "https://my.csbsju.edu/api/v2/events/unauthenticated/"
CAMPUS_PAGE = re.compile(r"my\.csbsju\.edu/public/events/(\d+)")
POST = re.compile(r"(?:facebook|instagram)\.com/")
OWN = "event photos"           # place_photos.proposed_by on this step's own picks; any other live row a person kept
FOLLOW = "its title's kept photo"  # proposed_by on a copy: only the row a person kept follows, so taking it down ends it
FOLLOWED = ("town", "url", "source_url", "kind", "width", "height", "credit", "description", "whole")


def out_dir():
    return find_root() / ".runs" / "morning"


def todo(db, now):
    """Approved Events found in the last NEW, still to come, never looked at, that aren't a sport."""
    today, since = now.astimezone(LOCAL).date(), (now - NEW).isoformat()
    rows = db.rest("GET", "club_events?select=id,title,event_date,location,description,category,sport,team_ids,"
                          "source_name,source_url,place_entry_id"
                          f"&status=eq.approved&kind=eq.event&photo_checked_at=is.null&created_at=gte.{quote(since)}"
                          f"&or={quote(f'(event_date.gte.{today},end_at.gte.{today})')}&order=created_at&limit=300")
    import place_photos
    return [r for r in rows if not place_photos.is_sport(r)]


def todo_news(db, now):
    """Published News found in a Facebook or Instagram post within LOOKBACK (the runs that can still be read again for
    free), never looked at (town-feed 53)."""
    since = (now - LOOKBACK).isoformat()
    return db.rest("GET", "board_items?select=id,title,blurb,source_name,source_url,place_entry_id"
                          f"&status=eq.published&photo_checked_at=is.null&created_at=gte.{quote(since)}"
                          f"&source_url=match.{quote('(facebook|instagram)[.]com/')}&order=created_at&limit=300")


def news_groups(news):
    """One block per News, keyed n1, n2… beside the Events' e1, e2…"""
    return [{"source_url": n["source_url"], "title": n["title"], "news": n, "events": [], "key": f"n{i}"}
            for i, n in enumerate(news, 1)]


def in_list(values):
    """A PostgREST in.() filter's value, each quoted, so commas, quotes and brackets in a title stay inside it."""
    return quote("(" + ",".join('"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"' for v in sorted(values)) + ")")


def kept_photos(db, events):
    """{Event id: the live photo a person kept for another Event of its title at its place}, the newest one when there
    are several. Only a photo follows: a flyer's words name one date, and nothing reads them here. This step's own
    picks don't follow (their Event's listing picked them), nor do earlier copies (so a photo taken down stops
    following), nor to an Event with no place. Both reads are bounded by the morning's places, not by a title's
    history: a weekly Event adds a date every week."""
    keys = {(e["title"], e["place_entry_id"]) for e in events if e.get("place_entry_id")}
    if not keys:
        return {}
    places = in_list({p for _, p in keys})
    same = {o["id"]: (o["title"], o["place_entry_id"])
            for o in db.rest("GET", f"club_events?select=id,title,place_entry_id&title=in.{in_list({t for t, _ in keys})}"
                                    f"&place_entry_id=in.{places}")
            if (o["title"], o["place_entry_id"]) in keys}
    if not same:
        return {}
    best = {}
    for r in db.rest("GET", f"place_photos?select=id,event_id,proposed_by,{','.join(FOLLOWED)}&status=eq.live&kind=eq.event"
                            f"&entry_id=in.{places}&event_id=not.is.null&order=id.desc"):
        k = same.get(r["event_id"])
        if k and r.get("proposed_by") not in (OWN, FOLLOW) and (k not in best or r["id"] > best[k]["id"]):
            best[k] = r
    return {e["id"]: best[(e["title"], e.get("place_entry_id"))] for e in events if (e["title"], e.get("place_entry_id")) in best}


def post_key(url):
    """One post however its address is written: a Facebook post's id, an Instagram code, an Event's number."""
    m = re.search(r"pfbid\w+|/posts/(\d+)|/p/([\w-]+)|/reel/([\w-]+)|/events/(\d+)", url or "")
    return next((g for g in m.groups() if g), m.group(0)) if m else None


def full_size(url):
    """A Facebook picture as uploaded: its address names the 590 px copy (ctp=s590x590) beside the original's
    size (cstp=mx1536x2048), and asks for the original without it (Oct 30: 443 px became 1536)."""
    return re.sub(r"[?&]ctp=[^&]*", "", url) if "fbcdn" in url else url


def owner(row):
    return (row.get("ownerUsername") or row.get("pageName") or (row.get("user") or {}).get("name")
            or row.get("facebookUrl") or "").lower()


def kind_of(row):
    return "instagram" if row.get("_task", "").endswith("instagram") or row.get("shortCode") else "facebook"


def pictures(row):
    """A row's pictures as [{url, about}]: a post's (social.picture_urls, full size), an Events tab's cover."""
    if row.get("imageUrl") and not row.get("media"):
        return [{"url": row["imageUrl"], "about": row.get("imageCaption") or ""}]
    return [{**p, "url": full_size(p["url"])} for p in social.picture_urls(kind_of(row), row)]


def social_rows(now):
    """Every post and Events-tab row of the social watch's runs that finished within LOOKBACK, newest first."""
    tasks = {n: t for n, t in social.by_name("/actor-tasks").items() if re.match(r"bp-(busy|weekly)-", n)}
    rows = []
    for name, t in sorted(tasks.items()):
        runs = social.api("GET", f"/actor-tasks/{t['id']}/runs?desc=true&limit=20")["data"]["items"]
        for r in runs:
            done = r.get("finishedAt") and datetime.fromisoformat(r["finishedAt"].replace("Z", "+00:00"))
            if done and now - done < LOOKBACK and r.get("status") == "SUCCEEDED":
                rows += [{"_task": name, "_at": r["finishedAt"], **x} for x in social.items(r["defaultDatasetId"])
                         if not x.get("error")]
    return sorted(rows, key=posted, reverse=True)


def posted(row):
    """When a row was posted, as text that sorts: Facebook gives seconds, Instagram an ISO time."""
    t = row.get("timestamp") or row.get("time") or row.get("_at") or ""
    return datetime.fromtimestamp(t, timezone.utc).isoformat() if isinstance(t, (int, float)) else str(t)


def from_posts(group, rows, share=None, more=PLACE_MORE):
    """A post's own pictures, then its page's other photos: [{url, about, from, page}]. An Event a post links
    to (facebook.com/events/<n>) takes that post's pictures, or the Events tab's cover. A post that shares a
    link to a story (CSB's post on Emily Sheehan's show, 2026-11-03) comes with Facebook's 139 px preview only:
    the story's own share picture goes first. A link that names no post (a page, a video) has none: every row
    without a post id would match it, whoever posted it."""
    key = post_key(group["source_url"])
    if not key:
        return []
    own = [r for r in rows if post_key(r.get("url") or r.get("topLevelUrl")) == key]
    if not own and "/events/" in group["source_url"]:
        own = [r for r in rows if key in json.dumps(r.get("text") or r.get("caption") or "")
               or key in json.dumps(r.get("textReferences") or [])]
    if not own:
        return []
    page = own[0].get("url") or group["source_url"]
    link = own[0].get("link") or ""
    story = (share or share_picture)(link) if link.startswith("http") and not POST.search(link) else None
    out = ([{"url": story, "about": "", "from": "page", "page": link}] if story else []) \
        + [{**p, "from": "post", "page": page} for p in pictures(own[0])]
    mine = len(out)
    seen = {post_key(r.get("url")) for r in own}
    for r in rows:
        if len(out) >= mine + more:
            break
        if owner(r) == owner(own[0]) and post_key(r.get("url")) not in seen:
            seen.add(post_key(r.get("url")))
            out += [{**p, "from": "other post", "page": r.get("url") or page} for p in pictures(r)[:2]]
    return out[:mine + more]


def campus_banners(groups, get=fetch):
    """{listing id: banner picture} for the campus listings among the groups, in one call."""
    ids = {m.group(1) for g in groups for m in [CAMPUS_PAGE.search(g["source_url"] or "")] if m}
    if not ids:
        return {}
    days = sorted(e["event_date"] for g in groups for e in g["events"] if CAMPUS_PAGE.search(g["source_url"] or ""))
    after = datetime.combine(date.fromisoformat(days[0]), datetime.min.time(), LOCAL).astimezone(timezone.utc)
    before = datetime.combine(date.fromisoformat(days[-1]) + timedelta(days=1), datetime.min.time(), LOCAL).astimezone(timezone.utc)
    _, raw = get(f"{CAMPUS_API}?in_range_after={after:%Y-%m-%dT%H:%M:%SZ}&in_range_before={before:%Y-%m-%dT%H:%M:%SZ}"
                 "&field=id&field=effective_banner_picture_url&paginate=false&published=true")
    rows = json.loads(raw)
    rows = rows.get("results", rows) if isinstance(rows, dict) else rows
    return {str(r["id"]): r["effective_banner_picture_url"] for r in rows
            if str(r.get("id")) in ids and r.get("effective_banner_picture_url")}


def share_picture(url, get=fetch):
    """A page's share picture (og:image), read politely; None when it has none or won't answer."""
    import place_photos
    try:
        _, raw = get(url)
    except Exception:
        return None
    return next((v for k, v in place_photos.metas(raw) if k in place_photos.SHARE_KEYS), None)


def groups_of(events):
    """One block per post or page and title: three dates of one yoga class share their post's pictures."""
    out = {}
    for e in events:
        out.setdefault((e.get("source_url") or "", e["title"]), {"source_url": e.get("source_url") or "",
                                                                 "title": e["title"], "events": []})["events"].append(e)
    return list(out.values())


def candidates(groups, rows, banners, share=share_picture):
    for g in groups:
        src = g["source_url"]
        if POST.search(src):
            # A News takes only its own post's pictures (Jesse, 2026-11-08).
            g["cands"] = from_posts(g, rows, share, more=0 if g.get("news") else PLACE_MORE)
        elif CAMPUS_PAGE.search(src):
            pic = banners.get(CAMPUS_PAGE.search(src).group(1))
            g["cands"] = [{"url": pic, "about": "", "from": "listing", "page": src}] if pic else []
        elif src.startswith("http"):
            pic = share(src)
            g["cands"] = [{"url": pic, "about": "", "from": "page", "page": src}] if pic else []
        else:
            g["cands"] = []
    return groups


def download(groups, folder, grab=None):
    """Each candidate to folder/c<n>.jpg; one under MIN_WIDTH, a repeat of another, or one that won't
    download is dropped. Returns the failures as lines."""
    import place_photos
    from PIL import Image
    grab = grab or (lambda c, dest: social.fetch_picture(c["url"], dest) if POST.search(c["page"])
                    else place_photos.download(c["url"], dest))
    folder.mkdir(parents=True, exist_ok=True)
    n, failed = 0, []
    for g in groups:
        kept, hashes = [], []
        for c in g["cands"]:
            n += 1
            dest = folder / f"c{n}.{'jpg' if POST.search(c['page']) else 'png'}"  # a page's may be see-through
            try:
                w, h = grab(c, dest)
            except Exception as e:
                failed.append(f"{g['title']}: c{n} would not download ({str(e)[:80]})")
                continue
            if w < (NEWS_MIN_WIDTH if g.get("news") else MIN_WIDTH):
                continue
            hsh = place_photos.dhash(Image.open(dest))
            if any(place_photos.same_picture(hsh, x) for x in hashes):
                continue
            hashes.append(hsh)
            kept.append({**c, "n": n, "file": str(dest), "w": w, "h": h})
        g["cands"] = kept
    return failed


def sheets(groups, folder):
    """One sheet per PER_SHEET groups with pictures: each Event's block, its pictures numbered, and a batch file
    naming the sheet and every picture's source for the helper."""
    import place_photos
    from PIL import Image, ImageDraw
    shown = [g for g in groups if g["cands"]]
    for i in range(0, len(shown), PER_SHEET):
        part, k = shown[i:i + PER_SHEET], i // PER_SHEET + 1
        cols = max(len(g["cands"]) for g in part)
        sheet = Image.new("RGB", (cols * TILE + 20, len(part) * (TILE + 80) + 10), "white")
        d, big, small = ImageDraw.Draw(sheet), place_photos.font(22), place_photos.font(16)
        lines = [f"Sheet: {folder / f'sheet-{k}.png'}", ""]
        for row, g in enumerate(part):
            y, e = row * (TILE + 80) + 10, g.get("news") or g["events"][0]
            if g.get("news"):
                head = f"{g['key']}  News: {g['title']} · {e.get('source_name') or ''}"
                about = {"news": True, "host": e.get("source_name") or "", "about": " ".join((e.get("blurb") or "").split())[:240]}
            else:
                head = f"{g['key']}  {g['title']} · {e['event_date']} · {e.get('location') or e.get('source_name') or ''}"
                about = {"host": e.get("source_name") or "", "place": e.get("location") or "", "date": e["event_date"],
                         "about": " ".join((e.get("description") or "").split())[:240]}
            place_photos.label(d, (10, y), head, big, cols * TILE)
            lines.append(json.dumps({"event": g["key"], "title": g["title"], **about,
                                     "pictures": [{"pick": f"c{c['n']}", "from": c["from"], "meta_says": c["about"][:160]}
                                                  for c in g["cands"]]}, ensure_ascii=False))
            for col, c in enumerate(g["cands"]):
                im = Image.open(c["file"])
                im.thumbnail((TILE - 10, TILE - 10))
                x = col * TILE + 10
                sheet.paste(im, (x, y + 32))
                place_photos.label(d, (x, y + TILE + 26), f"c{c['n']} · {c['from']} · {c['w']}×{c['h']}", small, TILE - 12)
        sheet.save(folder / f"sheet-{k}.png")
        (folder / f"batch-{k}.txt").write_text("\n".join(lines) + "\n")
    return (len(shown) + PER_SHEET - 1) // PER_SHEET


def prepare(out, now=None, db=None, rows=None, banners=None, share=share_picture, grab=None):
    now = now or datetime.now(timezone.utc)
    folder = out / "photos"
    if folder.exists():
        for f in folder.iterdir():
            f.unlink()
    db = db or Supabase()
    events = todo(db, now)
    try:
        kept = kept_photos(db, events)
    except DbError as x:  # following is a shortcut: without it every Event is laid out as before
        print(f"[photos] kept photos not read, every new Event laid out: {x}")
        kept = {}
    follow =[{"event": e, "row": kept[e["id"]]} for e in events if e["id"] in kept]
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "follow.json").write_text(json.dumps(follow, indent=1, ensure_ascii=False))
    if follow:
        print(f"[photos] {len(follow)} new Events take the photo kept for their title: "
              + "; ".join(sorted({f['event']['title'] for f in follow})))
    events = [e for e in events if e["id"] not in kept]
    groups = groups_of(events)
    for i, g in enumerate(groups, 1):
        g["key"] = f"e{i}"
    try:
        news = news_groups(todo_news(db, now))
    except DbError as x:  # the News are an addition: without them every Event is still laid out
        print(f"[photos] new News not read, Events only: {x}")
        news = []
    groups += news
    if rows is None:
        rows = social_rows(now) if any(POST.search(g["source_url"]) for g in groups) else []
    candidates(groups, rows, campus_banners(groups) if banners is None else banners, share)
    failed = download(groups, folder, grab)
    n = sheets(groups, folder)
    (folder / "events.json").write_text(json.dumps(groups, indent=1, ensure_ascii=False))
    with_pics = sum(1 for g in groups if g["cands"] and not g.get("news"))
    news_pics = sum(1 for g in news if g["cands"])
    print(f"[photos] {len(events)} new Events to look at ({len(groups) - len(news)} posts or pages): {with_pics} with pictures, "
          f"{len(groups) - len(news) - with_pics} with none; {len(news)} new News from posts, {news_pics} with pictures; "
          f"{n} sheets ({folder})")
    for ln in failed:
        print(f"[photos]   {ln}")
    return groups


def plan(lines, groups):
    """The helpers' lines as picks: {group key: (candidate, what it shows, a flyer?)}, only a group laid out and one
    of its own pictures, each group once. A flyer from another post of the place counts too, when its words still
    hold for the Event (`sources/models/event-photo.md`, Jesse, 2026-11-05). A News takes its own post's flyer too
    (Jesse, 2026-11-08)."""
    by, picks = {g["key"]: g for g in groups}, {}
    for ln in lines:
        if not isinstance(ln, dict) or ln.get("event") not in by or ln["event"] in picks:
            continue
        c = next((c for c in by[ln["event"]]["cands"] if f"c{c['n']}" == str(ln.get("pick") or "").strip()), None)
        if c:
            picks[ln["event"]] = (c, " ".join(str(ln.get("shows") or "").split())[:80] or None, bool(ln.get("flyer")))
    return picks


def entry_of(e):
    """Where an Event's photo is filed: its place, else its host's registry entry."""
    if e.get("place_entry_id"):
        return e["place_entry_id"]
    ids = write_judged.names().get(place_key(e.get("source_name") or ""), [])
    return ids[0] if ids else "unplaced"


def keep(out, dry_run=False, db=None, now=None):
    import place_photos
    from PIL import Image
    folder = out / "photos"
    groups = json.loads((folder / "events.json").read_text()) if (folder / "events.json").exists() else []
    picks = plan(read_items(out / "event_photos.jsonl"), groups)
    follow = json.loads((folder / "follow.json").read_text()) if (folder / "follow.json").exists() else []
    db = db or (None if dry_run else Supabase())
    stamp = (now or datetime.now(timezone.utc)).isoformat()
    by_key = {g["key"]: g for g in groups}
    followed = {f["event"]["id"]: f for f in follow}

    def save_one(key):
        kind, what = key.split(":", 1)
        if kind == "looked":
            return db.rest("PATCH", f"club_events?id=eq.{what}", {"photo_checked_at": stamp}, prefer="return=minimal")
        if kind == "seen":
            return db.rest("PATCH", f"board_items?id=eq.{what}", {"photo_checked_at": stamp}, prefer="return=minimal")
        try:
            if kind == "follow":
                e, r = followed[what]["event"], followed[what]["row"]
                return db.rest("POST", "place_photos", [{**{k: r[k] for k in FOLLOWED if r.get(k) is not None},
                                                         "entry_id": e["place_entry_id"], "event_id": e["id"], "status": "live",
                                                         "proposed_by": FOLLOW}],
                               "return=minimal")
            g, (c, shows, flyer) = by_key[what], picks[what]
            if g.get("news"):
                n = g["news"]
                return place_photos.save_picture(db, Image.open(c["file"]), "news", c["page"], town=TOWN,
                                                 events=[(n["id"], entry_of(n))], description=shows,
                                                 credit=n.get("source_name") if POST.search(c["page"]) else None,
                                                 proposed_by=OWN)
            place_photos.save_picture(db, Image.open(c["file"]), "flyer" if flyer else "event", c["page"], town=TOWN,
                                      events=[(e["id"], entry_of(e)) for e in g["events"]], description=shows,
                                      credit=g["events"][0].get("source_name") if POST.search(c["page"]) else None,
                                      proposed_by=OWN)
        except DbError as e:
            if e.status != 409:  # the database's one live photo an Event has: an earlier run's save that got through
                raise
    if not dry_run:
        # Each write its own key, so lines that come late are still saved and a stop leaves only what wasn't sent.
        # prepare clears the file.
        Part(folder / "kept.json").each([k for f in follow for k in (f"follow:{f['event']['id']}", f"looked:{f['event']['id']}")]
                                        + [k for g in groups for k in ([f"photo:{g['key']}"] if g["key"] in picks else [])
                                           + [f"looked:{e['id']}" for e in g["events"]]
                                           + ([f"seen:{g['news']['id']}"] if g.get("news") else [])], save_one)
    kept = [g for g in groups if g["key"] in picks]
    events = sum(len(g["events"]) for g in groups)
    got = sum(len(g["events"]) for g in kept)
    own = sum(len(g["events"]) for g in kept if picks[g["key"]][0]["from"] != "other post")
    flyers = sum(len(g["events"]) for g in kept if picks[g["key"]][2])
    none = [g["title"] for g in groups if g["key"] not in picks and not g.get("news")]
    news = [g for g in groups if g.get("news")]
    line = (f"[photos] {got + len(follow)} of {events + len(follow)} new Events got a photo of their own ("
            + (f"{len(follow)} the one kept for their title, " if follow else "") + f"{own} from their own post or page, "
            f"{got - own} from their place's other posts; {flyers} of them their own flyer)" + (f"; none for {len(none)}: " + "; ".join(none[:20])
                                                               if none else "")
            + (f"; {sum(1 for g in news if g['key'] in picks)} of {len(news)} new News from posts got their post's photo"
               if news else "")
            + (" (dry run: nothing written)" if dry_run else ""))
    print(line)
    return line


# --- Self-test --------------------------------------------------------------------------------------

def selftest():
    import tempfile
    from PIL import Image
    ok, bad = 0, 0

    def check(cond, what):
        nonlocal ok, bad
        ok, bad = ok + bool(cond), bad + (not cond)
        print(("  ok   " if cond else "  FAIL ") + what)

    check(full_size("https://scontent.xx.fbcdn.net/v/a.png?stp=dst-jpg&cstp=mx1536x2048&ctp=s590x590&oh=1")
          == "https://scontent.xx.fbcdn.net/v/a.png?stp=dst-jpg&cstp=mx1536x2048&oh=1", "a Facebook picture asked for full size")
    check(post_key("https://www.facebook.com/SJUJohnnies/posts/pfbid0LVC?x=1") == "pfbid0LVC"
          and post_key("https://www.instagram.com/p/DfFG3nHkVH3/") == "DfFG3nHkVH3"
          and post_key("https://www.facebook.com/events/2380009089072052") == "2380009089072052", "one post however it's written")
    listed = [{"title": "Boys Swim vs Brainerd · JV", "category": "watch_sports"},
              {"title": "The Little Mermaid", "category": "art_theater", "source_url": "https://gobound.com/direct/x"}]
    seen = type("Db", (), {"rest": lambda self, *a, **k: listed})()
    check([r["title"] for r in todo(seen, datetime(2026, 11, 3, tzinfo=timezone.utc))] == ["The Little Mermaid"],
          "a meet is left out, a school's play is looked at (place_photos.is_sport)")

    post = lambda url, owner_, pics, **more: {"_task": "bp-busy-facebook", "url": url, "pageName": owner_,
                                              "media": [{"__typename": "Photo", "image": {"uri": u}, "photo_image": {"uri": u},
                                                         "ocrText": about} for u, about in pics], **more}
    rows = [post("https://www.facebook.com/prep/posts/pfbidPLAY", "Prep", [("https://x.fbcdn.net/flyer.jpg?ctp=s590x590", "May be an image of text")]),
            post("https://www.facebook.com/prep/posts/pfbidCAST", "Prep", [("https://x.fbcdn.net/cast.jpg", "May be an image of 6 people"),
                                                                           ("https://x.fbcdn.net/menu.jpg", "May be an image of text that says MENU")]),
            post("https://www.facebook.com/shop/posts/pfbidSHOP", "Shop", [("https://x.fbcdn.net/shop.jpg", "")]),
            post("https://www.facebook.com/rescue/posts/pfbidLINK", "Rescue", [("https://x.fbcdn.net/tattoo.jpg", "")],
                 text="Join us! https://www.facebook.com/events/2380009089072052")]
    g = {"source_url": "https://www.facebook.com/prep/posts/pfbidPLAY", "title": "Fall Play", "events": []}
    got = from_posts(g, rows)
    check([(c["url"], c["from"]) for c in got] == [("https://x.fbcdn.net/flyer.jpg", "post"), ("https://x.fbcdn.net/cast.jpg", "other post"),
                                                    ("https://x.fbcdn.net/menu.jpg", "other post")],
          "its post's flyer, full size, then the same page's photos and flyers, never another page's")
    check([c["url"] for c in from_posts({"source_url": "https://www.facebook.com/events/2380009089072052", "events": []}, rows)]
          == ["https://x.fbcdn.net/tattoo.jpg"], "an Event a post links to takes that post's pictures")
    check(from_posts({"source_url": "https://www.facebook.com/x/posts/pfbidGONE", "events": []}, rows) == [], "a post not read: none")
    check(from_posts({"source_url": "https://www.facebook.com/x/videos/123/", "events": []}, rows + [post("https://www.facebook.com/y/videos/9/", "Y", [("https://x.fbcdn.net/y.jpg", "")])]) == [],
          "a link that names no post takes none, not another place's post that names none either")
    shared = [post("https://www.facebook.com/csbsju/posts/pfbidART", "csbsju", [("https://external.fbcdn.net/emg1/preview.jpg", "")],
                   link="https://www.csbsju.edu/news/alum-drawings/")]
    check([(c["url"], c["from"], c["page"]) for c in from_posts({"source_url": "https://www.facebook.com/csbsju/posts/pfbidART",
                                                                  "events": []}, shared, share=lambda u: "https://www.csbsju.edu/art.jpg")][0]
          == ("https://www.csbsju.edu/art.jpg", "page", "https://www.csbsju.edu/news/alum-drawings/"),
          "a post that shares a story takes the story's share picture first")
    check([c["url"] for c in from_posts(g, rows, share=lambda u: 1 / 0)][0] == "https://x.fbcdn.net/flyer.jpg",
          "a post with no link reads no other page")
    check(sorted([{"timestamp": 1761800000}, {"timestamp": "2026-10-31T01:00:00.000Z"}], key=posted, reverse=True)[0]
          == {"timestamp": "2026-10-31T01:00:00.000Z"}, "Facebook's seconds and Instagram's times sort together")

    events = [{"id": f"id{i}", "title": t, "event_date": "2026-11-05", "source_url": u, "source_name": "Prep"}
              for i, (t, u) in enumerate([("Yoga", "https://www.facebook.com/prep/posts/pfbidPLAY"),
                                          ("Yoga", "https://www.facebook.com/prep/posts/pfbidPLAY"),
                                          ("Reflection", "https://my.csbsju.edu/public/events/4758895"),
                                          ("Give to the Max", "https://www.givemn.org/organization/Grey-Face-Rescue")])]
    gs = groups_of(events)
    check([len(x["events"]) for x in gs] == [2, 1, 1], "three dates of one class share one block")
    for i, x in enumerate(gs, 1):
        x["key"] = f"e{i}"
    candidates(gs, rows, {"4758895": "https://storage.googleapis.com/art.jpg"}, share=lambda u: "https://givemn.org/og.jpg")
    check([c["from"] for c in gs[1]["cands"]] == ["listing"] and gs[2]["cands"][0]["url"] == "https://givemn.org/og.jpg",
          "a campus listing's banner, a page's share picture")

    with tempfile.TemporaryDirectory() as tmp:
        folder, out = Path(tmp) / "sheets", Path(tmp) / "out"
        folder.mkdir()
        sizes = {"flyer": (1536, 2048), "cast": (1206, 1608), "menu": (1080, 1350), "art": (4568, 3000), "og": (500, 500)}

        def grab(c, dest):
            name = next(k for k in sizes if k in c["url"])
            Image.effect_noise(sizes[name], 60 + 10 * list(sizes).index(name)).convert("RGB").save(dest)
            return sizes[name]
        failed = download(gs, folder, grab)
        check(not failed and [c["n"] for c in gs[0]["cands"]] == [1, 2, 3] and gs[2]["cands"] == [],
              f"each picture downloaded once and numbered; one under {MIN_WIDTH} px dropped")
        check(sheets(gs, folder) == 1 and (folder / "sheet-1.png").exists(), "one sheet for three blocks")
        batch = (folder / "batch-1.txt").read_text()
        check('"pick": "c2", "from": "other post"' in batch and '"event": "e3"' not in batch, "the batch names each picture and its source; a block with none isn't shown")

        picks = plan([{"event": "e1", "pick": "c2", "shows": "The cast on stage"}, {"event": "e1", "pick": "c1"},
                      {"event": "e2", "pick": "c9"}, {"event": "e9", "pick": "c1"}, "unreadable line: x"], gs)
        check(list(picks) == ["e1"] and picks["e1"][0]["n"] == 2 and picks["e1"][1:] == ("The cast on stage", False),
              "only a block laid out, once, and only one of its own pictures")
        own, other = (next(f"c{c['n']}" for c in gs[0]["cands"] if c["from"] == w) for w in ("post", "other post"))
        flyers = plan([{"event": "e1", "pick": own, "flyer": True}], gs), plan([{"event": "e1", "pick": other, "flyer": True}], gs)
        check(flyers[0]["e1"][2] is True and flyers[1]["e1"][2] is True,
              "a flyer from the Event's own post, or from another post of the place (Jesse, 2026-11-03)")

        (folder / "events.json").write_text(json.dumps(gs))
        (out / "photos").mkdir(parents=True)
        for f in folder.iterdir():
            (out / "photos" / f.name).write_bytes(f.read_bytes())
        (out / "photos" / "events.json").write_text(json.dumps(gs).replace(str(folder), str(out / "photos")))
        (out / "event_photos.jsonl").write_text('{"event": "e1", "pick": "c2", "shows": "The cast on stage"}\n')

        import place_photos
        fake = place_photos.Unsent("https://db.example")
        line = keep(out, db=fake, now=datetime(2026, 10, 31, 11, tzinfo=timezone.utc))
        put = [p for m, p, b in fake.calls if m == "PUT"]
        rows_in = [r for m, p, b in fake.calls if p == "place_photos" for r in b]
        check(len(put) == 1 and put[0].startswith(f"places/{TOWN}/events/event-") and [r["event_id"] for r in rows_in] == ["id0", "id1"]
              and all(r["kind"] == "event" and r["credit"] == "Prep" and r["description"] == "The cast on stage"
                      and r["source_url"] == "https://www.facebook.com/prep/posts/pfbidCAST" for r in rows_in),
              "one upload, a row for each of the post's Events, credited to the place, linking the post it came from")
        check(sorted(p.split("=eq.")[1] for m, p, b in fake.calls if m == "PATCH") == ["id0", "id1", "id2", "id3"],
              "every Event laid out is marked looked at, found or not")
        check(line.startswith("[photos] 2 of 4 new Events got a photo of their own (0 from their own post or page, 2 from")
              and "none for 2: Reflection; Give to the Max" in line, f"the line says what it did: {line}")
        fake = place_photos.Unsent("https://db.example")
        again = keep(out, db=fake, now=datetime(2026, 10, 31, 11, tzinfo=timezone.utc))
        check(fake.calls == [] and again == line, "keep run again saves nothing twice, and says the same")
        (out / "photos" / "kept.json").unlink()

        class Stops(place_photos.Unsent):  # the routine stopped at the mark of the picked block's second Event
            def rest(self, method, path, body=None, prefer=None):
                if path == "club_events?id=eq.id1":
                    raise KeyboardInterrupt
                return super().rest(method, path, body, prefer)
        fake, rest = Stops("https://db.example"), place_photos.Unsent("https://db.example")
        try:
            keep(out, db=fake, now=datetime(2026, 10, 31, 11, tzinfo=timezone.utc))
        except KeyboardInterrupt:
            pass
        keep(out, db=rest, now=datetime(2026, 10, 31, 11, tzinfo=timezone.utc))
        check(sum(m == "PUT" for m, p, b in fake.calls) == 1 and not any(m != "PATCH" for m, p, b in rest.calls)
              and [p.split("=eq.")[1] for m, p, b in rest.calls] == ["id1", "id2", "id3"],
              "keep stopped inside a picked block goes on from there: its photo isn't sent again, and the marks left are made")
        (out / "photos" / "kept.json").unlink()
        answers = (out / "event_photos.jsonl").read_text()
        (out / "event_photos.jsonl").write_text("")  # keep run before the helpers' lines are in
        early, late_ = place_photos.Unsent("https://db.example"), place_photos.Unsent("https://db.example")
        keep(out, db=early, now=datetime(2026, 10, 31, 11, tzinfo=timezone.utc))
        (out / "event_photos.jsonl").write_text(answers)
        said = keep(out, db=late_, now=datetime(2026, 10, 31, 11, tzinfo=timezone.utc))
        check(not any(m == "PUT" for m, p, b in early.calls) and [m for m, p, b in late_.calls] == ["PUT", "POST"] and said == line,
              "lines that come after a keep are still saved, and only they are; the line says so")
        (out / "photos" / "kept.json").unlink()

        class Taken(place_photos.Unsent):  # the database already has this photo: an earlier run's save got through
            def rest(self, method, path, body=None, prefer=None):
                if path == "place_photos":
                    raise DbError(method, path, self.status, "duplicate key value")
                return super().rest(method, path, body, prefer)
        fake = Taken("https://db.example")
        fake.status = 409
        keep(out, db=fake, now=datetime(2026, 10, 31, 11, tzinfo=timezone.utc))
        check(sorted(p.split("=eq.")[1] for m, p, b in fake.calls if m == "PATCH") == ["id0", "id1", "id2", "id3"],
              "an Event that already has its one live photo doesn't stop the blocks after it")
        (out / "photos" / "kept.json").unlink()
        fake = Taken("https://db.example")
        fake.status = 500
        try:
            keep(out, db=fake, now=datetime(2026, 10, 31, 11, tzinfo=timezone.utc))
            check(False, "a save the database refuses for any other reason stops keep")
        except DbError:
            check(True, "a save the database refuses for any other reason stops keep")
        (out / "photos" / "kept.json").unlink(missing_ok=True)
        (out / "event_photos.jsonl").write_text(json.dumps({"event": "e1", "pick": own, "flyer": True}) + "\n")
        fake = place_photos.Unsent("https://db.example")
        keep(out, db=fake, now=datetime(2026, 11, 2, 11, tzinfo=timezone.utc))
        check({r["kind"] for m, p, b in fake.calls if p == "place_photos" for r in b} == {"flyer"}, "a flyer is saved as kind flyer")
        dry = keep(out, dry_run=True)
        check("dry run" in dry, "a dry run writes nothing")

        class Found(place_photos.Unsent):  # the new Events, as the database answers; no new News
            def rest(self, method, path, body=None, prefer=None):
                self.calls.append((method, path, body))
                return ([dict(e) for e in events] if path.startswith("club_events") else []) if method == "GET" else None
        fake = Found("https://db.example")
        laid_out = lambda: {f.name for f in (out / "photos").iterdir()}
        (out / "photos" / "kept.json").write_text("[]")
        lay_out = lambda: prepare(out, now=datetime(2026, 11, 3, tzinfo=timezone.utc), db=fake, rows=rows, banners={"4758895": "https://storage.googleapis.com/art.jpg"},
                                  share=lambda u: "https://givemn.org/og.jpg", grab=grab)
        first = lay_out()
        check([len(g["events"]) for g in first] == [2, 1, 1] and "kept.json" not in laid_out() and "events.json" in laid_out()
              and all(m == "GET" for m, p, b in fake.calls), "prepare alone lays the sheets out, writes nothing, and clears the last keep's memory")
        before = (out / "photos" / "events.json").read_text()
        lay_out()
        check((out / "photos" / "events.json").read_text() == before, "prepare run again lays out the same")

        # dig-deeper 20: a photo a person kept for a title follows to its new dates
        sheehan = {"id": 624, "event_id": "old", "url": "https://db.example/sheehan.webp", "kind": "event", "town": TOWN,
                   "source_url": "https://www.csbsju.edu/news/x", "width": 1102, "height": 1600, "proposed_by": None,
                   "description": "Sheehan's drawing"}

        class Follows(place_photos.Unsent):  # Reflection's new date, and its earlier date with Jesse's kept photo
            def rest(self, method, path, body=None, prefer=None):
                self.calls.append((method, path, body))
                if method != "GET":
                    return None
                if path.startswith("club_events?select=id,title,place_entry_id"):
                    return [{"id": "old", "title": "Reflection", "place_entry_id": "arts"}]
                if path.startswith("place_photos"):
                    return [sheehan]
                if path.startswith("board_items"):
                    return []
                return [dict(e, place_entry_id="arts") if e["title"] == "Reflection" else dict(e) for e in events]
        laid = prepare(out, now=datetime(2026, 11, 3, tzinfo=timezone.utc), db=Follows("https://db.example"), rows=rows,
                       banners={}, share=lambda u: "https://givemn.org/og.jpg", grab=grab)
        follow_file = json.loads((out / "photos" / "follow.json").read_text())
        check([g["title"] for g in laid] == ["Yoga", "Give to the Max"] and [f["event"]["id"] for f in follow_file] == ["id2"],
              "an Event whose title has a kept photo at its place isn't laid out: it follows that photo")
        (out / "event_photos.jsonl").write_text('{"event": "e1", "pick": "c2", "shows": "The cast on stage"}\n')
        fake = place_photos.Unsent("https://db.example")
        said = keep(out, db=fake, now=datetime(2026, 11, 3, 11, tzinfo=timezone.utc))
        copy = [r for m, p, b in fake.calls if p == "place_photos" for r in b if r["event_id"] == "id2"]
        check(len(copy) == 1 and copy[0]["url"] == sheehan["url"] and copy[0]["entry_id"] == "arts" and copy[0]["status"] == "live"
              and copy[0]["description"] == "Sheehan's drawing" and "id" not in copy[0] and copy[0]["proposed_by"] == FOLLOW
              and sum(m == "PUT" for m, p, b in fake.calls) == 1,
              "keep gives it a live row of the same picture, filed under its place and marked a copy, nothing uploaded again for it")
        check("id2" in [p.split("=eq.")[1] for m, p, b in fake.calls if m == "PATCH"]
              and said.startswith("[photos] 3 of 4 new Events got a photo of their own (1 the one kept for their title, "),
              f"it is marked looked at, and the line counts it: {said}")

        class NoNews(Found):  # the News can't be read (a database without photo_checked_at): the Events still are
            def rest(self, method, path, body=None, prefer=None):
                if path.startswith("board_items"):
                    raise DbError(method, path, 400, "column board_items.photo_checked_at does not exist")
                return super().rest(method, path, body, prefer)
        laid = prepare(out, now=datetime(2026, 11, 3, tzinfo=timezone.utc), db=NoNews("https://db.example"), rows=rows,
                       banners={"4758895": "https://storage.googleapis.com/art.jpg"}, share=lambda u: "https://givemn.org/og.jpg", grab=grab)
        check([len(g["events"]) for g in laid] == [2, 1, 1], "a failed News read still lays every Event out")

        class Refused(Follows):  # the kept photos can't be read: every Event is laid out, as before this step
            def rest(self, method, path, body=None, prefer=None):
                if path.startswith("club_events?select=id,title,place_entry_id"):
                    raise DbError(method, path, 414, "URI too long")
                return super().rest(method, path, body, prefer)
        laid = prepare(out, now=datetime(2026, 11, 3, tzinfo=timezone.utc), db=Refused("https://db.example"), rows=rows,
                       banners={}, share=lambda u: "https://givemn.org/og.jpg", grab=grab)
        check([len(g["events"]) for g in laid] == [2, 1, 1] and json.loads((out / "photos" / "follow.json").read_text()) == [],
              "a failed read of kept photos lays every Event out as before, and nothing follows")

    # town-feed 53: a News found in a post gets its own post's photo.
    paths = []
    todo_news(type("Db", (), {"rest": lambda self, m, p, *a, **k: paths.append(p) or []})(), datetime(2026, 11, 8, tzinfo=timezone.utc))
    check(paths[0].startswith("board_items?") and "status=eq.published" in paths[0] and "photo_checked_at=is.null" in paths[0]
          and "source_url=match." in paths[0] and "created_at=gte.2026-10-31" in paths[0],
          "News asked for: published, found in a post, never looked at, within the 8 days Apify's runs can be read again")
    merch = {"id": "news1", "title": "New Joetown merch", "blurb": "Fresh Joetown tees", "source_name": "JoeTown",
             "source_url": "https://www.instagram.com/p/MERCH/", "place_entry_id": "joetown"}
    ig = lambda code, pics: {"_task": "bp-busy-instagram", "url": f"https://www.instagram.com/p/{code}/", "shortCode": code,
                             "ownerUsername": "joetownmn", "displayUrl": pics[0], "childPosts": [{"displayUrl": u} for u in pics[1:]]}
    igrows = [ig("MERCH", ["https://x.cdninstagram.com/group.jpg", "https://x.cdninstagram.com/tee.jpg",
                           "https://x.cdninstagram.com/small.jpg"]),
              ig("OTHER", ["https://x.cdninstagram.com/other.jpg"])]
    ng = news_groups([merch])
    candidates(ng, igrows, {}, share=lambda u: 1 / 0)
    check(ng[0]["key"] == "n1" and [c["url"].rsplit("/", 1)[1] for c in ng[0]["cands"]] == ["group.jpg", "tee.jpg", "small.jpg"]
          and {c["from"] for c in ng[0]["cands"]} == {"post"}, "a News takes only its own post's pictures, never its place's other posts")
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        nsizes = {"group": (720, 960), "tee": (1365, 1820), "small": (640, 800)}

        def ngrab(c, dest):
            name = next(k for k in nsizes if k in c["url"])
            Image.effect_noise(nsizes[name], 50 + 20 * list(nsizes).index(name)).convert("RGB").save(dest)
            return nsizes[name]
        check(not download(ng, out / "photos", ngrab) and [c["url"].rsplit("/", 1)[1] for c in ng[0]["cands"]] == ["group.jpg", "tee.jpg"],
              f"a News keeps a picture down to {NEWS_MIN_WIDTH} px wide (Jesse's 720 px group shot); an Event's floor stays {MIN_WIDTH}")
        sheets(ng, out / "photos")
        said = json.loads((out / "photos" / "batch-1.txt").read_text().splitlines()[2])
        check(said["event"] == "n1" and said["news"] is True and said["host"] == "JoeTown" and "date" not in said,
              "the batch marks a News as one, with its words and no date")
        check(plan([{"event": "n1", "pick": "c1", "flyer": True}], ng)["n1"][2] is True
              and list(plan([{"event": "n1", "pick": "c1", "shows": "Four friends in the new tees"}], ng)) == ["n1"],
              "a News takes a real photo, else its own flyer (Jesse, 2026-11-08: \"never a flyer\" allow)")
        (out / "photos" / "events.json").write_text(json.dumps(ng))
        (out / "event_photos.jsonl").write_text('{"event": "n1", "pick": "c1", "shows": "Four friends in the new tees"}\n')
        fake = place_photos.Unsent("https://db.example")
        said = keep(out, db=fake, now=datetime(2026, 11, 8, 11, tzinfo=timezone.utc))
        put = [p for m, p, b in fake.calls if m == "PUT"]
        sent = [r for m, p, b in fake.calls if p == "place_photos" for r in b]
        check(len(put) == 1 and put[0].startswith(f"places/{TOWN}/news/news-") and len(sent) == 1
              and {k: sent[0].get(k) for k in ("news_id", "event_id", "entry_id", "kind", "credit", "description", "source_url")}
              == {"news_id": "news1", "event_id": None, "entry_id": "joetown", "kind": "news", "credit": "JoeTown",
                  "description": "Four friends in the new tees", "source_url": "https://www.instagram.com/p/MERCH/"},
              "keep saves a News's pick as its own kind, tied to the News, credited to its place, linking its post")
        check([(m, p) for m, p, b in fake.calls if m == "PATCH"] == [("PATCH", "board_items?id=eq.news1")]
              and said.endswith("; 1 of 1 new News from posts got their post's photo"),
              f"the News is marked looked at, and the line counts it: {said}")

    def asked(new, kept_rows, others):
        class Kept:
            calls = []

            def rest(self, method, path, body=None, prefer=None):
                self.calls.append(path)
                return others if path.startswith("club_events") else kept_rows
        db = Kept()
        return kept_photos(db, new), db.calls
    others = [{"id": "o1", "title": "Reflection", "place_entry_id": "arts"}, {"id": "o2", "title": "Reflection", "place_entry_id": "arts"},
              {"id": "o3", "title": "Bréagán", "place_entry_id": "sju"}, {"id": "o4", "title": "Reflection", "place_entry_id": "elsewhere"}]
    kept_rows = [{"id": 10, "event_id": "o1", "url": "u/older", "proposed_by": None},
                 {"id": 20, "event_id": "o2", "url": "u/sheehan", "proposed_by": "Jesse, 2026-11-02"},
                 {"id": 30, "event_id": "o3", "url": "u/calendar", "proposed_by": OWN},
                 {"id": 40, "event_id": "o4", "url": "u/elsewhere", "proposed_by": None},
                 {"id": 60, "event_id": "o1", "url": "u/copy", "proposed_by": FOLLOW}]
    got, paths = asked([{"id": "n1", "title": "Reflection", "place_entry_id": "arts"}, {"id": "n2", "title": "Bréagán", "place_entry_id": "sju"},
                    {"id": "n3", "title": "Reflection", "place_entry_id": "other"}, {"id": "n4", "title": "Reflection", "place_entry_id": None}],
                   kept_rows, others)
    check({k: v["url"] for k, v in got.items()} == {"n1": "u/sheehan"},
          "the newest kept photo of the title at its place follows; this step's own pick doesn't, nor an earlier copy, nor another "
          "place's, nor to an Event with no place")
    check(all("place_entry_id=in." in p or "entry_id=in." in p for p in paths) and "kind=eq.event" in paths[1]
          and "event_id=in." not in paths[1], "both reads are bounded by the morning's places, and only photos are asked for, not flyers")
    got, calls = asked([{"id": "n5", "title": 'Say "Hi", All', "place_entry_id": "p"}], [], [])
    check(got == {} and quote('("Say \\"Hi\\", All")') in calls[0] and len(calls) == 1,
          "a title with quotes and a comma is asked for whole; no Event of it, no photo asked for")
    print(f"{ok} passed, {bad} failed")
    return bad == 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("step", nargs="?", choices=["prepare", "keep"])
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--town", default=DEFAULT, help="the town whose photo folder the photos go in")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        sys.exit(0 if selftest() else 1)
    global TOWN
    TOWN = lookup(a.town)["photo_slug"]
    if a.step == "prepare":
        prepare(out_dir())
    elif a.step == "keep":
        keep(out_dir(), a.dry_run)
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
