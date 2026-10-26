# Flaky tests

Tests that have gone red on GitHub with no change that touched them. bp-build's `ci_wait.sh` reads
this file at the pushed commit and says "known flaky" for a test listed under Flaky, so a red run
tells a ship whether the red is its own. Unit tests count too: the list lives here, beside the
UI tests that flake most.

One line per test: `Class.testMethod`, when it flaked, the cause if found, the fix commit. A fixed
flake moves to Fixed, dated, and stays there.

## Flaky

- `RealLifeActionsTests.testTheLastHeartTapWins` · red once on main at 30e6168 (2026-10-25), green
  on the next run with no change near hearts · cause not found

## Fixed

- 2026-10-25 · `EventCardPhotoTapTests.testASwipeOnTheTitlePagesThePhoto` · red on 4 main runs
  in a row from ee03ef6 · a quick drag flung the feed until the title sat under the status bar,
  where iOS keeps the touch · fix 6484bce (the drag stops before it swipes)
