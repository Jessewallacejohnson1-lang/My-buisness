#!/usr/bin/env python3
"""Validate every sources/*.md. Exit 1 on any error. Run before every commit."""
import sys
from collections import Counter
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from registry import find_root, load, validate, is_todo

root = find_root(sys.argv[1] if len(sys.argv) > 1 else ".")
entries, errors = load(root)
errors += validate(entries)
counts = Counter(e.get("status") for e in entries)
todo = sum(1 for e in entries for s in (e.get("sources") or [])
           if isinstance(s, dict) and is_todo(s.get("url")))
print(f"{len(entries)} entries | " + ", ".join(f"{k}:{v}" for k, v in sorted(counts.items()))
      + f" | {todo} TODO urls")
for e in errors:
    print("ERROR", e)
print("OK" if not errors else f"FAIL ({len(errors)} errors)")
sys.exit(1 if errors else 0)
