# Flaky tests

Tests that have gone red on GitHub with no change that touched them. bp-build's `ci_wait.sh` reads
this file at the pushed commit and says "known flaky" for a test listed under Flaky, so a red run
tells a ship whether the red is its own. Unit tests count too: the list lives here, beside the
UI tests that flake most.

One line per test: `Class.testMethod`, when it flaked, the cause if found, the fix commit. A fixed
flake moves to Fixed, dated, and stays there.

## Flaky

- 2026-10-30 · `town_feed.test.mjs` "the feed is read in under 100 ms with 5,000 people" · red on
  fix/rootview-typecheck (run 41157284060, a Swift-only change): median 250.2 ms against CI's 250 ms
  budget · a slow GitHub runner; green on main at fbd23337 and 4d97358e · no fix yet

## Fixed

- 2026-10-30 · `RealLifeActionsTests.testTheLastHeartTapWins` (red at 30e6168, 2026-10-25),
  `RealLifeActionsTests.testAClosedPageCountsNoShake` (red at 54a27ac, 2026-10-21, and fb5cedb) and
  `YouCalendarTests.testRealLifeActionsDriveWhatShows` (red at b2331ba) · each slept a fixed time
  (150 ms, 720 ms, 50 + 200 ms) that a slow GitHub runner outlasted · they wait on the state they
  check (`waitWhile`, at most 5 s), and the You test's refused Join is its own Event, so no write
  still in flight can fail · fix in this commit
- 2026-10-25 · `EventCardPhotoTapTests.testASwipeOnTheTitlePagesThePhoto` · red on 4 main runs
  in a row from ee03ef6 · a quick drag flung the feed until the title sat under the status bar,
  where iOS keeps the touch · fix 6484bce (the drag stops before it swipes)
