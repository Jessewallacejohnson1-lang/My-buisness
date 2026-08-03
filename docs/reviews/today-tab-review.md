# Today Tab — Phase 0 Review

**Date:** 2026-08-03 · **Worktree:** `block-party-utility-row` · **Branch:** `build-current-trunk` (c2d8f5b)
**Baseline build:** SUCCEEDED, **0 warnings, 0 errors** (`.dd/`, iPhone 17 / iOS 26.5)
**Status:** recon only — no production code changed.

Screenshots: `docs/reviews/baseline/`
- `today-tab-current.jpg` — the tab as it ships today
- `utility-row-fresh-state.jpg` — first-run row
- `utility-row-STUCK-repro.jpg` — Jesse's reported state, reproduced

---

## 0. Headline

Two of the three premises in the build spec are **factually wrong about this codebase**, and one
undocumented defect is worse than anything the spec anticipated.

| # | Spec premise | Reality |
|---|---|---|
| 1 | Utility tiles are lost by a persistence one-way door | **Refuted.** Storage is sound. The *entry point* to the Customize sheet is withdrawn after first save — a UI dead end, one line. |
| 2 | An animated profile avatar sits top-right | **Refuted.** It is a `person` SF Symbol in a frosted circle plus a 3-dot affordance. The photo `ProfileAvatar` lives in the drawer, not here. |
| 3 | Tiles pass 4.5:1 contrast (per `docs/UTILITY_ROW.md`) | **Refuted.** 18 of 33 text layers fail, 3.64–4.24:1. Only full-opacity value text passes. |

---

## 1. Files that render the Today tab

`HomeView` is the tab root: a single `ScrollView`, no `NavigationStack`, no toolbar.

| File | Lines | Responsibility |
|---|---:|---|
| `Features/Home/HomeView.swift` | 179 | Tab root; ScrollView + VStack; refresh + reveal orchestration |
| `Features/Home/Masthead.swift` | 113 | Wordmark, date line, **top-right menu button + its animation** |
| `Features/Home/AlmanacSection.swift` | 538 | Almanac card; greeting, typewriter write, weather + AI-line fetch |
| `Features/Home/HomeModel.swift` | 336 | 13 `@Published` props; feed/quest/board loads |
| `Features/Home/Feed/TodayFeedView.swift` | 200 | `TODAY`/`THIS WEEK` headers, empty state, skeletons |
| `Features/Home/Feed/FeedEventCard.swift` | 489 | Event cards (largest view in the tab) |
| `Features/Home/Utility/*` (8 files) | 1,082 | The utility row — see §2 |
| `Features/Home/Almanac/MoonPhase.swift` | 104 | **Dead** — never called |
| `Features/Home/Almanac/OnThisDay.swift` | 72 | **Dead** — never called |
| `Features/Home/TodayCard.swift` | 47 | **Dead** — never mounted |
| `Features/Home/TodayInStJoe.swift` | 201 | **Dead view**, but its model still fetches on every load |
| `Features/Home/WeatherBar.swift` | 246 | `WeatherService` (live, shared) + **dead** `WeatherBar` view |
| `Features/Home/CommunityFeed/*` | 334 | **Orphaned** — superseded by `Feed/FeedSectioning` |

Feature total ≈ 7,000 lines; **~1,100 lines are dead or orphaned.**

---

## 2. The utility tile system

**Catalog** — `UtilityTileRegistry.swift:37-65`. A hardcoded 4-entry array (`weather, garbage, roads,
library`) rebuilt on every launch. Not persisted, not derived from prefs. It cannot be trimmed.

**Persistence** — `UtilityPrefsStore.swift:24-27`, `UserDefaults.standard`:
`utility.tiles` (JSON `[String]`), `utility.settings` (JSON dict), `utility.hasSavedOnce`,
`utility.pendingSync`. **No schema-version field** anywhere.

**Sheet seeding** — `UtilityCustomizeSheet.swift:21-29`, already catalog-based:

```swift
let enabled = model.prefs.tiles
let enabledSet = Set(enabled)
let disabled = model.registry.catalog.filter { !enabledSet.contains($0) }
_draftTiles = State(initialValue: enabled + disabled)
```

**Save** — `UtilityRowView.swift:56`: `order.filter { enabled.contains($0) }`. Disabled ids *are*
dropped from `tiles`, but `settings` is never filtered, so per-tile config survives.

### 2.1 THE DEFECT — `UtilityRowView.swift:50`

```swift
var showCustomizeTile: Bool { !prefs.hasSavedOnce || tiles.isEmpty }
```

After the first save, with ≥1 tile enabled, the Customize tile is removed from the row. The only
remaining entry is an undiscoverable `.contextMenu` long-press on a tile
(`UtilityRowView.swift:163-167`).

Why the shipped acceptance test missed it: `docs/UTILITY_ROW.md:84` tested *"disable all four"* →
`tiles.isEmpty` → the tile returns. **Disabling *some* is the broken path and was never tested.**

**Reproduced** (`utility-row-STUCK-repro.jpg`): seeded `utility.tiles=["roads","library"]` +
`hasSavedOnce=true` on a clean container → row shows two tiles, no Customize tile, no caption.

Data is intact. Open the sheet by any means and all four tiles are listed.

### 2.2 Supabase sync

`supabase/migrations/20260724120100_user_utility_prefs.sql` — `user_utility_prefs(user_id pk,
tiles jsonb, settings jsonb, updated_at timestamptz)`. Own-row RLS for select/insert/update; no
delete policy. Client `UtilityPrefsAPI.swift` upserts with
`on_conflict=user_id` + `resolution=merge-duplicates`.

- **Whole-row last-write-wins.** No version, no etag, no arbitration.
- **`updated_at` is dead**: set at INSERT, no trigger bumps it, the client never sends it, and the
  decoded `UtilityPrefsRow.updatedAt` is never read. Two devices silently drop one edit.
- Sync fires on save (push) and on `start()` (`hydrate`). No debounce, no realtime on this table.
- `hydrate()` correctly re-pushes instead of pulling when `pendingSync` is set — a previously-fixed
  offline-data-loss bug.

### 2.3 Per-tile config, reorder

Garbage is the only tile with a `settingsEditor` (weekday). It survives disable → re-enable, because
`settings` is never filtered. Reorder works and persists for *enabled* tiles; relative order among
*disabled* tiles is not preserved (recomputed in catalog order each open).

### 2.4 Per-tile data quality

| Tile | Source | Offline | Stale shown |
|---|---|---|---|
| Weather | `WeatherService` (Open-Meteo, 15-min TTL, coalesced) | keeps last value | via TTL only |
| Garbage | `GarbageSchedule`, pure local math | n/a | n/a |
| Roads | `TownStatusAPI` + realtime on `town_status` | keeps last value | yes, `Updated Nd ago` |
| Library | `LibraryHours`, static weekday table | n/a | n/a |

**Library holiday closures: NOT EXPOSED.** `LibraryHours.table` is keyed only by weekday with no
date-exception mechanism. The tile will report normal hours on Christmas.

### 2.5 Test coverage

Covered: codec round-trips, `sanitize`, garbage date math (incl. floating holidays, 2028 regression),
library hours. All pin `America/Chicago` explicitly.

**Not covered:** `UtilityPrefsStore.save/hydrate/pushToServer`, the sheet's draft-seeding, the Save
filter, `applyDraft`, registry contents, `UtilityContrast`, and every provider end-to-end. The exact
code this review had to verify has **zero** tests.

---

## 3. Almanac card data flow

- **Greeting** — `DailyGreeting.line(name:at:)`, pure/local/deterministic. Cannot fail.
- **Weather nudge** — `WeatherService.current()` (`WeatherBar.swift:33-192`). 15-min in-memory TTL,
  concurrent callers coalesced. Failure → `nil` → number-free line. No disk cache.
- **AI day-line** — `DailyAlmanac.line(auth:)` → `functions/v1/daily-almanac`. Cached by
  user-id + town-day, 30-min TTL (correctly keyed by owner so lines can't leak across accounts).
  Failure → silent fallback to the on-device template.
- **Loading** — 300 ms grace then a two-bar skeleton, only on a non-writing open.
- **Moon phase — NOT RENDERED.** `MoonPhase.moonInfo` is fully built, self-checked, and never called.
  The spec describes it as shipping; it does not.

**One weather client only.** `WeatherService` is shared by the almanac, `WeatherBar`,
`TodayInStJoeCard`, and (via `WeatherState`) `WeatherBackground`. No second path exists to avoid.

---

## 4. The top-right animation — preserved verbatim

**It is not a profile avatar.** `Masthead.swift:63-88` renders a 3-dot `VStack` plus a `Button`
containing `Image(systemName: "person")`, 38×38, `.ultraThinMaterial` in a `Circle()`, `Hue.hairline`
1pt stroke. The photo-backed `ProfileAvatar` (`Profile/ProfileComponents.swift:44-77`) is used in the
drawer header and Profile screens only.

State: `@State private var activated`, `@State private var bounce`. **No `@Namespace`, no
`matchedGeometryEffect`.**

`tap()` — `Masthead.swift:92-102`, exact timeline (`s = slowTap`, 1 normally, 4 under `-slow-tap`):

| Step | Animation | Timing |
|---|---|---|
| Haptic | `Haptics.light()` | t=0, synchronous |
| Dots hide | `.easeOut(duration: 0.18 * s)` | t=0 |
| Bounce in | `.spring(response: 0.26 * s, dampingFraction: 0.42)` → `scale 1.12` | t=0 |
| Bounce settle | `.spring(response: 0.34 * s, dampingFraction: 0.62)` → `scale 1.0` | t=+0.13s |
| Drawer hand-off | `onMenu()` | t=+0.15s |
| Restore on close | `.easeOut(duration: 0.28)` → `activated = false` | on `menuOpen → false` |

Dots modifier order: `.opacity(activated ? 0 : 1)` → `.scaleEffect(activated ? 0.4 : 1, anchor:
.trailing)` → `.blur(radius: activated ? 1.5 : 0)`.

**Relocatable verbatim**: the unit is `menuButton` + 2 `@State` vars + `tap()` + `slowTap` +
`debugAutoTap`, with no external geometry dependency.

**It does not honor Reduce Motion.** No `accessibilityReduceMotion` read exists in the file. This
collides with the acceptance checklist — see Question 3.

---

## 5. Hardcoded values that should be tokens

**Tokens today:** `Hue` (7 colors incl. `accent` `#8E3B6B`), `Radius` (12/16/20), `CardShadow`,
`Motion.*`, `Font.display/sans/mono`.

**Gaps — things Home needs that have no token at all:**
- **No spacing scale.** 116 raw padding/spacing literals across 16 files. 18pt is the de-facto gutter
  but exists only as a repeated literal.
- **No on-dark text token.** 36 raw `.white` at ad-hoc opacities (0.35–0.9) — the direct cause of §6.
- **No scrim token.** 12 raw `.black.opacity(…)` (0.12–0.68).
- **No icon-size token.** 30 raw `.system(size:)`, mostly glyph sizing.

**Violations:**
- **34 raw hex** in 2 undocumented files: `UtilityTileColor.swift:17-34` (22) and
  `WeatherBackground.swift:48-53` (12). CLAUDE.md claims only `BasemapPalette.swift` may hold hexes.
- **8 undocumented radii** across 20 sites: 2, 4, 5, 6, 8, 10, 14, **22**. `UtilityTileMetrics.corner
  = 22` is a third tile family outside the 12/16/20 scale.
- **Shadow drift** — `UtilityTileView.swift:45` / `UtilityRowView.swift:226` use
  `black 6%, r14, y8`, duplicated verbatim, while `CardShadow` is `r10, y4`. Comment claims they match.
- **Inline spring** — `UtilityRowView.swift:185` `spring(0.44, 0.82)` literal, against `Motion.swift`'s
  explicit "no inline magic spring values" rule.
- Clean: **zero** `.red/.orange/.blue/.green/.accentColor`, zero `print(`, zero `FIXME`, zero
  commented-out code.

---

## 6. Ranked quality problems

### Correctness

1. **HIGH — Customize sheet unreachable after first save.** `UtilityRowView.swift:50`. §2.1. Reproduced.
2. **HIGH — timezone.** `LibraryHours.status` and `GarbageSchedule.nextPickup` default to
   `Calendar.current`; neither provider overrides it, while `WeatherService` correctly pins
   `America/Chicago`. Off-Central devices get wrong open/closed and wrong pickup day. Every test pins
   the zone explicitly, so this is **untested by construction**.
3. **MEDIUM — last-write-wins sync with a dead `updated_at`.** §2.2. Concurrent edits silently drop.
4. **MEDIUM — dead view with a live fetch.** `HomeModel.board` calls `getTodayInStJoe()` +
   `getEvergreenLine()` on every load to feed `TodayInStJoeCard`, which is never instantiated. Real
   network cost, zero pixels.
5. **LOW — `hydrate()`'s `try?`** collapses network error, decode error, and "no row" into one silent
   no-op. Failures are unobservable.
6. **LOW — no library holiday model.** Confidently wrong on holidays.

### Accessibility

1. **HIGH — 18 contrast failures.** Independently recomputed (WCAG 2.1 relative luminance;
   script in scratchpad, proposed for `scripts/contrast.py`):

   | Layer | Alpha | Ratio range | Verdict |
   |---|---|---|---|
   | Value text (`:86,90,113`) | 1.00 | 4.76–10.20:1 | PASS |
   | **Tile name label (`:139`, `UtilityRowView:218`)** | 0.90 | **4.18–4.24:1** | **FAIL** |
   | **Secondary / expanded rows (`:65,109`)** | 0.80 | **3.64–3.73:1** | **FAIL** |

   Only `clearNight` and `storm` pass at every layer. The gradients were tuned to ~4.77:1 at
   alpha 1.0 — **zero headroom**, so any alpha reduction fails immediately. `docs/UTILITY_ROW.md:25`
   claims all pass; it only ever tested full opacity.
2. **HIGH — loading state untested.** `UtilityTileView.swift:40-43` drops the gradient to
   `.opacity(0.4)` while the 0.9-white label stays fully opaque — strictly worse than the above.
3. **HIGH — `WeatherBar` clear-day ≈2.97:1.** Currently a dead view; will ship broken if remounted.
4. **MEDIUM — Dynamic Type is systemic.** No `BlockPartyFont` helper uses `relativeTo:` or
   `@ScaledMetric`; the whole type system is fixed-point. Utility tiles break first (`compactH = 92`
   fixed, label and secondary lines have no `minimumScaleFactor`).
5. **MEDIUM — Reduce Motion gaps:** `Masthead.swift:47,96-99` (the animation you want preserved),
   the entire `AroundTownCarousel` incl. `rotation3DEffect`, `FeedCardMedia.swift:62`,
   `TodayFeedView.swift:39`.
6. **MEDIUM — VoiceOver:** `AroundTownCarousel` has no labels or traits at all and cannot be advanced;
   `Masthead`'s 3 dots aren't `.accessibilityHidden`; `TownMenuView` header and `WeatherBar` aren't combined.

### Performance

1. **MEDIUM — over-broad invalidation.** 13 `@Published` on `HomeModel`; one like-tap re-runs all of
   `HomeView.body` and recomputes the **unmemoized** `feedSections` (dedupe + group + sort over the
   whole feed), re-diffing Masthead, Almanac, and the utility row for nothing.
2. **LOW —** `FeedEventCard` holds 12 `@State`; any one re-invokes a `GeometryReader` body.
   `AroundTownCarousel.swift:41` uses `GeometryReader { _ in }` and discards the proxy.
3. **Correct already:** image decode is off-main via an actor with downsampling + LRU;
   `WeatherService` coalesces; no unguarded work in `ForEach`.

### Dead code

`TodayCard` (47), `TodayInStJoeCard` (201, live fetch), `MoonPhase` (104), `OnThisDay` (72),
`CommunityFeedBucketer` subsystem (334), `WeatherBar` view. **~1,100 lines.** Also stale: a
`UtilityTile.swift:18` reference to a non-existent `reconcile` method (it's `sanitize`), a
`AlmanacSection.swift:229` comment citing the deleted `honey`/`sky` ramps, and `scripts/contrast.py`
cited in two places but absent from the repo.

**4 TODOs**, 3 owned (`TODO(jesse)` — garbage holiday policy, library branch choice),
1 unowned (`AlmanacSection.swift:23`).

---

## 7. Top 8 improvements beyond the spec

| # | Improvement | Effort | Impact |
|---|---|---|---|
| 1 | **Fix the tile contrast properly** — add an on-dark text token scale and darken gradients to give real headroom, instead of the current zero-margin tuning | M | **High** — 18 live failures |
| 2 | **Pin providers to `America/Chicago`** — one-line default change each, plus a test that does *not* inject a calendar | S | **High** — silent wrong data |
| 3 | **Delete the ~1,100 dead lines**, and remove the `HomeModel.board` fetch feeding a dead view | S | Med — real network saving |
| 4 | **Memoize `feedSections`** and split `HomeModel` so a like-tap doesn't re-diff the whole tab | M | Med |
| 5 | **Introduce a `Spacing` scale + on-dark/scrim/icon tokens** — the 116/36/12/30 literal counts are all one missing token family | M | Med — compounding |
| 6 | **Make `BlockPartyFont` Dynamic-Type aware** (`relativeTo:`), then decide tile scaling deliberately | L | Med — currently systemic |
| 7 | **Add `updated_at` trigger + read it** for conflict detection, or state LWW as intended | S | Med — silent data loss |
| 8 | **Give `AroundTownCarousel` VoiceOver + Reduce Motion** — today it is unusable with either | M | Med |

---

## 8. Numbered questions for Jesse

**Q1 — Phase 1 scope.** The persistence migration in §3.2.2/§3.2.4 fixes a defect that does not
exist, while changing the `user_utility_prefs` jsonb contract under whole-row LWW sync. Recommend
**dropping it** and shipping the one-line entry-point fix + §3.2.5 empty state + §3.2.6 reachability
test. Drop, or build as specified?

**Q2 — trailing slot.** Phase 2 wants avatar *and* overflow menu as separate items. Today they are
one button; the `+` and search were deliberately removed and folded into the drawer. Split them back
out (a product change), or keep the single menu button and restyle it?

**Q3 — Reduce Motion vs. verbatim.** The `Masthead` animation ignores Reduce Motion. "Preserved
verbatim" and "Reduce Motion honored on every animation" cannot both hold. Preserve exactly, or
preserve values and add a Reduce-Motion branch?

**Q4 — dark mode.** Gate 3 asks for light/dark screenshots. `DECISIONS.md:153` records the token set
as light-mode-only with dark mode explicitly deferred. Drop dark from Gate 3, or is dark mode now in
scope (a much larger job)?

**Q5 — corner radius.** Spec says 20pt; tiles ship 22pt as a deliberate Calendar-bento match, and 22
is not in the `Radius` scale. Move to `Radius.card` (20), keep 22, or add a `bento` token?

**Q6 — expand spring.** Spec says `response 0.38, damping 0.86`; tiles ship `0.44 / 0.82`, chosen to
match the Calendar bento. Retune to spec and diverge from Calendar, or keep parity?

**Q7 — live Supabase.** No CLI, no `psql`, no env token, MCP unauthenticated. To verify the migration
against a real row, either authenticate the Supabase MCP, or I verify through the app with your
signed-in session on the simulator. Which?

**Q8 — the "colour exception".** `block-party-brand` allows exactly two exceptions (photography, map
basemap); `docs/UTILITY_ROW.md:7` records the tiles as a third, user-approved one. Confirming that
still holds before Phase 3 builds on it — and note fixing Q/§6.1 means **darkening** those gradients.

**Q9 — town name.** There is no town model; the app is single-town by design, with St. Joseph
hardcoded in 5 places including the weather lat/lon. "Data-driven from the user's town record" has no
record to read. Introduce a `Town` constant now, or build the real per-user town record (large)?

**Q10 — missing skills.** `design-match-loop`, `hygge-keeper`, and `grill-with-docs` do not exist in
this environment, nor a `code-reviewer` agent or an "iOS build-out plugin". Proposed substitutes:
XcodeBuildMCP screenshot loop; `refactor-cleaner` agent; `codex-review` + `superpowers:requesting-code-review`;
Codex via the `codex` plugin MCP. Approve, or install the real ones first?

---

## 9. Environment notes

- Target worktree is `block-party-utility-row`; the main `Hygge` checkout is ~20 commits stale and
  has no utility row at all.
- Build profile `today-tab` isolates DerivedData at `.dd/` (gitignored) to avoid the documented
  stale-build trap.
- The simulator is currently **left in the reproduced stuck state** as Gate 1 "before" evidence.
