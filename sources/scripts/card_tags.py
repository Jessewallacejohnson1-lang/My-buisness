#!/usr/bin/env python3
"""
card_tags.py: the fine, hidden tags on each Event and News (poetry, polka, author talk), so the Town feed can later
learn what each person likes (BP app docs/plans/feed-learns, ticket 03; Jesse, 2026-11-22 and 2026-11-24).

Tags are words from one shared list (private.tags), and nobody in the app can read them. The tagger (card-tag.md) is
handed the list and reuses a word before it makes one. A new word goes on the list only when a second helper with its own
brief agrees (new-tag.md); a word it turns down leaves the card its other tags, and a near-copy becomes the word it
copies. A game gets its sport and level by rule, with no helper (Jesse, 2026-11-24). Posts are BP app feed-learns 09's:
the Watch key is closed to them.

`prepare` lays out the Events and News with no tags yet in batches of BATCH, the same thing on several dates asked once.
`words`, after the tagger, lays out the new words for the second helper. `keep`, a step of `morning.py finish`, saves the
agreed words and the cards. A card is asked about once, whatever it ends with; one the tagger left out, or with a word
the second helper left out, waits for tomorrow.

  python3 sources/scripts/card_tags.py prepare
  python3 sources/scripts/card_tags.py words
  python3 sources/scripts/card_tags.py keep --dry-run
  python3 sources/scripts/card_tags.py --selftest
"""

import argparse
import json
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import registry  # noqa: E402
import write_judged  # noqa: E402
from db import DbError  # noqa: E402

BATCH = 40
AGENTS = ("card-tag.md", "new-tag.md")  # the two that agree on a new word, by their briefs
RULE = ("game rule", "Jesse, 2026-11-24")  # and on a game's words
NEWS_KINDS = ("business", "announcement", "campus", "school", "road")  # as the Town feed shows (supabase/town_feed.sql)
SHOW = 5  # cards a new word is shown on
WORD = re.compile(r"[^\W_](?:[^\W_]|[ '&-]){0,28}[^\W_]")  # as private.tags takes
SAVE = 400  # cards to a save


def tidy(word):
    """A word as the list holds it, or None."""
    w = " ".join(str(word).replace("’", "'").split()).strip(" .,#") if isinstance(word, str) else ""
    return w if WORD.fullmatch(w) else None


LEVELS = {"jv": "junior varsity", "c-squad": "c-squad", "c2-squad": "c-squad", "b-squad": "b-squad", "ms": "middle school sports",
          "7th grade": "middle school sports", "8th grade": "middle school sports"}
WHO = {"girls": "girls", "women's": "women's", "boys": "boys", "men's": "men's"}


def sport_words(sport):
    """A game's words from its sport and level as the schedule writes them: "Girls Basketball · JV" is basketball, girls
    basketball, junior varsity."""
    text = " ".join(str(sport or "").replace("·", " ").replace("’", "'").lower().split())
    words = []
    for level, word in LEVELS.items():
        if re.search(rf"(?<!\w){re.escape(level)}(?!\w)", text):
            text = re.sub(rf"(?<!\w){re.escape(level)}(?!\w)", " ", text)
            words.append(word)
    who = next((w for w in WHO if re.search(rf"(?<!\w){w}(?!\w)", text)), None)
    game = " ".join(t for t in text.split() if t not in (*WHO, "coed", "varsity"))
    game = "swimming" if re.match(r"swim", game) else game
    if not tidy(game):
        return []
    return list(dict.fromkeys([game, *([f"{who} {game}"] if who and tidy(f"{who} {game}") else []), *words]))


def lay(work, now):
    """(cards, games) of `work`: each thing once, its other dates its `same`, the News showing now, and the games with
    their words."""
    things, games = {}, []
    for e in work["events"]:
        if words := sport_words(e.get("sport")):
            games.append({"kind": "event", "id": e["id"], "words": words})
            continue
        key = (" ".join(e["title"].lower().split()), e["host"], e["about"])
        if key in things:
            things[key]["same"].append(e["id"])
        else:
            things[key] = {"kind": "event", "same": [], **{k: e[k] for k in ("id", "title", "host", "place", "about", "category")}}
    return [*things.values(), *({"kind": "news", "same": [], **{k: n[k] for k in ("id", "title", "host", "about", "category")}}
                                for n in work["news"] if n["category"] in NEWS_KINDS and write_judged.news_lasts_until(n) > now)], games


def message(words, cards):
    line = lambda c: {**{k: v for k, v in c.items() if k not in ("kind", "same")}, **({"news": True} if c["kind"] == "news" else {})}
    return ("Tags: " + (", ".join(words) or "none yet") + "\n\nCards:\n"
            + "".join(json.dumps(line(c), ensure_ascii=False) + "\n" for c in cards))


def prepare(run, now=None):
    folder = run.folder / "card-tags"
    if folder.exists():
        shutil.rmtree(folder)
    for name in ("card-tags.jsonl", "new-tags.jsonl"):  # an earlier prepare's answers
        (run.folder / name).unlink(missing_ok=True)
    folder.mkdir(parents=True)
    try:
        work = run.db.rest("POST", "rpc/tag_work", {})
    except DbError as e:  # the morning goes on without tags
        return print(f"[tags] skipped: {' '.join(str(e).split())[:150]}")
    cards, games = lay(work, now or datetime.now(write_judged.LOCAL))
    (folder / "cards.json").write_text(json.dumps({"words": work["words"], "cards": cards, "games": games}, indent=1, ensure_ascii=False))
    for i in range(0, len(cards), BATCH):
        (folder / f"batch-{i // BATCH + 1}.txt").write_text(message(work["words"], cards[i:i + BATCH]))
    print(f"[tags] {sum(1 + len(c['same']) for c in cards)} cards to tag in {len(cards)} lines, "
          f"{len(list(folder.glob('batch-*.txt')))} batches ({folder}); {len(games)} games by rule; {len(work['words'])} words on the list")


def given_in(lines, cards):
    """{card id: its words} from the tagger's lines, for the cards laid out: each tidy word once, its last answer."""
    ids, out = {c["id"] for c in cards}, {}
    for ln in lines:
        if isinstance(ln, dict) and ln.get("id") in ids and isinstance(ln.get("tags"), list):
            words = {}
            for w in filter(None, map(tidy, ln["tags"])):
                words.setdefault(w.lower(), w)
            out[ln["id"]] = list(words.values())
    return out


def new_in(given, listed):
    """{word in lower case: (its spelling, [card ids])} for each word not on the list."""
    have, out = {w.lower() for w in listed}, {}
    for card, words in given.items():
        for w in words:
            if w.lower() not in have:
                out.setdefault(w.lower(), (w, []))[1].append(card)
    return out


def words_text(listed, new, cards):
    """The second helper's batch: the list, then each new word with the cards that carry it."""
    by_id = {c["id"]: c for c in cards}
    on = lambda i: " | ".join(x for x in (by_id[i]["title"], by_id[i]["host"], by_id[i]["about"][:160]) if x)
    return ("Tags: " + (", ".join(listed) or "none yet") + "\n\nNew words:\n"
            + "".join(json.dumps({"word": w, "cards": sum(1 + len(by_id[i]["same"]) for i in ids), "on": [on(i) for i in ids[:SHOW]]},
                                 ensure_ascii=False) + "\n" for w, ids in new.values()))


def settle(new, lines, listed):
    """What the second helper made of each new word it answered: {word in lower case: the word its cards get, or None},
    and the spellings it agreed to. A near-copy's `use` counts only when it is on the list or agreed to."""
    said = {}
    for ln in lines:
        if isinstance(ln, dict) and isinstance(ln.get("word"), str) and ln["word"].lower() in new and isinstance(ln.get("ok"), bool):
            said[ln["word"].lower()] = ln
    agreed = [new[k][0] for k, ln in said.items() if ln["ok"]]
    known = {w.lower(): w for w in [*listed, *agreed]}
    return {k: new[k][0] if ln["ok"] else known.get(str(ln.get("use") or "").lower()) for k, ln in said.items()}, agreed


def plan(given, listed, settled):
    """({card id: its words}, card ids that wait): every new word on a card must have an answer."""
    have, out, wait = {w.lower(): w for w in listed}, {}, []
    for card, words in given.items():
        if any(w.lower() not in have and w.lower() not in settled for w in words):
            wait.append(card)
            continue
        got = [have.get(w.lower()) or settled.get(w.lower()) for w in words]
        out[card] = list(dict.fromkeys(w for w in got if w))
    return out, wait


def lines_in(path):
    """A helper's JSON lines; one that isn't JSON is skipped."""
    out = []
    for ln in path.read_text().splitlines() if path.exists() else []:
        try:
            out.append(json.loads(ln.strip().strip(",")))
        except ValueError:
            continue
    return out


def worked(run):
    """(what `prepare` laid out, the tagger's words per card, the new words), or None with nothing laid out."""
    path = run.folder / "card-tags" / "cards.json"
    if not path.exists():
        return None
    laid = json.loads(path.read_text())
    given = given_in(lines_in(run.folder / "card-tags.jsonl"), laid["cards"])
    return laid, given, new_in(given, laid["words"])


def lay_words(run):
    got = worked(run)
    path = run.folder / "card-tags" / "new-words.txt"
    path.unlink(missing_ok=True)
    if not got or not got[2]:
        return print("[tags] no new words")
    laid, _, new = got
    path.write_text(words_text(laid["words"], new, laid["cards"]))
    print(f"[tags] {len(new)} new words to check ({path})")


def decided(laid, given, new, verdicts):
    """(the words to make, the cards to save, the lines of the report) from both helpers' answers."""
    settled, agreed = settle(new, verdicts, laid["words"])
    words, wait = plan(given, laid["words"], settled)
    cards = [{"kind": c["kind"], "id": i, "words": words[c["id"]]} for c in laid["cards"] if c["id"] in words
             for i in (c["id"], *c["same"])]
    rule = list(dict.fromkeys(w for g in laid["games"] for w in g["words"]))
    make = ([{"word": w, "first_by": AGENTS[0], "second_by": AGENTS[1]} for w in agreed]
            + [{"word": w, "first_by": RULE[0], "second_by": RULE[1]} for w in rule
               if w.lower() not in {x.lower() for x in [*laid["words"], *agreed]}])
    count = lambda kind, rows: sum(r["kind"] == kind for r in rows)
    of = lambda kind: sum(1 + len(c["same"]) for c in laid["cards"] if c["kind"] == kind)
    have = [c for c in cards if c["words"]]
    lines = [f"[tags] tagged {count('event', have)} of {of('event')} Events, {count('news', have)} of {of('news')} News, "
             f"{len(laid['games'])} games by rule; {len(cards) - len(have)} fit no tag, {len(wait)} wait for tomorrow"]
    if new:
        lines.append(f"[tags] new words: the second helper agreed to {len(agreed)} of {len(settled)} "
                     f"({len(agreed) / max(1, len(settled)):.0%}), {len(new) - len(settled)} not answered")
        lines += [f"- New tag: {', '.join(agreed)}"] if agreed else []
        lines += [f"- Turned down: {new[k][0]}" + (f" (is {use})" if use else "")
                  for k, use in settled.items() if use != new[k][0]]
    return make, cards + laid["games"], lines


def keep(run, dry_run=False):
    got = worked(run)
    if not got:
        return []
    done = run.part(f"card-tags/kept{'-dry-run' if dry_run else ''}.json")
    if done.saved is not None:
        return done.saved
    make, cards, lines = decided(*got, lines_in(run.folder / "new-tags.jsonl"))
    if dry_run:
        lines[0] += " (dry run: nothing written)"
    else:
        # The words go with the first cards; a save that breaks leaves the rest for finish run again.
        listed = None
        for i in range(0, max(len(cards), 1 if make else 0), SAVE):
            saved = run.db.rest("POST", "rpc/save_card_tags", {"p_words": make if i == 0 else [], "p_cards": cards[i:i + SAVE]})
            listed = saved.get("list") if isinstance(saved, dict) else None
        lines[0] += f"; {listed} words on the list" if listed is not None else ""
    done.save(lines)
    return lines


def selftest():
    import tempfile
    from datetime import date, timedelta
    from morning_run import FakeDb, Run
    checks = []
    ok = lambda good, why: checks.append((bool(good), why))

    ok([tidy(w) for w in ("  poetry ", "Saint John’s", "#jazz", "x", "a" * 31, "jazz; drop", "hip-hop", "R&B", None, "café")]
       == ["poetry", "Saint John's", "jazz", None, None, None, "hip-hop", "R&B", None, "café"], "a word is tidied, or it isn't one")
    said = {s: sport_words(s) for s in ("Girls Basketball · JV", "Boys Hockey", "Wrestling · Boys MS", "Swimming and Diving", "Boys Swim",
                                        "MS Coed Wrestling", "Boys Basketball · C2-squad", "Adapted Floor Hockey", "Men's Hockey",
                                        "Girls Basketball · 7th Grade", "Football", "", None)}
    ok(said == {"Girls Basketball · JV": ["basketball", "girls basketball", "junior varsity"], "Boys Hockey": ["hockey", "boys hockey"],
                "Wrestling · Boys MS": ["wrestling", "boys wrestling", "middle school sports"], "Swimming and Diving": ["swimming"],
                "Boys Swim": ["swimming", "boys swimming"], "MS Coed Wrestling": ["wrestling", "middle school sports"],
                "Boys Basketball · C2-squad": ["basketball", "boys basketball", "c-squad"],
                "Adapted Floor Hockey": ["adapted floor hockey"], "Men's Hockey": ["hockey", "men's hockey"],
                "Girls Basketball · 7th Grade": ["basketball", "girls basketball", "middle school sports"], "Football": ["football"],
                "": [], None: []}, f"a game's words are its sport and level: {said}")

    cards = [{"id": "a", "title": "Reading", "host": "CSB", "about": "Poems.", "same": ["a2"], "kind": "event"},
             {"id": "b", "title": "Polka Mass", "host": "Church", "about": "", "same": [], "kind": "event"},
             {"id": "n", "title": "Soup", "host": "Cafe", "about": "", "same": [], "kind": "news"}]
    given = given_in([{"id": "a", "tags": ["Poetry", "poems", "poetry", 7, "##"]}, {"id": "b", "tags": ["polka", "Mass"]},
                      {"id": "zz", "tags": ["polka"]}, {"id": "n"}, "x"], cards)
    ok(given == {"a": ["Poetry", "poems"], "b": ["polka", "Mass"]}, f"only cards laid out, each tidy word once: {given}")
    new = new_in(given, ["poetry"])
    ok({k: v[1] for k, v in new.items()} == {"poems": ["a"], "polka": ["b"], "mass": ["b"]}, f"a word on the list, in any spelling, isn't new: {new}")
    text = words_text(["poetry"], new, cards)
    ok(text.startswith("Tags: poetry\n\nNew words:\n") and '{"word": "poems", "cards": 2, "on": ["Reading | CSB | Poems."]}' in text,
       f"the second helper sees the list, and each new word on its cards: {text}")
    settled, agreed = settle(new, [{"word": "Poems", "ok": False, "use": "Poetry"}, {"word": "polka", "ok": True},
                                   {"word": "mass", "ok": False, "use": "worship"}, {"word": "made up", "ok": True}, {"word": "polka"}], ["poetry"])
    ok(settled == {"poems": "poetry", "polka": "polka", "mass": None} and agreed == ["polka"],
       f"a new word needs the second helper's yes; a near-copy becomes the word it copies; one off the list is no answer: {settled}")
    ok(plan(given, ["poetry"], settled) == ({"a": ["poetry"], "b": ["polka"]}, []), "a word turned down leaves the card its other tags, as the list spells them")
    ok(plan(given, ["poetry"], {"poems": "poetry"}) == ({"a": ["poetry"]}, ["b"]), "a card whose new word has no answer waits for tomorrow")
    ok(plan({"b": ["mass"]}, [], {"mass": None}) == ({"b": []}, []), "a card left with no word is done")

    now = datetime.now(write_judged.LOCAL)
    stamp = lambda days: (now - timedelta(days=days)).isoformat()
    event = lambda i, title, **more: {"id": i, "title": title, "host": "CSB", "place": "Hall", "about": "", "category": "talks", "sport": None,
                                      "event_date": "2026-12-01", **more}
    story = lambda i, **more: {"id": i, "title": i, "host": "Cafe", "about": "", "category": "business", "created_at": stamp(1), "published_at": stamp(1),
                               "posted_at": None, "starts_at": None, "ends_on": None, **more}
    work = {"words": ["poetry"], "events": [event("new", "Reading"), event("t1", "Trivia"), event("t2", " trivia"), event("t3", "Trivia", about="Other."),
                                            event("g", "ROCORI vs Sartell", sport="Boys Hockey · JV")],
            "news": [story("n1"), story("gone", created_at=stamp(9), published_at=stamp(9)), story("job", category="jobs")]}
    with tempfile.TemporaryDirectory() as tmp:
        db = FakeDb(answers={"rpc/tag_work": work, "rpc/save_card_tags": {"words": 1, "events": 3, "news": 1, "list": 5}})
        run = Run(Path(tmp), date(2026, 11, 24), db)
        (run.folder / "card-tags.jsonl").write_text("yesterday's")
        prepare(run, now)
        batch = (run.folder / "card-tags" / "batch-1.txt").read_text()
        asked = [json.loads(x) for x in batch.splitlines() if x.startswith("{")]
        ok(batch.startswith("Tags: poetry\n\nCards:\n") and [(x["id"], x.get("news")) for x in asked]
           == [("new", None), ("t1", None), ("t3", None), ("n1", True)] and "kind" not in asked[0]
           and not (run.folder / "card-tags.jsonl").exists(),
           f"each thing is asked about once, a game never, News only while it shows, on the list: {batch}")
        (run.folder / "card-tags.jsonl").write_text('not json\n{"id": "new", "tags": ["poetry", "author talk"]},\n'
                                                    '{"id": "t1", "tags": ["trivia"]}\n{"id": "n1", "tags": ["soup"]}\n')
        lay_words(run)
        ok('"word": "author talk"' in (run.folder / "card-tags" / "new-words.txt").read_text(), "the new words are laid out")
        (run.folder / "new-tags.jsonl").write_text('{"word": "author talk", "ok": true}\n{"word": "trivia", "ok": true}\n{"word": "soup", "ok": false}\n')
        dry = keep(run, True)
        ok(not db.writes("rpc/save_card_tags") and "(dry run: nothing written)" in dry[0], f"a dry run writes nothing: {dry}")
        lines = keep(run)
        (_, _, sent), = db.writes("rpc/save_card_tags")
        ok([(c["id"], c["words"]) for c in sent["p_cards"]] == [("new", ["poetry", "author talk"]), ("t1", ["trivia"]), ("t2", ["trivia"]),
                                                               ("n1", []), ("g", ["hockey", "boys hockey", "junior varsity"])]
           and [c["kind"] for c in sent["p_cards"]] == ["event", "event", "event", "news", "event"],
           f"every date of a thing gets its words, one nothing fits is done, one left out waits, and a game has its rule: {sent['p_cards']}")
        ok({w["word"]: (w["first_by"], w["second_by"]) for w in sent["p_words"]}
           == {"author talk": AGENTS, "trivia": AGENTS, "hockey": RULE, "boys hockey": RULE, "junior varsity": RULE},
           f"a new word names the two that agreed: {sent['p_words']}")
        ok(lines == ["[tags] tagged 3 of 4 Events, 0 of 1 News, 1 games by rule; 1 fit no tag, 0 wait for tomorrow; 5 words on the list",
                     "[tags] new words: the second helper agreed to 2 of 3 (67%), 0 not answered",
                     "- New tag: author talk, trivia", "- Turned down: soup"], f"the report counts cards, words and the agreement: {lines}")
        ok(keep(run) == lines and len(db.writes("rpc/save_card_tags")) == 1, "a finish run again neither writes nor reports twice")
        (run.folder / "new-tags.jsonl").unlink()
        (run.folder / "card-tags" / "kept.json").unlink()
        ok("3 wait for tomorrow" in keep(run)[0] and [c["id"] for c in db.writes("rpc/save_card_tags")[1][2]["p_cards"]] == ["g"],
           "with no second helper, no new word goes live and its cards wait")

        def refuse(*_):
            raise DbError("POST", "rpc/tag_work", 404, "no function")
        down = Run(Path(tmp), date(2026, 11, 24), FakeDb(answers={"rpc/tag_work": refuse}))
        prepare(down)
        ok(keep(down) == [] and not list((down.folder / "card-tags").iterdir()), "with no answer from the database the morning goes on without tags")
    failed = [why for good, why in checks if not good]
    for why in failed:
        print(f"FAIL {why}")
    print(f"{len(checks) - len(failed)} passed, {len(failed)} failed")
    return not failed


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("step", nargs="?", choices=["prepare", "words", "keep"])
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if selftest() else 1)
    from morning_run import Run
    from run import Supabase
    folder, today = registry.find_root() / ".runs" / "morning", datetime.now(write_judged.LOCAL).date()
    if a.step == "words":
        lay_words(Run(folder, today))
    elif a.step == "prepare":
        prepare(Run(folder, today, Supabase()))
    elif a.step == "keep":
        print("\n".join(keep(Run(folder, today, Supabase()), a.dry_run)))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
