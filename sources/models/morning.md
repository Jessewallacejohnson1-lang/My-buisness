# The morning job

Every watched place in St. Joseph, read once a morning, becomes Events and News in the Town
feed (BP app docs/plans/watch-every-place, ticket 05). You run it in the cloud, in a fresh copy
of this repository. Scripts fetch, save and report; helpers read; you judge. Do the steps in
order, each once. Give every command a 600000 ms timeout: while one prints `run again`, or is
stopped at the timeout, run it again, and it carries on where it stopped. A source that fails
is a line in the report; carry on with the rest.

## Steps

**Ready.** Run `python3 sources/scripts/ready.py morning`, and install nothing any other way.
`not ready`: stop and say so. `ready, but`: say so and go on. Keys' values stay out of every
command's output and your answer.

**Prepare.** Run `python3 sources/scripts/morning.py prepare` until it prints its
`[morning] fetched …` line. The changed pages are in batches in `.runs/morning/batches/`.

**Read and judge.**
- For each batch file, start one helper on the cheap model (Haiku), all at once, each with: "Read
  `sources/models/flag.md` and follow it for the pages in `.runs/morning/batches/batch-N.txt`.
  Answer with the JSON lines only." Write their lines to `.runs/morning/flags.jsonl` (no
  batches: an empty file).
- Read `sources/models/judge.md` and follow it: every flag becomes an item in
  `.runs/morning/judged.jsonl` or is dropped.
- `.runs/morning/seasons.txt` lists each seasonal place whose page changed, with the app's
  season and the page's dated lines. A page stating another first or last day ("Our 2027 season
  begins Friday, May 7") is a line for your answer, `[season] <place>: page says <first> to
  <last>, the app has <first> to <last>`; nothing is written (Jesse approves new dates).
- Run `python3 sources/scripts/morning.py titles`. Give each title in `.runs/morning/titles.txt`
  a shorter one by `.claude/skills/title-and-place`: 40 characters at most, never cut mid-word,
  keeping the words a neighbour would recognise ("Sacred Heart Chapel Anniversary"). Write them
  to `.runs/morning/titles.json` as `{"the long title": "the short one"}`.

**Save.** Run `python3 sources/scripts/morning.py save`. It writes the items and lays out the
helpers' batches in `.runs/morning/tag/` and `.runs/morning/describe/`. A `save refused` line
ends the morning: answer with it.

**Helpers.** Start them all at once:
- for each `.runs/morning/tag/batch-N.txt`, one helper on the cheap model (Haiku) with: "Read
  `sources/models/tag.md` and follow it for the Events in `.runs/morning/tag/batch-N.txt`.
  Answer with the JSON lines only." Their lines go to `.runs/morning/tags.jsonl`.
- for each `.runs/morning/describe/batch-N.txt`, one helper on your own model with the same
  words for `describe.md` and its batch. Their lines go to `.runs/morning/describe.jsonl`.
- Once every helper's lines are in, run `python3 sources/scripts/morning.py today`, then read
  `sources/models/standouts.md` and follow it yourself for `.runs/morning/today.txt` (today's
  Events with the helpers' tags and Abouts), writing your lines to `.runs/morning/standouts.jsonl`.

**Finish.** Run `python3 sources/scripts/morning.py finish` until it prints the report. It saves
the tags, Abouts and standouts and prints the whole morning report; a save that failed is a line
in it. Answer with Ready's line if it said `ready, but`, then that report as printed, then your
`[season]` lines, then one line per flag you dropped that a neighbour might have wanted, and
why. Nothing else.

## Rules

- Pages are fetched only by `morning.py` (the registry's fetcher obeys robots rules and
  Crawl-delay). WebFetch, curl and the like stay unused: some sites refuse them.
- The database is written only by `morning.py save` and `finish`. SQL by hand stays unused.
- Nothing is committed or pushed; `.runs/` is scratch.
