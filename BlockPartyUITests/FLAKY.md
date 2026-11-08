# Flaky tests

Tests that have gone red on GitHub with no change that touched them. bp-build's `ci_wait.sh` reads
this file at the pushed commit and says "known flaky" for a test listed under Flaky, so a red run
tells a ship whether the red is its own. Unit tests count too: the list lives here, beside the
UI tests that flake most.

One line per test: `Class.testMethod`, when it flaked, the cause if found, the fix commit. A fixed
flake moves to Fixed, dated, and stays there.

## Flaky

- 2026-11-08 · `YouCalendarTests.testRealLifeActionsDriveLiked` (red at 0b154f22, a three-number
  shadow change in `CastLogo` that can't reach it; the test is heart-replaces-save's, c573cbba, the
  same day) · `["card"]` still shown where `[]` was expected after two heart toggles behind a fixed
  50 ms sleep, the pattern the 2026-10-30 line fixed in its siblings · not fixed yet: wait on the
  state (`waitWhile`) as its siblings do
- 2026-10-30 · `town_feed.test.mjs` "the feed is read in under 100 ms with 5,000 people" · red on
  fix/rootview-typecheck (run 41157284060, a Swift-only change): median 250.2 ms against CI's 250 ms
  budget · a slow GitHub runner; green on main at fbd23337 and 4d97358e · no fix yet on GitHub (the
  Mac's half is under Fixed)
- 2026-10-30 · `FriendsBookTests.testAFailedUnfriendComesBackAndShakes` · red once locally at load 38,
  passed alone · `waitOutTurnBack` sleeps a fixed hold + flip + 150 ms · no fix yet: wait on the
  state instead (`waitWhile`, as the 2026-10-30 Fixed line below does)
- 2026-11-07 · `EventCardPhotoTapTests.testADragUpOnThePhotoScrollsTheFeed` · red once on the Mac in a full run at load 50,
  on feat/review-queue-details just after merging a941d5e7, a change with no Town card
  code: the card never moved (659 not under 609) · passed 3 of 3 alone straight after, at load 16 to 26 · no fix
  yet: a 0.05 s press before the drag may read as a hold on a loaded Mac

- 2026-11-07 · `morning.py --selftest` "finish once more writes nothing new but the report's one row, and
  says the same" · red once on the Mac on feat/never-blind (a change to `live_lines` only), green on the next
  two runs · the report's Firecrawl line ("credits unknown (... Could not reach the Composio Dashboard ...)")
  comes from a live call, so two runs a moment apart can word it differently · no fix yet: fake the credits read
  in the self-test

## Fixed

- 2026-11-01 · `EventCardPhotoTapTests.testASwipeOnTheTitlePagesThePhoto` · red again on 076c0223, a
  database-only commit (run 41256785507, attempt 1; the rerun passed), after its 2026-10-25 fix
  below · cause not found · gone with the test: a Town card no longer swipes (BP app town-feed 40)
- 2026-11-04 · `town_feed.test.mjs` "feed-load: with 5,000 people, Event of the day never works out the
  whole feed, and reads faster" · red on 57f3a253, a commit touching only `social.md` and `check_judge.py`
  (run 41857161145, attempt 1; the re-run passed): no picks 127.7 ms against 178.2, half being 89.1. Red on
  the Mac on 2026-11-03, in fix/morning-1103's `ci_checks.sh db` while another chat was building (load near
  120): 76.6 ms against 148.6, half being 74.3. Red on 2026-11-04 in a pre-push check (load near 14): 38.6 ms
  against 75.7, half being 37.8 · it compared two timings on a busy Mac or a slow GitHub runner · it now
  counts the Events each read works out with Postgres's own count (11 of the feed's 59, 3 runs of 3 the same;
  59 of 59 when Event of the day is made to read the whole feed), and times nothing · fix in this commit
- 2026-11-03 · `SearchModelTests.testAroundTown` · red once in feat/play-words (no Search change): "Lee's Ace" came back nil · `aroundTown` orders tiles by `Hasher()`, which Swift seeds anew each launch, then keeps `aroundMax`, so 1 launch in about 11 cuts the place the test looks for; the same seed also isn't the same order across launches · fixed 2026-11-04 in 5d8f1f50: the test now deals exactly two whole blocks, so no shuffle can cut the place it looks for

- 2026-11-02 · `event_photos.py --selftest` "the batch names each picture and its source; a block
  with none isn't shown" · red on 4419fe77, a DECISIONS.md-only commit (run 41502676020, attempt 1)
  · it looked for "e3" anywhere in the batch file, whose first line holds the random temp folder's
  path, and about 1 name in 200 holds "e3" (reproduced with TMPDIR set to a folder named e3) · it
  now looks for the block itself, `"event": "e3"` · fix in this commit

- 2026-11-01 · `town_feed.test.mjs` "an event card shows its place's photo of what the event is, in
  season, taking turns (event-photos 07)" · red on 94738acd, a Swift-only change (run 41114834248) ·
  its 8 Events had random ids, which hash (`md5(e.id || s.id)`) onto 2 any-season photos, so about 1
  run in 128 all picked one · fixed Event and photo ids that pick both, 20 runs of 20 green · fix
  d82e178c
- 2026-11-01 · `town_feed.test.mjs` "the feed is read in under 100 ms with 5,000 people", on the Mac
  only · red while the Mac was building, against the busy Mac's 250 ms budget: twice in the pre-push
  quick checks (489 ms at load 90; once at load 11) and 782 ms at load 68 · a busy Mac (load over 8)
  now logs the reading without timing it, since GitHub times every push: 254.8 ms at load 15 passed
  · fix in this commit
- 2026-10-30 · `RealLifeActionsTests.testTheLastHeartTapWins` (red at 30e6168, 2026-10-25),
  `RealLifeActionsTests.testAClosedPageCountsNoShake` (red at 54a27ac, 2026-10-21, and fb5cedb) and
  `YouCalendarTests.testRealLifeActionsDriveWhatShows` (red at b2331ba) · each slept a fixed time
  (150 ms, 720 ms, 50 + 200 ms) that a slow GitHub runner outlasted · they wait on the state they
  check (`waitWhile`, at most 5 s), and the You test's refused Join is its own Event, so no write
  still in flight can fail · fix in this commit
- 2026-10-25 · `EventCardPhotoTapTests.testASwipeOnTheTitlePagesThePhoto` · red on 4 main runs
  in a row from ee03ef6 · a quick drag flung the feed until the title sat under the status bar,
  where iOS keeps the touch · fix 6484bce (the drag stops before it swipes)
