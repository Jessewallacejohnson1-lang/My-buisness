"""
town.py — load one town's settings from towns/<slug>.json.

Every script that needs to know which town it is working on reads it here, so a
new town is one new file under towns/ and no script edits. Pick the town with
BP_TOWN (the file name without .json); St. Joseph is the default.

    BP_TOWN=st-cloud python3 scripts/review_park_photos.py

See towns/README.md for what each field means.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOWNS = ROOT / "towns"
DEFAULT = "st-joseph"

REQUIRED = (
    "slug",
    "short_name",
    "search_suffix",
    "center",
    "search_radius_m",
    "place_id_prefix",
    "parks_file",
    "rain_excluded",
)


def load_town(slug: str | None = None) -> dict:
    slug = slug or os.environ.get("BP_TOWN") or DEFAULT
    path = TOWNS / f"{slug}.json"
    if not path.exists():
        have = ", ".join(sorted(p.stem for p in TOWNS.glob("*.json"))) or "none"
        sys.exit(f"no town file {path.relative_to(ROOT)} (towns: {have})")
    town = json.loads(path.read_text())
    missing = [k for k in REQUIRED if k not in town]
    if missing:
        sys.exit(f"{path.relative_to(ROOT)} is missing: {', '.join(missing)}")
    if town["slug"] != slug:
        sys.exit(f"{path.relative_to(ROOT)} says slug {town['slug']!r}, file name says {slug!r}")
    return town


def rain_excluded(town: dict) -> dict[str, str]:
    """{business name: reason} across every group in `rain_excluded`."""
    return {e["name"]: e["reason"] for group in town["rain_excluded"].values() for e in group}
