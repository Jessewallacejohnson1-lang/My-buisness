"""
maps.py — one cached Google Maps search through Composio (`COMPOSIO_SEARCH_GOOGLE_MAPS`).

Discovery uses it to sweep a town category by category; verification uses it to ask
"is this place still there?". ADR-016 sets the limits: a Google answer may show that a
place exists or has closed, but a registry entry's name and address never come from it.

Composio holds the credentials, so nothing here needs a key. Every answer is cached on
disk, which is what makes a rerun cost nothing and keeps a sweep resumable after a
network blip.
"""
import json, re
from pathlib import Path

from composio import ComposioError, execute


def answered(text):
    """True for a real answer. A failure comes back as a banner, or as JSON that says
    so: {"successful": false, "error": "getaddrinfo ENOTFOUND backend.composio.dev"}.
    Two of those were cached as empty answers on 2026-10-02, and "snow removal" showed
    no places in St. Joseph until 2026-10-17."""
    try:
        return json.loads(text).get("successful") is not False
    except (ValueError, AttributeError):
        return False


def search(q, cache_dir, ll=None, start=0, refresh=False):
    """Return the `results` dict for one query (local_results / place_results)."""
    cache_dir = Path(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)
    f = cache_dir / f"{re.sub(r'[^a-z0-9]+', '-', q.lower()).strip('-')}-{start}.json"
    if refresh or not f.exists() or not answered(f.read_text()):
        args = {"q": q, "start": start}
        if ll:
            args["ll"] = ll
        try:
            data = execute("COMPOSIO_SEARCH_GOOGLE_MAPS", args)
        except ComposioError as ex:
            # Leave no cache file behind, so the next run asks again.
            f.unlink(missing_ok=True)
            raise RuntimeError(f"maps search failed for {q!r}: {str(ex)[:200]}") from None
        f.write_text(json.dumps({"successful": True, "data": data}))
    raw = json.loads(f.read_text())
    if raw.get("storedInFile"):
        # A cache from before composio.py may still be a pointer to a temp file; keep a real copy.
        raw = json.loads(Path(raw["outputFilePath"]).read_text())
        f.write_text(json.dumps(raw))
    return (raw.get("data") or {}).get("results") or {}


def hits(results):
    """The places in one answer, as plain dicts."""
    if results.get("place_results"):
        return [results["place_results"]]
    return results.get("local_results") or []


def is_closed(hit):
    return "permanently closed" in json.dumps(hit).lower()
