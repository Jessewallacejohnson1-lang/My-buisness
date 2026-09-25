# Gutting Ledger

A running record of what is being stripped out of the Block Party iOS app, why, and what
replaced it. This file exists so the removals are recoverable knowledge without keeping them
in an agent's working context. **Do not read this file as background.** Open it only when
someone asks what was removed, asks to restore something, or asks why a surface is gone.

Started 2026-09-17 on branch `integration/block-party`.

---

## Round 1 — 2026-09-17

Direction from Jesse: a deep gut of the app's surfaces. The Today tab becomes essentially
blank except the profile picture; two tabs disappear entirely; the map moves from a tab to a
button on Today.

### Today tab — remove

| Surface | Notes |
| --- | --- |
| "JoeTown" header at the top of Today | The colorful script wordmark in the top bar |
| Daily Almanac | The dated greeting block — "Evening on the block, Jesse.", weather line, sunrise/sunset, trash pickup, civic line |
| Your Day | The horizon/scrub card, including the "Nothing posted for today yet." rail |
| Spotlight | The weekly spotlight card |
| The card under Spotlight | Whatever module follows Spotlight in the feed order |
| The text at the bottom | The sign-off / caught-up footer copy |

**Keep:** the profile picture. Everything else on Today goes.

### Tabs — remove

| Tab | Disposition |
| --- | --- |
| Activities | Delete completely. Nothing in it is kept. |
| Calendar | Delete. The *calendar visual style* may be wanted again later — the style is worth remembering, the tab is not. |
| Map | Not deleted — relocated. See below. |

### Map — relocate

The map stops being its own tab. It becomes a **translucent white map button in the top-right
corner of the Today tab**. Tapping it opens the map.

### Deliberately preserved elsewhere

- Uncommitted "Your Day" rail work from the retired main checkout was committed as `f8567eb`
  on branch `worktree-agent-a0a9d032f65fb52bb` before that checkout was deleted. Removing Your
  Day here does not destroy that branch.
- Everything removed in this round remains in git history on `integration/block-party` and its
  ancestors. Recovery is `git log --diff-filter=D --name-only` plus a checkout of the parent
  commit.

---

## Round 1 — what actually shipped

Landed 2026-09-17 on `integration/block-party`. Build clean, 0 warnings. Tests 460 → 437, all passing.

### Today

`FeedRegistry` now ships with **zero modules**. The registry, the `FeedModule` protocol and
`FeedView`'s column renderer all survive intact — adding a module back is still one entry in one
array. Seven modules were removed in feed order: Almanac, Your Day, Town Notes, For You, Spotlight,
Trivia, Sign-Off.

Town Notes and For You were **not** in Jesse's list. They sat between Your Day and Spotlight and had
never appeared on screen (empty or unloaded), which is why they went unnamed. They were removed
under "basically the whole app blank except the profile picture."

Two mappings worth recording, because the names in the request were positional rather than literal:
**"the card under it" was Trivia** (which renders two cards — the daily poll and the trivia card),
and **"the bottom of the text" was Sign-Off** (the caught-up footer).

The top bar lost the `JoetownHeader` image lockup and all its centering math. The profile avatar
stays and still opens the town drawer — it was always the menu button, not decoration.

### Tabs

Activities and Calendar had every file deleted but **keep their slots in the tab bar**, rendering a
`BlankTab` — the tab's name in secondary ink on paper. Jesse asked for them blank rather than gone
so there are slots to brainstorm into. `Tab.map` was deleted outright.

### Map

Now a `.fullScreenCover` raised by a rounded-square glass button in Today's top-right, left of the
avatar. Three things had to change for it to survive off the tab bar:

- `MapSheet.tabBarReserve` (74) was baked into four call sites — sheet seat, Mapbox ⓘ ornament,
  pin-label collision, town-rain floor. It became a `bottomBarInset` parameter defaulting to 0
  rather than being deleted, so the map still seats correctly if it ever goes back over a bar.
- `SJMapView` had **no way out** — the tab bar was the only exit. It gained a close "X".
- `mapDetail` moved from the shell into `SJMapView`'s own `@State`.

`-open-tab map` died with the tab. **`-open-map` replaces it** and is now the only headless way in.

### What survived deliberately

- **The whole Horizon pure layer** (solar model, palette, time axis, scrub) and
  `-horizon-card-gallery`. Deleting it would have cascaded into 7 more test files and ~3.5k lines.
  `HorizonScrubHost`, `horizonScrub` and `HorizonScrubScrim` live on in `HorizonScrubSeam.swift`
  (renamed from `YourDayHorizonSection.swift`) because `HorizonCard` still drives them.
- **`TriviaModel`** — `Backend/TriviaAPI.swift` returns its types. Only the card view went.
- **`YourDayLogic`, `DayItem`, `YourDayRailMetrics`** — used across `Feed/DaySchedule/`, which is a
  separate surface and was not touched.
- **`BriefingSkeletons`** — `Components/Skeleton.swift` still mounts three of them.

### Known dead code left standing

Not part of the ask, so not swept. A second pass could take: `Feed/FeedDebugFocus.swift`,
`DaySchedule/DayScheduleDemoOpener`, the legacy `FeedPosting` pipeline
(`TodayFeedView`, `TodayFeedPreview`, `FeedCardMapping`, `FeedSectioning`, `FeedRecurrence`,
`FeedPipelineSelfCheck`, `BlockMotifSpinner`), `Briefing/BriefingUnavailableCard`,
`Briefing/DwellTracker`, `CommunityFeed/**`, `HomeModel.swift`, and the orphaned
`ExploreKit` members (`ExploreBlankPhoto`, `ExploreCard`, `SaveBookmarkButton`, `MetaItem`,
`exploreMetaRow`, `exploreCircleIcon` — but NOT `PressableStyle`, which 13 files use).

### Open visual question

The map's `mapBottomFade` is a hardcoded 172pt band, tuned as 74 (tab bar) + 96 (peek). With the
reserve at 0 the sheet sits 74pt lower, so the fade now reaches ~76pt above the sheet top instead of
hugging it — a heavier bottom wash. Restoring the old relationship is `172 → ~118`. Not changed,
because it is a design call.

---

## The Calendar's visual style, recorded before deletion

Jesse may want this look back. The files are gone; this is what made them work.

The Calendar was the app's purest ink-on-paper surface — `Hue.paper` ground, essentially no accent
color, where **value did all the work a tint would normally do**. Day numerals carried `Hue.ink`
when the day had something on it and dropped to `Hue.inkSecondary` when empty; that single value
step was the *only* signal separating a busy day from a quiet one, for future days as much as past.
Today was a filled 38pt `Hue.ink` disc with its numeral in `Hue.surface` (never literal white — the
disc inverts in dark mode). The day being *looked at* was a 42pt rounded-rect stroke at 1.5pt,
`Radius.button`, sliding between cells on `matchedGeometryEffect`. One weight for every numeral,
`monospacedDigit`, so nothing snapped when data loaded.

Layout was **not** a paging month swipe: one continuous vertical `LazyVStack` of a full year of
month sections 36pt apart, each a `LazyVGrid` of 7 flexible columns, 0pt column spacing, 18pt row
spacing, 38pt cells in 48pt rows, 18pt page gutter, closing on a 96pt spacer.

Type ran `displaySemi(22)` month titles, `sansMedium(11)` + 0.4 kerning for the uppercase weekday
row, `sansSemibold(15)`/`sans(13)` agenda rows, `mono(12)` times. Radii almost entirely
`Radius.button` (12), with `card` (20) and `bento` (22) once each in Insights.

Three interactions are worth rebuilding: the header's **segmented pill** (Upcoming ⇄ Calendar) where
an ink capsule slid under the active label via `matchedGeometryEffect(id: "seg")` on
`spring(0.32, 0.84)`, the two faces cross-transitioning at ±28pt offset + opacity; a **live-now
pulse**, a 6pt ink dot 4pt above today's cell with a 35%-opacity ring expanding to 2.8× on a 1.6s
`repeatForever` easeOut; and `PressableStyle(scale: 0.9)` on day cells, lighter (0.92–0.97) on
chrome. Cards lifted on a soft low shadow (black 6%, radius 14, y+8) rather than borders. Every
motion had an explicit Reduce Motion fallback.

The one deliberate break from the monochrome rule: `DayDetailView` was multi-color **on purpose** —
each event's accent bar and icon came from its `EventCategory` as a colored circle with a white
glyph, on the stated reasoning that "a calendar reads deliberately multi-color."

---

## Round 2 — 2026-09-24: Create removed, posting paused

**What went:** the tab bar's centre Create disc (`createButton`, `CreatePlusGlyph`,
`onCreate`) and every way into a composer — `Features/Add/AddView.swift`,
`AddFormView.swift`, `AddModel.swift` (with `AddKind`),
`Features/Components/ComposeSpeedDial.swift`, `Features/Components/VenueAutocompleteField.swift`,
the shell's compose state, sheets and speed-dial overlay, the town menu's "Add an event" row,
`HomeView.onCompose`, `TodayFeedView.onCompose` and its plus, the day sheet's "Add to today"
button (`.callToAction`, the `cta` fixture state, `ctaHeight` / `ctaRadius` / `ctaMargin` /
`ctaScrimFade`), `YourDayRailCopy.addTile`, and the `-open-speeddial` / `-speeddial-loop` flags.

**Why:** Jesse paused posting. A Create button with nothing honest behind it is a dead end,
and the bar reads better as four even slots.

**What replaced it:** nothing, on purpose. The bar is four slots from `Tab.allCases` again.
The yellow disc token lives on as `Hue.brandDisc` for the Town bar's map disc. The back-end
write paths the composer used are still in `Backend/`, unused (listed in `DECISIONS.md`).

**Recover:** `git show fd25875:<path>` for any file above (`fd25875` is the last commit with
all of it), or `git checkout fd25875 -- <path>` to restore it. App files need no pbxproj edit.

---

## Round 3 — 2026-09-25 — the almanac, completely

Direction from Jesse: *"literally remove it completely cause it has no purpose."*

Round 1 deleted the almanac **card**. Its entire back end was left running for a week: a
deployed edge function, two tables, a column, a helper, a section of the briefing RPC, a CI
job, and twenty tests. The app was still downloading an almanac on every Town open and
throwing it away. This round removes the rest.

### Removed

| Thing | Where |
| --- | --- |
| `DailyAlmanac.swift` | the edge-function client, zero callers since 2026-08-09 |
| `BriefingAlmanac` + `BriefingPayload.almanac` | the payload type and its field |
| `DwellTracker.swift` | unreferenced; existed to measure almanac reads |
| `BriefingAnalytics.almanacDwell` | the event it reported to, zero callers |
| `FeedModuleID.almanac`, `FeedStateCopy.almanacUnavailable` | ids and copy for a deleted card |
| 1 test + 8 assertions | `testAlmanacFallsBackToTheTownLineWhenPersonalIsMissing` and the almanac asserts in the payload/parity/model tests |
| `almanac` key in 6 fixtures + `BriefingSample` | canned payloads |
| `almanac-checks` CI job | ran the prompt-sync and variety checks |
| `supabase/functions/daily-almanac/` | 18 files |
| `almanac_daily`, `town_almanac` tables | dropped |
| `daily_briefings.almanac_md` column | dropped |
| `town_almanac_line(date)` | dropped |
| `compose_briefing`'s `p_almanac_md` argument | new 5-arg signature; old 6-arg dropped |
| the `almanac` section of `get_today_briefing` | the RPC no longer returns it |

### Deliberately kept

- **`evergreen_pool`** — `town_almanac_line()` read from it, but it is the feed's own
  fallback pool and has nothing to do with the almanac.
- **The briefing pipeline** — `daily_briefings`, `compose_briefing`, `publish_briefing`,
  `run_briefing_reconcile` and the hourly cron all still run. They carry featured events,
  weather, the touch card and "all caught up"; only the almanac parts were cut.
- **The parked utility row's comments** (`Features/Civic/Parked/`) still name
  `AlmanacReveal`. That folder is kept intact as a unit, so they were not edited — the
  Parked README explains it.

### Not recoverable

The town facts and the generated lines lived only in the database. They were exported to
**`docs/ST-JOSEPH-ALMANAC-ARCHIVE.md`** before the drop — 15 distinct facts and 13
generated lines. That file is now the only copy.

**Recover:** `git checkout 291ca50 -- <path>` for any deleted file above (291ca50 is the last
commit with all of it). The database side needs the migration reversed by hand; there is no
down-migration, and the data is gone regardless.

---

## Recovering something from a round

1. Find the commit that removed it: `git log --oneline --diff-filter=D -- <path>`
2. Restore the file at its last living state: `git checkout <commit>^ -- <path>`
3. Re-register it if it is a **test** file — the test target uses an explicit source list in
   `project.pbxproj` (4 entries), so a restored test file does not run until it is added back.
   App-target sources under `BlockParty/` are file-system synchronized and need no registration.
