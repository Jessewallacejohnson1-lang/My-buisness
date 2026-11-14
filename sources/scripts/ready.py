#!/usr/bin/env python3
"""
ready.py: the first step of every routine (BP app smooth-mornings 01). It installs each library on
ci-packages.txt that a fresh python3 can't import (one listed with no Ubuntu package, "-", only for the
morning, and failing there only warns: the map spots' libraries), with `python3 -m pip` (in the cloud sandbox plain
`pip` belongs to another Python), checks that the database takes the routine's key with one read
only that key may make, never printing a value, and ends with one line: ready on which Python, with the libraries
found and installed, or what is missing. The morning's line also goes in finish's report row (`report`, `kept`),
or, when Ready stops the morning, in a row of its own (`failed_row`).
Each routine readied its own tools in its own words until 2026-10-28, and a library added for one
job broke another (social.py's Pillow took the morning report's spend line on Oct 27 and 28).

A library is judged by importing the module the scripts use (the list's fourth column, else its
import name): the cloud's Debian Pillow imports as PIL but fails at PIL.Image ("cannot import name
'_imaging'"). It is installed with --ignore-installed, because pip can't uninstall Debian's own
copies ("Cannot uninstall PyYAML 6.0.1, RECORD file not found"; Oct 27 social run).

Every script must parse on this python3: the cloud's is 3.11, and on Oct 29 two self-tests written
on a newer Python (a backslash inside an f-string's braces) stopped the social watch at its first
script while this step still said ready. `scripts/ci_checks.sh registry` parses them on 3.11 too.

The cloud environment's own setup script stays unused: each routine's copy starts on
integration/block-party, which has no sources/, so it would find nothing to install from. Apify's
key is the environment's network secret, never seen by the session: the social routines check it
with `social.py spend`. So is the database's Watch key (BP app loopholes 12): the session holds only
the public key, so a key's name proves nothing and the read does.

  python3 sources/scripts/ready.py morning|social|photos|accounts
  python3 sources/scripts/ready.py --selftest
"""

import contextlib, io, os, subprocess, sys, tempfile, time, traceback
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from db import Db, DbError, key_headers

HERE = Path(__file__).resolve().parent
ROUTINES = ("morning", "social", "photos", "accounts")
KEPT = "ready-morning.txt"  # the morning's line, for finish's report row
WARN = {"morning": {"FIRECRAWL_API_KEY": "pages that refuse the cloud's address or are built by JavaScript fail or read empty"}}


def pip(args, timeout=None):
    """'' when pip did it, else pip's first error line (or its last line)."""
    try:
        r = subprocess.run([sys.executable, "-m", "pip", *args], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return f"stopped after {timeout} s"
    lines = (r.stderr + r.stdout).strip().splitlines() or ["no output"]
    return "" if r.returncode == 0 else next((l for l in lines if l.lower().startswith("error")), lines[-1])


def broken(modules):
    """The modules a fresh python3 can't import (this process caches what it imported)."""
    return [m for m in modules if subprocess.run([sys.executable, "-c", f"import {m}"], capture_output=True).returncode]


def unparsable(folder=HERE):
    """Each script in folder this python3 can't parse, with its line and why."""
    bad = []
    for p in sorted(folder.glob("*.py")):
        try:
            compile(p.read_text(), p.name, "exec")
        except SyntaxError as e:
            bad.append(f"{p.name} line {e.lineno} ({e.msg})")
    return bad


def reach():
    """'' when the database takes the routine's key, else why not. The app's own key may not read the
    morning reports, so one read proves the Watch key came along (or a Mac's service key)."""
    try:
        Db().rest("GET", "morning_reports?select=day&limit=1")
        return ""
    except DbError as e:
        return (f"the database refused the key (HTTP {e.status}): is the Watch key this environment's network "
                "secret for the Supabase host?" if e.status in (401, 403) else f"the database didn't answer: {e}")


def ready(routine, env=os.environ, listing=HERE / "ci-packages.txt", install=pip, probe=broken, scripts=HERE,
          reach=reach):
    """The routine's one line, and whether it may go on."""
    libs, extras = {}, {}  # pip name: the module that must import; extras: an Ubuntu package of "-"
    for line in listing.read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            name, ubuntu, pip_name, *module = line.split()
            (extras if ubuntu == "-" else libs)[pip_name] = (module or [name])[0]
    bad = probe(list(libs.values()))
    lacking = [n for n, module in libs.items() if module in bad]
    failed = install(["install", "--quiet", "--ignore-installed", *lacking]) if lacking else ""
    if lacking and not failed and probe([libs[n] for n in lacking]):
        failed = "installed, still won't import"
    # every routine reads or writes the database
    unset = ["SUPABASE_URL"] * (not env.get("SUPABASE_URL")) + (
        [] if key_headers(env) else ["SUPABASE_PUBLISHABLE_KEY (the cloud) or SUPABASE_SERVICE_ROLE_KEY (a Mac)"])
    refused = "" if unset else reach()
    wont_run = unparsable(scripts)
    missing = ([f"libraries {', '.join(lacking)} (pip: {failed})"] if failed else []) + (
        [f"keys {', '.join(unset)} not set"] if unset else []) + ([refused] if refused else []) + (
        [f"can't parse {'; '.join(wont_run)}"] if wont_run else [])
    py = f"Python {sys.version.split()[0]}"
    if missing:
        return f"[ready] not ready on {py}: " + "; ".join(missing), False
    weak = [f"{k} is not set: {why}" for k, why in WARN.get(routine, {}).items() if not env.get(k)]
    # The map spots' libraries (BP app inside-cards 20) and the flyer sharpener's (sharpen.py, BP app event-photos 19)
    # are the morning's alone, and only a warning: without them the spots step keeps the spots found before, a small
    # flyer isn't saved, and every other step runs.
    short = [n for n, module in extras.items() if module in probe(list(extras.values()))] if routine == "morning" else []
    # Wheels only, past Debian's copies (pyarrow and numpy come along), and never long enough to hold up the morning.
    extra_failed = install(["install", "--quiet", "--ignore-installed", "--only-binary=:all:", *short],
                           timeout=180) if short else ""
    if short and not extra_failed and probe([extras[n] for n in short]):
        extra_failed = "installed, still won't import"
    if extra_failed:
        weak.append(f"libraries {', '.join(short)} (pip: {extra_failed}): the map spots keep the ones found before, "
                    "and a small flyer runs on no Event")
    installed = lacking + (short if not extra_failed else [])
    found = [n for n in [*libs, *(extras if routine == "morning" else ())] if n not in lacking + short]
    have = "; ".join(f"{how} {', '.join(names)}" for how, names in (("found", found), ("installed", installed)) if names)
    head = f"[ready] ready on {py}" + (f" ({have})" if have else "")
    return (f"{head}, but " + "; ".join(weak) if weak else head), True


def report(routine, runs=HERE.parents[1] / ".runs", check=ready, db=None):
    """Prints Ready's line and whether the routine may go on. The morning's line is also kept in runs/ (beside
    .runs/morning/, which prepare clears) for finish to put in the report row: each step is a process of its own,
    and a chat once read 50,000 tokens of the run's log for this one line (BP app agent-guardrails 20). A Ready
    that stops the morning writes the row itself (`failed_row`), since finish never runs."""
    try:
        line, go = check(routine)
    except Exception as e:  # a Ready that breaks says so in the row too, not only in the log
        traceback.print_exc()
        line, go = f"[ready] failed: {type(e).__name__}: {' '.join(str(e).split())[:300]}", False
    print(line)
    if routine == "morning":
        runs.mkdir(parents=True, exist_ok=True)
        (runs / KEPT).write_text(line + "\n")
        if not go:
            failed_row(line, db)
    return go


def failed_row(line, db=None):
    """The morning's report row when Ready stops it: one `[morning] Ready failed: <why>` line, which the 8:00 email
    names, instead of no row and "the morning run didn't finish". Only db.py is needed, so a library that wouldn't
    install can't stop it (finish can't import without PyYAML). A row already there today, a finished morning's,
    stays. Without a key the database takes, nothing can write a row: that is printed, and the email says no report."""
    why = line.removeprefix("[ready] ").removeprefix("failed: ")
    try:
        (db or Db()).rest("POST", "morning_reports?on_conflict=day",
                          {"day": str(datetime.now(ZoneInfo("America/Chicago")).date()),
                           "report": f"[morning] Ready failed: {why}"}, prefer="resolution=ignore-duplicates,return=minimal")
    except (Exception, SystemExit) as e:  # Db() exits when no key is set
        print(f"[ready] no report row saved either: {' '.join(str(e).split())[:200]}")


def kept(runs, now=None):
    """The morning's Ready line for finish's report, or that there is none. A Mac's .runs/ outlives a run, so a
    line over 12 hours old is an earlier morning's."""
    p = runs / KEPT
    if p.exists() and (now or time.time()) - p.stat().st_mtime < 12 * 3600:
        return p.read_text().strip()
    return "[ready] no line from this morning's Ready step: ready.py morning didn't run, or stopped before its line"


def selftest():
    ok = 0
    def check(cond, what):
        nonlocal ok
        if not cond:
            sys.exit(f"selftest failed: {what}")
        ok += 1
    secret = "https://not-to-be-printed.supabase.co"
    py = f"Python {sys.version.split()[0]}"
    env = {"SUPABASE_URL": secret, "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_x"}  # the cloud's: no key that writes
    takes = lambda: ""
    asked, fixed = [], set()
    def fake_pip(error="", fixes=True):
        def run(args, timeout=None):
            asked.append(args)
            fixed.update(args[3:] if fixes and not error else [])
            return error
        return run
    # Debian's Pillow: found, but its probe fails until pip puts a working one beside it
    probe = lambda modules: [m for m in modules if m != "json" and m.split(".")[0] not in fixed]
    with tempfile.TemporaryDirectory() as tmp:
        fake = Path(tmp) / "packages.txt"
        fake.write_text("# import name, Ubuntu package, pip name, module\njson python3-json json\n"
                        "fakepil python3-fakepil fakepil fakepil.Image\nbp_nothing python3-x bp_nothing\n")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            line, go = ready("morning", {"SUPABASE_URL": secret}, fake, fake_pip("ERROR: No matching distribution"), probe)
        check(not go and "bp_nothing" in line and "SUPABASE_SERVICE_ROLE_KEY" in line,
              f"a missing library and a missing key are both named: {line}")
        check(asked == [["install", "--quiet", "--ignore-installed", "fakepil", "bp_nothing"]],
              "a broken library and a missing one go to pip by their pip names, past the system's own copies")
        check(secret not in line + out.getvalue() and "SUPABASE_URL" not in line, "a set key is neither named nor printed")
        asked.clear()
        line, go = ready("morning", env, fake, fake_pip(), probe, reach=takes)
        check(go and line.startswith(f"[ready] ready on {py} (found json; installed fakepil, bp_nothing), but FIRECRAWL_API_KEY is not set")
              and secret not in line and "sb_publishable_x" not in line and asked[0][2] == "--ignore-installed",
              f"a found library that fails its probe is installed with --ignore-installed, Firecrawl only warned: {line}")
        fixed.clear()
        line, go = ready("social", env, fake, fake_pip(fixes=False), probe, reach=takes)
        check(not go and "still won't import" in line, f"pip saying yes is not enough: the probe runs again: {line}")
        fixed.update(["fakepil", "bp_nothing"])
        check(ready("social", env, fake, fake_pip(), probe, reach=takes) == (f"[ready] ready on {py} (found json, fakepil, bp_nothing)", True),
              "Firecrawl is the morning job's alone, and the line names the Python and every library found")
        # The public key is set but the network secret didn't come along: the database says so, by the read.
        line, go = ready("photos", env, fake, fake_pip(), probe, reach=lambda: "the database refused the key (HTTP 401)")
        check(not go and line == f"[ready] not ready on {py}: the database refused the key (HTTP 401)",
              f"a key the database refuses stops the routine at Ready: {line}")
        line, go = ready("photos", {**env, "SUPABASE_PUBLISHABLE_KEY": ""}, fake, fake_pip(), probe,
                         reach=lambda: check(False, "no key: nothing to ask the database"))
        check(not go and "SUPABASE_PUBLISHABLE_KEY (the cloud) or SUPABASE_SERVICE_ROLE_KEY (a Mac) not set" in line,
              f"no key at all is named, and the database isn't asked: {line}")
        (Path(tmp) / "fine.py").write_text("x = 1\n")
        (Path(tmp) / "newer.py").write_text("x = 1\ndef (:\n")
        line, go = ready("social", env, fake, fake_pip(), probe, scripts=Path(tmp), reach=takes)
        check(not go and "can't parse newer.py line 2" in line and "fine.py" not in line,
              f"a script this python3 can't parse stops the routine at Ready, named with its line: {line}")
    with tempfile.TemporaryDirectory() as tmp:
        fake = Path(tmp) / "packages.txt"
        fake.write_text("json python3-json json\nbp_maps - bp_maps\n")
        asked.clear()
        fails = lambda args, timeout=None: asked.append((args, timeout)) or "ERROR: No matching distribution"
        line, go = ready("morning", env, fake, fails, probe, reach=takes)
        check(go and "libraries bp_maps (pip: ERROR: No matching distribution): the map spots keep" in line
              and asked == [(["install", "--quiet", "--ignore-installed", "--only-binary=:all:", "bp_maps"], 180)],
              f"a library only the map spots need is a wheel, past system copies, within 3 minutes; failing, it "
              f"warns and the morning goes on: {line} {asked}")
        asked.clear()
        check(ready("social", env, fake, fails, probe, reach=takes) == (f"[ready] ready on {py} (found json)", True) and not asked,
              "another routine doesn't install the map spots' libraries")
        fixed.add("bp_maps")
        check(ready("morning", {**env, "FIRECRAWL_API_KEY": "k"}, fake, fake_pip(), probe, reach=takes)
              == (f"[ready] ready on {py} (found json, bp_maps)", True), "once installed, nothing to warn of, and the map spots' library is found")
    class Rows:  # the database, offline: what a failed morning's row would send, or a refusal
        def __init__(self, refuse=None):
            self.calls, self.refuse = [], refuse

        def rest(self, method, path, body=None, prefer=None):
            if self.refuse:
                raise self.refuse
            self.calls.append((method, path, body, prefer))
    today = str(datetime.now(ZoneInfo("America/Chicago")).date())
    not_ready = f"[ready] not ready on {py}: libraries numpy (pip: ERROR: No matching distribution)"
    with tempfile.TemporaryDirectory() as tmp:
        runs, said, fine, rows = Path(tmp) / ".runs", io.StringIO(), f"[ready] ready on {py} (found json)", Rows()
        with contextlib.redirect_stdout(said):
            go = report("morning", runs, check=lambda r: (fine, True), db=rows)
        check(go and said.getvalue() == fine + "\n" and kept(runs) == fine and not rows.calls,
              "the morning's line is printed and kept for finish's report row; a ready Ready writes no row")
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            go = report("morning", runs, check=lambda r: {}["SUPABASE_URL"], db=rows)
        check(not go and kept(runs) == "[ready] failed: KeyError: 'SUPABASE_URL'" and rows.calls == [
              ("POST", "morning_reports?on_conflict=day", {"day": today, "report": "[morning] Ready failed: KeyError: 'SUPABASE_URL'"},
               "resolution=ignore-duplicates,return=minimal")],
              f"a Ready that breaks keeps one plain line with its error and writes the morning's row itself, never over "
              f"a finished morning's: {kept(runs)} {rows.calls}")
        rows.calls.clear()
        with contextlib.redirect_stdout(io.StringIO()):
            go = report("morning", runs, check=lambda r: (not_ready, False), db=rows)
        check(not go and [c[2]["report"] for c in rows.calls] == [
              f"[morning] Ready failed: not ready on {py}: libraries numpy (pip: ERROR: No matching distribution)"],
              f"a morning Ready stops writes why as the row, a line the 8:00 email names: {rows.calls}")
        for refusal in (DbError("POST", "morning_reports", 401, "refused"), SystemExit("needs SUPABASE_URL and a key")):
            said = io.StringIO()
            with contextlib.redirect_stdout(said):
                go = report("morning", runs, check=lambda r: (not_ready, False), db=Rows(refusal))
            check(not go and said.getvalue().startswith(not_ready + "\n[ready] no report row saved either: "),
                  f"a row the database refuses, or no key at all, is one printed line, not a crash: {said.getvalue()}")
        rows.calls.clear()
        with contextlib.redirect_stdout(io.StringIO()):
            report("social", runs, check=lambda r: (not_ready, False), db=rows)
        check(not rows.calls, "another routine's Ready writes no morning row")
        (runs / KEPT).write_text(fine + "\n")
        check("no line from this morning's Ready step" in kept(runs, now=time.time() + 13 * 3600),
              "a line over 12 hours old is an earlier morning's")
        (runs / KEPT).unlink()
        with contextlib.redirect_stdout(io.StringIO()):
            report("social", runs, check=lambda r: (fine, True))
        check(not (runs / KEPT).exists() and "no line" in kept(runs), "only the morning keeps its line; none kept says so")
    check(key_headers(env) == {"apikey": "sb_publishable_x"}, "in the cloud the network secret sends the Watch key")
    check(key_headers({**env, "SUPABASE_SERVICE_ROLE_KEY": "s"}) == {"apikey": "s", "Authorization": "Bearer s"},
          "on a Mac the service key goes as both headers")
    check(unparsable() == [], f"every script here parses on this python3: {unparsable()}")
    check(broken(["json", "bp_nothing_here.Image"]) == ["bp_nothing_here.Image"], "the probe imports in a fresh python3")
    rows = [l.split() for l in (HERE / "ci-packages.txt").read_text().splitlines() if l.strip() and not l.startswith("#")]
    check(all(len(r) >= 3 for r in rows) and ["PIL", "python3-pil", "pillow", "PIL.Image"] in rows,
          "every library on ci-packages.txt has its pip name, and Pillow is judged by PIL.Image")
    print(f"ready.py selftest: {ok} passed, 0 failed")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    elif sys.argv[1:2] and sys.argv[1] in ROUTINES:
        sys.exit(0 if report(sys.argv[1]) else 1)
    else:
        sys.exit(__doc__)
