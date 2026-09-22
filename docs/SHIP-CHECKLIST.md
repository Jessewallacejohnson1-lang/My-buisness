# Ship checklist — the pass that runs once, at the end of production

**Why this file exists** (Jesse, 2026-09-22): some checks are worth running before the
App Store build and are not worth running on every change. The Dynamic Type / text-size
layout audit was the first of them — it costs about a minute per surface, needs an
uncontended simulator to be trustworthy, and re-proved the same fixes over and over.
Those checks live here now. They run in one deliberate pass, and anything already
confirmed is not run again.

This file is meant to grow. Anything that belongs at the end of production rather than
in the daily loop gets added under **Run before ship** using the template below.

---

## How to use it

1. Work down **Run before ship**, top to bottom. Each item names its own command and what
   a pass looks like, so no item needs outside context.
2. When an item passes clean, move it to **Confirmed — do not recheck** with the date and
   the evidence. That is the whole point of the file: a confirmed item is finished.
3. A confirmed item comes back to **Run before ship** only when its *Re-run if* line
   actually happens. Not "to be safe" — the re-run line is the trigger.
4. Items that are blocked on unfinished screens sit in **Waiting on pages** until the page
   they name exists. They are not silently dropped.

## How to add an item

Copy this block into **Run before ship**. Every field is required; an item without a
command or without a pass condition is a reminder, not a check, and reminders rot.

```
### <name>

- **What it proves:** <the user-visible failure this catches>
- **Command:** <exact command, runnable as written>
- **Pass looks like:** <the specific output or number that means pass>
- **Re-run if:** <what invalidates the result once confirmed>
```

---

## Run before ship

### Dynamic Type / text-size layout audit

- **What it proves:** the app still works when a reader turns text size up. Launches the
  real app at AX3 and AX5 and lets iOS report what clips, truncates, or overlaps.
- **Command** — one uncontended simulator, nothing else running:

  ```bash
  TEST_RUNNER_BP_SHIP_AUDIT=1 xcodebuild test \
    -project BlockParty.xcodeproj -scheme BlockParty \
    -destination 'platform=iOS Simulator,name=iPhone Air' \
    -only-testing:BlockPartyUITests \
    CODE_SIGNING_ALLOWED=NO
  ```

  Without that variable the audit skips itself, which is what keeps it out of every-change
  runs and out of CI. **The variable goes in front of `xcodebuild`, as an environment
  variable of the shell** — `TEST_RUNNER_` is the prefix Xcode strips before handing the
  rest to the UI test runner process. Passing `TEST_RUNNER_BP_SHIP_AUDIT=1` as an argument
  after `xcodebuild`, the way build settings are passed, does **not** reach the runner:
  measured on 2026-09-22, that form skipped the test while the environment form ran all six
  audits. A skip is the failure mode here, so read the result — "1 test skipped" means the
  audit did not run.
  Resolve `-destination` against the machine (`xcrun simctl list devices available`) — a
  name that does not exist fails the whole invocation. Use a **non-primary** simulator: a
  test run replaces the installed app and wipes that simulator's app container, including
  the signed-in session. If the machine has only one iPhone simulator, accept that it gets
  wiped and sign back in afterwards, or add a second device first.
- **Pass looks like:** the suite passes with `knownIssueCounts` still empty in
  `BlockPartyUITests/DynamicTypeAuditTests.swift`. An empty map means every audited surface
  must report zero issues, so a pass is a real zero and not a tolerated number.
- **Re-run if:** a surface is added to `DynamicTypeAuditTests.surfaces`, a layout on an
  audited surface changes (line limits, stacking, fixed heights, truncation), or
  `BlockPartyFont` changes how a role scales. Run it once more on the final release build.
- **If it fails:** the failure names the surface, the text size, and every element, with a
  screenshot attached. Fix the layout — do not add a baseline number to make it green, and
  do not add the element to `isFrozenByDesign` unless it is chrome that is frozen on
  purpose in the app already.

### Audit coverage ledger — decide the deferred screens

- **What it proves:** every screen the app can present has actually been looked at once at
  accessibility text sizes, rather than being unseen. `DynamicTypeAuditCoverageTests`
  guarantees each screen is *listed*; it cannot tell you a listed screen was ever opened.
- **Command:** read the `.notYetAudited` entries in
  `BlockPartyTests/DynamicTypeAuditCoverageTests.swift`. For each one, either add the
  surface to `DynamicTypeAuditTests.surfaces` (with a launch flag from
  `docs/debug-flags.md`) and run the audit above, or write down why it ships unaudited.
- **Pass looks like:** no `.notYetAudited` entry is left for a screen that ships, except
  ones with an explicit written decision.
- **Re-run if:** new screens land after this pass. The coverage test will force them onto
  the ledger; this item decides what happens next.
- **Priority order when time is short:** anything holding user-generated text of any
  length — comments, profile, the add form — then long explanatory copy (About,
  Moderation, Map help), then pickers and chip grids.

### Stale numbers and copy in the shipped UI

- **What it proves:** the app does not ship a claim that contradicts the seeded content.
- **Command:** grep the app for event-count copy and compare against what is actually
  seeded:

  ```bash
  grep -rniE "[0-9]+\+? *(st\.? joe|happenings|events a month|events per month|places)" BlockParty/
  ```

- **Pass looks like:** every number in shipped copy matches the current public estimate in
  `MEMORY.md` (**200+ events a month across 150+ places**) and the seeded data. Known
  outstanding case: onboarding screen 13 reads "30+ St. Joe happenings a month".
- **Re-run if:** the public estimate changes, or seeded content is regenerated.

---

## Confirmed — do not recheck

| Item | Confirmed | Evidence | Re-run if |
|---|---|---|---|
| Text scales everywhere — no raw point sizes outside `BlockPartyFont` | 2026-09-22 | `TypographyScalingGuardTests` runs in the unit target on every change, so this one stays continuously proven rather than needing a ship pass | never manually; the unit test owns it |
| Town, town menu and scrolled town hold their layout at AX3 and AX5 | 2026-09-22 | Re-confirmed the day this file was written: all six audits (3 surfaces x AX3/AX5) passed in 64s, zero findings. Commit `dc45d18`. Six labels were freed to take the lines they need (event card host name, meta line, going-summary, town menu neighbour name, posting caption, meta summary). Audit ran clean on an uncontended simulator with `knownIssueCounts` empty — the strictest form of the gate | a layout on one of those three surfaces changes |
| Loading states are skeletons, never spinners or full-screen covers | 2026-09-21 | Commit `768b814`, plus `LoadingGuardTests` in the unit target as the standing regression guard | never manually; the unit test owns it |
| Accessibility audit is scoped to developed pages only | 2026-09-22 | `DynamicTypeAuditTests.surfaces` holds town, town-menu, town-scrolled; unfinished pages are parked in `notDevelopedYet` with reasons | a parked page is finished — move it one line into `surfaces` |
| The audit harness survives a contended simulator | 2026-09-22 | One retry on a thrown audit, added after `XCAXAuditConfiguration` timed out under full-suite load while the same surface audited clean in 57s alone. Only a thrown audit retries, and findings are cleared first, so it cannot hide a real finding | the harness times out twice in a row |

Add a row here when an item passes. Keep the evidence column concrete — a commit, a
number, or a test name. "Looked fine" is not evidence and will get the item re-run.

---

## Waiting on pages

These are on the record rather than forgotten. Each returns to **Run before ship** the day
the page it names is finished.

- **Daily** and **Business** — `BlankTab` placeholders. A title and one promise line;
  there is no layout to hold or break yet.
- **You / profile** — `ProfileView` is real but still moving. Its unfinished states ("No
  plans yet", "a neighbor", "Around town") were what the auditor kept reporting. High
  priority the day it settles: a profile is user-generated text of any length.
- **Map** — mostly frozen marker chrome; the payoff is the search and filter row, not the
  map itself.

Surfaces are parked in `DynamicTypeAuditTests.notDevelopedYet` and screens in the
coverage ledger, so both lists stay in the code next to what they describe.
