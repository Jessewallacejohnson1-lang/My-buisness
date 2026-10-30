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
  same page's other posts, for an Event whose own post is only a flyer
- a CSB SJU campus listing: its banner picture, one call to the campus calendar for every listing
- any other page: its share picture (og:image), read politely
Each is downloaded once, at least MIN_WIDTH wide, and drawn numbered on .runs/morning/photos/sheet-N.png; a
helper on the cheap model picks one per Event by sources/models/event-photo.md, or none. `keep` uploads each
pick to the places bucket as a place_photos row of kind 'event' for that Event (one row per Event when one
post names several), credited to its place (a post) or its site (a page), and marks every Event laid out as
looked at (club_events.photo_checked_at), found or not, so none is looked at twice. A game, a meet or any
sport has no photo of its own for now, and a sport's card shows the scene pool (event-photos 07).
"""
import argparse, hashlib, io, json, re, sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import quote, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, place_key  # noqa: E402
import social, write_judged  # noqa: E402
from read_events import LOCAL  # noqa: E402
from run import Supabase, fetch  # noqa: E402
from morning import read_items  # noqa: E402
from db import DbError  # noqa: E402

LOOKBACK = timedelta(days=8)   # the weekly read is Thursday's: a Friday morning still finds its posts
NEW = timedelta(days=3)        # an Event found longer ago than this was there before this step
PLACE_MORE = 6                 # the same page's other photos offered beside a post's own pictures
MIN_WIDTH = 1000               # as scenes.py: the card is width-bound and asks for 1200 px
PER_SHEET = 4                  # Events on one sheet, so a helper sees each picture big enough
TILE = 300
TOWN = "st-joseph"
CAMPUS_API = "https://my.csbsju.edu/api/v2/events/unauthenticated/"
CAMPUS_PAGE = re.compile(r"my\.csbsju\.edu/public/events/(\d+)")
POST = re.compile(r"(?:facebook|instagram)\.com/")
GAME_PAGE = re.compile(r"mshsl\.org|gobound\.com|gojohnnies\.com|gobennies\.com|athletics", re.I)
SPORT = re.compile(r"hockey|basketball|wrestl|swim|diving|gymnast|volleyball|football|cross country|track|soccer|"
                   r"nordic|\bski|tennis|golf|softball|baseball|lacrosse|bowling|\bvs\.?\b", re.I)
TEXT = re.compile(r"\btext\b", re.I)  # Meta's own description: "May be an image of text that says ..."


def out_dir():
    return find_root() / ".runs" / "morning"


def sport(e):
    """A game, a meet or any sport: no photo of its own yet (Jesse: "dont worry about games for now")."""
    return bool(write_judged.is_game(e) or e.get("sport") or e.get("category") == "watch_sports"
                or SPORT.search(e.get("title") or "") or GAME_PAGE.search(f"{e.get('source_url')} {e.get('source_name')}"))


def todo(db, now):
    """Approved Events found in the last NEW, still to come, never looked at, that aren't a sport."""
    today, since = now.astimezone(LOCAL).date(), (now - NEW).isoformat()
    rows = db.rest("GET", "club_events?select=id,title,event_date,location,description,category,sport,team_ids,"
                          "source_name,source_url,place_entry_id"
                          f"&status=eq.approved&kind=eq.event&photo_checked_at=is.null&created_at=gte.{quote(since)}"
                          f"&or={quote(f'(event_date.gte.{today},end_at.gte.{today})')}&order=created_at&limit=300")
    return [r for r in rows if not sport(r)]


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
    return sorted(rows, key=lambda x: x.get("timestamp") or x.get("time") or x["_at"], reverse=True)


def from_posts(group, rows):
    """A post's own pictures, then its page's other photos: [{url, about, from, page}]. An Event a post links
    to (facebook.com/events/<n>) takes that post's pictures, or the Events tab's cover."""
    key = post_key(group["source_url"])
    own = [r for r in rows if post_key(r.get("url") or r.get("topLevelUrl")) == key]
    if not own and "/events/" in group["source_url"]:
        own = [r for r in rows if key in json.dumps(r.get("text") or r.get("caption") or "")
               or key in json.dumps(r.get("textReferences") or [])]
    if not own:
        return []
    page = own[0].get("url") or group["source_url"]
    out = [{**p, "from": "post", "page": page} for p in pictures(own[0])]
    seen = {post_key(r.get("url")) for r in own}
    for r in rows:
        if len(out) >= len(pictures(own[0])) + PLACE_MORE:
            break
        if owner(r) == owner(own[0]) and post_key(r.get("url")) not in seen:
            seen.add(post_key(r.get("url")))
            out += [{**p, "from": "other post", "page": r.get("url") or page} for p in pictures(r)[:2]
                    if not TEXT.search(p["about"])]
    return out[:len(pictures(own[0])) + PLACE_MORE]


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
            g["cands"] = from_posts(g, rows)
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
            if w < MIN_WIDTH:
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
            y, e = row * (TILE + 80) + 10, g["events"][0]
            head = f"{g['key']}  {g['title']} · {e['event_date']} · {e.get('location') or e.get('source_name') or ''}"
            place_photos.label(d, (10, y), head, big, cols * TILE)
            lines.append(json.dumps({"event": g["key"], "title": g["title"], "host": e.get("source_name") or "",
                                     "place": e.get("location") or "", "date": e["event_date"],
                                     "about": " ".join((e.get("description") or "").split())[:240],
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
    events = todo(db or Supabase(), now)
    groups = groups_of(events)
    for i, g in enumerate(groups, 1):
        g["key"] = f"e{i}"
    if rows is None:
        rows = social_rows(now) if any(POST.search(g["source_url"]) for g in groups) else []
    candidates(groups, rows, campus_banners(groups) if banners is None else banners, share)
    failed = download(groups, folder, grab)
    n = sheets(groups, folder)
    (folder / "events.json").write_text(json.dumps(groups, indent=1, ensure_ascii=False))
    with_pics = sum(1 for g in groups if g["cands"])
    print(f"[photos] {len(events)} new Events to look at ({len(groups)} posts or pages): {with_pics} with pictures "
          f"on {n} sheets, {len(groups) - with_pics} with none ({folder})")
    for ln in failed:
        print(f"[photos]   {ln}")
    return groups


def plan(lines, groups):
    """The helpers' lines as picks: {group key: (candidate, what it shows)}, only a group laid out and one of its
    own pictures, each group once."""
    by, picks = {g["key"]: g for g in groups}, {}
    for ln in lines:
        if not isinstance(ln, dict) or ln.get("event") not in by or ln["event"] in picks:
            continue
        c = next((c for c in by[ln["event"]]["cands"] if f"c{c['n']}" == str(ln.get("pick") or "").strip()), None)
        if c:
            picks[ln["event"]] = (c, " ".join(str(ln.get("shows") or "").split())[:80] or None)
    return picks


def entry_of(e):
    """Where an Event's photo is filed: its place, else its host's registry entry."""
    if e.get("place_entry_id"):
        return e["place_entry_id"]
    ids = write_judged.names().get(place_key(e.get("source_name") or ""), [])
    return ids[0] if ids else "unplaced"


def keep(out, dry_run=False, db=None, put=None, now=None):
    import place_photos
    from PIL import Image
    folder = out / "photos"
    groups = json.loads((folder / "events.json").read_text()) if (folder / "events.json").exists() else []
    picks = plan(read_items(out / "event_photos.jsonl"), groups)
    db = db or (None if dry_run else Supabase())
    stamp = (now or datetime.now(timezone.utc)).isoformat()
    kept = []
    for g in groups:
        if g["key"] in picks and not dry_run:
            c, shows = picks[g["key"]]
            data = place_photos.webp(Image.open(c["file"]))
            w, h = Image.open(io.BytesIO(data)).size
            path = f"{TOWN}/events/{hashlib.sha1(data).hexdigest()[:12]}.webp"
            try:
                (put or db.storage_put)(f"places/{path}", data, "image/webp")
            except DbError as x:
                if x.status not in (400, 409):  # the same file from an earlier, interrupted keep
                    raise
            url = f"{db.url}/storage/v1/object/public/places/{quote(path)}"
            for e in g["events"]:
                db.rest("POST", "place_photos", [{
                    "entry_id": entry_of(e), "town": TOWN, "url": url, "source_url": c["page"], "kind": "event",
                    "event_id": e["id"], "status": "live", "width": w, "height": h, "description": shows,
                    "credit": e.get("source_name") if POST.search(c["page"]) else None,
                    "proposed_by": "event photos"}], "return=minimal")
        if not dry_run:
            for e in g["events"]:
                db.rest("PATCH", f"club_events?id=eq.{e['id']}", {"photo_checked_at": stamp}, prefer="return=minimal")
        if g["key"] in picks:
            kept.append(g)
    events = sum(len(g["events"]) for g in groups)
    got = sum(len(g["events"]) for g in kept)
    own = sum(len(g["events"]) for g in kept if picks[g["key"]][0]["from"] != "other post")
    none = [g["title"] for g in groups if g["key"] not in picks]
    line = (f"[photos] {got} of {events} new Events got a photo of their own ({own} from their own post or page, "
            f"{got - own} from their place's other posts)" + (f"; none for {len(none)}: " + "; ".join(none[:20])
                                                               if none else "")
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
    check(sport({"title": "Boys Swim vs Brainerd · JV"}) and sport({"title": "Fall Play", "source_url": "https://www.mshsl.org/x"})
          and sport({"title": "Pep fest", "category": "watch_sports"}) and not sport({"title": "Annual Dog Costume Contest"})
          and not sport({"title": "Yoga and Pelvic Floor Health", "category": "health"}), "games, meets and sports left out")

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
    check([(c["url"], c["from"]) for c in got] == [("https://x.fbcdn.net/flyer.jpg", "post"), ("https://x.fbcdn.net/cast.jpg", "other post")],
          "its post's flyer, full size, then the same page's photos, never another page's nor a picture Meta reads as text")
    check([c["url"] for c in from_posts({"source_url": "https://www.facebook.com/events/2380009089072052", "events": []}, rows)]
          == ["https://x.fbcdn.net/tattoo.jpg"], "an Event a post links to takes that post's pictures")
    check(from_posts({"source_url": "https://www.facebook.com/x/posts/pfbidGONE", "events": []}, rows) == [], "a post not read: none")

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
        sizes = {"flyer": (1536, 2048), "cast": (1206, 1608), "art": (4568, 3000), "og": (500, 500)}

        def grab(c, dest):
            name = next(k for k in sizes if k in c["url"])
            Image.effect_noise(sizes[name], 60 + 10 * list(sizes).index(name)).convert("RGB").save(dest)
            return sizes[name]
        failed = download(gs, folder, grab)
        check(not failed and [c["n"] for c in gs[0]["cands"]] == [1, 2] and gs[2]["cands"] == [],
              f"each picture downloaded once and numbered; one under {MIN_WIDTH} px dropped")
        check(sheets(gs, folder) == 1 and (folder / "sheet-1.png").exists(), "one sheet for three blocks")
        batch = (folder / "batch-1.txt").read_text()
        check('"pick": "c2", "from": "other post"' in batch and "e3" not in batch, "the batch names each picture and its source; a block with none isn't shown")

        picks = plan([{"event": "e1", "pick": "c2", "shows": "The cast on stage"}, {"event": "e1", "pick": "c1"},
                      {"event": "e2", "pick": "c9"}, {"event": "e9", "pick": "c1"}, "unreadable line: x"], gs)
        check(list(picks) == ["e1"] and picks["e1"][0]["n"] == 2 and picks["e1"][1] == "The cast on stage",
              "only a block laid out, once, and only one of its own pictures")

        (folder / "events.json").write_text(json.dumps(gs))
        (out / "photos").mkdir(parents=True)
        for f in folder.iterdir():
            (out / "photos" / f.name).write_bytes(f.read_bytes())
        (out / "photos" / "events.json").write_text(json.dumps(gs).replace(str(folder), str(out / "photos")))
        (out / "event_photos.jsonl").write_text('{"event": "e1", "pick": "c2", "shows": "The cast on stage"}\n')

        class FakeDb:
            url = "https://db.example"

            def __init__(self):
                self.calls = []

            def rest(self, method, path, body=None, prefer=None):
                self.calls.append((method, path, body))

        fake, put = FakeDb(), []
        line = keep(out, db=fake, put=lambda *a: put.append(a[0]), now=datetime(2026, 10, 31, 11, tzinfo=timezone.utc))
        rows_in = [b[0] for m, p, b in fake.calls if p == "place_photos"]
        check(len(put) == 1 and [r["event_id"] for r in rows_in] == ["id0", "id1"]
              and all(r["kind"] == "event" and r["credit"] == "Prep" and r["description"] == "The cast on stage"
                      and r["source_url"] == "https://www.facebook.com/prep/posts/pfbidCAST" for r in rows_in),
              "one upload, a row for each of the post's Events, credited to the place, linking the post it came from")
        check(sorted(p.split("=eq.")[1] for m, p, b in fake.calls if m == "PATCH") == ["id0", "id1", "id2", "id3"],
              "every Event laid out is marked looked at, found or not")
        check(line.startswith("[photos] 2 of 4 new Events got a photo of their own (0 from their own post or page, 2 from")
              and "none for 2: Reflection; Give to the Max" in line, f"the line says what it did: {line}")
        dry = keep(out, dry_run=True)
        check("dry run" in dry, "a dry run writes nothing")
    print(f"{ok} passed, {bad} failed")
    return bad == 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("step", nargs="?", choices=["prepare", "keep"])
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        sys.exit(0 if selftest() else 1)
    if a.step == "prepare":
        prepare(out_dir())
    elif a.step == "keep":
        keep(out_dir(), a.dry_run)
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
