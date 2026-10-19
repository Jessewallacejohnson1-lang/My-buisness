#!/usr/bin/env python3
"""Place photos: is each live place photo still on the page it came from, and what could replace a
stale one. The monthly photo refresh (sources/models/photos.md) runs it in the cloud; BP app's
place-photos skill imports its picture-finding from here, so there is one copy.

    python3 sources/scripts/place_photos.py check [--logos]      every live photo (or logo) against its page:
                                                                  .runs/photos/check-<kind>.json, stale ones printed
    python3 sources/scripts/place_photos.py candidates           the pages of each stale photo and of every place
                                                                  still without a real photo, their pictures drawn
                                                                  on .runs/photos/sheet-<n>.png
    python3 sources/scripts/place_photos.py propose <key> <n>    candidate n saved as a proposal: <key> is a stale
                                                                  row's id (it takes that slot) or an entry id (a
                                                                  first photo); the app shows none until Jesse's yes
    python3 sources/scripts/place_photos.py --selftest

`check` reads and `propose` writes with SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (the morning job's
keys); pages and pictures are read with run.py's polite fetch (robots.txt, crawl-delay, one request
per server). A photo is matched by its fingerprint (a difference hash), so the check works however the
photo was added. Jesse's own walk photos have no page, and a Facebook or Instagram page is read only
through Apify (ADR-020): both are skipped.
"""
import concurrent.futures as cf
import hashlib
import html as htmllib
import io
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from datetime import date
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run  # noqa: E402  (the polite fetch)

TOWN = 'st-joseph'
OUT = Path(__file__).resolve().parents[2] / '.runs' / 'photos'
LONG_SIDE = 1600  # the feed hero asks for 1200 px; a little more for the 3x detail view
MIN_PHOTO = 200  # short side
STALE_DAYS = 365
WALK_CREDIT = 'Block Party'
SOCIAL = re.compile(r'(^|\.)(facebook|instagram)\.com$')

EXT = r'\.(?:jpe?g|png|webp)(?:\?[^"\'\s)]*)?'
ATTR = re.compile(r'(?:src|data-src|data-lazy-src|data-bg|data-image|data-original|href|content)\s*=\s*["\']([^"\']+?'
                  + EXT + r')["\']', re.I)
SRCSET = re.compile(r'srcset\s*=\s*["\']([^"\']+)["\']', re.I)
IMG_ATTR = re.compile(r'\b(?:src|data-[\w-]*(?:src|load|image|original))\s*=\s*["\']([^"\']+)["\']', re.I)
ALT = re.compile(r'\balt\s*=\s*["\']([^"\']*)["\']', re.I)
BG = re.compile(r'url\(\s*["\']?([^"\')]+?' + EXT + r')["\']?\s*\)', re.I)
SHARE_KEYS = ('og:image', 'og:image:url', 'og:image:secure_url', 'twitter:image', 'twitter:image:src')
NOT_PHOTO = re.compile(r'logo|icon|favicon|sprite|badge|placeholder|blank|spacer|avatar|emoji|gravatar|arrow|button|'
                       r'loader|pixel|1x1|facebook|instagram|twitter|youtube|linkedin|pinterest|google(?!usercontent)|yelp|tripadvisor|'
                       r'bbb|visa|mastercard|paypal|apple-pay|seal|award|cookie', re.I)
# Google Sites serve every photo from lh*.googleusercontent.com with no extension, and the link dies within
# minutes (St. Joseph Farmers' Market, 2026-10-19). That host's robots.txt doesn't answer, so the polite
# fetch waits 10 s between its pictures: they go first, before the page's other pictures.
EXPIRING = re.compile(r'googleusercontent\.com/', re.I)
# File names (or alt text) that usually mean the place itself, tried before the rest of the page
PLACE_WORDS = re.compile(r'interior|exterior|inside|outside|store|shop|front|building|location|dining|patio|room|'
                         r'team|staff|about|space|venue|crew|owner|family|lobby|office|bar|kitchen|cafe|restaurant|park',
                         re.I)
SOCIAL_ICON = r'facebook|instagram|twitter|x-logo|tiktok|youtube|linkedin|yelp|pinterest|tripadvisor|google|apple-pay|visa|mastercard'
COMMONS = 'https://commons.wikimedia.org/w/api.php'


# --- Reading a page's pictures -----------------------------------------------------------------------

def metas(page):
    for tag in re.findall(r'<meta\b[^>]*>', page, re.I):
        key = re.search(r'(?:property|name)\s*=\s*["\']([^"\']+)', tag, re.I)
        val = re.search(r'content\s*=\s*["\']([^"\']+)', tag, re.I)
        if key and val:
            yield key.group(1).strip().lower(), htmllib.unescape(val.group(1).strip())


def full_size(u):
    """The original upload behind a resized copy a site builder serves: WordPress's -300x120,
    Shopify's _400x, Wix's /v1/fill/... transform, Squarespace's format=750w."""
    u = re.sub(r'(/wp-content/uploads/.+)-\d+x\d+(\.\w+)(\?|$)', r'\1\2\3', u)
    if 'shopify' in u or '/cdn/shop/' in u:
        u = re.sub(r'_(\d+x\d*|x\d+)(@\dx)?(\.\w+)(\?|$)', r'\3\4', u)
    u = re.sub(r'(static\.wixstatic\.com/media/[^/]+)/v1/.*', r'\1', u)
    return re.sub(r'format=\d+w', 'format=2500w', u)


def from_page(page, base):
    """Every picture a page names, with its alt text: its share picture, img and srcset (the
    biggest), backgrounds, and an <img>'s lazy or extension-less source (CivicPlus city sites serve
    /ImageRepository/Document?documentID=1638, and put a slideshow's photos in data-delay-load)."""
    found = [(v, '') for k, v in metas(page) if k in SHARE_KEYS]
    for m in re.finditer(r'<[^>]+>|url\([^)]*\)', page):
        tag = m.group(0)
        alt = (ALT.findall(tag) or [''])[0]
        sets = SRCSET.findall(tag)
        if sets:  # the last entry of a srcset is its biggest
            found.append((sets[0].split(',')[-1].strip().split(' ')[0], alt))
        urls = ATTR.findall(tag) + BG.findall(tag)
        if tag[:4].lower() == '<img':
            urls += IMG_ATTR.findall(tag)
        found += [(u, alt) for u in urls]
    # a browser reads Documents\41\IMG.JPG as Documents/41/IMG.JPG (stjosephmn.gov's park photos)
    return [(urllib.parse.urljoin(base, u.replace('&amp;', '&').replace('\\', '/')), alt) for u, alt in found
            if not u.startswith('data:')]


def from_browser(item):
    """The same, from what Apify's browser saw on a page built in the browser."""
    return ([(item['og'], '')] if item.get('og') else []) + [(b['src'], '') for b in item.get('bgs') or []] + [
        (i['src'], i.get('alt') or '') for i in item.get('imgs') or []
        if not re.search(r'logo|brand', i.get('cls') or '', re.I)]


def photo_urls(found):
    """Of [(url, alt)], the pictures that may be photos, each once, at full size; place-named ones
    (by file name or alt text) first."""
    seen, out = set(), []
    for u, alt in found:
        u = full_size(u)
        # ?ver=2 on a .jpg is the same file; on /Document?documentID=1638 the query is the file
        key = re.sub(r'(\.(?:jpe?g|png|webp))\?.*', r'\1', u.split('#')[0], flags=re.I)
        if key not in seen and not NOT_PHOTO.search(u) and not NOT_PHOTO.search(alt):
            seen.add(key)
            out.append((u, alt))
    out.sort(key=lambda x: (not EXPIRING.search(x[0]),
                            not (PLACE_WORDS.search(x[0].rsplit('/', 1)[-1]) or PLACE_WORDS.search(x[1]))))
    return [u for u, _ in out]


def logo_urls(page, base):
    """Logo image URLs on a page, most likely first: 'logo' files, then icons, then the share picture."""
    found = []
    for m in re.finditer(r'<(?:img|link|meta|source)[^>]+>', page, re.I):
        tag = m.group(0)
        if not re.search(r'logo|og:image|apple-touch-icon|brand', tag, re.I) or re.search(SOCIAL_ICON, tag, re.I):
            continue  # a footer's Facebook or Yelp icon is "logo" too, and isn't theirs
        for u in re.findall(r'(?:src|href|content|data-src|srcset)="([^"\s]+)', tag):
            u = urllib.parse.urljoin(base, u.replace('&amp;', '&'))
            if re.search(r'\.(png|jpe?g|svg|webp)(\?|$)|format=', u, re.I):
                found.append((1 if 'og:image' in tag else 0, 0 if re.search(r'logo|brand', u, re.I) else 1, u))
    return list(dict.fromkeys(u for *_, u in sorted(found)))


def commons(query, n=4):
    """Freely licensed photos for a search on Wikimedia Commons: free to store with a credit."""
    params = {'action': 'query', 'format': 'json', 'generator': 'search', 'gsrsearch': f'filetype:bitmap {query}',
              'gsrnamespace': 6, 'gsrlimit': n, 'prop': 'imageinfo', 'iiprop': 'url|extmetadata', 'iiurlwidth': LONG_SIDE}
    req = urllib.request.Request(f'{COMMONS}?{urllib.parse.urlencode(params)}', headers={'User-Agent': run.UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        pages = (json.loads(r.read()).get('query') or {}).get('pages', {}).values()
    out = []
    for p in sorted(pages, key=lambda p: p.get('index', 0)):
        ii = p['imageinfo'][0]
        meta = ii.get('extmetadata', {})
        out.append({'url': ii.get('thumburl') or ii['url'], 'page': ii['descriptionurl'], 'source': 'commons',
                    'licence': (meta.get('LicenseShortName') or {}).get('value'),
                    'author': re.sub(r'<[^>]+>', '', (meta.get('Artist') or {}).get('value', '')).strip()[:80]})
    return out


def credit(c):
    """A free photo names its author and licence; a website photo has none (the app shows its site)."""
    return f"{c.get('author') or 'Unknown'} · {c['licence']}" if c.get('licence') else None


def download(url, dest, svg_to_png=None):
    """One image to dest (.png, long side at most 1600 px) through the polite fetch's rules; its (w, h).
    An SVG needs `svg_to_png(svg, png, px)` (the skill passes Chrome's); without it, it is refused."""
    p = urllib.parse.urlparse(url)
    server = run.server_of(p.netloc)
    with run._host_lock[server]:
        wait = run.SERVER_GAP - (time.monotonic() - run._server_hit.get(server, -run.SERVER_GAP))
        if wait > 0:
            time.sleep(wait)
        run._server_hit[server] = time.monotonic()
        if not run.robots_ok(url):
            raise RuntimeError('robots.txt disallows')
        run._respect_crawl_delay(url)
        with run._open(urllib.request.Request(url, headers={'User-Agent': run.UA})) as r:
            data = r.read(15_000_000)
    if data.lstrip()[:5].lower() in (b'<?xml', b'<svg ') or url.lower().split('?')[0].endswith('.svg'):
        if not svg_to_png:
            raise RuntimeError('an SVG (no renderer here)')
        svg = dest.with_suffix('.svg')
        svg.write_bytes(data)
        svg_to_png(svg, dest, 1024)
        im = Image.open(dest)
    else:
        im = Image.open(io.BytesIO(data))
        im.load()
    im = ImageOps.exif_transpose(im).convert('RGBA')
    im.thumbnail((LONG_SIDE, LONG_SIDE))
    im.save(dest)
    return im.size


# --- Looking at pictures -----------------------------------------------------------------------------

def kind(im):
    """photo or graphic, by colour count and flat fill: a first sort, the sheet gets looked at."""
    im = im.convert('RGBA')
    if im.getchannel('A').getextrema()[0] < 250:
        return 'graphic'
    raw = im.convert('RGB').resize((64, 64)).tobytes()  # not getdata(): Pillow 12 deprecates it
    px = list(zip(raw[0::3], raw[1::3], raw[2::3]))
    buckets = {(r // 16, g // 16, b // 16) for r, g, b in px}
    top = Counter(px).most_common(1)[0][1] / len(px)
    return 'photo' if len(buckets) > 180 and top < 0.25 else 'graphic'


def dhash(im, n=8):
    """A picture's fingerprint that survives resizing and recompression (difference hash)."""
    g = list(im.convert('L').resize((n + 1, n)).tobytes())
    return sum(1 << i for i in range(n * n) if g[i // n * (n + 1) + i % n] > g[i // n * (n + 1) + i % n + 1])


def drawn(im):
    """A logo's drawn part: on white, the blank border (or a square's padding) trimmed. A saved logo
    is cut off its page and squared, so only this part matches the file on the page."""
    im = im.convert('RGBA')
    flat = Image.new('RGB', im.size, 'white')
    flat.paste(im, mask=im.getchannel('A'))
    box = ImageOps.invert(flat.convert('L')).point(lambda v: 255 if v > 24 else 0).getbbox()
    return flat.crop(box) if box else flat


def same_picture(a, b):
    return bin(a ^ b).count('1') <= 10


def verdict(row, page_hashes, today, complete=True):
    """ok; gone (its page answers 404 or 410); changed (every picture on the page was read and none is
    it); old (over a year); or unsure (the page or some of its pictures didn't answer, so the photo may
    be among them: a slow city site timed out 16 times on 2026-10-18 and each looked "changed")."""
    if page_hashes is None:
        return 'gone' if complete else 'unsure'
    if not any(same_picture(row['hash'], h) for h in page_hashes):
        return 'changed' if complete else 'unsure'
    return 'old' if (today - date.fromisoformat(row['added_at'][:10])).days > STALE_DAYS else 'ok'


def webp(im, logo=False):
    """A photo at most 1600 px; a logo square (Search's logo view draws into a square), see-through."""
    if logo:
        im = im.convert('RGBA')
        side = max(im.size)
        sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
        sq.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
        im = sq
        im.thumbnail((1024, 1024), Image.LANCZOS)
    else:
        im = im.convert('RGB')
        im.thumbnail((LONG_SIDE, LONG_SIDE), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, 'WEBP', quality=90 if logo else 80, method=6)
    return buf.getvalue()


def font(size):
    try:
        return ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', size)
    except OSError:  # the cloud has no Mac fonts
        return ImageFont.load_default(size)


def label(d, xy, text, f, width, fill=(30, 30, 30)):
    while f.getlength(text) > width and len(text) > 4:
        text = text[:-2] + '…'
    d.text(xy, text, fill=fill, font=f)


# --- The database ------------------------------------------------------------------------------------

def api(method, path, body=None, headers=None):
    """One call to the project's REST or Storage API with the service key from the environment."""
    url, key = os.environ.get('SUPABASE_URL', '').rstrip('/'), os.environ.get('SUPABASE_SERVICE_ROLE_KEY', '')
    if not url or not key:
        sys.exit('needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment (never in the repo)')
    data = body if isinstance(body, bytes) or body is None else json.dumps(body).encode()
    h = {'apikey': key, 'Authorization': f'Bearer {key}', **({} if isinstance(body, bytes) else {'Content-Type': 'application/json'}),
         **(headers or {})}
    with urllib.request.urlopen(urllib.request.Request(url + path, data, h, method=method), timeout=60) as r:
        text = r.read()
    return json.loads(text) if text.strip() else None


def public_url(path):
    return f"{os.environ['SUPABASE_URL'].rstrip('/')}/storage/v1/object/public/places/{urllib.parse.quote(path)}"


# --- The monthly check ----------------------------------------------------------------------------

def deadline(minutes):
    """When a timed part stops starting new work (None: never); a part's work then has 3 minutes to end."""
    return time.monotonic() + minutes * 60 if minutes else None


def late(stop, grace=0):
    return stop is not None and time.monotonic() > stop + grace


def check(logos=False, rows=None, minutes=None):
    """Every live photo (or logo) against its page: .runs/photos/check-<kind>.json, one row each with its
    verdict. Changes nothing. `rows` lets the skill pass its own read of the table. With `minutes`, it
    reads pages for about that long and saves them (.runs/photos/pages-<kind>.json); run it again
    until it prints its summary (a cloud command must end within 10 minutes)."""
    kind_ = 'logo' if logos else 'photo'
    stop = deadline(minutes)
    if rows is None:
        rows = api('GET', f'/rest/v1/place_photos?select=id,entry_id,position,url,source_url,credit,added_at'
                          f'&status=eq.live&kind=eq.{kind_}&order=entry_id,position')
    skipped = [r for r in rows if r['credit'] == WALK_CREDIT or SOCIAL.search(urllib.parse.urlparse(r['source_url']).netloc)]
    rows = [r for r in rows if r not in skipped]
    tmp = OUT / 'check'
    tmp.mkdir(parents=True, exist_ok=True)
    saved_f = OUT / f'pages-{kind_}.json'
    saved = json.loads(saved_f.read_text()) if saved_f.exists() else {}
    if saved.get('day') != str(date.today()):
        saved = {'day': str(date.today()), 'hashes': {}, 'pages': {}, 'tries': {}}
    for r in rows:
        if str(r['id']) not in saved['hashes']:
            with urllib.request.urlopen(r['url'], timeout=30) as f:
                im = Image.open(io.BytesIO(f.read()))
                saved['hashes'][str(r['id'])] = dhash(drawn(im) if logos else im)
        r['hash'] = saved['hashes'][str(r['id'])]
    pages = {}
    for r in rows:
        pages.setdefault(r['source_url'], []).append(r)

    def read(item):
        """(page, its pictures' fingerprints or None, why, whether every picture answered); None when
        the part's time ran out first."""
        n, (page, mine) = item
        if late(stop):
            return None
        try:
            _, html = run.fetch(page)
            base = run.final_url.get(page, page)
        except urllib.error.HTTPError as x:
            return page, None, f'HTTP {x.code}', x.code in (404, 410)
        except Exception as x:
            return page, None, str(x)[:80], False
        urls = (logo_urls(html, base)[:6] if logos else []) + photo_urls(from_page(html, base))
        hashes, failed = [], 0
        for i, u in enumerate(urls):
            if late(stop, 180):
                if saved['tries'].get(page):  # its second part out of time too: what it read stands
                    failed += 1
                    break
                saved['tries'][page] = 1
                return None  # read again in the next part
            if i == 40:
                failed += 1  # a page with this many pictures: the rest stay unread
                break
            for attempt in (1, 2):  # a slow server gets a second try
                try:
                    download(u, tmp / f'{n}-{i}.png')
                    im = Image.open(tmp / f'{n}-{i}.png')
                    hashes.append(dhash(drawn(im) if logos else im))
                    break
                except urllib.error.HTTPError as x:
                    if x.code in (404, 410):
                        break  # a dead picture link: that picture is gone
                    failed += attempt == 2
                except RuntimeError:
                    break  # robots refuses it, or an SVG: never one of the photos
                except Exception:
                    failed += attempt == 2
            if all(any(same_picture(r['hash'], h) for h in hashes) for r in mine):
                break  # every saved picture from this page is found: no need to read the rest
        if not hashes:  # a page built in the browser shows a plain read no pictures: that proves nothing
            return page, hashes, 'no pictures readable on the page', False
        return page, hashes, f'{failed} pictures did not answer' if failed else None, not failed
    todo = [(n, item) for n, item in enumerate(pages.items()) if item[0] not in saved['pages']]
    with cf.ThreadPoolExecutor(6) as pool:
        for got in pool.map(read, todo):
            if got:
                saved['pages'][got[0]] = got[1:]
    saved_f.write_text(json.dumps(saved))
    left = [p for p in pages if p not in saved['pages']]
    if left:
        print(f"{len(pages) - len(left)} of {len(pages)} pages read; run check{' --logos' if logos else ''} again")
        return None
    today = date.today()
    out = []
    for r in rows:
        hashes, why, complete = saved['pages'][r['source_url']]
        out.append({k: r[k] for k in ('id', 'entry_id', 'position', 'url', 'source_url', 'credit', 'added_at', 'hash')}
                   | {'kind': kind_, 'verdict': verdict(r, hashes, today, complete), 'why': why})
    by = Counter(o['verdict'] for o in out)
    print(f"{len(out)} live {kind_}s checked against {len(pages)} pages: {by['ok']} ok, {by['changed']} changed, "
          f"{by['gone']} page gone, {by['old']} over a year old, {by['unsure']} unsure (their page or pictures "
          f"didn't answer); {len(skipped)} skipped (walk or social)")
    for o in out:
        if o['verdict'] != 'ok':
            print(f"  {o['verdict']:8} {o['entry_id']} (row {o['id']}, {kind_} {o['position']}) {o['source_url']}"
                  + (f" ({o['why']})" if o['why'] else ''))
    (OUT / f'check-{kind_}.json').write_text(json.dumps(out, indent=1))
    return out


def without_photo(entries):
    """Every place people see that still has no real photo (Jesse, 2026-10-18: re-read every month, the
    first pass missed some): app places and the places upcoming found events happen at, each with
    its pages (the app's website and the registry's)."""
    places = api('GET', '/rest/v1/places?select=entry_id,links&entry_id=not.is.null')
    events = api('GET', f'/rest/v1/club_events?select=place_entry_id&source_uid=not.is.null'
                        f'&event_date=gte.{date.today()}&place_entry_id=not.is.null')
    have = {r['entry_id'] for r in api('GET', '/rest/v1/place_photos?select=entry_id&kind=eq.photo'
                                              '&status=in.(live,proposed)')}
    sites = {}
    for p in places:
        sites.setdefault(p['entry_id'], []).extend(l['url'] for l in p['links'] or [] if l.get('kind') == 'website')
    for e in {r['place_entry_id'] for r in events}:
        sites.setdefault(e, [])
    out = []
    for eid in sorted(set(sites) - have):
        e = entries.get(eid, {})
        pages = sites[eid] + [s['url'] for s in e.get('sources') or []
                              if s.get('kind') == 'website' and s.get('url', 'TODO') != 'TODO']
        out.append({'entry_id': eid, 'pages': list(dict.fromkeys(pages))})
    return out


def candidates(minutes=None):
    """For each stale photo in check-photo.json, the pictures on its page now (for a free photo, Commons' for
    the place's name), and for each place still without a real photo, the pictures on its pages;
    downloaded as .runs/photos/<key>/c<n>.png (the place's live photos left out) and drawn on numbered
    contact sheets. <key> is the stale row's id, or the entry id of a place with no photo. With
    `minutes`, like check: run it again until it draws the sheets."""
    stop = deadline(minutes)
    import registry
    entries = {e['id']: e for e in registry.load(registry.find_root(Path(__file__).parent))[0]}
    names = {k: e['_name'] for k, e in entries.items()}
    stale = [r for r in json.loads((OUT / 'check-photo.json').read_text()) if r['verdict'] in ('changed', 'gone', 'old')]
    jobs = [{'key': str(r['id']), 'entry_id': r['entry_id'], 'position': r['position'], 'verdict': r['verdict'],
             'hash': r['hash'], 'pages': [r['source_url']]} for r in stale]
    jobs += [{'key': w['entry_id'], 'entry_id': w['entry_id'], 'position': None, 'verdict': 'no photo yet',
              'hash': None, 'pages': w['pages']} for w in without_photo(entries)]
    live = api('GET', '/rest/v1/place_photos?select=entry_id,url&status=in.(live,proposed)')
    done_f = OUT / 'candidates.json'
    result = json.loads(done_f.read_text()) if done_f.exists() else {}
    if result.get('_day') != str(date.today()):
        result = {'_day': str(date.today())}
    for r in jobs:
        if r['key'] in result:
            continue
        if late(stop):
            break
        folder = OUT / r['key']
        folder.mkdir(parents=True, exist_ok=True)
        known = [r['hash']] if r['hash'] is not None else []
        for x in live:
            if x['entry_id'] == r['entry_id']:
                with urllib.request.urlopen(x['url'], timeout=30) as f:
                    known.append(dhash(Image.open(io.BytesIO(f.read()))))
        found, why = [], None
        for page in r['pages']:
            try:
                if 'commons.wikimedia.org' in page:
                    found += commons(f"{names.get(r['entry_id'], r['entry_id'])} Minnesota")
                else:
                    _, html = run.fetch(page)
                    found += [{'url': u, 'page': page, 'source': 'site'}
                              for u in photo_urls(from_page(html, run.final_url.get(page, page)))[:12]]
            except Exception as x:
                why = str(x)[:80]
        if not r['pages']:
            why = 'no website to read'
        cands = []
        for f in found:
            n = len(cands) + 1
            try:
                w, h = download(f['url'], folder / f'c{n}.png')
                im = Image.open(folder / f'c{n}.png')
            except Exception:
                continue
            if min(w, h) < MIN_PHOTO or any(same_picture(dhash(im), k) for k in known):
                (folder / f'c{n}.png').unlink()
                continue
            cands.append({**f, 'n': n, 'px': [w, h], 'kind': kind(im)})
        result[r['key']] = {'entry_id': r['entry_id'], 'name': names.get(r['entry_id'], r['entry_id']),
                            'position': r['position'], 'verdict': r['verdict'], 'why': why, 'cands': cands}
        done_f.write_text(json.dumps(result, indent=1, ensure_ascii=False))
    done_f.write_text(json.dumps(result, indent=1, ensure_ascii=False))
    left = [r for r in jobs if r['key'] not in result]
    if left:
        print(f'{len(jobs) - len(left)} of {len(jobs)} read; run candidates again')
        return None
    result = {k: v for k, v in result.items() if not k.startswith('_')}
    files = sheets(result)
    print(f"{len(stale)} stale photos, {len(jobs) - len(stale)} places without a photo; "
          f"{sum(1 for v in result.values() if v['cands'])} with candidates; sheets:", *files)
    for k, v in result.items():
        if not v['cands']:
            print(f"  {v['name']} ({k}): nothing found" + (f" ({v['why']})" if v['why'] else ''))
    return result


def sheets(result, per=6, cols=5):
    """Contact sheets, one block per stale photo: every candidate numbered, with its size and kind."""
    tw, th, gap = 300, 210, 8
    blocks = [(rid, v) for rid, v in result.items() if v['cands']]
    files = []
    for s in range(0, len(blocks), per):
        chunk = blocks[s:s + per]
        height = 10 + sum(34 + -(-len(v['cands']) // cols) * (th + 24) for _, v in chunk)
        sheet = Image.new('RGB', (cols * (tw + gap) + gap, height), 'white')
        d = ImageDraw.Draw(sheet)
        y = 10
        for rid, v in chunk:
            label(d, (gap, y + 4), f"{v['name']}  (key {rid}, {v['verdict']})", font(20), cols * (tw + gap))
            y += 34
            for i, c in enumerate(v['cands']):
                x, cy = gap + (i % cols) * (tw + gap), y + (i // cols) * (th + 24)
                d.rectangle([x, cy, x + tw, cy + th], fill=(236, 236, 236))
                im = Image.open(OUT / rid / f"c{c['n']}.png").convert('RGBA')
                im.thumbnail((tw, th))
                sheet.paste(im, (x + (tw - im.width) // 2, cy + (th - im.height) // 2), im)
                d.rectangle([x, cy, x + 34, cy + 28], fill='black')
                d.text((x + 6, cy + 2), str(c['n']), fill='white', font=font(22))
                label(d, (x, cy + th + 3), f"{c['px'][0]}×{c['px'][1]}  {c['kind']}" + (f"  {c['licence']}" if c.get('licence') else ''),
                      font(13), tw, (90, 90, 90))
            y += -(-len(v['cands']) // cols) * (th + 24)
        f = OUT / f'sheet-{s // per + 1}.png'
        sheet.save(f)
        files.append(str(f))
    return files


def propose(key, n):
    """Candidate n, uploaded and saved as a proposal (status 'proposed', which the app never reads): a
    stale row's in that row's slot, a first photo after the place's live rows. Jesse's yes on the
    review page swaps it in (the skill's `swap`)."""
    v = json.loads((OUT / 'candidates.json').read_text())[str(key)]  # KeyError: not a key on the sheets
    c = next(x for x in v['cands'] if x['n'] == n)
    if v['position'] is None:  # a first photo: the next free slot (a live logo keeps its own)
        taken = [r['position'] for r in api('GET', f"/rest/v1/place_photos?select=position&entry_id=eq.{v['entry_id']}"
                                                   '&status=in.(live,proposed)')]
        v['position'] = max(taken) + 1 if taken else 0
    data = webp(Image.open(OUT / str(key) / f'c{n}.png'))
    width, height = Image.open(io.BytesIO(data)).size  # the Town card takes the photo's shape before it loads
    path =f"{TOWN}/{v['entry_id']}/photo-{hashlib.sha1(data).hexdigest()[:10]}.webp"
    try:
        api('POST', f'/storage/v1/object/places/{urllib.parse.quote(path)}', data,
            {'Content-Type': 'image/webp', 'x-upsert': 'false', 'cache-control': 'max-age=31536000'})
    except urllib.error.HTTPError as x:
        if x.code not in (400, 409):  # the same file from an earlier, interrupted run
            raise
    api('POST', '/rest/v1/place_photos', [{'entry_id': v['entry_id'], 'town': TOWN, 'url': public_url(path),
                                           'source_url': c['page'], 'position': v['position'], 'status': 'proposed',
                                           'kind': 'photo', 'credit': credit(c), 'proposed_by': 'the monthly refresh',
                                           'width': width, 'height': height}],
        {'Prefer': 'return=minimal'})
    print(f"{v['entry_id']}: proposed" + (f" in place of row {key}" if str(key).isdigit() else ' as its first photo')
          + f" (position {v['position']})")


# --- Self-test ------------------------------------------------------------------------------------

def selftest():
    page = ('<meta property="og:image" content="/share.jpg"><img src="/a/storefront.jpg">'
            '<img srcset="/s-300.jpg 300w, /s-1200.jpg 1200w"><div style="background:url(\'/bg.webp\')"></div>'
            '<img src="/img/logo.png"><img data-src="/team-1.png"><img src="/Docs\\41\\park.JPG">')
    found = from_page(page, 'https://x.com/')
    urls = [u for u, _ in found]
    civic = from_page('<img src="data:image/gif;base64,R0" data-delay-load="/ImageRepository/Document?documentID=1641" '
                      'alt="Outside Picnic Tables"><img src="/ImageRepository/Document?documentID=2615" alt="Facebook">'
                      '<img src="/ImageRepository/Document?documentID=2616" alt="Homepage">', 'https://city.gov/x')
    red = Image.new('RGBA', (120, 60), (220, 30, 30, 255))
    rnd = random.Random(1)
    noise = Image.frombytes('RGB', (64, 64), bytes(rnd.randrange(256) for _ in range(64 * 64 * 3)))
    logo_on_white = Image.new('RGB', (400, 200), 'white')
    ImageDraw.Draw(logo_on_white).rectangle([60, 40, 340, 160], fill=(200, 30, 40))
    ImageDraw.Draw(logo_on_white).ellipse([150, 70, 250, 130], fill=(20, 20, 90))
    squared_cut = Image.new('RGBA', (500, 500), (0, 0, 0, 0))
    squared_cut.paste(logo_on_white.crop((60, 40, 341, 161)).convert('RGBA').resize((420, 181)), (40, 160))
    checks = [
        ("a page gives its share picture, img, srcset's biggest, background, lazy src",
         all(f'https://x.com/{u}' in urls for u in ('share.jpg', 'a/storefront.jpg', 's-1200.jpg', 'bg.webp', 'team-1.png',
                                                     'Docs/41/park.JPG'))),
        ('logos and icons are not photos, place-named files go first',
         photo_urls(found + [('https://x.com/i/facebook.png', '')])[:2] == ['https://x.com/a/storefront.jpg', 'https://x.com/team-1.png']
         and not any('logo' in u or 'facebook' in u for u in photo_urls(found))),
        ("a lazy, extension-less <img> counts; its alt text sorts and filters it",
         photo_urls(civic) == ['https://city.gov/ImageRepository/Document?documentID=1641',
                               'https://city.gov/ImageRepository/Document?documentID=2616']),
        ("a Google Sites photo counts and goes first (its link dies in minutes), Google's own badge does not",
         photo_urls([('https://x.com/shop-front.jpg', ''), ('https://lh3.googleusercontent.com/sitesv/AAbc=w1280', ''),
                     ('https://x.com/google-badge.png', '')]) ==
         ['https://lh3.googleusercontent.com/sitesv/AAbc=w1280', 'https://x.com/shop-front.jpg']),
        ('?ver= on a .jpg is one file', len(photo_urls([('https://x.com/a.jpg?ver=1', ''), ('https://x.com/a.jpg?ver=2', '')])) == 1),
        ('a resized WordPress copy becomes its original',
         photo_urls([('https://x.com/wp-content/uploads/p-300x200.jpg', '')]) == ['https://x.com/wp-content/uploads/p.jpg']),
        ("a page's logo file comes before its share picture, a footer's Facebook icon never",
         logo_urls('<meta property="og:image" content="/share.jpg"><img src="/i/facebook-logo.png"><img class="logo" src="/l.svg">',
                   'https://x.com/') == ['https://x.com/l.svg', 'https://x.com/share.jpg']),
        ('a flat fill is a graphic, noise is a photo', kind(red) == 'graphic' and kind(noise) == 'photo'),
        ('a resized, recompressed copy is the same picture; another picture is not',
         same_picture(dhash(noise), dhash(noise.resize((300, 300)))) and not same_picture(dhash(noise), dhash(red))),
        ('a photo is ok, changed, gone, old, or unsure when its page or pictures did not all answer',
         [verdict({'hash': 5, 'added_at': a}, h, date(2026, 10, 18), c) for a, h, c in
          [('2026-10-01', [5], True), ('2026-10-01', [2 ** 40 - 1], True), ('2026-10-01', None, True),
           ('2025-09-01', [5], True), ('2026-10-01', [2 ** 40 - 1], False), ('2026-10-01', None, False)]] ==
         ['ok', 'changed', 'gone', 'old', 'unsure', 'unsure']),
        ('a logo is saved square, a photo at most 1600 px',
         Image.open(io.BytesIO(webp(red, logo=True))).size[0] == Image.open(io.BytesIO(webp(red, logo=True))).size[1]
         and max(Image.open(io.BytesIO(webp(Image.new('RGB', (4000, 3000))))).size) == 1600),
        ('a free photo is credited Author · Licence, a site photo not at all',
         credit({'author': 'Tomruen', 'licence': 'CC BY-SA 4.0'}) == 'Tomruen · CC BY-SA 4.0' and credit({}) is None),
        ('a logo cut out and squared is still the logo on its white page',
         same_picture(dhash(drawn(logo_on_white)), dhash(drawn(squared_cut)))),
        ('a Facebook or Instagram page is skipped, a website is not',
         bool(SOCIAL.search('www.facebook.com')) and bool(SOCIAL.search('instagram.com')) and not SOCIAL.search('myfacebookfan.com')),
    ]
    failed = [name for name, ok in checks if not ok]
    for name in failed:
        print('FAIL:', name)
    print(f'place_photos.py: {len(checks) - len(failed)} passed, {len(failed)} failed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    a = sys.argv[1:]
    if a == ['--selftest']:
        selftest()
    elif a[:1] == ['check']:
        check('--logos' in a, minutes=6)  # each part ends within 9 minutes: the cloud stops a command at 10
    elif a == ['candidates']:
        candidates(minutes=6)
    elif a[:1] == ['propose'] and len(a) == 3:
        propose(a[1], int(a[2]))
    else:
        sys.exit(__doc__)
