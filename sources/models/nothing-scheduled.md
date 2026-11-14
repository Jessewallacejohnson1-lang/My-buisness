# Nothing scheduled: the Sunday chat

When the Sunday morning report says `[scheduled] N of M things with nothing scheduled are due for a walk`, or Jesse says
"nothing scheduled" (BP app docs/plans/nothing-scheduled, tickets 04 and 06). The walk looks for a page that gives the
dates of each confirmed thing with no Event coming; nothing it finds is watched until Jesse ticks it (ADR-008, ADR-022).
Script: `sources/scripts/nothing_scheduled.py`; the finders' job: `sources/models/dates.md`.

1. **Walk.** In a detached worktree off `origin/main`, with the master key wrapper (the `source-registry` skill, "Keys on
   the Mac"; it writes `public.date_walks`, so it waits for Jesse's yes):
   `python3 sources/scripts/nothing_scheduled.py walk`. It lays out the things due, 40 at most, in
   `.runs/morning/scheduled/find-N.txt`.
2. **Find.** For each `find-N.txt`, one `general-purpose` helper, at most 10 at once: "Read `sources/models/dates.md`
   and follow it for `.runs/morning/scheduled/find-N.txt`. Answer with the JSON lines only. Load WebSearch with
   ToolSearch first." Their lines go to `.runs/morning/scheduled/pages.jsonl`. Add up the tokens the helpers used.
3. **Keep.** `python3 sources/scripts/nothing_scheduled.py keep --tokens <the helpers' tokens>`: the pages with a date
   go to `picks.json` by registry entry, the Facebook and Instagram pages to `social.json`, and each thing walked is
   remembered for four weeks. Its first line is what the Sunday cost: things walked, found per rung, searches, tokens.
4. **Posts** (the paid rung): `python3 sources/scripts/nothing_scheduled.py posts --dry-run`, then `posts`, again while
   it prints "run again". It reads each page in `social.json` once through Apify, inside the photo dig's $5 a month and
   10 cents a place; at the limit the rest wait and its report names them. A page whose posts give a dated Event goes
   to `social-picks.json`; a page turned down isn't read again for 180 days. Tell Jesse the Apify cost after (BP app
   `CLAUDE.md`, Apify).
5. **Jesse's ticks.** One approval page (an artifact) from `picks.json` and `social-picks.json`, as for a whole town's
   picks (the `source-registry` skill, "Watch a place or switch one on"). Write his choices as
   `{"unticked_places": [ids], "unticked_pages": ["id|url"]}`.
6. **A ticked `new` row** names a thing with no registry entry (the Lions Club). Write its entry first, in a branch
   worktree, as the `source-registry` skill's "Add, fix or retire a place or page" says (`status: proposed`,
   `added_by: agent:claude`, its pages), then put the new id in that row: `"id": "<id>", "state": "ok"` in
   `picks.json`, or `entry_id` in its line in `social-picks.json`. Promote passes over a row with no id.
7. **Watch.** In that branch worktree: `python3 sources/scripts/find_calendars.py --promote <choices.json> --picks
   <the walk's worktree>/.runs/morning/scheduled/picks.json`, and each ticked social page's `line` into
   `sources/social/<town>.json`. `sources/validate`, commit quoting his ticks, and ask before the push. After the push,
   `social.py setup` makes the new social pages' tasks. A Group's Events show on its Group page only once its
   `clubs.own_entry_id` names the entry: tell Jesse, it's a migration.
8. **Report:** keep's and posts' lines as printed, the tokens and Apify money spent, and what Jesse ticked.
