#!/usr/bin/env python3
"""
verify.py — decide whether each place in a town is operating now, from evidence.

Discovery (`sources/discover`) says what exists. This says what is open, and writes the
lists a person acts on. Every place gets one verdict — Open, Renamed, Moved, Closed or
Unknown — and the evidence behind it. Unknown is never a guess (sources/CONTEXT.md).

The cheapest proof is tried first:

  1. Research already done: verdicts from research agents in
     .runs/verify/<town>/research/*.json. They weighed the conflicts, so they win.
  2. A current listing: Overture (open, confidence >= 0.5), a Google Maps listing not
     marked closed, the chamber, or the town directory. A "permanently closed" flag with
     no current listing is Closed.
  3. A Google Maps lookup by name (ADR-016 allows Google to say whether a place is open).
  4. Whatever is left goes to research-needed.json for research agents, and its verdict
     stays Unknown until they answer.

A place only Google knows about also needs a non-Google source before it can be
proposed (ADR-016). Its own website, read politely through run.fetch, is checked here;
the rest is research.

The Minnesota Secretary of State's site (mblsportal.sos.mn.gov) has robots.txt
`Disallow: /` (measured 2026-10-04), so this script never fetches it. Filings count only
through search snippets, which research agents read (ADR-012).

Outputs, in --out (default .runs/verify/<town>/):
  places.csv     every place: type, status, proof
  retire.csv     registry entries verification found closed, moved or renamed
  outreach.csv   places nobody could settle online, and Google-only places unconfirmed
  same-place.csv pairs discovery was unsure about (ADR-018)
  proposed.md    `proposed` drafts for open, confirmed places the registry lacks
"""
import argparse, csv, json, re, sys
from datetime import date, datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from discover import (TOWNS, GOOGLE, NOT_A_PLACE, build_alias_map, entry_md, looks_like_event,
                      match_key, norm, phone_key, registry_keys, street_key, _names_overlap)
from registry import find_root, load

CURRENT_LISTINGS = {"stjosephchamber.com", "www.joetown.org"}
TYPES = ["Business", "Community group", "Church", "School / college", "Government",
         "Park / historic"]


# --- place type --------------------------------------------------------------------------

def place_type(p, overrides):
    if p["name"] in overrides:
        return overrides[p["name"]]
    cat = " ".join(filter(None, [p.get("category") or "", (p.get("google") or {}).get(
        "category") or ""])).lower()
    name = p["name"].lower()
    rules = [  # (type, category pattern, name pattern)
        ("Church", r"worship|religious|church", r"\b(church|parish|monastery|chapel|baha.i)\b"),
        ("School / college", r"college_university|campus|elementary_school|place_of_learning|"
                             r"^education\b|library|amenity=school|^school|^college|"
                             r"\bschool\b(?!.*(driving|dance|martial))",
         r"\bschool\b|college of|\blibrary\b"),
        ("Government", r"\bgov\b|government|police|fire_station|fire station|post_office|"
                       r"post office|military|city hall",
         r"\bcity of\b|police|township|post office|waste water|maintenance department"),
        ("Park / historic", r"\bpark\b|leisure=park|dog_park|monument|nature preserve|lake\b",
         r"\bpark\b|trailhead"),
        ("Community group", r"nonprofit|non-profit|social_or_community|food_bank|political",
         r"\blegion\b|\bvfw\b|\bassn\b"),
    ]
    for label, cat_pat, name_pat in rules:
        if re.search(cat_pat, cat) or re.search(name_pat, name):
            return label
    return "Business"


# --- evidence ----------------------------------------------------------------------------

def from_listings(p):
    """Step 2: what the sightings themselves say."""
    open_ev, closed_ev = [], []
    for s in p["signals"]:
        src = s["source"]
        if s.get("closed"):
            closed_ev.append(f"{'Google Maps' if src in GOOGLE else src.title()} marks it "
                             f"permanently closed")
        elif src in GOOGLE:
            hours = f" ({s['open_state']})" if s.get("open_state") else ""
            open_ev.append(f"Google Maps lists it, not closed{hours}")
        elif src == "overture" and (s.get("confidence") or 0) >= 0.5:
            open_ev.append(f"Overture lists it open (confidence {s['confidence']})")
        elif src in CURRENT_LISTINGS:
            open_ev.append(f"current listing on {src}")
    if open_ev:
        # Prefer a listing with hours, then the local directories, then Overture.
        open_ev.sort(key=lambda e: (0 if "Open" in e or "Closes" in e or "Opens" in e
                                    else 1 if "current listing" in e else 2))
        return {"verdict": "Open", "evidence": open_ev[0], "how": "listing"}
    if closed_ev:
        return {"verdict": "Closed", "evidence": closed_ev[0], "how": "listing"}
    return None


def from_maps_lookup(p, town, cache_dir):
    """Step 3: ask the map about this one place by name."""
    import maps
    try:
        res = maps.search(f"{p['name']} {town['label']} {town['zips'][0]}", cache_dir)
    except Exception as ex:
        return {"verdict": "Unknown", "evidence": f"map lookup failed: {ex}", "how": "error"}
    phones = {phone_key(s.get("phone")) for s in p["signals"]} - {None}
    streets = {street_key(s.get("address")) for s in p["signals"]} - {None}
    hint = None
    for h in maps.hits(res):
        hk = {"key": match_key(h.get("title") or ""), "display_key": norm(h.get("title") or "")}
        same_name = hk["key"] == p["key"] or _names_overlap(hk, p)
        same_phone = phone_key(h.get("phone")) in phones
        same_street = street_key(h.get("address")) in streets
        if same_name and (same_phone or same_street or not (phones or streets)):
            if maps.is_closed(h):
                return {"verdict": "Closed", "how": "maps",
                        "evidence": "Google Maps marks it permanently closed"}
            if h.get("open_state") or h.get("hours"):
                return {"verdict": "Open", "how": "maps",
                        "evidence": f"Google Maps listing with hours ({h.get('open_state')})"}
            hint = "Google Maps has a listing with no hours"
        elif same_phone or same_street:
            hint = (f"its {'phone' if same_phone else 'address'} is now listed as "
                    f"{h.get('title')!r} — rename or successor? (ADR-017)")
    return {"verdict": "Unknown", "how": "needs-research",
            "evidence": hint or "no current listing found"}


def confirm_off_google(p):
    """ADR-016: a Google-only place needs a non-Google source. Its own site counts."""
    from run import fetch
    url = (p.get("google") or {}).get("website")
    if not url:
        return None
    try:
        _status, text = fetch(url)
    except Exception:
        return None
    words = [w for w in norm(p["name"]).split() if len(w) > 2]
    body = norm(re.sub(r"<[^>]+>", " ", text))
    if words and all(w in body for w in words):
        return f"its own website, {url.split('?')[0]}"
    return None


# --- main --------------------------------------------------------------------------------

def load_research(folder, aliases):
    out = {}
    for f in sorted(folder.glob("*.json")):
        for c in json.loads(f.read_text()):
            k = match_key(c["name"])
            if k in aliases and aliases[k][0] != k:
                continue    # an old name folded into another place; its verdict was the old name's
            out[k] = dict(c, how="research", research_file=f.name)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--town", default="st-joseph-mn")
    ap.add_argument("--root", default=".")
    ap.add_argument("--out", help="folder for the spreadsheets (default .runs/verify/<town>)")
    ap.add_argument("--fresh", action="store_true", help="ignore verdicts newer than --cadence-days")
    ap.add_argument("--cadence-days", type=int, default=90,
                    help="re-check a verdict once it is this old (ADR-011: listed = quarterly)")
    ap.add_argument("--offline", action="store_true", help="no map lookups or website checks")
    args = ap.parse_args()

    town = dict(TOWNS[args.town], id=args.town)
    root = find_root(args.root)
    work = root / ".runs" / "verify" / args.town
    (work / "research").mkdir(parents=True, exist_ok=True)
    out = Path(args.out).expanduser() if args.out else work
    out.mkdir(parents=True, exist_ok=True)

    roster = json.loads((root / ".runs" / "latest" / "roster.json").read_text())
    entries = [e for e in load(root)[0] if e.get("_town") == args.town]
    aliases = build_alias_map(town.get("aliases"))
    research = load_research(work / "research", aliases)
    store_f = work / "verdicts.json"
    store = json.loads(store_f.read_text()) if store_f.exists() else {}
    overrides = town.get("place_types", {})

    # Registry entries are places too, sighted or not.
    by_key = {p["key"]: p for p in roster}
    for p in roster:
        for a in p.get("aka", ()):
            by_key.setdefault(match_key(a), p)
    skip = {match_key(n) for n in town.get("not_places", ())}
    for e in entries:
        keys = {match_key(e["_name"])} | {match_key(a) for a in (e.get("aka") or [])}
        keys |= {aliases[k][0] for k in keys if k in aliases}
        if keys & skip or NOT_A_PLACE.search(e["_name"]) or e.get("category") in ("town", "festival", "vendors"):
            continue    # the town itself, an event or a kiosk: a source, not a place
        hit = next((by_key[k] for k in keys if k in by_key), None)
        if hit is None:
            hit = {"name": e["_name"], "key": match_key(e["_name"]), "display_key": norm(e["_name"]),
                   "sources": [], "signals": [], "google": {}, "category": e.get("category")}
            roster.append(hit)
            by_key[hit["key"]] = hit
        hit["entry"] = {"id": e["id"], "status": e.get("status"), "name": e["_name"]}
        if "registry" not in hit["sources"]:
            hit["sources"].append("registry")

    today = date.today()
    research_needed = []
    for p in roster:
        if looks_like_event(p["name"]):
            p["event"] = True
            continue
        old = store.get(p["key"])
        fresh = old and not args.fresh and old.get("how") != "needs-research" and \
            (today - date.fromisoformat(old["checked"])).days < args.cadence_days
        if p["key"] in research:
            v = research[p["key"]]
        elif fresh:
            v = old
        else:
            v = from_listings(p)
            if v is None:
                v = ({"verdict": "Unknown", "how": "needs-research", "evidence": "offline"}
                     if args.offline else from_maps_lookup(p, town, root / ".runs" / "cache" / "maps" / args.town))
        v = dict(v, checked=v.get("checked") or today.isoformat())
        store[p["key"]] = v
        p["v"] = v
        if v.get("how") == "needs-research":
            research_needed.append({"name": p["name"], "address": p.get("address") or
                                    (p.get("google") or {}).get("address") or "",
                                    "phone": p.get("phone") or (p.get("google") or {}).get("phone") or "",
                                    "hint": v["evidence"]})
        # ADR-016: a Google-only place needs a non-Google source before it is proposed.
        if set(p["sources"]) <= GOOGLE and v["verdict"] in ("Open", "Renamed"):
            conf = old.get("confirmed_by") if old else None
            if not conf and not args.offline:
                conf = confirm_off_google(p)
            if not conf and research.get(p["key"], {}).get("confirmed_by"):
                conf = research[p["key"]]["confirmed_by"]
            v["confirmed_by"] = conf
            if not conf and p["key"] not in research:   # researched and still unnamed: outreach
                research_needed.append({"name": p["name"], "address": (p.get("google") or {}).get(
                    "address", ""), "phone": (p.get("google") or {}).get("phone", ""),
                    "hint": "open, but only Google knows it: find a non-Google source "
                            "that names it (ADR-016)"})
    store_f.write_text(json.dumps(store, indent=1, ensure_ascii=False))
    (work / "research-needed.json").write_text(json.dumps(research_needed, indent=1, ensure_ascii=False))

    # A rename whose new name is already a place of its own is that place, under an old
    # name (ADR-017): fold it in rather than list the business twice.
    for p in roster:
        v = p.get("v") or {}
        target = by_key.get(match_key(v.get("current_name") or ""))
        if v.get("verdict") == "Renamed" and target is not None and target is not p:
            target.setdefault("aka", []).append(p["name"])
            p["event"] = True        # out of every list; its name lives on as an aka

    # --- write the lists ------------------------------------------------------------------
    places = [p for p in roster if not p.get("event")]
    for p in places:
        p["type"] = place_type(p, overrides)
        v = p["v"]
        p["status"] = "Open" if v["verdict"] == "Renamed" else v["verdict"]
        p["shown_name"] = (f"{v['current_name']} (was {p['name']})"
                           if v["verdict"] == "Renamed" and v.get("current_name") else p["name"])
    rank = ["Open", "Unknown", "Moved", "Closed"]
    places.sort(key=lambda p: (TYPES.index(p["type"]), rank.index(p["status"]), norm(p["name"])))

    g = lambda p, f: p.get(f) or (p.get("google") or {}).get(f) or ""
    with open(out / "places.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Name", "Type", "Status", "Category", "Address", "Phone", "Website",
                    "In Block Party", "Seen in", "Proof", "Proof link", "Checked"])
        for p in places:
            v = p["v"]
            w.writerow([p["shown_name"], p["type"], p["status"], g(p, "category"),
                        v.get("current_address") or g(p, "address"), g(p, "phone"),
                        g(p, "website"), (p.get("entry") or {}).get("status", ""),
                        ", ".join(s for s in p["sources"] if s != "registry"),
                        v.get("evidence", ""), v.get("source_url", ""), v.get("checked", "")])
    retire = [p for p in places if p.get("entry") and p["v"]["verdict"] in ("Closed", "Moved", "Renamed")]
    with open(out / "retire.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Entry id", "Name", "Verdict", "New name", "Proof", "Proof link"])
        for p in retire:
            v = p["v"]
            w.writerow([p["entry"]["id"], p["name"], v["verdict"], v.get("current_name", ""),
                        v.get("evidence", ""), v.get("source_url", "")])
    outreach = [p for p in places if p["status"] == "Unknown" or
                (set(p["sources"]) <= GOOGLE and p["status"] == "Open" and not p["v"].get("confirmed_by"))]
    with open(out / "outreach.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Name", "Type", "Why", "Address", "Phone"])
        for p in outreach:
            why = (p["v"].get("evidence") if p["status"] == "Unknown"
                   else "open, but only Google knows it")
            w.writerow([p["name"], p["type"], why, g(p, "address"), g(p, "phone")])
    pairs = json.loads((root / ".runs" / "latest" / "same-place.json").read_text())
    with open(out / "same-place.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Place A", "Place B", "Similarity", "Same place? (yes / no)"])
        for ratio, a, b in pairs:
            w.writerow([a, b, ratio, ""])

    # Drafts: open, not yet in the registry, and named by a non-Google source.
    drafts = []
    for p in places:
        v = p["v"]
        if p.get("entry") or p["status"] != "Open":
            continue
        if set(p["sources"]) <= GOOGLE and not v.get("confirmed_by"):
            continue
        rec = dict(p, place_type=p["type"])
        if v["verdict"] == "Renamed" and v.get("current_name"):
            rec["aka"] = list(p.get("aka", [])) + [p["name"]]
            rec["name"] = v["current_name"]
            rec["address"] = v.get("current_address") or p.get("address")
        if set(p["sources"]) <= GOOGLE:       # ADR-016: nothing from Google goes in
            site = re.match(r"its own website, (\S+)", v.get("confirmed_by") or "")
            rec.update(address=v.get("current_address") or None, phone=None, category=None,
                       website=site.group(1) if site else None)
        note = f" Verified {v['checked']}: {v['evidence']}."
        if v.get("confirmed_by"):
            note += f" Named by {v['confirmed_by']} (ADR-016)."
        drafts.append(entry_md(rec, added_by="agent:town-verify", note=note))
    (out / "proposed.md").write_text("\n\n".join(drafts) + "\n")

    from collections import Counter
    print(f"[verify] {len(places)} places; {len(research_needed)} need research "
          f"(.runs/verify/{args.town}/research-needed.json)")
    for t in TYPES:
        c = Counter(p["status"] for p in places if p["type"] == t)
        if c:
            print(f"  {t:18} {sum(c.values()):4}  " + "  ".join(f"{s.lower()} {c[s]}" for s in rank if c[s]))
    print(f"  retire {len(retire)} | outreach {len(outreach)} | same place? {len(pairs)} | "
          f"drafts {len(drafts)}")
    print(f"lists: {out}")


if __name__ == "__main__":
    main()
