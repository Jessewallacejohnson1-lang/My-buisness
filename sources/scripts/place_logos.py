#!/usr/bin/env python3
"""
place_logos.py: every place's logo made in the new look in the cloud, with no Mac step (BP app logo-cutouts 06).

Search shows a place's own logo, its map pin is that logo on a white square, and its Town card shows it as the host
(private.entry_picture). A place new to the app gets its first logo here, the morning after it comes in
(source-registry, A new place in the app), and every Search logo is kept made by today's logo module (logo.py).

`prepare`, a morning step: the open places with a website and no logo (no Search logo, no pin), never looked at
first, then the longest ago, at most MAX. A place is looked at again after LOOK_AGAIN days, so a site that adds a logo
gets it. Each website is read with the polite fetch and its logo files downloaded, the original upload behind a site
builder's resized copy first (`candidates`). Check 1 is here: a picture, not an SVG (the cloud draws none), at least
MIN_PX on its short side. The files go on one sheet for two helpers (sources/models/place-logo.md, check 2).

`keep`, a step of `morning.py finish`: a place whose two helpers picked the same file gets it made by the logo module
(logo.make: sharpened, cut off its page, fine print trimmed, cleaned, lit), its white inside kept only when both said
so. The logo and pin are saved once in Storage where BP app's logo-3d keeps them (places/<town>/<key>/), their file
and its options in the private place-sources bucket (so `check` can make it again), and the place's search_logo
(`by: morning`, which BP app's publish leaves alone) and logo_url are set. Each place looked at today gets
logo_looked and one report line: live, with the migration that takes it down, or why not.

`check`, a Sunday step of finish: each Search logo not in 3D that another version of logo.py made (search_logo
`made`) is made again from its file in place-sources and replaces it, a team on the old file moving with it. Its
line: how many Search logos today's logo module made.

  python3 sources/scripts/place_logos.py prepare
  python3 sources/scripts/place_logos.py keep --dry-run
  python3 sources/scripts/place_logos.py check --dry-run
  python3 sources/scripts/place_logos.py --selftest
"""

import argparse, hashlib, io, json, re, sys, urllib.parse
from datetime import date, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run  # noqa: E402  (the polite fetch)
from db import DbError  # noqa: E402

MAX = 8           # places looked at a morning: one site read and up to FILES pictures each, a second apart per server
LOOK_AGAIN = 30   # days before a place with no logo is looked at again
FILES = 6         # pictures on the sheet per place
MIN_PX = 100      # a logo file's short side, at least (BP app logo-3d rule 1)
TILE = 220        # a picture's square on the sheet
REMAKE = 60       # Search logos made again a Sunday at most (about 15 s each on the cloud), the rest the next
READINGS = ("place-logos.jsonl", "place-logos-2.jsonl")
SOCIAL = r'facebook|instagram|twitter|x-logo|tiktok|youtube|linkedin|yelp|pinterest|tripadvisor|google|apple-pay|visa|mastercard'


# --- A page's logos (BP app's logo-3d find reads them from here too) ------------------------------------------------

def full_size(u):
    """The original upload behind a resized copy a site builder serves: WordPress's -300x120,
    Shopify's _400x, Wix's /v1/fill/... transform, Squarespace's format=750w, GoDaddy's /:/rs=h:200."""
    u = re.sub(r'(\.wsimg\.com/isteam/.+?\.\w+)/:/.*', r'\1', u)
    u = re.sub(r'(/wp-content/uploads/.+)-\d+x\d+(\.\w+)(\?|$)', r'\1\2\3', u)
    if 'shopify' in u or '/cdn/shop/' in u:
        u = re.sub(r'_(\d+x\d*|x\d+)(@\dx)?(\.\w+)(\?|$)', r'\3\4', u)
    u = re.sub(r'(static\.wixstatic\.com/media/[^/]+)/v1/.*', r'\1', u)
    return re.sub(r'format=\d+w', 'format=2500w', u)


def candidates(html, base):
    """Logo image URLs on a page, most likely first: SVG and 'logo' files, then icons, then og:image."""
    found = []
    for m in re.finditer(r'<(?:img|link|meta|source)[^>]+>', html, re.I):
        tag = m.group(0)
        if not re.search(r'logo|og:image|apple-touch-icon|brand', tag, re.I) or re.search(SOCIAL, tag, re.I):
            continue  # a footer's Facebook or Yelp icon is "logo" too, and isn't theirs
        for u in re.findall(r'(?:src|href|content|data-src|srcset)="([^"\s]+)', tag):
            u = urllib.parse.urljoin(base, u.replace('&amp;', '&'))
            if re.search(r'\.(png|jpe?g|svg|webp)(\?|$)|format=', full_size(u), re.I):
                # Shopify / Squarespace serve a small copy unless asked otherwise
                u = re.sub(r'([?&])(width|w|height|h)=\d+&?', r'\1', u).rstrip('?&')
                found += [(tag, full_size(u)), (tag, u)]  # the original upload first, the copy shown if it's gone

    def rank(t):  # a file named logo first, the share image (often a photo) last, vector before pixels
        tag, u = t
        return (1 if 'og:image' in tag else 0,
                0 if re.search(r'logo|brand', u, re.I) else 1 if re.search(r'logo|brand', tag, re.I) else 2,
                0 if u.lower().split('?')[0].endswith('.svg') else 1)
    seen, out = set(), []
    for t in sorted(found, key=rank):
        if t[1] not in seen:
            seen.add(t[1]); out.append(t[1])
    return out


# --- Which places ---------------------------------------------------------------------------------------------------

def key_of(row):
    """A place's Storage folder and logo key: its place id, else its registry id (BP app logo3d.py row_key)."""
    return row.get("place_id") or row["entry_id"]


def row_filter(row):
    col = "place_id" if row.get("place_id") else "entry_id"
    return f"{col}=eq.{urllib.parse.quote(row[col])}"


def website(row):
    return next((l["url"] for l in row.get("links") or [] if l.get("kind") == "website" and l.get("url")), None)


def todo(db, today, most=MAX):
    """The places to look at today, never looked at first, then the longest ago; and how many more wait."""
    rows = db.rest("GET", "places?select=place_id,entry_id,name,primary_type,links,logo_looked,logo_refused"
                          "&search_logo=is.null&logo_url=is.null&closed_at=is.null") or []
    due = [r for r in rows if website(r) and (not r.get("logo_looked")
                                              or date.fromisoformat(r["logo_looked"]) <= today - timedelta(LOOK_AGAIN))]
    due.sort(key=lambda r: (r.get("logo_looked") or "", r["name"]))
    return due[:most], max(0, len(due) - most)


# --- prepare --------------------------------------------------------------------------------------------------------

def find(place, folder, fetch=run.fetch, grab=None, scrape=run.firecrawl):
    """The place's logo files from its website, each passing check 1: [{n, file, from, px}], and a word on what was
    left out. A site our fetch can't read, or whose page names no logo file (one drawn by its script: Wix, GoDaddy),
    is read once more through Firecrawl's browser, as the morning reads such pages (run.read_page)."""
    import place_photos
    from PIL import Image
    grab = grab or place_photos.download
    site = website(place)
    try:
        _, html = fetch(site)
        base = run.final_url.get(site, site)
    except Exception:  # robots.txt, a site that won't answer: Firecrawl below
        html, base = "", site
    urls = candidates(html or "", base)
    if not urls:
        urls = candidates(scrape(site, fmt="rawHtml"), site)
    files, done, svg, small = [], set(), 0, 0
    sums = set()
    for u in urls:
        if len(files) == FILES:
            break
        if full_size(u) in done or u in (place.get("logo_refused") or []):
            continue  # its original came already, or it was taken down before
        if u.lower().split("?")[0].endswith(".svg"):
            svg += 1
            continue
        dest = folder / f"{key_of(place)}-{len(files) + 1}.png"
        try:
            w, h = grab(u, dest)
        except Exception:  # gone, refused by robots.txt, not a picture
            continue
        sha = hashlib.sha1(Image.open(dest).tobytes()).hexdigest()
        if min(w, h) < MIN_PX or sha in sums:
            small += min(w, h) < MIN_PX
            dest.unlink()
            continue
        done.add(full_size(u))
        sums.add(sha)
        files.append({"n": len(files) + 1, "file": str(dest), "from": u, "px": min(w, h)})
    left = [f"{svg} SVG" if svg else "", f"{small} under {MIN_PX} px" if small else ""]
    return files, ", ".join(x for x in left if x)


def sheet(places, folder):
    """One sheet: a row per place under its key and name, its files numbered on grey (white shows), and the batch
    file the helpers read with it."""
    from PIL import Image, ImageDraw
    import place_photos
    cols = max(len(p["files"]) for p in places)
    im = Image.new("RGB", (cols * TILE + 20, len(places) * (TILE + 50) + 10), "white")
    d, f = ImageDraw.Draw(im), place_photos.font(20)
    path = folder / "sheet.png"
    lines = [f"Sheet: {path}", ""]
    for i, p in enumerate(places):
        y = i * (TILE + 50) + 10
        place_photos.label(d, (10, y), f"{p['key']} · {p['name']}", f, cols * TILE - 12)
        for j, c in enumerate(p["files"]):
            x = j * TILE + 10
            d.rectangle([x, y + 30, x + TILE - 12, y + 30 + TILE - 12], fill=(222, 222, 222))
            pic = Image.open(c["file"]).convert("RGBA")
            pic.thumbnail((TILE - 28, TILE - 40))
            im.paste(pic, (x + (TILE - 12 - pic.width) // 2, y + 38 + (TILE - 40 - pic.height) // 2), pic)
            d.text((x + 6, y + TILE - 2), f"{c['n']} · {c['px']} px", fill=(80, 80, 80), font=place_photos.font(14))
        lines.append(json.dumps({"place": p["key"], "name": p["name"], "kind": p.get("primary_type"),
                                 "website": p["website"], "files": [{"n": c["n"], "from": c["from"]} for c in p["files"]]},
                                ensure_ascii=False))
    im.save(path)
    (folder / "batch.txt").write_text("\n".join(lines) + "\n")
    return path


def prepare(folder, db, today, fetch=run.fetch, grab=None, scrape=run.firecrawl):
    """Looks at today's places and lays their files out for the helpers. Writes folder/found.json: the places to
    check, and the ones looked at with nothing to check, with why."""
    for name in READINGS:  # an earlier prepare's answers: its keys were other places'
        (folder.parent / name).unlink(missing_ok=True)
    if folder.exists():
        for f in folder.iterdir():
            f.unlink()
    folder.mkdir(parents=True, exist_ok=True)
    places, later = todo(db, today)
    found, missed = [], []
    for p in places:
        p = {**p, "website": website(p)}
        try:
            files, left = find(p, folder, fetch, grab, scrape)
        except Exception as e:  # robots.txt says no, a site that won't answer: looked at again in LOOK_AGAIN days
            missed.append({**p, "why": f"its website didn't answer ({' '.join(str(e).split())[:100]})"})
            continue
        if not files:
            missed.append({**p, "why": "its website shows no logo file" + (f" we can use ({left})" if left else "")})
            continue
        found.append({**p, "key": f"p{len(found) + 1}", "id": key_of(p), "files": files})
    if found:
        sheet(found, folder)
    (folder / "found.json.new").write_text(json.dumps({"today": str(today), "places": found, "missed": missed,
                                                       "later": later}, indent=1, ensure_ascii=False))
    (folder / "found.json.new").replace(folder / "found.json")  # whole or not at all
    print(f"[place logos] {len(found)} places to check, {len(missed)} with no logo file, {later} for another morning"
          + (f" ({folder / 'batch.txt'})" if found else ""))
    return found


# --- keep -----------------------------------------------------------------------------------------------------------

def answers_in(text):
    """A helper's JSON lines, by place key; a line that isn't one is skipped."""
    out = {}
    for ln in text.splitlines():
        try:
            a = json.loads(ln.strip().strip(","))
        except ValueError:
            continue
        if isinstance(a, dict) and isinstance(a.get("place"), str):
            out[a["place"]] = a
    return out


def take_down(p, source):
    """The migration lines that take a logo down and keep its file from coming back."""
    q = lambda v: "'" + str(v).replace("'", "''") + "'"
    col = "place_id" if p.get("place_id") else "entry_id"
    return (f"update public.places set search_logo = null, logo_url = null, logo_refused = "
            f"array_append(logo_refused, {q(source)}) where {col} = {q(p[col])};")


def search_logo(made, stored=None):
    """The search_logo row for a logo the module made: its file, its backdrop hue (a stored one stays: Jesse's; a
    grey logo keeps it as a tint, as BP app's build.py does), the module's version, and who made it."""
    import logo
    stored = stored or {}
    hue = made.hue if made.hue is not None else stored.get("hue", 0)
    keep = {k: stored[k] for k in ("hue", "chroma", "rank", "wall") if k in stored}
    return {"hue": hue, "chroma": made.hue is not None, **keep, "made": logo.VERSION}


def save(db, town, p, made, src, notes, stored=None, by=None):
    """The logo, its pin and their source file into Storage, and the row's search_logo and logo_url pointed at them.
    Returns the new search_logo. A file already there (a finish run again) is the same bytes under the same name."""
    folder = f"{town}/{key_of(p)}"
    name = lambda stem, data, ext: f"{stem}-{hashlib.sha1(data).hexdigest()[:8]}.{ext}"
    files = [(f"places/{folder}/{name('logo', made.webp, 'webp')}", made.webp, "image/webp"),
             (f"places/{folder}/{name('pin', made.pin, 'png')}", made.pin, "image/png")]
    if src:
        files += [(f"place-sources/{folder}/flat/{Path(notes['flat']['src']).name}", src, "image/png"),
                  (f"place-sources/{folder}/notes.json", json.dumps(notes, indent=1).encode(), "application/json")]
    for path, data, kind in files:
        try:
            db.storage_put(path, data, kind)
        except DbError as e:  # there already: same bytes, same name; a notes.json kept from before stays
            if e.status not in (400, 409):
                raise
    url = lambda path: f"{db.url}/storage/v1/object/public/{path}"
    logo_row = {"url": url(files[0][0]), **search_logo(made, stored), **({"by": by} if by else {})}
    return logo_row, url(files[1][0])


def keep(run_, dry_run=False):
    """Each logo both helpers picked goes live; every place looked at today is one report line. Kept as the step's
    lines, so a finish run again neither writes nor reports twice. Anything that breaks is one line: finish catches
    only a database error, and a lost morning report costs more than a logo a day late."""
    try:
        return kept_lines(run_, dry_run)
    except Exception as e:
        return [f"[morning] place logos failed: {' '.join(str(e).split())[:200]}"]


def kept_lines(run_, dry_run):
    import logo
    import place_photos
    folder = run_.folder / "place-logos"
    if not (folder / "found.json").exists():
        return []
    done = run_.part(f"place-logos/kept{'-dry-run' if dry_run else ''}.json")
    if done.saved is not None:
        return done.saved
    found = json.loads((folder / "found.json").read_text())
    readings = [answers_in(f.read_text() if f.exists() else "") for f in (run_.folder / n for n in READINGS)]
    lines, looked = [], []
    for p in found["places"]:
        said = [r.get(p["key"]) or {} for r in readings]
        picks = [a.get("logo") for a in said]
        looked.append(p)
        if picks[0] is None or picks[0] != picks[1]:
            why = next((a.get("why") for a in said if a.get("logo") is None and a.get("why")), "")
            what = ("the checks picked different files" if picks[0] is not None and picks[1] is not None
                    else f"a check found none of its files is its logo: {why}".rstrip(": ") if any(said)
                    else "the checks gave no answer")
            lines.append(f"- No logo yet: {p['name']}: {what}")
            continue
        c = next((c for c in p["files"] if c["n"] == picks[0]), None)
        if not c:
            lines.append(f"- No logo yet: {p['name']}: the checks picked a file it doesn't have ({picks[0]})")
            continue
        white = all(a.get("white_inside") is True for a in said)
        try:
            made = logo.make(c["file"], {"keep": True} if white else {})
            if made.bare.getchannel("A").getbbox() is None:
                raise ValueError("nothing left after the cut")
        except Exception as e:
            lines.append(f"- No logo yet: {p['name']}: its logo couldn't be made ({' '.join(str(e).split())[:120]})")
            continue
        src = Path(c["file"]).read_bytes()
        notes = {"flat": {"name": p["name"], "src": f"flat-src/{p['id']}/theirs.png", "from": c["from"],
                          **({"keep": True} if white else {})}, "by": "morning", "day": found["today"]}
        if not dry_run:
            try:
                row, pin = save(run_.db, place_photos.TOWN, p, made, src, notes, by="morning")
                took = run_.db.rest("PATCH", f"places?{row_filter(p)}&search_logo=is.null&select=entry_id",
                                    {"search_logo": row, "logo_url": pin, "logo_looked": found["today"]},
                                    prefer="return=representation")
            except DbError as e:
                lines.append(f"[morning] place logo for {p['name']} failed: {' '.join(str(e).split())[:200]}")
                continue
            if not took:  # it got a logo another way since prepare: that one stays
                lines.append(f"- Logo already there: {p['name']} has one now, so the one found was left out")
                continue
        lines.append(f"- Logo live: {p['name']}, from {c['from']}; both checks picked it"
                     f"{', its white inside kept' if white else ''}. Wrong? Take it down with a migration: "
                     f"{take_down(p, c['from'])}" + (" (dry run: nothing written)" if dry_run else ""))
    for m in found["missed"]:
        looked.append(m)
        lines.append(f"- No logo yet: {m['name']}: {m['why']}")
    if not dry_run:
        for p in looked:  # looked at today, whatever came of it: not again for LOOK_AGAIN days
            run_.db.rest("PATCH", f"places?{row_filter(p)}", {"logo_looked": found["today"]}, prefer="return=minimal")
    if found.get("later"):
        lines.append(f"- No logo yet: {found['later']} more places with a website, looked at on another morning")
    done.save(lines)
    return lines


# --- check (Sundays) ------------------------------------------------------------------------------------------------

def check(run_, dry_run=False):
    """The Sunday lines, after making again at most REMAKE Search logos another version of logo.py made. A part whose
    time is spent says run again, and the next carries on; the lines are kept, so a finish run again neither makes nor
    reports twice."""
    tag = "-dry-run" if dry_run else ""
    done = run_.part(f"place-logos-check{tag}.json")
    if done.saved is not None:
        return done.saved
    try:
        lines = checked_lines(run_.db, dry_run, remade=run_.part(f"place-logos-remade{tag}.json"),
                              said=run_.part(f"place-logos-said{tag}.json", empty=[]))
    except Exception as e:  # never a lost report
        lines = [f"[logos] the Sunday check failed: {' '.join(str(e).split())[:200]}"]
    if not lines[0].startswith("[morning] run again"):
        done.save(lines)
    return lines


def checked_lines(db, dry_run, get=None, remade=None, said=None):
    """`remade`: the keys made again so far this Sunday (a morning_run Part, saved after each); `said`: their lines."""
    import logo
    import place_photos
    from morning_run import Part
    get = get or db.storage_get
    remade, said = remade or Part(None), said or Part(None, empty=[])
    rows = db.rest("GET", "places?select=place_id,entry_id,name,search_logo,logo_url&search_logo=not.is.null"
                          "&closed_at=is.null") or []
    flat = [r for r in rows if not r["search_logo"].get("d3")]
    old = {key_of(r): r for r in flat if r["search_logo"].get("made") != logo.VERSION}
    teams = {t["id"]: t["logo_url"] for t in db.rest("GET", "teams?select=id,logo_url&logo_url=not.is.null") or []}

    def again(key):
        r = old[key]
        folder = f"{place_photos.TOWN}/{key}"
        try:
            o = json.loads(get(f"place-sources/{folder}/notes.json"))["flat"]
            made = logo.make(io.BytesIO(get(f"place-sources/{folder}/flat/{Path(o['src']).name}")), o)
            if dry_run:
                return
            row, pin = save(db, place_photos.TOWN, r, made, None, None, r["search_logo"], by=r["search_logo"].get("by"))
            db.rest("PATCH", f"places?{row_filter(r)}", {"search_logo": row, "logo_url": pin}, prefer="return=minimal")
            moved = {r["search_logo"]["url"]: row["url"], r["logo_url"]: pin}
            for tid, url in sorted(teams.items()):
                if moved.get(url) and moved[url] != url:
                    db.rest("PATCH", f"teams?id=eq.{urllib.parse.quote(tid)}", {"logo_url": moved[url]}, prefer="return=minimal")
                    said.save(said.saved + [f"- {r['name']}: team {tid} moved to its new logo"])
        except Exception as e:  # its file isn't in place-sources, or it won't make: a line, the rest go on
            said.save(said.saved + [f"- {r['name']}: its logo couldn't be made again ({' '.join(str(e).split())[:120]})"])

    before = len(remade.saved or [])
    todo = sorted(k for k in old if k not in (remade.saved or []))[:max(0, REMAKE - before)]
    if remade.each(todo, again):
        return [f"[morning] run again: {len(remade.saved or []) - before} Search logos made again this part, "
                f"{len(todo) - len(remade.saved or []) + before} still to make"]
    n = len(remade.saved or [])
    if not dry_run:  # read again: what this Sunday made is in the rows now
        rows = db.rest("GET", "places?select=place_id,entry_id,name,search_logo,logo_url&search_logo=not.is.null"
                              "&closed_at=is.null") or []
        flat = [r for r in rows if not r["search_logo"].get("d3")]
    now = sum(r["search_logo"].get("made") == logo.VERSION for r in flat)
    bare = db.rest("GET", "places?select=entry_id,links&search_logo=is.null&logo_url=is.null&closed_at=is.null") or []
    head = (f"[logos] {now} of {len(flat)} Search logos made by today's logo module ({logo.VERSION})"
            + (f", {len(flat) - now} still to make" if now < len(flat) else "")
            + f"; {len(rows) - len(flat)} in 3D; {len(bare)} places with no logo, {sum(not website(b) for b in bare)}"
              " of them with no website on file"
            + (f" (dry run: {n} would be made again, nothing written)" if dry_run else f"; {n} made again today" if n else ""))
    return [head] + said.saved


# --- Self-test ------------------------------------------------------------------------------------------------------

def selftest():
    import tempfile
    from PIL import Image, ImageDraw
    from morning_run import Run, FakeDb
    import logo
    checks = []
    ok = lambda cond, why: checks.append((bool(cond), why))

    html = ('<meta property="og:image" content="/hero.jpg"><img class="x" src="/a/icon.png">'
            '<img alt="logo" src="/a/b.png?width=320"><img src="/logo-big.svg"><img src="/icons/facebook-logo.svg">')
    c = candidates(html, 'https://shop.test/')
    ok(c[0] == 'https://shop.test/logo-big.svg' and c[1] == 'https://shop.test/a/b.png' and c[-1].endswith('hero.jpg'),
       "a page's logos: SVG and logo files first, the share picture last, a footer's Facebook icon never")
    sizes = [('https://x.test/wp-content/uploads/2024/05/Logo-300x120.png', 'https://x.test/wp-content/uploads/2024/05/Logo.png'),
             ('https://x.test/cdn/shop/files/logo_400x.png?v=1', 'https://x.test/cdn/shop/files/logo.png?v=1'),
             ('https://static.wixstatic.com/media/ab12~mv2.png/v1/fill/w_200,h_80/logo.png', 'https://static.wixstatic.com/media/ab12~mv2.png'),
             ('https://images.squarespace-cdn.com/c/logo.png?format=750w', 'https://images.squarespace-cdn.com/c/logo.png?format=2500w'),
             ('https://img1.wsimg.com/isteam/ip/ab12/logo.png/:/rs=h:200,cg:true,m/qt=q:95', 'https://img1.wsimg.com/isteam/ip/ab12/logo.png'),
             ('https://x.test/img/logo-2x.png', 'https://x.test/img/logo-2x.png')]
    ok(all(full_size(small) == big for small, big in sizes)
       and candidates('<img class="logo" src="/wp-content/uploads/Logo-300x120.png">', 'https://x.test/')
       == ['https://x.test/wp-content/uploads/Logo.png', 'https://x.test/wp-content/uploads/Logo-300x120.png'],
       "a site builder's resized logo leads to its original upload, the copy shown kept behind it")

    today = date(2026, 11, 22)
    site = lambda u: [{"kind": "website", "url": u}]
    rows = [{"place_id": None, "entry_id": "never", "name": "B Never", "links": site("https://b.test/")},
            {"place_id": "stjoe-old", "entry_id": "old", "name": "A Old", "links": site("https://a.test/"),
             "logo_looked": "2026-10-01"},
            {"place_id": None, "entry_id": "recent", "name": "Recent", "links": site("https://r.test/"),
             "logo_looked": "2026-11-10"},
            {"place_id": None, "entry_id": "nosite", "name": "No Site", "links": []},
            {"place_id": None, "entry_id": "empty", "name": "C Empty", "links": site("https://e.test/")}]
    db = FakeDb(answers={"places?select=place_id": rows})
    got, later = todo(db, today, most=2)
    ok([r["entry_id"] for r in got] == ["never", "empty"] and later == 1,
       f"never looked at first, then the longest ago; one looked at this month and one with no website wait: {got}, {later}")

    def logo_file(path, size=(300, 200)):
        im = Image.new("RGB", size, "white")
        ImageDraw.Draw(im).ellipse([20, 20, size[0] - 20, size[1] - 20], fill=(30, 90, 200))
        im.save(path)
        return im.size
    pages = {"https://b.test/": '<img class="logo" src="/logo.png"><img src="/brand.svg"><img class="logo" src="/tiny-logo.png">'
                                '<img class="logo" src="/same-logo.png">',
             "https://a.test/": '<img class="logo" src="/a-logo.png">',
             "https://e.test/": '<p>no pictures</p>'}

    def grab(u, dest):
        return logo_file(dest, (60, 40) if "tiny" in u else (300, 200))
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp) / "morning" / "place-logos"
        db = FakeDb(answers={"places?select=place_id": rows})
        scraped = []
        found = prepare(folder, db, today, fetch=lambda u: (200, pages[u]), grab=grab,
                        scrape=lambda u, fmt: (scraped.append((u, fmt)), "<p>still none</p>")[1])
        batch = (folder / "batch.txt").read_text().splitlines()
        f = json.loads((folder / "found.json").read_text())
        ok([p["name"] for p in found] == ["B Never", "A Old"] and [c["n"] for c in found[0]["files"]] == [1]
           and batch[0] == f"Sheet: {folder / 'sheet.png'}" and json.loads(batch[2])["files"][0]["from"] == "https://b.test/logo.png"
           and (folder / "sheet.png").exists(),
           f"check 1: an SVG, a file under {MIN_PX} px and the same picture twice stay off the sheet: {found}")
        ok([m["name"] for m in f["missed"]] == ["C Empty"] and "no logo file" in f["missed"][0]["why"]
           and scraped == [("https://e.test/", "rawHtml")],
           f"a site with no logo file is read once more through Firecrawl, then is a line: {f['missed']}, {scraped}")

        r = Run(Path(tmp) / "morning", today, FakeDb())
        r.db.url = "https://db.test"
        (r.folder / READINGS[0]).write_text('{"place": "p1", "logo": 1, "white_inside": true, "why": "its name"}\n')
        (r.folder / READINGS[1]).write_text('{"place": "p1", "logo": 1, "white_inside": false, "why": "its name"}\n')
        real = logo.make
        asked = []
        logo.make = lambda f, o: (asked.append(o), real(f, o))[1]
        r.db.storage_put = lambda path, data, kind: r.db.calls.append(("PUT", path, len(data)))
        r.db.answers = {"places?entry_id=eq.never&search_logo=is.null": [{"entry_id": "never"}]}
        try:
            lines = keep(r)
        finally:
            logo.make = real
        puts = [c[1] for c in r.db.calls if c[0] == "PUT"]
        patch = next(c for c in r.db.calls if c[0] == "PATCH" and "search_logo=is.null" in c[1])
        ok(lines[0].startswith("- Logo live: B Never, from https://b.test/logo.png; both checks picked it.")
           and "array_append(logo_refused, 'https://b.test/logo.png') where entry_id = 'never'" in lines[0]
           and lines[1:] == ["- No logo yet: A Old: the checks gave no answer",
                             "- No logo yet: C Empty: its website shows no logo file"],
           f"a logo both checks picked goes live with its take-down line; a place with none is a line: {lines}")
        ok(asked == [{}], f"its white inside is kept only when both checks say so: {asked}")
        ok([p.split("/")[0] for p in puts] == ["places", "places", "place-sources", "place-sources"]
           and puts[0].startswith(f"places/{__import__('place_photos').TOWN}/never/logo-") and puts[3].endswith("never/notes.json"),
           f"the logo and pin in places, their file and notes in place-sources: {puts}")
        row = patch[2]["search_logo"]
        ok(row["by"] == "morning" and row["made"] == logo.VERSION and row["chroma"] is True and 190 <= row["hue"] <= 230
           and patch[2]["logo_url"].startswith("https://db.test/storage/v1/object/public/places/") and patch[2]["logo_looked"] == "2026-11-22",
           f"the row: the module's version, made by the morning, its main colour: {patch[2]}")
        looked = [c[1] for c in r.db.calls if c[0] == "PATCH" and c[2] == {"logo_looked": "2026-11-22"}]
        ok(looked == ["places?entry_id=eq.never", "places?place_id=eq.stjoe-old", "places?entry_id=eq.empty"],
           f"every place looked at today gets logo_looked: {looked}")
        calls = len(r.db.calls)
        ok(keep(r) == lines and len(r.db.calls) == calls, "a finish run again neither writes nor reports twice")

        r2 = Run(Path(tmp) / "morning2", today, FakeDb())
        (r2.folder / "place-logos").mkdir(parents=True)
        (r2.folder / "place-logos" / "found.json").write_text((folder / "found.json").read_text())
        (r2.folder / READINGS[0]).write_text('{"place": "p1", "logo": 1}\n')
        (r2.folder / READINGS[1]).write_text('{"place": "p1", "logo": null, "why": "a supplier\'s logo"}\n')
        lines = keep(r2, dry_run=True)
        ok(lines[0] == "- No logo yet: B Never: a check found none of its files is its logo: a supplier's logo"
           and not r2.db.writes(), f"one check's no keeps it off, and a dry run writes nothing: {lines}")

        # Sunday: a logo another version made is made again from place-sources; one this version made is left
        src = io.BytesIO()
        Image.open(found[0]["files"][0]["file"]).save(src, "PNG")
        notes = {"flat": {"src": "flat-src/stjoe-x/theirs.png"}}
        town = __import__("place_photos").TOWN
        store = {f"place-sources/{town}/stjoe-x/notes.json": json.dumps(notes).encode(),
                 f"place-sources/{town}/stjoe-x/flat/theirs.png": src.getvalue()}
        live = "https://db.test/storage/v1/object/public/places/st-joseph/stjoe-x/"
        places = [{"place_id": "stjoe-x", "entry_id": "x", "name": "Old Co", "logo_url": live + "pin-1.png",
                   "search_logo": {"url": live + "logo-1.webp", "hue": 12, "chroma": True, "rank": 3}},
                  {"place_id": "stjoe-y", "entry_id": "y", "name": "New Co", "logo_url": "p",
                   "search_logo": {"url": "u", "made": logo.VERSION}},
                  {"place_id": "stjoe-z", "entry_id": "z", "name": "3D Co", "logo_url": "p", "search_logo": {"url": "u", "d3": True}}]
        def rows_now(method, path, body):  # the places table: a PATCH changes the row it names
            for r in places:
                if method == "PATCH" and path == f"places?place_id=eq.{r['place_id']}":
                    r.update(body)
            return [dict(r) for r in places] if method == "GET" else None
        db = FakeDb(answers={"places?select=entry_id,links": [{"entry_id": "q", "links": []}],
                             "places?": rows_now, "teams?": [{"id": "sjp", "logo_url": live + "logo-1.webp"}]})
        db.url = "https://db.test"
        db.storage_put = lambda path, data, kind: db.calls.append(("PUT", path, len(data)))
        lines = checked_lines(db, False, get=store.__getitem__)
        patch = next(c for c in db.calls if c[0] == "PATCH" and c[1].startswith("places?place_id=eq.stjoe-x"))
        ok(lines[0] == f"[logos] 2 of 2 Search logos made by today's logo module ({logo.VERSION}); 1 in 3D;"
                      " 1 places with no logo, 1 of them with no website on file; 1 made again today"
           and patch[2]["search_logo"]["hue"] == 12 and patch[2]["search_logo"]["rank"] == 3
           and patch[2]["search_logo"]["made"] == logo.VERSION and "by" not in patch[2]["search_logo"]
           and any(c[0] == "PATCH" and c[1] == "teams?id=eq.sjp" for c in db.calls) and lines[1] == "- Old Co: team sjp moved to its new logo",
           f"Sunday: an old logo is made again from its file, keeping its hue and rank, its team moving with it: {lines}")
        db.calls.clear()
        places[0]["search_logo"]["made"] = "older"
        lines = checked_lines(db, True, get=store.__getitem__)
        ok(not db.writes() and lines[0].startswith("[logos] 1 of 2") and lines[0].endswith("(dry run: 1 would be made again, nothing written)"),
           f"a dry run makes it but writes nothing: {lines}")
        db.storage_get = store.__getitem__
        (Path(tmp) / "sunday").mkdir()
        spent = check(Run(Path(tmp) / "sunday", today, db, minutes=-1))
        whole = check(Run(Path(tmp) / "sunday", today, db, minutes=None))
        ok(spent == ["[morning] run again: 0 Search logos made again this part, 1 still to make"]
           and whole[0].startswith("[logos] 2 of 2") and check(Run(Path(tmp) / "sunday", today, db)) == whole,
           f"a Sunday part whose time is spent says run again; the next carries on, and its lines are kept: {spent}, {whole}")

    failed = [why for good, why in checks if not good]
    for why in failed:
        print(f"FAIL {why}")
    print(f"place_logos.py selftest: {len(checks) - len(failed)} passed, {len(failed)} failed")
    return not failed


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("step", nargs="?", choices=["prepare", "keep", "check"])
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if selftest() else 1)
    from registry import find_root
    from morning_run import Run
    from read_events import LOCAL
    r = Run(find_root() / ".runs" / "morning", datetime.now(LOCAL).date(), run.Supabase())
    if a.step == "prepare":
        prepare(r.folder / "place-logos", r.db, r.today)
    elif a.step == "keep":
        print("\n".join(keep(r, a.dry_run)))
    elif a.step == "check":
        print("\n".join(check(r, a.dry_run)))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
