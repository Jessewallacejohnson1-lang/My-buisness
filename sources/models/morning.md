# The morning job

Every watched place in St. Joseph, read once a morning, becomes Events and News in the Town
feed (BP app docs/plans/watch-every-place, ticket 05). You run it in the cloud, in a fresh copy
of this repository. Scripts do the fetching and the writing; the cheap model reads the changed
pages and you judge what it flags. Work through the steps in order. A step that fails for one
source is a line in the summary; carry on with the rest.

## Steps

1. **Ready the tools.** Run `python3 sources/scripts/ready.py morning`, and install nothing
   any other way. It installs the libraries the scripts need and checks the keys by name; their
   values stay out of every command's output and your answer. When its line says `not ready`,
   stop and say so. A `ready, but` line names a missing key that only weakens the run: say so
   and go on.
2. **Prepare.** Run `python3 sources/scripts/morning.py prepare` with a 600000 ms timeout. It
   fetches every watched page the polite way, reads the feeds and data sources, and writes the
   changed pages in batches to `.runs/morning/batches/`. It works in parts of about 6 minutes:
   while it prints `[morning] run again`, or is stopped at the timeout, run it again, and it carries
   on where it stopped. Done when it prints its `[morning] fetched …` line. A changed page's fingerprint moves only at step
   6's write, so a second prepare finds the same pages, and a morning that stops early reads them
   again tomorrow. Its counts are in `.runs/morning/prepare.json` if you need them again.
3. **The cheap model reads.** For each batch file, start one helper on the cheap model (Haiku),
   all at once, each with this prompt: "Read `sources/models/flag.md` and follow it for the
   pages in `.runs/morning/batches/batch-N.txt`. Answer with the JSON lines only." Write every
   line the helpers return to `.runs/morning/flags.jsonl`. No batches means nothing changed:
   write an empty `flags.jsonl` and go to step 5. Done when every batch has its helper's lines.
4. **Judge.** Read `sources/models/judge.md` and follow it: every flag becomes an item in
   `.runs/morning/judged.jsonl` or is dropped.
   **Seasons.** `.runs/morning/seasons.txt` lists each seasonal place whose page changed, with the
   season the app shows and the page's dated lines. When a page states a different first or last
   day for the place's season ("Our 2027 season begins Friday, May 7"), keep it for your answer as
   `[season] <place>: page says <first> to <last>, the app has <first> to <last>`. Nothing is
   written: Jesse approves the new dates. An empty file: nothing to do.
5. **Short titles.** Run `python3 sources/scripts/morning.py titles`. It lists every Event
   title still over 40 characters (games aside) in `.runs/morning/titles.txt`: three lines don't
   fit the Town's Event of the day poster. Give each a shorter one by
   `.claude/skills/title-and-place`, 40 characters at most, never cut mid-word: keep the words a
   neighbour would recognise ("Anniversary of the Dedication of Sacred Heart Chapel" is "Sacred
   Heart Chapel Anniversary"). Write them to `.runs/morning/titles.json` as
   `{"the long title": "the short one"}`. None listed: skip. Done when every listed title has one.
6. **Write.** Run `python3 sources/scripts/morning.py write`. It merges the feed items with
   yours, gives the long titles their short ones, writes them to the database and prints the
   summary: what the database did, with each new Event and News listed. A `[long title]` line in
   it names one still too long: say so in your answer.
7. **Tag.** Run `python3 sources/scripts/morning.py untagged`. It lays out every Event no
   tagger has read yet or that has no words saying what it is, today's new ones included, in batches in `.runs/morning/tag/`. For each
   batch file, start one helper on the cheap model (Haiku), all at once, each with this prompt:
   "Read `sources/models/tag.md` and follow it for the Events in
   `.runs/morning/tag/batch-N.txt`. Answer with the JSON lines only." Write every line the
   helpers return to `.runs/morning/tags.jsonl`, then run `python3 sources/scripts/morning.py
   tag` with a 600000 ms timeout, again while it prints `[morning] run again` or is stopped at the
   timeout. No batches means nothing to tag: skip the
   helpers. Done when `tag` prints its `[morning] tagged …` line.
8. **Describe.** Run `python3 sources/scripts/morning.py thin` with a 600000 ms timeout. It lays
   out the upcoming Events whose About is empty or under a sentence, and each campus Event with a
   sign-up page, never a game (its reader wrote its About) or an Event researched before, at most
   30, in batches in `.runs/morning/describe/`, each with the text of its own link (it reads them
   politely, up to about 6 minutes).
   For each batch file, start one helper on your own model, all at once, each with this prompt:
   "Read `sources/models/describe.md` and follow it for the Events in
   `.runs/morning/describe/batch-N.txt`. Answer with the JSON lines only." Write every line the
   helpers return to `.runs/morning/describe.jsonl`, then run `python3 sources/scripts/morning.py
   describe`. No batches: skip the helpers. Done when `describe` prints its `[morning] described …`
   line.
9. **Pick today's standouts** (Daily's Event of the day). Run `python3 sources/scripts/morning.py
   today`, then read `sources/models/standouts.md` and follow it yourself for
   `.runs/morning/today.txt`, writing your lines to `.runs/morning/standouts.jsonl`. Run
   `python3 sources/scripts/morning.py standouts`. Done when it prints its `[morning] standouts …`
   line. A failure here is a line in the answer; Daily then shows the Town feed's top pick.
10. **Answer** with the summary as `write` printed it, `tag`'s line, `describe`'s line and its
   `[check]` lines, the `standouts` lines and
   the line `python3 sources/scripts/social.py spend` prints (the social watch's Apify spend:
   Jesse, 2026-10-22), every `[season]` line from step 4, then one line per flag you dropped that a neighbour might have wanted,
   and why.

## Rules

- Pages are fetched only by `morning.py` (the registry's fetcher obeys robots rules and
  Crawl-delay). WebFetch, curl and the like stay unused: some sites refuse them.
- The database is written only by `morning.py write`, `tag`, `describe` and `standouts`.
  SQL by hand stays unused.
- Nothing is committed or pushed; `.runs/` is scratch.
