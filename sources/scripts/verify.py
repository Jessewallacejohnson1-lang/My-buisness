#!/usr/bin/env python3
"""
verify.py — decide whether each place in a town is operating now, from evidence.

Discovery (`sources/discover`) says what exists. This says what is open, and writes the
lists a person acts on. Every place gets one verdict — Open, Renamed, Moved, Closed or
Unknown — and the evidence behind it. Unknown is never a guess (sources/CONTEXT.md).

The cheapest proof is tried first:

  1. Research already done: verdicts from research agents in
     <census runs>/verify/<town>/research/*.json. They weighed the conflicts, so they win.
     Files load by the date their name starts with; a `-review` file loads last on its
     date, so a correction beats the batch it corrects, and newer research beats both.
  2. A current listing: Overture (open, confidence >= 0.5), a Google Maps listing not
     marked closed, the chamber, or the town directory. A "permanently closed" flag with
     no current listing is Closed.
  3. A Google Maps lookup by name (ADR-016 allows Google to say whether a place is open).
  4. Whatever is left goes to research-needed.json for research agents, and its verdict
     stays Unknown until they answer.

Every verdict is reused until it is --cadence-days old. Then a researched place goes
back to research (a listing never undoes research), except a researched Closed, which
stands until --fresh. The roster is discover's newest for the town (<census runs>/latest-<town>).

A place only Google knows about also needs a non-Google source before it can be
proposed (ADR-016). Its own website, read politely through run.fetch, is checked here;
the rest is research.

The Minnesota Secretary of State's site (mblsportal.sos.mn.gov) has robots.txt
`Disallow: /` (measured 2026-10-04), so this script never fetches it. Filings count only
through search snippets, which research agents read (ADR-012).

The census runs folder is discover.RUNS (~/Documents/town-census/.runs).

Outputs, in --out (default <census runs>/verify/<town>/):
  places.csv     every place: type, status, proof
  retire.csv     registry entries verification found closed, moved or renamed
  outreach.csv   places nobody could settle online, and Google-only places unconfirmed
  same-place.csv pairs discovery was unsure about (ADR-018)
  proposed.md    `proposed` drafts for open, confirmed places the registry lacks
"""
import argparse, csv, json, re, sys
from datetime import date
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
from discover import (RUNS, TOWNS, GOOGLE, NOT_A_PLACE, build_alias_map, entry_md, looks_like_event,
                      match_key, norm, phone_key, street_key, _names_overlap)
from registry import find_root, load

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

def from_listings(p, current):
    """Step 2: what the sightings themselves say. `current`: the town's directories that
    are kept up to date."""
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
        elif src in current:
            open_ev.append(f"current listing on {src}")
    if open_ev:
        # Prefer a listing with hours, then the local directories, then Overture.
        open_ev.sort(key=lambda e: (0 if "Open" in e or "Closes" in e or "Opens" in e
                                    else 1 if "current listing" in e else 2))
        return {"verdict": "Open", "evidence": open_ev[0], "how": "listing"}
    if closed_ev:
        return {"verdict": "Closed", "evidence": closed_ev[0], "how": "listing"}
    return None


def from_maps_lookup(p, town, cache_dir, refresh=False):
    """Step 3: ask the map about this one place by name."""
    import maps
    try:
        res = maps.search(f"{p['name']} {town['label']} {town['zips'][0]}", cache_dir, refresh=refresh)
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

def load_research(folder, aliases, today):
    out = {}
    order = lambda f: (f.name[:10], f.stem.endswith("-review"), f.name)
    for f in sorted(folder.glob("*.json"), key=order):
        try:
            rows = json.loads(f.read_text())
        except ValueError:
            print(f"[verify] skipped {f.name}: not finished JSON (a batch still writing?)")
            continue
        try:
            made = date.fromisoformat(f.name[:10]).isoformat()
        except ValueError:
            made = today.isoformat()
        for c in rows:
            k = match_key(c["name"])
            if k in aliases and aliases[k][0] != k:
                continue    # an old name folded into another place; its verdict was the old name's
            out[k] = dict(c, how="research", research_file=f.name, checked=c.get("checked") or made)
    return out


def prior(r, old, today, days, fresh):
    """What one place starts from: research answer `r`, else its last verdict `old`, or
    None to work it out from the listings. A listing never undoes research: once research
    is too old (or under --fresh) the place goes back to research, its last answer as the
    hint. A researched Closed stands until --fresh."""
    if r:
        if not fresh and (r["verdict"] == "Closed" or still_good(r, today, days)):
            return r
        return {"verdict": "Unknown", "how": "needs-research",
                "evidence": f"re-check: on {r['checked']} research said {r['verdict']}: {r.get('evidence', '')}"}
    if not fresh and still_good(old, today, days):
        return old
    return None


def still_good(v, today, days):
    """A verdict is reused until it is `days` old; a lookup that failed or still waits on
    research is tried again every run."""
    return bool(v) and v.get("how") not in ("needs-research", "error") and \
        (today - date.fromisoformat(v["checked"])).days < days


def selftest():
    import tempfile
    checks = []
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        files = {"2026-10-04-1.json": [{"name": "Mattressota", "verdict": "Open"}],
                 "2026-10-05-review.json": [{"name": "Mattressota", "verdict": "Unknown"},
                                            {"name": "Heinen", "verdict": "Unknown"}],
                 "2026-10-05-sweep.json": [{"name": "Mattressota", "verdict": "Open"},
                                           {"name": "Bo Diddleys", "verdict": "Open", "checked": "2026-10-01"}],
                 "2026-11-01-1.json": [{"name": "Heinen", "verdict": "Open"}]}
        for name, rows in files.items():
            (d / name).write_text(json.dumps(rows))
        (d / "2026-11-02-2.json").write_text('[{"name": "Half wri')
        got = load_research(d, {}, date(2026, 11, 3))
        v = lambda n: got[match_key(n)]
        checks.append((v("Mattressota")["verdict"] == "Unknown", "a review beats the batch of its own date"))
        checks.append((v("Heinen")["verdict"] == "Open", "newer research beats an older review"))
        checks.append((v("Mattressota")["checked"] == "2026-10-05", "an answer is dated by its file"))
        checks.append((v("Bo Diddleys")["checked"] == "2026-10-01", "an answer's own date wins"))
        checks.append((len(got) == 3, "a half-written file is skipped, not fatal"))
    today = date(2027, 1, 1)
    checks.append((still_good({"how": "research", "checked": "2026-10-04"}, today, 90),
                   "research 89 days old is reused"))
    checks.append((not still_good({"how": "research", "checked": "2026-10-03"}, today, 90),
                   "research 90 days old is checked again"))
    checks.append((not still_good({"how": "error", "checked": "2026-12-31"}, today, 90),
                   "a failed lookup is tried again"))
    checks.append((not still_good({"how": "needs-research", "checked": "2026-12-31"}, today, 90),
                   "a place waiting on research waits again"))
    shut = {"verdict": "Closed", "how": "research", "checked": "2026-01-01", "evidence": "razed"}
    seen = {"verdict": "Open", "how": "research", "checked": "2026-01-01", "evidence": "posts"}
    listed = {"verdict": "Open", "how": "listing", "checked": "2026-01-01"}
    checks.append((prior(shut, listed, today, 90, False) is shut, "a researched Closed stands"))
    got = prior(seen, listed, today, 90, False)
    checks.append((got["how"] == "needs-research" and "said Open" in got["evidence"],
                   "old research goes back to research, not to the listings"))
    checks.append((prior(shut, None, today, 90, True)["how"] == "needs-research", "--fresh re-checks a Closed"))
    checks.append((prior(None, listed, today, 90, False) is None, "an old listing verdict is worked out again"))
    bad = [m for ok, m in checks if not ok]
    print(f"{len(checks) - len(bad)} passed, {len(bad)} failed" + "".join(f"\n  FAILED {m}" for m in bad))
    sys.exit(1 if bad else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--town", default="st-joseph-mn")
    ap.add_argument("--root", default=".")
    ap.add_argument("--out", help="folder for the spreadsheets (default <census runs>/verify/<town>)")
    ap.add_argument("--fresh", action="store_true", help="re-check every place, researched ones too")
    ap.add_argument("--cadence-days", type=int, default=90,
                    help="re-check a verdict once it is this old (ADR-011: listed = quarterly)")
    ap.add_argument("--offline", action="store_true", help="no map lookups or website checks")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        selftest()

    if args.town not in TOWNS:
        sys.exit(f"no discovery config for town {args.town!r}: add its block to TOWNS in discover.py")
    town = dict(TOWNS[args.town], id=args.town)
    root = find_root(args.root)
    work = RUNS / "verify" / args.town
    (work / "research").mkdir(parents=True, exist_ok=True)
    out = Path(args.out).expanduser() if args.out else work
    out.mkdir(parents=True, exist_ok=True)

    latest = RUNS / f"latest-{args.town}"
    if not (latest / "roster.json").exists():
        sys.exit(f"no roster for {args.town} in {RUNS}: run sources/discover --town {args.town} first")
    roster = json.loads((latest / "roster.json").read_text())
    entries = [e for e in load(root)[0] if e.get("_town") == args.town]
    aliases = build_alias_map(town.get("aliases"))
    today = date.today()
    roster_day = date.fromtimestamp((latest / "roster.json").stat().st_mtime)
    if (today - roster_day).days >= args.cadence_days:
        print(f"[verify] the roster is {(today - roster_day).days} days old, so its listings are too: "
              f"run sources/discover --town {args.town} --refresh first")
    research = load_research(work / "research", aliases, today)
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
        # The entry's own name first, then its old names: "BSN SPORTS" must find the BSN
        # place, not the Game Day Athletic place its aka also points at.
        keys = [match_key(e["_name"])] + [match_key(a) for a in (e.get("aka") or [])]
        keys += [aliases[k][0] for k in keys if k in aliases]
        keys = list(dict.fromkeys(keys))
        if set(keys) & skip or NOT_A_PLACE.search(e["_name"]) or \
                e.get("category") in ("town", "festival", "vendors", "nearby-school"):
            continue    # the town itself, an event, a kiosk or a school nearby: a source, not a place
        hit = next((by_key[k] for k in keys if k in by_key), None)
        if hit is None:
            hit = {"name": e["_name"], "key": match_key(e["_name"]), "display_key": norm(e["_name"]),
                   "sources": [], "signals": [], "google": {}, "category": e.get("category")}
            roster.append(hit)
            by_key[hit["key"]] = hit
        hit["entry"] = {"id": e["id"], "status": e.get("status"), "name": e["_name"]}
        if "registry" not in hit["sources"]:
            hit["sources"].append("registry")

    # Answers written for this roster whose name finds no place (older ones are places the
    # roster has since dropped, such as businesses that left town).
    lost = sorted(r["name"] for k, r in research.items()
                  if k not in by_key and r["research_file"][:10] >= roster_day.isoformat())
    if lost:
        print(f"[verify] {len(lost)} research answers match no place, so they count for nothing "
              f"(give each the input's name): {', '.join(lost)}")
    current = {urlparse(d["url"]).netloc for d in town["directories"] if not d.get("stale")}
    research_needed = []
    for p in roster:
        if looks_like_event(p["name"]):
            p["event"] = True
            continue
        old = store.get(p["key"])
        v = prior(research.get(p["key"]), old, today, args.cadence_days, args.fresh)
        if v is None:
            v = from_listings(p, current)
        if v is None:
            # A verdict that has expired had its map answer cached as long ago: ask again.
            expired = bool(old) and old.get("how") not in ("needs-research", "error")
            v = ({"verdict": "Unknown", "how": "needs-research", "evidence": "offline"}
                 if args.offline else from_maps_lookup(p, town, RUNS / "cache" / "maps" / args.town,
                                                       refresh=args.fresh or expired))
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
    retire = [p for p in places if p.get("entry") and p["entry"]["status"] != "retired"
              and p["v"]["verdict"] in ("Closed", "Moved", "Renamed")
              # an entry already carrying the new name has nothing left to change
              and not (p["v"]["verdict"] == "Renamed" and
                       match_key(p["entry"]["name"]) == match_key(p["v"].get("current_name") or ""))]
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
    pairs = json.loads((latest / "same-place.json").read_text())
    with open(out / "same-place.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Place A", "Place B", "Similarity", "Same place? (yes / no)"])
        for ratio, a, b in pairs:
            w.writerow([a, b, ratio, ""])

    # Drafts: open, not yet in the registry, and named by a non-Google source.
    stale = {urlparse(d["url"]).netloc for d in town["directories"] if d.get("stale")}
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
        # An old directory's address loses to a current listing somewhere else: the place
        # moved (Peaceful Village left its farm for Elm St), so leave the field empty.
        # House numbers only: "County Road 2" and "Stearns 2 County" are one road.
        number = lambda a: street_key(a).split()[0] if street_key(a) else None
        g_no = number((p.get("google") or {}).get("address"))
        if (p.get("from") or {}).get("address") in stale and g_no and \
                g_no != number(p.get("address")) and not v.get("current_address"):
            rec.update(address=None, phone=None)
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
          f"({work / 'research-needed.json'})")
    for t in TYPES:
        c = Counter(p["status"] for p in places if p["type"] == t)
        if c:
            print(f"  {t:18} {sum(c.values()):4}  " + "  ".join(f"{s.lower()} {c[s]}" for s in rank if c[s]))
    print(f"  retire {len(retire)} | outreach {len(outreach)} | same place? {len(pairs)} | "
          f"drafts {len(drafts)}")
    print(f"lists: {out}")


if __name__ == "__main__":
    main()
