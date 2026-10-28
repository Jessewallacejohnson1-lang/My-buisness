#!/usr/bin/env python3
"""
towns.py — each town's settings, one YAML file per town in sources/towns/.

discover.py, verify.py, read_events.py and write_judged.py read a town's ZIP codes, map
boxes, same-place names and the rest from TOWNS, keyed by file name: sources/towns/
st-joseph-mn.yaml is TOWNS["st-joseph-mn"], the same id as the town's registry file
(sources/st-joseph-mn.md). The YAML has lists where the old dict in discover.py had
tuples; nothing that reads them minds.

  python3 sources/scripts/towns.py --check [ROOT]   every registry town has a town file
  python3 sources/scripts/towns.py --selftest
"""

import ast, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import registry
import yaml

HERE = Path(__file__).resolve().parent


def load_towns(folder):
    """Every <town>.yaml in `folder`, keyed by its file name."""
    return {p.stem: yaml.safe_load(p.read_text(encoding="utf-8")) or {}
            for p in sorted(Path(folder).glob("*.yaml"))}


TOWNS = load_towns(HERE.parent / "towns")


def missing(root):
    """Towns the registry (sources/*.md) names that have no sources/towns/<town>.yaml."""
    entries, _ = registry.load(root)
    have = load_towns(root / "sources" / "towns")
    return sorted({e["_town"] for e in entries} - set(have))


def check(root):
    root = registry.find_root(root)
    gone = missing(root)
    for town in gone:
        print(f"ERROR towns: {town} is in the registry but has no sources/towns/{town}.yaml")
    if not gone:
        print(f"towns: every registry town has its file in sources/towns/ ({len(load_towns(root / 'sources' / 'towns'))})")
    sys.exit(1 if gone else 0)


# discover.py's TOWNS dict as it stood on main before it moved into sources/towns/.
OLD_COMMIT = "56a9650"


def old_towns(root):
    src = subprocess.run(["git", "-C", str(root), "show", f"{OLD_COMMIT}:sources/scripts/discover.py"],
                         capture_output=True, text=True).stdout
    if not src:
        return None
    node = next(n for n in ast.parse(src).body
                if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == "TOWNS")
    return ast.literal_eval(node.value)


def as_lists(v):
    if isinstance(v, dict):
        return {k: as_lists(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [as_lists(x) for x in v]
    return v


def selftest():
    import tempfile
    root = registry.find_root(HERE)
    old = old_towns(root)
    with tempfile.TemporaryDirectory() as tmp:
        fake = Path(tmp)
        (fake / "sources" / "towns").mkdir(parents=True)
        (fake / "sources" / "waite-park-mn.md").write_text(
            "---\nschema: 1\ntown: waite-park-mn\n---\n## A Place\n```yaml\nid: a-place\n```\n")
        unfiled = missing(fake)
        (fake / "sources" / "towns" / "waite-park-mn.yaml").write_text("label: Waite Park MN\n")
        filed = missing(fake)
    checks = [
        (set(TOWNS) == {p.stem for p in (HERE.parent / "towns").glob("*.yaml")}
         and all(isinstance(t, dict) for t in TOWNS.values()),
         "every sources/towns/*.yaml loads, keyed by its file name"),
        (old is not None and as_lists(old) == TOWNS and list(old["st-joseph-mn"]) == list(TOWNS["st-joseph-mn"]),
         f"TOWNS equals discover.py's old dict at {OLD_COMMIT}, value for value (tuples read as lists)"),
        (missing(root) == [], "every town in this registry has a town file"),
        (unfiled == ["waite-park-mn"] and filed == [], "a registry town without a town file is named, and passes once it has one"),
    ]
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    elif sys.argv[1:2] == ["--check"] and len(sys.argv) <= 3:
        check(sys.argv[2] if len(sys.argv) == 3 else ".")
    else:
        sys.exit(__doc__)
