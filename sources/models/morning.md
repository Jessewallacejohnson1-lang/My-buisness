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
- For each batch file, start one helper on the cheap model (Haiku), at most 10 running at once
  (the cloud refuses more: Oct 29's 53 at once lost six), each with: "Read
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
  keeping the words a neighbour would recognise ("Sacred Heart Chapel Anniversary"). The titles
  under its `News, 30 characters at most:` line are News headlines past their card's 2 lines: 30
  at most, keeping what happened ("Pumpkin Cold Brew at Caribou"). Write them all to
  `.runs/morning/titles.json` as `{"the long title": "the short one"}`.
- `titles` also lays out `.runs/morning/repeats/`: each new News the word rules didn't settle, beside
  what its place already has. For each `.runs/morning/repeats/batch-N.txt`, start one helper on your own
  model (Haiku read too unevenly: BP app smooth-mornings 16) with: "Read `sources/models/repeat.md` and follow it for
  `.runs/morning/repeats/batch-N.txt`. Answer with the JSON lines only." Write their lines to
  `.runs/morning/repeats.jsonl`. Save holds back each News they call a repeat.

**Save.** Run `python3 sources/scripts/morning.py save`. It writes the items and lays out the
helpers' batches in `.runs/morning/tag/` and `.runs/morning/describe/`. A `save stopped` line
names judged lines the writer can't use: fix each in `.runs/morning/judged.jsonl` and run save
again. A `save refused` line ends the morning: answer with it.

**Helpers.** First run `python3 sources/scripts/event_photos.py prepare`: it lays out each new Event's
pictures, games aside, and each new News's own post pictures, on sheets in `.runs/morning/photos/` (event-photos 09,
town-feed 53). Then run `python3 sources/scripts/team_logos.py prepare`: it looks up a logo for each team whose games
wait on one, on a sheet in `.runs/morning/logos/` (game-card 17). Then run `python3 sources/scripts/venue_spots.py prepare`: it
takes the place lines of upcoming Events that have no spot, at most 8, into `.runs/morning/venues/batch.txt` (BP app
inside-cards 20; `skipped` or no batch: nothing to do). Then start the helpers
together, at most 10 running at once:
- for each `.runs/morning/tag/batch-N.txt`, one helper on the cheap model (Haiku) with: "Read
  `sources/models/tag.md` and follow it for the Events in `.runs/morning/tag/batch-N.txt`.
  Answer with the JSON lines only." Their lines go to `.runs/morning/tags.jsonl`.
- for each `.runs/morning/describe/batch-N.txt`, one helper on your own model with the same
  words for `describe.md` and its batch. Their lines go to `.runs/morning/describe.jsonl`.
- for each `.runs/morning/photos/batch-N.txt`, one helper on your own model (Jesse, 2026-11-07: Sonnet
  picks every photo, BP app dig-deeper 08) with: "Read
  `sources/models/event-photo.md` and follow it for `.runs/morning/photos/batch-N.txt`. Answer with the
  JSON lines only." Their lines go to `.runs/morning/event_photos.jsonl`.
- when `.runs/morning/logos/batch.txt` exists, two helpers on the cheap model (Haiku), each with: "Read
  `sources/models/team-logo.md` and follow it for `.runs/morning/logos/batch.txt`. Answer with the JSON lines only."
  The first's lines go to `.runs/morning/logos.jsonl`, the second's to `.runs/morning/logos-2.jsonl`. Only both
  their yeses put a logo live: never answer for them yourself.
- when `.runs/morning/venues/batch.txt` exists, two helpers on your own model (Jesse, 2026-11-09: "allow with an agent
  check"), each on its own and with the same words: "Read `sources/models/venue-spot.md` and follow it for
  `.runs/morning/venues/batch.txt`. Answer with the JSON lines only." The first's lines go to `.runs/morning/venues.jsonl`,
  the second's to `.runs/morning/venues-2.jsonl`. A spot goes live only where both agree: never answer for them yourself.
- Once every helper's lines are in, run `python3 sources/scripts/event_photos.py keep` (it saves the picked
  photos), then `python3 sources/scripts/morning.py today`, then read
  `sources/models/standouts.md` and follow it yourself for `.runs/morning/today.txt` (today's
  Events with the helpers' tags and Abouts), writing your lines to `.runs/morning/standouts.jsonl`.

**Dig.** The Events keep left with no photo look further (BP app dig-deeper 22). Run
`python3 sources/scripts/event_photos.py dig`; `no Event left bare` skips to Finish. On Sundays it is the weekly pass
(dig-deeper 24): every Event of the next four weeks still bare, however long ago it was found, so it may hand out more
batches than a weekday. Helpers on your own
model, at most 10 running at once:
- for each `.runs/morning/dig/find-N.txt`, one helper with: "Read the Find part of
  `sources/models/dig.md` and follow it for `.runs/morning/dig/find-N.txt`. Answer with the JSON lines
  only." Their lines go to `.runs/morning/dig/pages.jsonl`.
- then run `python3 sources/scripts/event_photos.py dig-sheets` until it prints its `[dig] laid out` line;
- for each `.runs/morning/dig/batch-N.txt`, one helper with: "Read `sources/models/event-photo.md`, then
  the Pick part of `sources/models/dig.md`, and follow them for `.runs/morning/dig/batch-N.txt`. Answer
  with the JSON lines only." Their lines go to `.runs/morning/dig/picks.jsonl`.
- then run `python3 sources/scripts/event_photos.py dig-posts` until it prints its `[dig] posts laid out`
  line: the titles still bare get their places' own posts read through Apify (dig-deeper 23);
- for each `.runs/morning/dig/posts/batch-N.txt`, one helper with the same words for that batch. Their
  lines go to `.runs/morning/dig/posts/picks.jsonl`.
- then run `python3 sources/scripts/event_photos.py dig-keep`.

**Finish.** Run `python3 sources/scripts/morning.py finish` until it prints the report. It saves
the tags, Abouts and standouts and prints the whole morning report; a save that failed is a line
in it. Answer with Ready's line if it said `ready, but`, then that report as printed, then keep's
`[photos]` line, then dig-keep's `[dig]` lines, then your `[season]` lines, then one line per flag you
dropped that a neighbour might have wanted, and why. Nothing else.

## Rules

- Pages are fetched only by `morning.py`, `event_photos.py` and `team_logos.py` (the registry's fetcher obeys robots
  rules and Crawl-delay). WebFetch, curl and the like stay unused: some sites refuse them.
- The database is written only by `morning.py save` and `finish` (which includes `venue_spots.py keep`), and `event_photos.py keep` and `dig-keep`. SQL by
  hand stays unused.
- Nothing is committed or pushed; `.runs/` is scratch.
