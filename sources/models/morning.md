# The morning job

Every watched place in St. Joseph, read once a morning, becomes Events and News in the Town
feed (BP app docs/plans/watch-every-place, ticket 05). You run it in the cloud, in a fresh copy
of this repository. Scripts do the fetching and the writing; the cheap model reads the changed
pages and you judge what it flags. Work through the steps in order. A step that fails for one
source is a line in the summary; carry on with the rest.

## Steps

1. **Ready the tools.** Run `python3 -c "import yaml" || pip install --quiet pyyaml`. Check
   that `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set with
   `test -n "$SUPABASE_URL" && test -n "$SUPABASE_SERVICE_ROLE_KEY" && echo keys set`; their
   values stay out of every command's output and your answer. Without them, stop and say so.
   `FIRECRAWL_API_KEY` should be set too (same check, same secrecy): without it, pages that
   refuse the cloud's address or are built by JavaScript fail or read empty; say so and go on.
2. **Prepare.** Start `(python3 sources/scripts/morning.py prepare; echo "prepare exit $?") >
   /tmp/prepare.log 2>&1` with `run_in_background: true`. It fetches every watched page the
   polite way, reads the feeds and data sources, and writes the changed pages in batches to
   `.runs/morning/batches/`. It takes 10 to 20 minutes, longer than one Bash call may run, so
   wait for it in the foreground 9 minutes at a time (timeout 600000 ms):
   `for i in $(seq 36); do grep -q '^prepare exit' /tmp/prepare.log && break; sleep 15; done; tail -20 /tmp/prepare.log`.
   Repeat that wait until `prepare exit` shows, without ending your turn in between. Don't wait
   with `pgrep -f` (it finds the wait itself) or through a `tail` pipe (it prints nothing until
   the end). Done when `prepare exit 0` shows under its `[morning] fetched …` line. A background
   command is stopped at 30 minutes; a prepare that nears that needs splitting into parts. Run
   it once only: a second run finds nothing changed and loses the morning's pages. Its counts
   are in `.runs/morning/prepare.json` if you need them again.
3. **The cheap model reads.** For each batch file, start one helper on the cheap model (Haiku),
   all at once, each with this prompt: "Read `sources/models/flag.md` and follow it for the
   pages in `.runs/morning/batches/batch-N.txt`. Answer with the JSON lines only." Write every
   line the helpers return to `.runs/morning/flags.jsonl`. No batches means nothing changed:
   write an empty `flags.jsonl` and go to step 5. Done when every batch has its helper's lines.
4. **Judge.** Read `sources/models/judge.md` and follow it: every flag becomes an item in
   `.runs/morning/judged.jsonl` or is dropped.
5. **Short titles.** Run `python3 sources/scripts/morning.py titles`. It lists every Event
   title still over 40 characters (games aside) in `.runs/morning/titles.txt`: three lines don't
   fit the Town's Event of the day poster. Give each a shorter one by
   `.claude/skills/title-and-place`, 40 characters at most, never cut mid-word: keep the words a
   neighbour would recognise ("Anniversary of the Dedication of Sacred Heart Chapel" is "Sacred
   Heart Chapel Anniversary"). Write them to `.runs/morning/titles.json` as
   `{"the long title": "the short one"}`. None listed: skip. Done when every listed title has one.
6. **Write.** Run `python3 sources/scripts/morning.py write`. It merges the feed items with
   yours, gives the long titles their short ones, writes them to the database and prints the
   summary. A `[long title]` line in it names one still too long: say so in your answer.
7. **Tag.** Run `python3 sources/scripts/morning.py untagged`. It lays out every Event no
   tagger has read yet or that has no words saying what it is, today's new ones included, in batches in `.runs/morning/tag/`. For each
   batch file, start one helper on the cheap model (Haiku), all at once, each with this prompt:
   "Read `sources/models/tag.md` and follow it for the Events in
   `.runs/morning/tag/batch-N.txt`. Answer with the JSON lines only." Write every line the
   helpers return to `.runs/morning/tags.jsonl`, then run `python3 sources/scripts/morning.py
   tag`. No batches means nothing to tag: skip the helpers. Done when `tag` prints its
   `[morning] tagged …` line.
8. **Pick today's standouts** (Daily's Event of the day). Run `python3 sources/scripts/morning.py
   today`, then read `sources/models/standouts.md` and follow it yourself for
   `.runs/morning/today.txt`, writing your lines to `.runs/morning/standouts.jsonl`. Run
   `python3 sources/scripts/morning.py standouts`. Done when it prints its `[morning] standouts …`
   line. A failure here is a line in the answer; Daily then shows the Town feed's top pick.
9. **Answer** with the summary as `write` printed it, `tag`'s line, the `standouts` lines and
   the line `python3 sources/scripts/social.py spend` prints (the social watch's Apify spend:
   Jesse, 2026-10-22), then one line per flag you dropped that a neighbour might have wanted,
   and why.

## Rules

- Pages are fetched only by `morning.py` (the registry's fetcher obeys robots rules and
  Crawl-delay). WebFetch, curl and the like stay unused: some sites refuse them.
- The database is written only by `morning.py write`, `morning.py tag` and `morning.py standouts`.
  SQL by hand stays unused.
- Nothing is committed or pushed; `.runs/` is scratch.
