#!/usr/bin/env python3
"""
ready.py: the first step of every routine (BP app smooth-mornings 01). It installs each library on
ci-packages.txt that this Python lacks, with `python3 -m pip` (in the cloud sandbox plain `pip`
belongs to another Python), checks by name that the routine's keys are set, never printing a
value, and ends with one line: ready, or what is missing. Each routine readied its own tools in its
own words until 2026-10-28, and a library added for one job broke another (social.py's Pillow
took the morning report's spend line on Oct 27 and 28).

The cloud environment's own setup script stays unused: each routine's copy starts on
integration/block-party, which has no sources/, so it would find nothing to install from. Apify's
key is the environment's network secret, never seen by the session: the social routines check it
with `social.py spend`.

  python3 sources/scripts/ready.py morning|social|photos|accounts
  python3 sources/scripts/ready.py --selftest
"""

import contextlib, importlib.util, io, os, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROUTINES = ("morning", "social", "photos", "accounts")
KEYS = ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY")  # every routine reads or writes the database
WARN = {"morning": {"FIRECRAWL_API_KEY": "pages that refuse the cloud's address or are built by JavaScript fail or read empty"}}


def pip_install(names):
    """'' when pip installed them all, else pip's first error line (or its last line)."""
    r = subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", *names], capture_output=True, text=True)
    lines = (r.stderr + r.stdout).strip().splitlines() or ["no output"]
    return "" if r.returncode == 0 else next((l for l in lines if l.lower().startswith("error")), lines[-1])


def ready(routine, env=os.environ, listing=HERE / "ci-packages.txt", install=pip_install):
    """The routine's one line, and whether it may go on."""
    pips = {}
    for line in listing.read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            name, _, pip = line.split()[:3]
            pips[name] = pip
    lacking = [n for n in pips if importlib.util.find_spec(n) is None]
    failed = install([pips[n] for n in lacking]) if lacking else ""
    unset = [k for k in KEYS if not env.get(k)]
    missing = ([f"libraries {', '.join(lacking)} (pip: {failed})"] if failed else []) + (
        [f"keys {', '.join(unset)} not set"] if unset else [])
    if missing:
        return "[ready] not ready: " + "; ".join(missing), False
    done = f" (installed {', '.join(pips[n] for n in lacking)})" if lacking else ""
    weak = [f"{k} is not set: {why}" for k, why in WARN.get(routine, {}).items() if not env.get(k)]
    return (f"[ready] ready{done}, but " + "; ".join(weak) if weak else f"[ready] ready{done}"), True


def selftest():
    ok = 0
    def check(cond, what):
        nonlocal ok
        if not cond:
            sys.exit(f"selftest failed: {what}")
        ok += 1
    secret = "https://not-to-be-printed.supabase.co"
    asked = []
    def no_pip(names):
        asked.append(names)
        return "ERROR: No matching distribution found for bp-nothing-here"
    with tempfile.TemporaryDirectory() as tmp:
        fake = Path(tmp) / "packages.txt"
        fake.write_text("# import name, Ubuntu package, pip name\njson python3-json json\nbp_nothing_here python3-x bp-nothing-here\n")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            line, go = ready("morning", {"SUPABASE_URL": secret}, fake, no_pip)
        check(not go and "bp_nothing_here" in line and "SUPABASE_SERVICE_ROLE_KEY" in line,
              f"a missing library and a missing key are both named: {line}")
        check(asked == [["bp-nothing-here"]], "only the missing library goes to pip, by its pip name")
        check(secret not in line + out.getvalue() and "SUPABASE_URL" not in line, "a set key is neither named nor printed")
        env = {"SUPABASE_URL": secret, "SUPABASE_SERVICE_ROLE_KEY": "sb_secret_x"}
        line, go = ready("morning", env, fake, lambda names: "")
        check(go and line.startswith("[ready] ready (installed bp-nothing-here), but FIRECRAWL_API_KEY is not set")
              and secret not in line and "sb_secret_x" not in line, f"installed and ready, Firecrawl only warned: {line}")
        check(ready("social", env, fake, lambda names: "") == ("[ready] ready (installed bp-nothing-here)", True),
              "Firecrawl is the morning job's alone")
    check(all(len(l.split()) >= 3 for l in (HERE / "ci-packages.txt").read_text().splitlines()
              if l.strip() and not l.startswith("#")), "every library on ci-packages.txt has its pip name")
    print(f"ready.py selftest: {ok} passed, 0 failed")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    elif sys.argv[1:2] and sys.argv[1] in ROUTINES:
        line, go = ready(sys.argv[1])
        print(line)
        sys.exit(0 if go else 1)
    else:
        sys.exit(__doc__)
