#!/usr/bin/env python3
"""
review_park_photos.py — human "does this actually look good?" check for every
City park photo the app will show.

Why this exists: the runtime photo picker (GooglePlacesService.bestScenicPhoto)
is GEOMETRY-ONLY — it can tell a landscape shot from a portrait one, but it
cannot tell a scenic park vista from a photo of a trash barrel. So a human must
eyeball the actual chosen photo for each park. This script assembles them into
one contact sheet for that review; when a Google auto-pick looks poor, override
it by bundling a hand-picked photo in Resources/Images + KnownLocalPhoto.swift.

Run:  python3 scripts/review_park_photos.py
Then open the printed HTML (and/or montage) and look at every tile.

Resolves, per park:
  • bundled  — a KnownLocalPhoto entry with a real file in Resources/Images
  • google   — the live confident-match scenic pick (what users actually see)
  • none     — no photo; the card shows the coral fallback
No Google photo bytes are persisted here beyond this local review folder.
"""
import json, urllib.request, math, re, struct, pathlib, sys

REPO = pathlib.Path(__file__).resolve().parent.parent
IMAGES = REPO / "Hygge/Resources/Images"
OUT = REPO / "build/park-photo-review"
OUT.mkdir(parents=True, exist_ok=True)

def read(p): return (REPO / p).read_text()

KEY = re.search(r'AIza[A-Za-z0-9_-]+', read("Hygge/Config/GooglePlacesConfig.swift")).group(0)
GBASE = "https://places.googleapis.com/v1"

# Parse CityParks.swift -> [(title, lat, lon)]
cp = read("Hygge/Backend/CityParks.swift")
parks = []
for m in re.finditer(r'title:\s*"([^"]+)".*?lat:\s*([\d.\-]+),\s*lon:\s*([\d.\-]+)', cp, re.S):
    parks.append((m.group(1), float(m.group(2)), float(m.group(3))))

# Parse KnownLocalPhoto.swift byTitle -> {title: slug}
bundled = dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', read("Hygge/Features/Components/KnownLocalPhoto.swift")))

def dist(a, b):
    R = 6371000; la1, lo1 = map(math.radians, a); la2, lo2 = map(math.radians, b)
    dla, dlo = la2-la1, lo2-lo1
    h = math.sin(dla/2)**2 + math.cos(la1)*math.cos(la2)*math.sin(dlo/2)**2
    return 2*R*math.asin(math.sqrt(h))

def names_align(a, b):
    na, nb = re.sub(r'[^a-z0-9 ]', ' ', a.lower()), re.sub(r'[^a-z0-9 ]', ' ', b.lower())
    if na in nb or nb in na: return True
    ta = {w for w in na.split() if len(w) >= 5}; tb = {w for w in nb.split() if len(w) >= 5}
    return bool(ta & tb)

def gsearch(q):
    body = json.dumps({"textQuery": q, "regionCode": "us",
        "locationBias": {"circle": {"center": {"latitude": 45.5648, "longitude": -94.3183}, "radius": 15000}}}).encode()
    req = urllib.request.Request(GBASE + "/places:searchText", data=body, method="POST")
    req.add_header("Content-Type", "application/json"); req.add_header("X-Goog-Api-Key", KEY)
    req.add_header("X-Goog-FieldMask", "places.id,places.displayName,places.location")
    return json.load(urllib.request.urlopen(req, timeout=30)).get("places", [])

def gdetails(pid):
    req = urllib.request.Request(GBASE + f"/places/{pid}")
    req.add_header("X-Goog-Api-Key", KEY)
    req.add_header("X-Goog-FieldMask", "photos.name,photos.widthPx,photos.heightPx")
    return json.load(urllib.request.urlopen(req, timeout=30)).get("photos", [])

def scenic(photos):  # mirror of GooglePlacesService.bestScenicPhoto
    best = None
    for i, p in enumerate(photos):
        w, h = p.get("widthPx"), p.get("heightPx")
        if not (w and h): continue
        ar, md = w/h, min(w, h)
        if not (1.15 <= ar <= 2.4 and md >= 480): continue
        s = min(w, 2400)/2400*40 + (30 - abs(ar-1.6)*20) + max(0, 10 - i*1.5)
        if best is None or s > best[0]: best = (s, p)
    return (best[1] if best else photos[0]) if photos else None

def resolve_google(title, lat, lon):
    for c in gsearch(f"{title} St Joseph MN")[:5]:
        loc = c.get("location", {})
        nm = c.get("displayName", {}).get("text", "")
        if dist((lat, lon), (loc.get("latitude"), loc.get("longitude"))) <= 75 and names_align(nm, title):
            ph = scenic(gdetails(c["id"]))
            if ph:
                data = urllib.request.urlopen(f"{GBASE}/{ph['name']}/media?maxWidthPx=1200&key={KEY}", timeout=60).read()
                return data
    return None

rows = []
for title, lat, lon in parks:
    slug = bundled.get(title)
    if slug and (IMAGES / f"{slug}.jpg").exists():
        dest = OUT / f"{slug}.jpg"; dest.write_bytes((IMAGES / f"{slug}.jpg").read_bytes())
        rows.append((title, "bundled", dest.name)); print(f"  {title:20} bundled  {slug}.jpg")
    else:
        try:
            data = resolve_google(title, lat, lon)
        except Exception as e:
            data = None; print(f"  {title:20} google ERROR {str(e)[:50]}")
        if data:
            fn = OUT / f"g_{title.lower().replace(' ', '_')}.jpg"; fn.write_bytes(data)
            rows.append((title, "google", fn.name)); print(f"  {title:20} google   {fn.name}")
        else:
            rows.append((title, "none (coral fallback)", None)); print(f"  {title:20} NONE — coral fallback")

html = ["<html><head><meta charset=utf-8><title>Park photo review</title>",
        "<style>body{font:14px system-ui;background:#faf8f5;margin:24px}",
        ".g{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}",
        ".c{background:#fff;border:1px solid #eee;border-radius:12px;overflow:hidden}",
        ".c img{width:100%;height:180px;object-fit:cover;display:block}",
        ".m{padding:8px 12px}.s{color:#999;font-size:12px}</style></head><body>",
        "<h2>Park photos — does each actually look good?</h2><div class=g>"]
for title, src, fn in rows:
    img = f'<img src="{fn}">' if fn else '<div style="height:180px;background:#FF6B571a;display:flex;align-items:center;justify-content:center;color:#FF6B57">coral fallback</div>'
    html.append(f'<div class=c>{img}<div class=m><b>{title}</b><div class=s>{src}</div></div></div>')
html.append("</div></body></html>")
(OUT / "index.html").write_text("\n".join(html))
print(f"\nReview sheet: {OUT/'index.html'}")

# Optional montage for quick viewing if Pillow is present
try:
    from PIL import Image, ImageDraw
    imgs = [(t, OUT / f) for t, s, f in rows if f]
    cols, cw, ch = 3, 400, 300
    rows_n = (len(imgs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols*cw, rows_n*ch), "#faf8f5")
    d = ImageDraw.Draw(sheet)
    for i, (t, p) in enumerate(imgs):
        im = Image.open(p).convert("RGB"); im.thumbnail((cw, ch-24))
        x, y = (i % cols)*cw, (i//cols)*ch
        sheet.paste(im, (x+4, y+4)); d.text((x+6, y+ch-18), t, fill="#333")
    sheet.save(OUT / "montage.jpg", quality=88)
    print(f"Montage: {OUT/'montage.jpg'}")
except Exception as e:
    print("(montage skipped — no Pillow)", str(e)[:60])
