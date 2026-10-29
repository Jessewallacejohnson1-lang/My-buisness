"""Shared parser for Block Party source registry (sources/<town>-mn.md).

Format (ADR-006/007):
  ---
  schema: 1
  town: st-joseph-mn
  ---
  ## Display Name
  ```yaml
  id: permanent-slug
  status: active
  sources:
    - url: https://...
      method: fetch
  ```
  Notes: freeform, never parsed.
"""
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML missing. Run: pip3 install pyyaml")

SUPPORTED_SCHEMAS = {1}
CORE_ENTRY_KEYS = {"id", "status", "tier", "place_id", "category", "partner", "added_by", "sources"}
ENUMS = {
    "status": {"proposed", "active", "paused", "retired"},
    # ADR-011. Absent means `listed`, so this is only checked when present.
    "tier": {"watched", "listed", "submitted"},
    "method": {"fetch", "search_snippet", "submission", "api"},
    "trust": {"official", "squishy"},
    "kind": {"website", "instagram", "facebook", "ical", "rss", "gov"},
}
FRONT = re.compile(r"\A---\n(.*?)\n---\n", re.S)
ENTRY = re.compile(r"^##\s+(.+?)\s*\n+```ya?ml\n(.*?)\n```", re.M | re.S)


def find_root(start="."):
    p = Path(start).resolve()
    for d in [p, *p.parents]:
        if (d / "sources").is_dir():
            return d
    sys.exit("No sources/ folder found. Run from inside the BP app repo.")


def load(root):
    """Return (entries, file_errors). Each entry gets _file, _name, _town, _extra."""
    entries, errors = [], []
    # README and CONTEXT (the glossary) are about the registry, not towns in it.
    files = sorted(p for p in (root / "sources").glob("*.md")
                   if p.name.lower() not in ("readme.md", "context.md"))
    if not files:
        errors.append("sources/: no town files found")
    for f in files:
        text = f.read_text(encoding="utf-8")
        rel = f.relative_to(root)
        m = FRONT.match(text)
        if not m:
            errors.append(f"{rel}: missing frontmatter (--- schema: 1 ---)")
            continue
        try:
            head = yaml.safe_load(m.group(1)) or {}
        except yaml.YAMLError as e:
            errors.append(f"{rel}: frontmatter YAML error: {e}")
            continue
        schema = head.get("schema")
        if schema not in SUPPORTED_SCHEMAS:
            errors.append(f"{rel}: schema {schema!r} not supported (known: {sorted(SUPPORTED_SCHEMAS)})")
            continue
        if not f.stem.endswith("-mn"):
            errors.append(f"{rel}: filename must end in -mn (ADR-006)")
        town = head.get("town", f.stem)
        for name, block in ENTRY.findall(text):
            try:
                data = yaml.safe_load(block)
            except yaml.YAMLError as e:
                errors.append(f"{rel} [{name}]: YAML error: {e}")
                continue
            if not isinstance(data, dict):
                errors.append(f"{rel} [{name}]: block is not a mapping")
                continue
            data.setdefault("status", "proposed")
            data["_extra"] = {k: v for k, v in data.items() if k not in CORE_ENTRY_KEYS}
            data["_file"], data["_name"], data["_town"] = str(rel), name, town
            entries.append(data)
    return entries, errors


def is_todo(url):
    return str(url).strip().upper() == "TODO"


def validate(entries):
    errs, seen = [], {}
    for e in entries:
        where = f"{e['_file']} [{e['_name']}]"
        eid = e.get("id")
        if not eid or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", str(eid)):
            errs.append(f"{where}: id missing or not a lowercase slug")
        elif eid in seen:
            errs.append(f"{where}: duplicate id '{eid}' (also in {seen[eid]})")
        else:
            seen[eid] = where
        if e.get("status") not in ENUMS["status"]:
            errs.append(f"{where}: bad status {e.get('status')!r}")
        if "tier" in e and e["tier"] not in ENUMS["tier"]:
            errs.append(f"{where}: bad tier {e['tier']!r}")
        srcs = e.get("sources")
        if not isinstance(srcs, list) or not srcs:
            errs.append(f"{where}: needs at least one source")
            continue
        for i, s in enumerate(srcs):
            if not isinstance(s, dict):
                errs.append(f"{where} source[{i}]: not a mapping")
                continue
            url = s.get("url")
            if not url:
                errs.append(f"{where} source[{i}]: url required")
            elif not is_todo(url) and not str(url).startswith(("http://", "https://")):
                errs.append(f"{where} source[{i}]: url must be http(s) or TODO")
            elif (is_todo(url) and e.get("status") == "active"
                  and s.get("method") in ("fetch", "api")):
                # Narrowed 2026-09-24 (ADR-015). The rule exists so nothing goes live
                # that the runner will try to READ and fail on. A `submission` source is
                # never read — `url: TODO` is its correct and honest encoding, and two
                # thirds of St. Joseph has no website (ADR-010). Blanket-refusing it kept
                # most of the town out of a registry whose whole goal is completeness.
                errs.append(f"{where} source[{i}]: active entry cannot have TODO url "
                            f"with method {s.get('method')!r} — nothing to read there")
            if not s.get("method"):
                errs.append(f"{where} source[{i}]: method required")
            for key in ("method", "trust", "kind"):
                if key in s and s[key] not in ENUMS[key]:
                    errs.append(f"{where} source[{i}]: bad {key} {s[key]!r}")
    return errs


# Where an event happens, as a registry entry (BP app docs/plans/place-photos): the key that
# picks the place's photo or logo for the event's card.
STREET_WORDS = {"street": "st", "saint": "st", "avenue": "ave", "road": "rd", "drive": "dr", "lane": "ln",
                "east": "e", "west": "w", "north": "n", "south": "s", "theatre": "theater", "county": "co",
                # JoeTown's "25 First Ave NW" is the registry's "25 1st Ave NW" (smooth-mornings 08).
                "first": "1st", "second": "2nd", "third": "3rd", "fourth": "4th", "fifth": "5th"}


def place_key(text):
    """A place line or name reduced to what tells places apart: the part before its first comma
    (the town comes after it), saint/street/ordinals spelled one way, no leading "the", letters and digits."""
    t = (text or "").lower().split(",")[0].replace("’", "'").replace("&", " and ")
    t = " ".join(STREET_WORDS.get(w, w) for w in re.findall(r"[a-z0-9']+", t))
    return re.sub(r"[^a-z0-9]", "", re.sub(r"^the ", "", t))


# A town is no one place: an address that reads only "St Joseph" must not claim every "St. Joseph
# ..." place line (Bloom Styling's did, 2026-10-16).
TOWN_KEYS = {"stjoseph", "collegeville", "stcloud", "sartell", "waitepark", "avon", "coldspring", "albany",
             "freeport", "saukrapids", "stjosephmn", "minnesota", "mn"}


def names_index(entries):
    """Every name, other name (`aka`), venue and address an entry answers to -> every entry answering
    to it, in file order: two shops in one building share its address (White Peony and W|R Home)."""
    index = {}
    for e in entries:
        if e.get("status") == "retired":
            continue
        for name in [e["_name"], *(e.get("aka") or []), *(e.get("venues") or []), e.get("address")]:
            key = place_key(name)
            if name and key and key not in TOWN_KEYS and e["id"] not in index.get(key, []):
                index.setdefault(key, []).append(e["id"])
    return index


def place_index(entries):
    """Every name, other name (`aka`), venue and address an entry answers to -> its id (the first
    entry in the file answering to it)."""
    return {key: ids[0] for key, ids in names_index(entries).items()}


def place_for(place, poster, index):
    """(entry id, True) for the place an event happens at: its place line matched whole, or the
    longest known name inside it ("Centennial Park shelter"). Otherwise (the poster's id, False):
    the entry that published the event stands in, so the card still gets a picture."""
    key = place_key(place)
    if key in index:
        return index[key], True
    inside = [k for k in index if len(k) >= 8 and k in key]
    if inside:
        return index[max(inside, key=len)], True
    return index.get(place_key(poster)), False
