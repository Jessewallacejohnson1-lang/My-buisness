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
2. **Prepare.** Run `python3 sources/scripts/morning.py prepare`. It fetches every watched page
   the polite way, reads the feeds and data sources, and writes the changed pages in batches
   to `.runs/morning/batches/`. Done when it prints its `[morning] fetched …` line.
3. **The cheap model reads.** For each batch file, start one helper on the cheap model (Haiku),
   all at once, each with this prompt: "Read `sources/models/flag.md` and follow it for the
   pages in `.runs/morning/batches/batch-N.txt`. Answer with the JSON lines only." Write every
   line the helpers return to `.runs/morning/flags.jsonl`. No batches means nothing changed:
   write an empty `flags.jsonl` and go to step 5. Done when every batch has its helper's lines.
4. **Judge.** Read `sources/models/judge.md` and follow it: every flag becomes an item in
   `.runs/morning/judged.jsonl` or is dropped.
5. **Write.** Run `python3 sources/scripts/morning.py write`. It merges the feed items with
   yours, writes them to the database and prints the summary.
6. **Answer** with the summary as `write` printed it, then one line per flag you dropped that
   a neighbour might have wanted, and why.

## Rules

- Pages are fetched only by `morning.py` (the registry's fetcher obeys robots rules and
  Crawl-delay). WebFetch, curl and the like stay unused: some sites refuse them.
- The database is written only by `morning.py write`. SQL by hand stays unused.
- Nothing is committed or pushed; `.runs/` is scratch.
