#!/usr/bin/env python3
"""
morning_run.py: one morning's or one social check's folder, .runs/morning/, and how its steps carry on
across parts (BP app codebase-health-2, ticket 11; its SPEC.md, section F).

Each command of the morning job and the social check is a process of its own, and the cloud stops a
command at 10 minutes, so long work runs in parts of about 6: a part saves where it got to and prints "run
again", and the next part carries on. Run is what a step needs to know: the folder, the day, the town, which
check this is, the part's clock and the database. Part is the one way a step remembers its progress.

  python3 sources/scripts/morning_run.py --selftest
"""

import json, os, shutil, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run import Supabase, CLEAR, deadline, late, only_one
from towns import DEFAULT

PART_MINUTES = 6  # a part starts nothing new after this, so it ends within 9: the cloud stops a command at 10


class Part:
    """A step's memory across the parts of a run: a JSON file, read when the part starts and saved as it
    goes. `path` None keeps it in memory only (a reader run by hand, not as a part)."""

    def __init__(self, path, stop=None, empty=None):
        self.path, self.stop = Path(path) if path else None, stop
        self.saved = json.loads(self.path.read_text()) if self.path and self.path.exists() else empty

    def save(self, saved=None):
        """Written whole or not at all: a part the cloud stops mid-write leaves the last good file."""
        if saved is not None:
            self.saved = saved
        if self.path:
            spare = self.path.with_name(f"{self.path.name}.{os.getpid()}.new")  # its own: two processes never share one
            spare.write_text(json.dumps(self.saved, default=str))
            spare.replace(self.path)

    def each(self, keys, work):
        """work(key) for each key not done in an earlier part, saved after each so a stopped part loses
        none, starting none once the part's time is spent. Returns how many are still to do. A work that
        raises leaves its key to do; those before it stay done."""
        keys, done = list(keys), set(self.saved or ())
        for key in keys:
            if key in done:
                continue
            if late(self.stop):
                break
            work(key)
            done.add(key)
            self.save(sorted(done))
        return sum(k not in done for k in keys)


class Run:
    """One check's folder, day, town and database, and the clock of the part this process is. `check`
    names a social check (busy, weekly); a morning has none."""

    def __init__(self, folder, today, db=None, town=DEFAULT, check=None, minutes=PART_MINUTES):
        self.folder, self.today, self.db, self.town, self.check = Path(folder), today, db, town, check
        self.stop = deadline(minutes)
        self._summary = self.folder / "prepare.json"

    def part(self, name, empty=None):
        """The memory `name`, in this run's folder and on this part's clock."""
        return Part(self.folder / name, self.stop, empty)

    def begin(self, name, empty):
        """Where a prepare stands, and its part: "busy", another prepare holds the lock (a second one
        beside it spent 49 minutes redoing pictures on Oct 29); "prepared", this check is already through
        prepare, so nothing is read again; "new", any other check's folder was cleared and `empty` starts
        this one; or "carrying on" from an earlier part."""
        self.folder.parent.mkdir(parents=True, exist_ok=True)
        if not only_one(self.folder.parent / "prepare.lock"):
            return "busy", None
        prep = self.summary() if self._summary.exists() else {}
        if prep.get("run") == self.check and prep.get("today") == str(self.today) and not prep.get("done"):
            return "prepared", None
        part = self.part(name, {})
        if part.saved.get("run") != self.check or part.saved.get("today") != str(self.today) or prep:
            if self.folder.exists():
                shutil.rmtree(self.folder)
            (self.folder / "batches").mkdir(parents=True)
            part.saved = {"today": str(self.today), "run": self.check, **empty}
            return "new", part
        return "carrying on", part

    def summary(self):
        """What prepare found, once it is through. No step runs before prepare, so no file stops it there."""
        return json.loads(self._summary.read_text())

    def prepared(self, summary):
        self._summary.write_text(json.dumps(summary, indent=1))

    def finished(self):
        """The check is over: the next prepare starts a new one."""
        self.prepared({**self.summary(), "done": True})


class FakeDb(Supabase):
    """The database for a step's self-test, offline: the `sources` table's rows in memory and every other call
    kept in `calls`. `answers`: what a call gets, by the start of its path, as rows or as a function of
    (method, path, body)."""

    def __init__(self, rows=None, answers=None):
        self.rows, self.answers, self.calls = rows if rows is not None else {}, answers or {}, []

    def upsert_registry(self, rows):
        pass

    def state(self):
        return ({k: r.get("last_hash") for k, r in self.rows.items()},
                {k for k, r in self.rows.items() if r.get("last_checked_at")},
                {k: dict(r) for k, r in self.rows.items() if any(r.get(c) for c in CLEAR)})

    def record(self, entry_id, url, fields):
        self.rows.setdefault(f"{entry_id}|{url}", {}).update(fields)

    def rest(self, method, path, body=None, prefer=None):
        self.calls.append((method, path, body))
        answer = next((a for start, a in self.answers.items() if path.startswith(start)), [])
        return answer(method, path, body) if callable(answer) else answer

    def writes(self, start=""):
        """The calls that change something, whose path starts with `start`. The read-only functions the
        steps call over POST aren't writes."""
        return [c for c in self.calls if c[0] != "GET" and c[1].startswith(start)
                and c[1] not in ("rpc/listed_for_writer", "rpc/event_picture", "rpc/live_marks")]


def selftest():
    import subprocess, tempfile
    from datetime import date
    import run as runner

    checks, was = [], runner.time
    clock = type("Clock", (), {"t": 1000.0, "monotonic": lambda self: self.t, "time": lambda self: self.t})()
    day, other_day = date(2026, 11, 3), date(2026, 11, 4)
    runner.time = clock
    try:
        with tempfile.TemporaryDirectory() as tmp:
            memo = Path(tmp) / "memo.json"
            did = []

            def slow(key):
                clock.t += 150
                did.append(key)
            left = Part(memo, deadline(6)).each("abcd", slow)
            checks.append((left == 1 and did == ["a", "b", "c"], "a part starts nothing once its time is spent, and says how many are left"))
            left = Part(memo, deadline(6)).each("abcd", slow)
            checks.append((left == 0 and did == ["a", "b", "c", "d"], "the next part does only what is left"))
            left = Part(memo, deadline(6)).each("abcd", slow)
            checks.append((left == 0 and len(did) == 4, "run again once done, it does nothing"))
            memo.unlink()
            did.clear()

            def breaks(key):
                if key == "b" and "broke" not in did:
                    did.append("broke")
                    raise RuntimeError("a timeout")
                did.append(key)
            try:
                Part(memo).each("abc", breaks)
            except RuntimeError:
                pass
            checks.append((json.loads(memo.read_text()) == ["a"], "a write that breaks leaves those before it done, and itself not"))
            checks.append((Part(memo).each("abc", breaks) == 0 and did == ["a", "broke", "b", "c"], "the next part writes only the rest"))
            real = Path.replace

            def cut_off(self, target):
                raise KeyboardInterrupt  # the cloud stops the command as it saves
            kept = Part(memo)
            Path.replace = cut_off
            try:
                kept.save(["z"])
            except KeyboardInterrupt:
                pass
            finally:
                Path.replace = real
            checks.append((json.loads(memo.read_text()) == ["a", "b", "c"], "a part stopped as it saves leaves the last good file"))
            checks.append((Part(memo.with_name("dated.json")).save({"day": day}) is None
                           and json.loads(memo.with_name("dated.json").read_text()) == {"day": "2026-11-03"},
                           "a date in a part's memory is saved as text (the league's listings)"))
            checks.append((Part(None, empty={"n": 1}).saved == {"n": 1} and Part(None).save({"n": 2}) is None, "no path: memory only"))
            checks.append((Part(memo.with_name("never.json"), empty=[]).saved == [], "no file yet: the empty it was given"))

            folder = Path(tmp) / "town" / "morning"
            run = Run(folder, day, check=None)
            state, part = run.begin("prepare-part.json", {"pages": []})
            checks.append((state == "new" and part.saved == {"today": "2026-11-03", "run": None, "pages": []}
                           and (folder / "batches").is_dir(), "the first part of a morning starts it"))
            part.saved["pages"].append("p1")
            part.save()
            (folder / "flags.jsonl").write_text("x")
            state, part = Run(folder, day).begin("prepare-part.json", {"pages": []})
            checks.append((state == "carrying on" and part.saved["pages"] == ["p1"] and (folder / "flags.jsonl").exists(),
                           "the next part carries on, with its folder"))
            state, part = Run(folder, other_day).begin("prepare-part.json", {"pages": []})
            checks.append((state == "new" and part.saved["pages"] == [] and not (folder / "flags.jsonl").exists(),
                           "a part left from another day starts over, its folder cleared"))
            part.save()
            state, part = Run(folder, other_day, check="busy").begin("social-part.json", {"failed": []})
            checks.append((state == "new" and part.saved["run"] == "busy" and not (folder / "prepare-part.json").exists(),
                           "a social check beside a morning's part is its own, and clears the morning's"))
            part.save()
            state, _ = Run(folder, other_day, check="weekly").begin("social-part.json", {"failed": []})
            checks.append((state == "new", "another social check doesn't carry on from this one's part"))
            run = Run(folder, day)
            state, part = run.begin("prepare-part.json", {"pages": []})
            part.save()
            (folder / "flags.jsonl").write_text("x")
            run.prepared({"today": "2026-11-03", "fetched": 3})
            state, part = Run(folder, day).begin("prepare-part.json", {"pages": []})
            checks.append((state == "prepared" and part is None and (folder / "flags.jsonl").exists(),
                           "once prepared, a prepare run again starts nothing over and keeps the helpers' files"))
            state, _ = Run(folder, day, check="busy").begin("social-part.json", {"failed": []})
            checks.append((state == "new", "a social check after a morning's prepare starts its own"))
            run = Run(folder, day)
            _, part = run.begin("prepare-part.json", {"pages": []})
            part.save()  # a part left beside a finished check
            run.prepared({"today": "2026-11-03", "fetched": 3})
            run.finished()
            checks.append((run.summary() == {"today": "2026-11-03", "fetched": 3, "done": True}, "a finished check keeps its summary, marked done"))
            state, _ = Run(folder, day).begin("prepare-part.json", {"pages": []})
            checks.append((state == "new", "and the next prepare, the same day too, starts a new one"))
            (Path(tmp) / "held").mkdir()
            holder = subprocess.Popen([sys.executable, "-c", "import fcntl,sys,time\nf=open(sys.argv[1],'w')\n"
                                       "fcntl.flock(f,fcntl.LOCK_EX)\nprint('held',flush=True)\ntime.sleep(30)",
                                       str(Path(tmp) / "held" / "prepare.lock")], stdout=subprocess.PIPE, text=True)
            holder.stdout.readline()
            state, part = Run(Path(tmp) / "held" / "morning", day).begin("prepare-part.json", {})
            holder.kill()
            holder.wait()
            checks.append((state == "busy" and part is None, "another prepare holding the lock: this one starts nothing"))
            db = FakeDb({"a|u": {"last_hash": "h", "last_checked_at": "t", "last_error": "e"}}, {"teams": [{"id": 1}], "rpc/x": lambda m, p, b: b})
            db.record("b", "v", {"last_hash": "n"})
            checks.append((db.rest("GET", "teams?select=id") == [{"id": 1}] and db.rest("POST", "rpc/x", 7) == 7 and db.rest("GET", "else") == []
                           and db.writes() == [("POST", "rpc/x", 7)] and db.state()[0] == {"a|u": "h", "b|v": "n"}
                           and db.state()[1] == {"a|u"} and list(db.state()[2]) == ["a|u"],
                           "the fake database answers reads, keeps writes and holds the sources rows"))
    finally:
        runner.time = was
    failed = [why for ok, why in checks if not ok]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    print(__doc__)
