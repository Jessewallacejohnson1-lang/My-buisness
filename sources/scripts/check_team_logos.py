#!/usr/bin/env python3
"""
check_team_logos.py: does the cheap model, looking at logos with sources/models/team-logo.md, say yes to a team's own
logo and never to another's? The morning puts a logo live on that yes with no person looking first (BP app
game-card 17; Jesse, 2026-11-09: "it has evals to make sure its the correct team").

The right pairs are 101 of the 102 logos Jesse approved on 2026-11-05 (sources/evals/team-logos/right.json, whose
README says why one is left out: each team as
team_logos.py would write it, and its live logo). The wrong pairs are the same logos on other teams, lookalikes on
purpose: a co-op beside one of its schools, two Saints, the same first letter. Two schools with the same nickname, or a lone
letter that is both schools' first, are twins, never a pair: no picture tells Marshall's tiger from Farmington's, and the morning never meets that swap, as its
logo comes from that school's own page (Jesse, 2026-11-09). Each pair goes on a
sheet of 6, as a morning's, through Claude Code on Jesse's plan (no API key, no bill). A morning reads each sheet
twice and accepts a logo only on two yeses, as team_logos.keep does; the check runs three mornings.

The bar: no wrong logo accepted on any morning, and at least 90 of the 101 right ones accepted on every morning. It
prints each morning's score and every wrong yes and right no, keeps the answers in .runs/check-team-logos/, and exits
1 below the bar. Run it whenever team-logo.md or the cheap model changes.

  python3 sources/scripts/check_team_logos.py [--model haiku] [--runs 3]
  python3 sources/scripts/check_team_logos.py --selftest
"""

import argparse, json, os, random, re, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import team_logos  # noqa: E402

SOURCES = Path(__file__).resolve().parents[1]
INSTRUCTIONS = SOURCES / "models" / "team-logo.md"
FIXTURE = SOURCES / "evals" / "team-logos" / "right.json"
WRONG_MAX, RIGHT_MIN = 0, 90
PER_SHEET = 6  # as a morning's: team_logos.MAX


def nickname(t):
    return (t.get("nickname") or "").lower().split()[-1:] or [""]


def lookalike(t, other):
    """How much `other` looks like `t`'s, most first: a co-op and one of its schools (a shared name word), both Saints,
    the same first letter (a lone B for Becker or Benson)."""
    tw, ow = team_logos.words(t["name"]), team_logos.words(other["name"])
    return (bool(tw & ow - team_logos.GENERIC),
            "st" in tw and "st" in ow,
            t["name"][:1] == other["name"][:1])


def twins(t, other):
    """`other`'s logo fits `t` as well as its own school, so no picture can tell them apart: the same nickname
    (Marshall's tiger and Farmington's, both Tigers), or a lone letter that is both schools' first (Princeton's P and
    Pierz; the fixture's `letter` marks a logo that is only a letter). The morning never meets this swap: its logo is
    the one on that school's own page, which check 1 proved is the school's (Jesse, 2026-11-09). So a twin is never a
    wrong pair, nor a co-op beside its first school, whose logo the morning gives it (Anoka-Hennepin shown Anoka's)."""
    first = lambda x: team_logos.first_school(x["name"]) or ""
    return ((nickname(t) == nickname(other) and nickname(t) != [""]) or other.get("letter") == t["name"][:1]
            or first(t) == other["name"] or first(other) == t["name"])


def wrong_pairs(teams, same_picture=lambda a, b: a["logo_url"] == b["logo_url"], seed=17):
    """Each team beside the logo of the team most like it whose logo is another school's and no twin of its own:
    one wrong pair a team."""
    rnd = random.Random(seed)
    out = []
    for t in teams:
        others = [o for o in teams if o["id"] != t["id"] and o["logo_of"] != t["logo_of"] and not same_picture(t, o)
                  and not twins(t, o)]
        rnd.shuffle(others)
        o = max(others, key=lambda o: lookalike(t, o))
        out.append({**t, "logo_url": o["logo_url"], "file": o.get("file"), "right": False, "logo_is": o["name"],
                    "lookalike": [why for why, hit in zip(("name", "saint", "letter"), lookalike(t, o)) if hit]})
    return out


def together(readings):
    """A morning's answer for each logo from its readings (team_logos.READINGS): yes only when every reading says
    yes, else the first that doesn't, with its why."""
    keys = {k for r in readings for k in r}
    yes = lambda a: str((a or {}).get("answer", "")).lower() == "yes"
    return {k: next((r.get(k) or {} for r in readings if not yes(r.get(k))), readings[0].get(k)) for k in keys}


def score(pairs, said):
    """Right ones accepted, wrong ones accepted, and each wrong answer, by the pair's key."""
    yes = lambda p: str((said.get(p["key"]) or {}).get("answer", "")).lower() == "yes"
    right = [p for p in pairs if p["right"]]
    wrong_yes = [p for p in pairs if not p["right"] and yes(p)]
    right_no = [p for p in right if not yes(p)]
    return len(right) - len(right_no), wrong_yes, right_no


def ask(model, system, batch, folder):
    """One sheet through Claude Code, the Read tool only, run in the sheet's folder; nothing saved."""
    env = dict(os.environ, CLAUDE_CODE_PROMPT_CACHE_TTL="5m")
    r = subprocess.run(["claude", "-p", "--safe-mode", "--tools", "Read", "--allowedTools", "Read", "--no-session-persistence",
                        "--model", model, "--output-format", "json", "--system-prompt", system],
                       input=batch, capture_output=True, text=True, cwd=folder, env=env, timeout=600)
    if r.returncode:
        raise RuntimeError(f"claude exited {r.returncode}: {(r.stderr or r.stdout)[-300:]}")
    return json.loads(r.stdout).get("result") or ""


def selftest():
    teams = [{"id": "new-ulm", "name": "New Ulm", "logo_of": "New Ulm High School", "nickname": "Eagles", "logo_url": "a"},
             {"id": "windom", "name": "Windom", "logo_of": "Windom Area High School", "nickname": "Eagles", "logo_url": "b"},
             {"id": "annandale", "name": "Annandale", "logo_of": "Annandale High School", "nickname": "Cardinals", "logo_url": "c"},
             {"id": "annandale-maple-lake", "name": "Annandale-Maple Lake", "logo_of": "Annandale High School",
              "nickname": "Cardinals", "logo_url": "c"},
             {"id": "maple-lake", "name": "Maple Lake", "logo_of": "Maple Lake High School", "nickname": "Irish", "logo_url": "d"},
             {"id": "st-francis", "name": "St. Francis", "logo_of": "St. Francis High School", "nickname": "Fighting Saints",
              "logo_url": "e"},
             {"id": "st-cloud", "name": "St. Cloud", "logo_of": "St. Cloud", "nickname": "Crush", "logo_url": "f"},
             {"id": "princeton", "name": "Princeton", "logo_of": "Princeton High School", "nickname": "Tigers", "logo_url": "g",
              "letter": "P"},
             {"id": "pierz", "name": "Pierz", "logo_of": "Pierz High School", "nickname": "Pioneers", "logo_url": "h"}]
    wrong = {p["id"]: p for p in wrong_pairs(teams)}
    checks = [
        (wrong["new-ulm"]["logo_is"] != "Windom" and wrong["windom"]["logo_is"] != "New Ulm",
         "two Eagles are twins, never a wrong pair"),
        (wrong["annandale-maple-lake"]["logo_is"] == "Maple Lake", "a co-op gets one of its other schools' logos"),
        (wrong["annandale"]["logo_is"] not in ("Annandale-Maple Lake",), "never the same school's own logo"),
        (wrong["st-cloud"]["logo_is"] == "St. Francis", "two Saints"),
        (wrong["pierz"]["logo_is"] != "Princeton", "a lone P is any P school's: a twin, never a wrong pair"),
        (all(not p["right"] for p in wrong.values()), "every wrong pair says so"),
    ]
    pairs = [{"key": "a1", "right": True}, {"key": "a2", "right": True}, {"key": "a3", "right": False}, {"key": "a4", "right": False}]
    accepted, wrong_yes, right_no = score(pairs, {"a1": {"answer": "yes"}, "a2": {"answer": "unsure"}, "a3": {"answer": "Yes"}})
    checks.append((accepted == 1 and [p["key"] for p in wrong_yes] == ["a3"] and [p["key"] for p in right_no] == ["a2"],
                   "only a yes accepts, a wrong yes and a right non-yes are each named"))
    both = together([{"a1": {"answer": "yes"}, "a2": {"answer": "yes"}}, {"a1": {"answer": "yes"}, "a2": {"answer": "no", "why": "SF"}}])
    checks.append((both["a1"]["answer"] == "yes" and both["a2"] == {"answer": "no", "why": "SF"},
                   "a morning says yes only when both readings do, else the doubt and its why"))
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="haiku", help="the cheap model (default haiku)")
    ap.add_argument("--runs", type=int, default=3, help="mornings, each of team_logos.READINGS readings, each held to the bar (default 3)")
    ap.add_argument("--instructions", type=Path, default=INSTRUCTIONS, help="a draft of team-logo.md to try")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    from PIL import Image
    import place_photos
    teams = json.loads(FIXTURE.read_text())
    cache = SOURCES.parent / ".runs" / "check-team-logos" / "logos"
    cache.mkdir(parents=True, exist_ok=True)
    for t in teams:  # each live logo once, trimmed as the morning trims it
        t["file"] = str(cache / f"{t['id']}.png")
        if not Path(t["file"]).exists():
            with tempfile.TemporaryDirectory() as tmp:
                raw = Path(tmp) / "raw.png"
                place_photos.download(t["logo_url"], raw)
                Path(t["file"]).write_bytes(team_logos.png(team_logos.trimmed(Image.open(raw))))
    hashes = {t["id"]: place_photos.dhash(Image.open(t["file"])) for t in teams}
    same = lambda a, b: a["logo_url"] == b["logo_url"] or place_photos.same_picture(hashes[a["id"]], hashes[b["id"]])
    pairs = [{**t, "right": True} for t in teams] + wrong_pairs(teams, same)
    random.Random(9).shuffle(pairs)

    run = SOURCES.parent / ".runs" / "check-team-logos" / f'{datetime.now():%Y%m%d-%H%M%S}-{args.model}'
    run.mkdir(parents=True)
    sheets = []
    for i in range(0, len(pairs), PER_SHEET):
        part, n = pairs[i:i + PER_SHEET], i // PER_SHEET + 1
        for k, p in enumerate(part, 1):
            p["key"] = f"t{k}"
        team_logos.sheet(part, run, f"sheet-{n}")
        sheets.append((n, part))
    (run / "pairs.json").write_text(json.dumps(pairs, indent=1, ensure_ascii=False))
    system = args.instructions.read_text()

    def one(job):
        reading, (n, part) = job
        try:
            answer = ask(args.model, system, (run / f"batch-{n}.txt").read_text(), run)
        except Exception as e:
            print(f"reading {reading} sheet {n}: {e}", flush=True)
            answer = ""
        (run / f"answer-{reading}-{n}.txt").write_text(answer)
        return reading, n, team_logos.answers_in(answer)

    per = len(team_logos.READINGS)
    jobs = [(r, s) for r in range(1, args.runs * per + 1) for s in sheets]
    with ThreadPoolExecutor(6) as pool:
        got = list(pool.map(one, jobs))
    passed = True
    for morning in range(1, args.runs + 1):
        accepted, wrong_yes, right_no = 0, [], []
        for n, part in sheets:
            said = together([a for r, m, a in got if m == n and (r - 1) // per + 1 == morning])
            a, w, x = score(part, said)
            accepted, wrong_yes, right_no = accepted + a, wrong_yes + [(p, said) for p in w], right_no + [(p, said) for p in x]
        ok = len(wrong_yes) <= WRONG_MAX and accepted >= RIGHT_MIN
        passed &= ok
        print(f"morning {morning}: {accepted} of {len(teams)} right logos accepted, {len(wrong_yes)} of {len(teams)} wrong ones"
              f" accepted: {'pass' if ok else 'FAIL'}")
        for p, said in wrong_yes:
            print(f"  wrong yes: {p['name']} shown {p['logo_is']}'s ({', '.join(p['lookalike']) or 'no lookalike'}): "
                  f"{(said.get(p['key']) or {}).get('why', '')}")
        for p, said in right_no:
            a = said.get(p["key"]) or {}
            print(f"  right {a.get('answer', 'no answer')}: {p['name']} ({p['logo_of']}): {a.get('why', '')}")
    print(f"{'PASS' if passed else 'FAIL'}: bar is {WRONG_MAX} wrong and at least {RIGHT_MIN} of {len(teams)} right, "
          f"in each of {args.runs} mornings of {per} readings ({run})")
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
