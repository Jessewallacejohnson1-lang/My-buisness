#!/usr/bin/env python3
"""Extract rule-shaped lines from the historical logs for manual classification.

Finds bolded bullet leads — the shape every durable rule in this repo is written
in — and prints them with their source and line number. It decides nothing: the
ledger it feeds is classified by hand and approved before anything moves.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SOURCES = ["MAP_BUILD_LOG.md", "REVIEW.md", "DECISIONS.md"]
RULE_LEAD = re.compile(r"^\s*[-*]\s+\*\*(?P<lead>[^*]{8,120})\*\*")


def candidates(repo: Path) -> list[tuple[str, int, str]]:
    found: list[tuple[str, int, str]] = []
    for name in SOURCES:
        path = repo / name
        if not path.exists():
            print(f"warning: {name} not found, skipping", file=sys.stderr)
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            match = RULE_LEAD.match(line)
            if match:
                found.append((name, number, match.group("lead").strip()))
    return found


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    rows = candidates(repo)
    print(f"| Source | Line | Rule lead | Verdict | Destination |")
    print(f"| --- | ---: | --- | --- | --- |")
    for name, number, lead in rows:
        print(f"| `{name}` | {number} | {lead} | | |")
    print(f"\n{len(rows)} candidates", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
