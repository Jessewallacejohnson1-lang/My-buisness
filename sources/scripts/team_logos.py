#!/usr/bin/env python3
"""
team_logos.py: a team with no logo gets its own, each morning, when two checks agree (BP app game-card 17).

A game shows nowhere until both its teams have logos (game-card 16), so a new team's logo is looked for with no one
asking (Jesse, 2026-11-09: "i dont have to accept rather it has evals to make sure its the correct team").

`prepare` takes the teams with no logo that have a game waiting, at most MAX, rotated by the day so a team never
found doesn't block the rest, and looks each one up: the state league's school page first (free, and its robots.txt
allows it), then Wikipedia for a team the league doesn't list (out of state, a college). A co-op with no page of its
own takes its first school's logo, and the report says so (the agent's default, 2026-11-09). Check 1 is here: the
page's title names the team's school, word for word both ways. The logos go on one sheet for a helper on the cheap
model, who answers yes, no or unsure for each (sources/models/team-logo.md, check 2; its eval is
check_team_logos.py).

`keep`, a step of `morning.py finish`, puts live each logo the helper said yes to: cut off its white box, cleaned and lit
(clean_logo.py, game-card 28; the helpers judge whose logo it is, not its cut), saved once in Storage
(places/teams/<id>/logo-<hash>.png), its colors read from it, and the team updated, which shows its games
(private.team_logo_changed). Each logo put live is a report line saying how to take it down, and each team still
waiting is one saying why.

  python3 sources/scripts/team_logos.py prepare
  python3 sources/scripts/team_logos.py keep --dry-run
  python3 sources/scripts/team_logos.py --selftest
"""

import argparse, hashlib, html as htmllib, io, json, re, sys, tempfile, time, urllib.parse, urllib.request
from collections import Counter
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run  # noqa: E402  (the polite fetch)
from db import DbError  # noqa: E402

MAX = 6        # teams looked up a morning: about 5 league reads each, a second apart
SIDE = 512     # the card draws 64 pt, 192 px on a 3x phone; 512 leaves room (game-card 17's first pass)
TILE = 300     # a logo's square on the sheet
LEAGUE = "https://www.mshsl.org"
LEAGUE_LOGO = re.compile(r'src="(/sites/default/files/styles/[^/"]+/public/logos/[^"]+)"')
BOUND = "https://www.gobound.com/mn/schools/"
BOUND_BRAND = "/brand/"  # Bound's own picture, on a page for a school it doesn't have
WIKI = "https://en.wikipedia.org/w/api.php"
WIKI_GAP = 4   # Wikipedia answered 429 after five quick lookups (find_wiki.py, 2026-10-20)
WIKI_LOGO = re.compile(r"logo|mascot|athletic|wordmark|emblem", re.I)
# Words a school's name carries beside its own: "Becker High School" names Becker.
GENERIC = {"high", "school", "schools", "secondary", "university", "college", "senior", "junior", "hs", "sr", "jr", "area", "public", "community",
           "the", "of", "and"}


def words(text):
    """"Saint Cloud" and "St. Cloud" are the same words, and "H.S." is one."""
    text = re.sub(r"\bh\.\s*s\.", "hs", re.sub(r"\bsaint\b", "st", str(text or "").lower()))
    return set(re.findall(r"[a-z0-9]+", text)) - {"the", "of"}


def names(title, name, town=""):
    """Check 1: the page's title names this school and no other. Every word of the name is in the title or the
    school's town ("Heritage Christian Academy Maple Grove" is Heritage Christian Academy, in Maple Grove), and
    every word of the title is the name's: "Minnesota River Valley Academy" is not Minnesota River, and "Lakeville
    North", in Lakeville, is not North-Tartan's first school."""
    want = words(name)
    return bool(want) and want <= words(title) | words(town) and words(title) - GENERIC <= want


def first_school(name):
    """A co-op's first school: "Becker-Big Lake" is Becker's. One name with no hyphen is its own."""
    first = re.split(r"\s*-\s*", name)[0].strip()
    return first if first != name.strip() else None


# --- Which teams ----------------------------------------------------------------------------------------------------

def todo(db, today, most=MAX):
    """The teams with no logo and a game waiting, rotated by the day; each with its waiting games' sports."""
    games = db.rest("GET", "club_events?select=team_ids,sport&status=eq.waiting_logo&kind=eq.event&cancelled_at=is.null") or []
    rows = db.rest("GET", "teams?select=id,name,logo_refused&logo_url=is.null") or []
    bare, refused = {t["id"]: t["name"] for t in rows}, {t["id"]: t.get("logo_refused") or [] for t in rows}
    sports = {}
    for g in games:
        for t in g.get("team_ids") or []:
            if t in bare:
                sports.setdefault(t, Counter())[re.sub(r"\s*·.*$", "", g.get("sport") or "")] += 1
    ids = sorted(sports)
    start = today.toordinal() % len(ids) if ids else 0
    picked = (ids[start:] + ids[:start])[:most]
    return [{"id": t, "name": bare[t], "refused": refused[t], "sports": [s for s, _ in sports[t].most_common() if s]}
            for t in picked], len(ids) - len(picked)


# --- Where each logo is ---------------------------------------------------------------------------------------------

def league_search(query, get=run.fetch):
    """The league's schools named like `query`: [(path, name)], from its own search."""
    _, page = get(f"{LEAGUE}/schools?{urllib.parse.urlencode({'name': query})}")
    page = page[page.find("views-exposed-form-schools-list"):]
    found = re.findall(r'<a[^>]+href="(/schools/[a-z0-9-]+)"[^>]*>\s*(?:<[^>]+>\s*)*([^<]+?)\s*<', page)
    return list(dict.fromkeys((p, re.sub(r"\s+", " ", n)) for p, n in found))


def league_page(page):
    """A league school page's name, logo, nickname, colors and town."""
    text = run.to_text(page)
    h1 = re.search(r"<h1[^>]*>(.*?)</h1>", page, re.S)
    title = " ".join(re.sub(r"<[^>]+>", " ", h1.group(1)).split()) if h1 else ""
    if not title:
        t = re.search(r"<title>([^<|]+)", page)
        title = t.group(1).strip() if t else ""
    logo = LEAGUE_LOGO.search(page)
    nick, colors = re.search(r"Nickname:\s*([^\n]+)", text), re.search(r"School Colors:\s*([^\n]+)", text)
    town = re.search(r"\n([A-Z][A-Za-z .'-]+),\s*\n\s*MN\b", text)
    return {"title": title, "logo": urllib.parse.urljoin(LEAGUE, logo.group(1).replace("&amp;", "&")) if logo else None,
            "nickname": nick.group(1).strip() if nick else "", "colors": colors.group(1).strip() if colors else "",
            "town": town.group(1).strip() if town else ""}


def from_league(team, get=run.fetch):
    """The team's school page on the league's site, or its first school's for a co-op the league doesn't list; None
    when neither is there. Searches by the name, the co-op's first school, then the name's first two words (the
    league's search wants the start of its own name: "Heritage Christian", not "... Maple Grove")."""
    name, first = team["name"], first_school(team["name"])
    tried = set()
    for query in dict.fromkeys(q for q in (name, first, " ".join(name.split()[:2])) if q):
        for path, listed in league_search(query, get):
            # Read only a page whose listed name could pass check 1 (every word of it the team's; the town is on the
            # page): each page is a second of the league's time.
            fits = lambda n: n and words(listed) - GENERIC <= words(n)
            if path in tried or not (fits(name) or fits(first)):
                continue
            tried.add(path)
            _, page = get(LEAGUE + path)
            p = league_page(page)
            own = names(p["title"], name, p["town"])
            if own or (first and names(p["title"], first, p["town"])):
                return {**p, "page": LEAGUE + path, "source": "the state league", "coop": None if own else p["title"]}
    return None


def ordered(text):
    """A name's words in order, "Saint" as "St.", generic words out: "Alexandria Area High School" is [alexandria]."""
    text = re.sub(r"\bh\.\s*s\.", "hs", re.sub(r"\bsaint\b", "st", str(text or "").lower()))
    return [w for w in re.findall(r"[a-z0-9]+", text) if w not in GENERIC]


def from_bound(school, read=lambda url: run.firecrawl(url, fmt="rawHtml")):
    """The logo the school shows on Bound, the app its teams post on (Jesse, 2026-11-09: "can we source from the bound
    app"), for a school the league's page has proved: a town can have several schools, so the logo must be that one
    school's. Its page sits at the school's name run together ("Mankato East High School": mankatoeast) and is
    titled "Bound | Mankato East Cougars High School Athletics and Activities": it counts only when that is the
    league's school with the league's nickname, word for word. One Firecrawl credit (Bound refuses our own fetch);
    None when Bound has no page for it."""
    slug = "".join(ordered(school["title"]))
    if not slug:
        return None
    page = read(BOUND + slug)
    t = re.search(r"<title>(.*?)</title>", page, re.S)
    og = (re.search(r'property="og:image"\s+content="([^"]+)"', page) or re.search(r'content="([^"]+)"\s+property="og:image"', page)
          or re.search(r'og:image"\s+content="([^"]+)"', page))
    title = re.sub(r"^\s*Bound\s*\|\s*|\s*Athletics and Activities\s*$", "", htmllib.unescape(t.group(1)) if t else "")
    if not og or BOUND_BRAND in og.group(1) or ordered(title) != ordered(school["title"]) + ordered(school["nickname"]):
        return None
    return {"logo": htmllib.unescape(og.group(1)), "page": BOUND + slug}


def wiki(params, opener=urllib.request.urlopen):
    """Wikipedia's API, 4 s apart. Its robots.txt is for crawlers; the API is how it asks to be read."""
    time.sleep(WIKI_GAP)
    req = urllib.request.Request(f"{WIKI}?{urllib.parse.urlencode({**params, 'format': 'json'})}", headers={"User-Agent": run.UA})
    with opener(req, timeout=30) as r:
        return json.load(r)


def from_wikipedia(team, ask=wiki):
    """The team's school's article on Wikipedia, when its title passes check 1, and its first image named like a
    logo; None when there is none."""
    hits = ask({"action": "query", "list": "search", "srsearch": f"{team['name']} school", "srlimit": 3})["query"]["search"]
    title = next((h["title"] for h in hits if names(h["title"], team["name"])), None)
    if not title:
        return None
    files = [f for f in ask({"action": "parse", "page": title, "prop": "images", "redirects": 1}).get("parse", {}).get("images", [])
             if WIKI_LOGO.search(f) and "commons-logo" not in f.lower()]
    if not files:
        return None
    info = next(iter(ask({"action": "query", "titles": "File:" + files[0], "prop": "imageinfo", "iiprop": "url",
                          "iiurlwidth": SIDE})["query"]["pages"].values()))["imageinfo"][0]
    return {"title": title, "logo": info.get("thumburl") or info["url"], "nickname": "", "colors": "", "town": "",
            "page": f"https://en.wikipedia.org/wiki/{urllib.parse.quote(title.replace(' ', '_'))}",
            "source": "Wikipedia", "coop": None}


# --- The logo itself ------------------------------------------------------------------------------------------------

def trimmed(im):
    """The logo cut to its own edges (its see-through border, or the white one it sits on) and fitted in SIDE px."""
    from PIL import Image, ImageOps
    im = im.convert("RGBA")
    alpha = im.getchannel("A")
    box = alpha.point(lambda a: 255 if a > 16 else 0).getbbox()
    if alpha.getextrema()[0] > 250:  # no see-through part: trim the white around it
        flat = Image.new("RGB", im.size, "white")
        flat.paste(im, mask=alpha)
        box = ImageOps.invert(flat.convert("L")).point(lambda v: 255 if v > 24 else 0).getbbox()
    im = im.crop(box or (0, 0, *im.size))
    im.thumbnail((SIDE, SIDE), Image.LANCZOS)
    return im


def colors(image, most=3, floor=0.04):
    """Up to three colours from a team's logo, most used first: BP app references/team-follow/team_colors.py, copied
    here as the cloud can't see that folder. See-through pixels and the white a logo sits on are skipped, near shades
    merge, and a colour under 4% of the logo's ink is dropped, so a thin outline never becomes a team colour."""
    image = image.convert("RGBA")
    image.thumbnail((160, 160))
    raw = image.tobytes()
    pixels = [tuple(raw[i:i + 4]) for i in range(0, len(raw), 4)]
    sums, counts = {}, Counter()
    for r, g, b, a in pixels:
        if a < 128 or min(r, g, b) > 235:
            continue
        key = (r // 32, g // 32, b // 32)
        counts[key] += 1
        s = sums.setdefault(key, [0, 0, 0, 0])
        s[0] += r; s[1] += g; s[2] += b; s[3] += 1
    total, picked = sum(counts.values()), []
    for key, n in counts.most_common():
        if n / total < floor or len(picked) == most:
            break
        r, g, b, c = sums[key]
        rgb = (r // c, g // c, b // c)
        if any(sum((x - y) ** 2 for x, y in zip(rgb, seen)) < 48 ** 2 for seen in picked):
            continue
        picked.append(rgb)
    return ["#%02X%02X%02X" % rgb for rgb in picked]


def png(im):
    out = io.BytesIO()
    im.save(out, "PNG", optimize=True)
    return out.getvalue()


def sheet(teams, folder, name="sheet"):
    """One sheet of the logos, each under its key and team, and the batch file the helper reads with it. Each team
    is {key, file, name, logo_of, coop, nickname, colors_said, town, sports, source}."""
    from PIL import Image, ImageDraw
    import place_photos
    cols = min(len(teams), 3)
    rows = (len(teams) + cols - 1) // cols
    im = Image.new("RGB", (cols * TILE + 20, rows * (TILE + 50) + 10), "white")
    d, f = ImageDraw.Draw(im), place_photos.font(20)
    path = folder / f"{name}.png"
    lines = [f"Sheet: {path}", ""]
    for i, t in enumerate(teams):
        x, y = (i % cols) * TILE + 10, (i // cols) * (TILE + 50) + 10
        place_photos.label(d, (x, y), f"{t['key']} · {t['name']}", f, TILE - 12)
        logo = Image.open(t["file"]).convert("RGBA")
        logo.thumbnail((TILE - 20, TILE - 20))
        im.paste(logo, (x + (TILE - 10 - logo.width) // 2, y + 36 + (TILE - 20 - logo.height) // 2), logo)
        lines.append(json.dumps({"team": t["key"], "name": t["name"], "logo_of": t["logo_of"],
                                 **({"co_op": f"{t['name']} plays as one team; this is its first school's logo"}
                                    if t.get("coop") else {}),
                                 **{k: t[k] for k in ("nickname", "town", "sports") if t.get(k)},
                                 **({"colors": t["colors_said"]} if t.get("colors_said") else {}),
                                 "from": t["source"]}, ensure_ascii=False))
    im.save(path)
    (folder / f"{name.replace('sheet', 'batch')}.txt").write_text("\n".join(lines) + "\n")
    return path


# --- The two steps --------------------------------------------------------------------------------------------------

def prepare(folder, db, today, league=from_league, wikipedia=from_wikipedia, bound=from_bound, grab=None):
    """Looks up today's teams, keeps each logo that passes check 1 (trimmed) and lays them out for the helper.
    Writes folder/found.json: the teams to check, and the ones not found with why."""
    from PIL import Image
    import place_photos
    grab = grab or place_photos.download
    for name in READINGS:  # an earlier prepare's answers: its keys were other teams'
        (folder.parent / name).unlink(missing_ok=True)
    if folder.exists():
        for f in folder.iterdir():
            f.unlink()
    folder.mkdir(parents=True, exist_ok=True)
    teams, later = todo(db, today)
    found, missed = [], []
    for t in teams:
        try:
            p = league(t)
            if p:  # the school's own logo on Bound first, the league's when Bound has none (Jesse, 2026-11-09)
                try:
                    b = bound(p)
                except Exception as e:  # no credits, Bound down: the league's logo
                    print(f"[logos] {p['title']} not read on Bound: {' '.join(str(e).split())[:120]}")
                    b = None
                if b:
                    p = {**p, **b, "source": "Bound"}
            else:
                p = wikipedia(t)
        except Exception as e:  # a page that won't answer: tried again another morning
            missed.append({**t, "why": f"its page didn't answer ({' '.join(str(e).split())[:100]})"})
            continue
        if not p:
            missed.append({**t, "why": "no school page names it (league or Wikipedia)"})
            continue
        if p["logo"] and p["logo"] in t.get("refused", []):  # taken down before: never put back on its own
            missed.append({**t, "why": f"{p['title']}'s page shows the logo taken down before"})
            continue
        if not p["logo"]:
            missed.append({**t, "why": f"{p['title']}'s page has no logo"})
            continue
        raw = folder / f"{t['id']}-raw.png"
        try:
            grab(p["logo"], raw)
        except Exception as e:
            missed.append({**t, "why": f"its logo wouldn't download ({' '.join(str(e).split())[:100]})"})
            continue
        im = trimmed(Image.open(raw))
        raw.unlink()
        dest = folder / f"{t['id']}.png"
        dest.write_bytes(png(im))
        found.append({**t, "key": f"t{len(found) + 1}", "file": str(dest), "logo_of": p["title"], "coop": p["coop"],
                      "nickname": p["nickname"], "colors_said": p["colors"], "town": p["town"], "page": p["page"],
                      "logo_url": p["logo"], "source": p["source"], "hex": colors(im)})
    if found:
        sheet(found, folder)
    (folder / "found.json.new").write_text(json.dumps({"today": str(today), "teams": found, "missed": missed, "later": later},
                                                  indent=1, ensure_ascii=False))
    (folder / "found.json.new").replace(folder / "found.json")  # whole or not at all
    print(f"[logos] {len(found)} logos to check, {len(missed)} teams not found, {later} for another morning"
          + (f" ({folder / 'batch.txt'})" if found else ""))
    return found


# The helper's two readings of the sheet: a logo goes live only on two yeses. One reading in about 20 says yes to a
# logo its own words had just ruled out ("SF is St. Francis, not St. Cloud"); two readings together never have.
READINGS = ("logos.jsonl", "logos-2.jsonl")


def answers_in(text):
    """The helper's JSON lines, by team key; a line that isn't one is skipped."""
    out = {}
    for ln in text.splitlines():
        try:
            a = json.loads(ln.strip().strip(","))
        except ValueError:
            continue
        if isinstance(a, dict) and isinstance(a.get("team"), str):
            out[a["team"]] = a
    return out


def keep(run_, dry_run=False):
    """Each logo with both yeses goes live; every team looked up today is one report line. Kept as the step's lines,
    so a finish run again neither writes nor reports twice. Anything that breaks is one line: finish catches only a
    database error, and a lost morning report costs more than a logo a day late."""
    try:
        return kept_lines(run_, dry_run)
    except Exception as e:
        return [f"[morning] team logos failed: {' '.join(str(e).split())[:200]}"]


def take_down(t):
    """The migration line that takes a logo down and keeps it down: the morning never puts back a logo refused."""
    q = lambda v: "'" + str(v).replace("'", "''") + "'"
    return (f"update public.teams set logo_url = null, color = null, colors = null, logo_refused = "
            f"array_append(logo_refused, {q(t['logo_url'])}) where id = {q(t['id'])};")


def kept_lines(run_, dry_run):
    folder = run_.folder / "logos"
    if not (folder / "found.json").exists():
        return []
    done = run_.part(f"logos/kept{'-dry-run' if dry_run else ''}.json")
    if done.saved is not None:
        return done.saved
    found = json.loads((folder / "found.json").read_text())
    readings = [answers_in(f.read_text() if f.exists() else "") for f in (run_.folder / n for n in READINGS)]
    lines = []
    for t in found["teams"]:
        said = [r.get(t["key"]) or {} for r in readings]
        whose = f"{t['logo_of']}'s, as its first school" if t.get("coop") else t["logo_of"]
        doubt = next((a for a in said if str(a.get("answer", "")).lower() != "yes"), None)
        if doubt is not None:
            why = (f"the check said {doubt['answer']}: {doubt.get('why', '')}".rstrip(": ") if doubt.get("answer")
                   else "the check gave no answer")
            lines.append(f"- Still waiting on a logo: {t['name']}: {whose} from {t['source']}, {why}")
            continue
        try:  # a white box shows its box on a game's page (game-card 26): a logo that can't be cleaned waits
            from PIL import Image
            import clean_logo
            im, did = clean_logo.clean(Image.open(t["file"]))
            data = png(im)
        except Exception as e:  # numpy missing, a file that won't decode, nothing left after the cut
            lines.append(f"- Still waiting on a logo: {t['name']}: {whose} from {t['source']}, its logo couldn't be "
                         f"cleaned ({' '.join(str(e).split())[:120]})")
            continue
        try:
            if not dry_run:
                path = f"places/teams/{t['id']}/logo-{hashlib.sha1(data).hexdigest()[:10]}.png"
                try:
                    run_.db.storage_put(path, data, "image/png")
                except DbError as e:  # there already from a finish run again: same bytes, same name
                    if "Duplicate" not in str(e.body) and "already exists" not in str(e.body):
                        raise
                url = f"{run_.db.url}/storage/v1/object/public/{path}"
                took = run_.db.rest("PATCH", f"teams?id=eq.{urllib.parse.quote(t['id'])}&logo_url=is.null&select=id",
                                    {"logo_url": url, "color": t["hex"][0] if t["hex"] else None,
                                     "colors": t["hex"] or None}, prefer="return=representation")
                if not took:  # it got a logo another way since prepare: that one stays
                    lines.append(f"- Logo already there: {t['name']} has one now, so the one found was left out")
                    continue
        except DbError as e:
            lines.append(f"[morning] team logo for {t['name']} failed: {' '.join(str(e).split())[:200]}")
            continue
        lines.append(f"- Logo live: {t['name']}, {whose} from {t['source']} ({t['page']}); its page names it and both readings "
                     f"said yes; {', '.join(did)}. Wrong? Take it down with a migration: {take_down(t)}" + (" (dry run: nothing written)" if dry_run else ""))
    lines += [f"- Still waiting on a logo: {m['name']}: {m['why']}" for m in found["missed"]]
    if found.get("later"):
        lines.append(f"- Still waiting on a logo: {found['later']} more teams, looked up on another morning")
    done.save(lines)
    return lines


# --- Self-test ------------------------------------------------------------------------------------------------------

def selftest():
    from PIL import Image
    from morning_run import Run, FakeDb
    checks = []
    ok = lambda cond, why: checks.append((bool(cond), why))
    order = lambda lines: sorted(lines, key=lambda ln: ("Logo live" not in ln, "Shanley" not in ln))

    ok(names("Mankato East High School", "Mankato East", "Mankato"), "a school's page names it")
    ok(names("Heritage Christian Academy", "Heritage Christian Academy Maple Grove", "Maple Grove"),
       "a name that carries its town is the school in that town")
    ok(names("Long Prairie-Grey Eagle H.S.", "Long Prairie-Grey Eagle", "Long Prairie"), "a hyphen is a space, H.S. a high school")
    ok(not names("Minnesota River Valley Academy", "Minnesota River", "Henderson"), "a longer name is another school")
    ok(not names("Lakeville North High School", "North", "Lakeville"), "the town is no part of the title's own name")
    ok(not names("Elk River High School", "Elk River-Zimmerman", "Elk River"), "one school is not the whole co-op")
    ok(names("Saint Francis High School", "St. Francis"), "Saint is St.")
    ok(first_school("Mounds View-Irondale-Roseville") == "Mounds View" and first_school("Shanley") is None,
       "a co-op's first school is the name before its first hyphen")

    db = FakeDb(answers={
        "club_events?": [{"team_ids": ["a", "z"], "sport": "Girls Hockey · JV"}, {"team_ids": ["a", "z"], "sport": "Girls Hockey"},
                         {"team_ids": ["b", "z"], "sport": "Boys Hockey"}, {"team_ids": ["c", "d"], "sport": None}],
        "teams?": [{"id": "a", "name": "A"}, {"id": "b", "name": "B"}, {"id": "c", "name": "C"}, {"id": "d", "name": "D"}]})
    got, later = todo(db, date.fromordinal(5), most=2)
    ok([t["id"] for t in got] == ["b", "c"] and later == 2, "the day picks where the rotation starts")
    ok(todo(db, date.fromordinal(4))[0][0] == {"id": "a", "name": "A", "refused": [], "sports": ["Girls Hockey"]},
       "a team's sports are its waiting games', level aside")

    search = ('<form id="views-exposed-form-schools-list"></form><ul><li><a href="/schools/becker-high-school">'
              '<span>Becker High School</span></a></li><li><a href="/schools/becker-ms">Becker Middle School</a></li></ul>')
    page = ('<title>Becker High School | Schools | MSHSL</title><h1><div>Becker High School</div></h1>'
            '<img src="/sites/default/files/styles/large/public/logos/2023/becker.png?itok=x&amp;y=1">'
            '<p>Nickname: Bulldogs</p><p>School Colors: Blue and Gold</p><p>1 Main St</p><p>Becker,</p><p>MN</p><p>55308</p>')
    asked = []

    def get(url):
        asked.append(url)
        if "?name=Becker-Big" in url:
            return 200, '<form id="views-exposed-form-schools-list"></form>'
        return 200, search if "?name=" in url else page
    p = from_league({"name": "Becker-Big Lake"}, get)
    ok(p and p["coop"] == "Becker High School" and p["nickname"] == "Bulldogs" and p["town"] == "Becker"
       and p["logo"] == "https://www.mshsl.org/sites/default/files/styles/large/public/logos/2023/becker.png?itok=x&y=1",
       "a co-op the league doesn't list takes its first school's page, logo, nickname and town")
    ok(sum("/schools/becker-" in u and "?" not in u for u in asked) == 1, "only a page whose listed name could pass is read")
    ok(from_league({"name": "Becker"}, get)["coop"] is None, "a school's own page is its own")
    ok(from_league({"name": "North Wright County"}, lambda u: (200, '<form id="views-exposed-form-schools-list"></form>')) is None,
       "no page: nothing")

    league = {"title": "Mankato East High School", "nickname": "Cougars"}
    seen = []

    def bound_page(title, image):
        return lambda url: seen.append(url) or (f'<title>Bound | {title}</title><meta property="og:image" content="{image}">')
    b = from_bound(league, bound_page("Mankato East Cougars High School Athletics and Activities", "https://cdn/me-Logo.png?a=1&amp;b=2"))
    ok(b == {"logo": "https://cdn/me-Logo.png?a=1&b=2", "page": "https://www.gobound.com/mn/schools/mankatoeast"}
       and seen == ["https://www.gobound.com/mn/schools/mankatoeast"], "Bound: the league's school, its name run together")
    ok(from_bound(league, bound_page("", "https://x/brand/ogimage.png")) is None, "Bound has no page for it: nothing")
    ok(from_bound({"title": "St. Cloud High School", "nickname": "Crush"},
                  bound_page("St. Cloud Christian Lions High School Athletics and Activities", "https://cdn/scc.png")) is None,
       "another school of the same town on Bound is not this one")
    ok(from_bound({"title": "Alexandria Area High School", "nickname": "Cardinals"},
                  bound_page("Alexandria Cardinals High School Athletics and Activities", "https://cdn/a.png")),
       "Area and High School are no part of the name")

    def ask(params):
        if params.get("list") == "search":
            return {"query": {"search": [{"title": "Shanley Catholic Schools"}, {"title": "Shanley High School"}]}}
        if params["action"] == "parse":
            return {"parse": {"images": ["Commons-logo.svg", "Shanley building.jpg", "Shanley Deacons logo.png"]}}
        return {"query": {"pages": {"1": {"imageinfo": [{"url": "u", "thumburl": "thumb"}]}}}}
    w = from_wikipedia({"name": "Shanley"}, ask)
    ok(w and w["title"] == "Shanley High School" and w["logo"] == "thumb", "Wikipedia: the article whose title names it, its logo file")

    red = Image.new("RGBA", (400, 300), (0, 0, 0, 0))
    for x in range(100, 300):
        for y in range(50, 250):
            red.putpixel((x, y), (194, 4, 48, 255) if x < 230 else (230, 180, 20, 255))
    ok(trimmed(red).size == (200, 200) and colors(trimmed(red))[0].startswith("#C"), "trimmed to its edges, red first")
    import clean_logo
    boxed = clean_logo.badge(side=600)
    white = Image.new("RGB", (300, 300), "white")
    white.paste((0, 0, 128), (100, 120, 200, 180))
    ok(trimmed(white).size == (100, 60), "a logo on white is trimmed to its ink")

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp) / "morning"
        teams = ["becker-big-lake", "nwc", "shanley", "elk", "lp"]
        db = FakeDb(answers={"club_events?": [{"team_ids": [t, "a"], "sport": "Boys Hockey"} for t in teams],
                             # the PATCH answers the row it changed: "lp" got a logo another way since prepare
                             "teams?id=eq.": lambda m, path, body: [] if "eq.lp" in path else [{"id": "x"}],
                             "teams?": [{"id": "becker-big-lake", "name": "Becker-Big Lake"}, {"id": "nwc", "name": "North Wright County"},
                                        {"id": "shanley", "name": "Shanley"},
                                        {"id": "elk", "name": "Elk River-Zimmerman", "logo_refused": [p["logo"]]},
                                        {"id": "lp", "name": "Long Prairie"}]})
        db.url = "https://db.example"
        (folder).mkdir()
        (folder / "logos-2.jsonl").write_text('{"team": "t1", "answer": "yes"}\n')  # an earlier prepare's
        db.storage_put = lambda path, data, kind: db.calls.append(("PUT", path, kind, data))
        pages = {"Becker-Big Lake": dict(p, page="https://www.mshsl.org/schools/becker-high-school"), "Shanley": None,
                 "North Wright County": None, "Elk River-Zimmerman": dict(p, page="e"),
                 "Long Prairie": dict(p, page="l", logo="https://x/lp.png")}
        found = prepare(folder / "logos", db, date(2026, 11, 10), league=lambda t: pages[t["name"]],
                        wikipedia=lambda t: w if t["name"] == "Shanley" else None,
                        bound=lambda p: {"logo": "https://cdn/lp.png", "page": "https://bound/lp"} if p["page"] == "l" else None,
                        grab=lambda url, dest: (boxed if url == p["logo"] else red).save(dest))
        batch = (folder / "logos" / "batch.txt").read_text().splitlines()
        ok(not (folder / "logos-2.jsonl").exists(), "an earlier prepare's answers go: their keys were other teams'")
        ok(len(found) == 3 and (folder / "logos" / "sheet.png").exists() and len(batch) == 5
           and next(json.loads(b) for b in batch[2:] if "Becker" in b)["co_op"].startswith("Becker-Big Lake plays as one team"),
           "the found logos go on one sheet, a co-op's line saying whose logo it is")
        key = {t["name"]: t["key"] for t in found}
        (folder / "logos.jsonl").write_text(f'{{"team": "{key["Becker-Big Lake"]}", "answer": "yes", "why": "a bulldog in blue"}}\n'
                                            f'prose\n{{"team": "{key["Shanley"]}", "answer": "yes", "why": "an S"}}\n')
        (folder / "logos-2.jsonl").write_text(f'{{"team": "{key["Becker-Big Lake"]}", "answer": "yes", "why": "a bulldog"}}\n'
                                              f'{{"team": "{key["Shanley"]}", "answer": "unsure", "why": "no name on it"}}\n')
        for f in ("logos.jsonl", "logos-2.jsonl"):
            with open(folder / f, "a") as out:
                out.write(f'{{"team": "{key["Long Prairie"]}", "answer": "yes"}}\n{{"team": ["t9"], "answer": "yes"}}\n')
        r = Run(folder, date(2026, 11, 10), db)
        lines = keep(r)
        puts = [c for c in db.calls if c[0] == "PUT"]
        patch = [c for c in db.calls if c[0] == "PATCH"]
        patch = [c for c in patch if "becker" in c[1]]
        ok(len(puts) == 2 and puts[0][1].startswith("places/teams/becker-big-lake/logo-") and len(patch) == 1
           and patch[0][1] == "teams?id=eq.becker-big-lake&logo_url=is.null&select=id"
           and patch[0][2]["logo_url"] == "https://db.example/storage/v1/object/public/" + puts[0][1]
           and patch[0][2]["colors"][0] == patch[0][2]["color"], "two yeses: the logo is saved once and the team takes it")
        lines = order(lines)
        put = Image.open(io.BytesIO(puts[0][3]))
        fill = put.getpixel((put.width // 4, put.height // 2))  # the badge's own white fill, left of its mark
        ok(put.size == (512, 512) and put.getpixel((0, 0))[3] == 0 and fill[3] == 255 and min(fill[:3]) > 230
           and "both readings said yes; cut off its white box, lit. Wrong?" in order(lines)[0],
           "a logo on a white box goes live cut off it, its own white kept, and the report says what was done")
        ok(lines[0].startswith("- Logo live: Becker-Big Lake, Becker High School's, as its first school")
           and f"logo_refused = array_append(logo_refused, '{p['logo']}') where id = 'becker-big-lake';" in lines[0],
           "the report says whose logo it is and how to take it down for good")
        ok(next(t for t in found if t["name"] == "Long Prairie")["source"] == "Bound"
           and next(t for t in found if t["name"] == "Becker-Big Lake")["source"] == "the state league",
           "Bound's logo when it has the school, the league's when not")
        ok("- Logo already there: Long Prairie has one now, so the one found was left out" in lines,
           "a team that got a logo another way since prepare keeps it, and the report doesn't call the found one live")
        ok("- Still waiting on a logo: Elk River-Zimmerman: Becker High School's page shows the logo taken down before" in lines,
           "a logo taken down is never put back")
        ok(lines[1] == "- Still waiting on a logo: Shanley: Shanley High School from Wikipedia, the check said unsure: no name on it",
           "anything but two yeses waits, and says why")
        ok("- Still waiting on a logo: North Wright County: no school page names it (league or Wikipedia)" in lines,
           "a team not found says so")
        n = len(db.calls)
        ok(order(keep(r)) == lines and len(db.calls) == n, "a finish run again neither writes nor reports twice")
        ok(keep(Run(Path(tmp) / "none", date(2026, 11, 10), db)) == [] and len(db.calls) == n,
           "a morning with no new team: no lines, nothing written")
        broken = Run(Path(tmp) / "broken", date(2026, 11, 10), db)
        (broken.folder / "logos").mkdir(parents=True)
        (broken.folder / "logos" / "found.json").write_text('{"teams": [{"key"')
        ok(keep(broken)[0].startswith("[morning] team logos failed:"), "a step that breaks is a line, never a lost report")
    ok(names("St. Cloud State University", "St. Cloud State"), "a college's article names it")

    failed = [why for good, why in checks if not good]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    return not failed


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("step", nargs="?", choices=["prepare", "keep"])
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
        prepare(r.folder / "logos", r.db, r.today)
    elif a.step == "keep":
        print("\n".join(keep(r, a.dry_run)))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
