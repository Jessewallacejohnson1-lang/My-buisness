# Flaky tests

Tests that have gone red on GitHub with no change that touched them. bp-build's `ci_wait.sh` reads
this file at the pushed commit and says "known flaky" for a test listed under Flaky, so a red run
tells a ship whether the red is its own. Unit tests count too: the list lives here, beside the
UI tests that flake most.

One line per test: `Class.testMethod`, when it flaked, the cause if found, the fix commit. A fixed
flake moves to Fixed, dated, and stays there.

## Flaky

- 2026-11-15 · `EventCardPhotoTapTests.testEdgeSwipeOverTheHeroPopsAndTheRootStillPushes` · crashed (signal term)
  once on the Mac in a full run on feat/name-hint (the onboarding name box's hint text only) just after merging
  663ca83, at load 30 to 50 · passed alone straight after · no fix yet
- 2026-11-15 · `LaunchBallTests.testTownIsThereAndTappableAfterTheLaunch` · red once on the Mac in a full run on
  feat/search-titles (Search's header and pills only; no launch or Town code) at load over 100: "Town's card didn't
  open after the launch" · passed alone straight after, and in the next full run at load about 15 · no fix yet
- 2026-11-15 · `AtNamesUITests.testTypingAtShowsTheRowAndAPickWritesTheName` · red once on the Mac in a full run on
  feat/search-titles (no New post code) at load about 18: "typing @dal showed no row" · passed alone straight after,
  and in the full run before it · red again 2026-11-16 in a full run on feat/town-live-midnight (fixtures only),
  passed alone straight after · no fix yet
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
- 2026-11-15 · `LaunchBallTests.testTownIsThereAndTappableAfterTheLaunch` · red once on the Mac in a full run on
  feat/inside-cards-29-live-door (the bell and pill's own-Event card; no launch or Town card code) at load 48 to 17:
  "Town's card didn't open after the launch" · passed alone straight after (23 s) · no fix yet · the same run's
  `EventCardPhotoTapTests.testDoubleTapOnPhotoLikesAndDoesNotPush` crashed (signal term) and passed alone too
- 2026-11-14 · `FriendsBookSuggestionTests.testAnXThatFailsBringsThemBackWhereTheyWere` · red once on the Mac in a
  full run on feat/several-photos (post photos only; no Friends code) at load about 200: `["Hal"]` where
  `["Kim", "Hal"]` was expected, the class taking 3.4 s · passed alone straight after (8 of 8, 0.44 s) · no fix yet:
  it sleeps a fixed 200 ms before checking the turn back: wait on the state (`waitWhile`) instead
- 2026-11-13 · `EventCardPhotoTapTests.testAHeldCardOpensItsMenuAndItsButtonsKeepTheirTaps` · red once on the Mac
  in a full run on feat/nothing-scheduled (no Town card code: school rows and the sources scripts) just after merging
  e5d335e4: "a tap on the poster's heart didn't like it" (the like's wait timed out) · passed alone straight after,
  at load 33 to 40 · no fix yet · red again 2026-11-13 in a full run on feat/game-logo-lift (game card logos; no
  poster or heart code) just after merging f9d31a9e, the same timed-out like, at load 45 to 57 · passed alone straight
  after, at load 10 to 29
- 2026-11-13 · `EventCardPhotoTapTests.testDoubleTapOnPhotoLikesAndDoesNotPush` · red once on the Mac in that alone
  run, at load 40: "a double tap on the photo pushed the event page" (the two taps read as one) · passed in the full
  run just before · no fix yet: on a loaded Mac the double tap's gap can outlast the single-tap wait
- 2026-11-07 · `EventCardPhotoTapTests.testADragUpOnThePhotoScrollsTheFeed` · red once on the Mac in a full run at load 50,
  on feat/review-queue-details just after merging a941d5e7, a change with no Town card
  code: the card never moved (659 not under 609) · passed 3 of 3 alone straight after, at load 16 to 26 · no fix
  yet: a 0.05 s press before the drag may read as a hold on a loaded Mac

- 2026-11-07 · `morning.py --selftest` "finish once more writes nothing new but the report's one row, and
  says the same" · red once on the Mac on feat/never-blind (a change to `live_lines` only), green on the next
  two runs · the report's Firecrawl line ("credits unknown (... Could not reach the Composio Dashboard ...)")
  comes from a live call, so two runs a moment apart can word it differently · no fix yet: fake the credits read
  in the self-test
- 2026-11-13 · `RealLifeActionsTests.testTheLastTapWins` · red at c6d316a4 (run 43468545945, attempt 1), a change
  to `sources/` and `DECISIONS.md` only (BP app event-photos 19): "Leave lands after Join, never before" got `[true]`
  where `[true, false]` was expected, and its mirror `[false, true]` for `[true]` · the rerun passed · cause not
  found: two taps' writes land out of order on a slow runner · no fix yet
- 2026-11-15 · `RealLifeActionsTests.testAHeartAndAJoinShakeOnlyWhereTheirControlIs` · red at 9488448 (run
  43799992618, attempt 1), a change to Search's matching only (BP app search-helpful 02): "the card's RSVP shakes
  and buzzes as Join does" got 0 shakes where 1 was expected · passed on the Mac (1,061 tests) and on the rerun ·
  it sleeps a fixed `(hold + flip) * 3` before reading, as the 2026-10-30 RealLifeActions flakes did · no fix yet:
  wait on the count, as its heart half already does
- 2026-11-14 · `OnboardingNextBarTests.testNextBarHoldsStillOnEveryStep` · red once on the Mac in a full run on
  feat/splash-wordmark (the launch only; UI tests skip the launch) at load 100 to 150, just after a macOS update:
  "Failed to get list of active applications: Timed out while fetching attributes
  'XC_kAXXCAttributeFocusedApplications'", XCTest's own read of the screen timing out · passed alone straight after
  (66 s) · no fix: XCTest's accessibility read under load
- 2026-11-14 · `friend_requests.test.mjs` "search and the Friends page stay quick with 5,000 neighbours", on the Mac
  only · red in the pre-push quick checks at load 390 (feat/guardrails-4, a change to `scripts/` only): search 1503 ms
  against 1500, Friends 3760 ms against 3000; the whole database stories took 12 minutes; red again the same hour in a
  full `ci_checks.sh` at load 100 to 300 (Friends 3756 ms), every other story green · no fix yet: skip its timing
  on a busy Mac, as town_feed.test.mjs's 5,000-people read does (Fixed, 2026-11-01)
- 2026-11-14 · `PhotoPinchUITests.testAPinchOpensNothingAndLeavesTheFeedWorking` · red once on the Mac on
  feat/pinch-edge just after merging 070f0204, at load 134: "after a pinch the feed didn't scroll" (the poster stayed
  at 137.7, the drag after the pinch never moved the feed) · passed alone twice straight after, at load 120 to 175 ·
  no fix yet: the 0.05 s press-then-drag can land as a tap on a busy Mac; drag again until the poster moves

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
