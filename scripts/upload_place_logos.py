#!/usr/bin/env python3
"""
upload_place_logos.py — push approved logos to the `place-logos` Storage bucket
and print the SQL that sets places.logo_url for each uploaded row.

Auth: uses the app's public anon key (parsed from SupabaseConfig.swift). Bucket
writes are admin-gated, so the caller must open a temporary scoped insert policy
for the upload window and drop it right after (see the migration notes) — or run
with SUPABASE_SERVICE_ROLE_KEY in the environment, which bypasses RLS.
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPROVED = ROOT / "build" / "place-logos" / "approved"

cfg = (ROOT / "BlockParty" / "Backend" / "SupabaseConfig.swift").read_text()
SUPABASE_URL = re.search(r'"(https://[a-z0-9]+\.supabase\.co)"', cfg).group(1)
KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or re.search(r'"(eyJ[A-Za-z0-9_\-\.]+)"', cfg).group(1)


def upload(path: Path) -> str:
    object_name = path.name
    url = f"{SUPABASE_URL}/storage/v1/object/place-logos/{object_name}"
    req = urllib.request.Request(
        url,
        data=path.read_bytes(),
        method="POST",
        headers={
            "Authorization": f"Bearer {KEY}",
            "apikey": KEY,
            "Content-Type": "image/png",
            "x-upsert": "true",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        resp.read()
    return f"{SUPABASE_URL}/storage/v1/object/public/place-logos/{object_name}"


def main() -> None:
    files = sorted(APPROVED.glob("*.png"))
    if not files:
        sys.exit("no approved logos found")
    rows = []
    for f in files:
        try:
            public_url = upload(f)
            rows.append((f.stem, public_url))
            print(f"[uploaded] {f.name}")
        except Exception as e:
            print(f"[FAILED  ] {f.name}: {e}")
    values = ",\n".join(f"('{uid}'::uuid, '{url}')" for uid, url in rows)
    sql = (
        "update public.places p set logo_url = v.url\n"
        "from (values\n" + values + "\n) as v(id, url)\nwhere p.id = v.id;"
    )
    out = ROOT / "build" / "place-logos" / "set_logo_urls.sql"
    out.write_text(sql)
    print(f"\n{len(rows)}/{len(files)} uploaded; UPDATE sql → {out}")


if __name__ == "__main__":
    main()
