# Today Utility Row — build notes & acceptance

A registry-driven, fully user-customizable row of glanceable town-info tiles on the
Today tab (weather · garbage · roads · library), below the almanac and above the
feed. Tiles are a structural clone of the Calendar bento box (22pt `.continuous`
corners, gradient, `insightsCardShadow`) and **tap-expand in place** with the
bento's spring (0.44 / 0.82). Colours are a deliberate, user-approved departure
from the monochrome chrome.

## Architecture (files)

- `Features/Home/Utility/UtilityTile.swift` — provider protocol + model types
  (`UtilityTileID` is string-backed for forward compat; `TileSettings`/`JSONValue`
  bridge the jsonb settings).
- `UtilityTileColor.swift` — the COLOR SYSTEM (gradient tokens + WeatherState map).
- `UtilityTileRegistry.swift` / `UtilityTileDescriptor` — single source of truth.
- `UtilityTileView.swift` — the box tile (compact/expanded, loading/failed/stale).
- `UtilityRowView.swift` + `UtilityRowModel` — the row, fetch/expand/subscribe.
- `UtilityCustomizeSheet.swift` — the customize sheet (+ MiniTilePreview, garbage picker).
- `Providers/*` — weather, garbage (`GarbageSchedule`), library (`LibraryHours`), roads.
- `Backend/{TownStatusAPI,UtilityPrefsAPI,SupabaseCoding}.swift`, `WeatherBar.swift`
  (`WeatherService`), `RealtimeClient.onAnyChange`.
- Migrations: `supabase/migrations/2026072412000{0,1}_*.sql` (applied live).

## Colour system — final hexes (all pass WCAG 4.5:1 white text on the lighter stop)

| tile | top | bottom | worst ratio |
|---|---|---|---|
| weather (static fallback) | `#3677AF` | `#20528F` | 4.76 |
| garbage | `#1F8438` | `#115A24` | 4.76 |
| roads | `#A46404` | `#7B3900` | 4.77 |
| library | `#A14BCD` | `#712B9B` | 4.77 |
| customize | `#727276` | `#47474B` | 4.79 |

Weather tile derives from the live condition, darkened to pass contrast:

| state | top | bottom | ratio |
|---|---|---|---|
| clearDay | `#375D7A` | `#637581` | 4.78 |
| clearNight | `#1B2A4A` | `#33415E` | 10.20 |
| cloudy | `#505962` | `#6E7379` | 4.78 |
| rain | `#46515C` | `#68747E` | 4.79 |
| snow | `#565C61` | `#6F7376` | 4.78 |
| storm | `#2C2E3A` | `#4A4E63` | 8.20 |

Verified programmatically (`UtilityContrast.worstRatioOnWhite`; derivation in
`scripts/contrast.py`). The raw spec hexes (bright green/orange) were 2.0–3.3:1 and
were darkened, hue-preserving, in linear light.

## Extensibility proof — adding a "school" tile

The row, sheet, and tile view contain **zero hardcoded tile ids** (verified by grep).
To add a tile you touch exactly four spots, none of them UI:

1. **Provider** — `Providers/SchoolTileProvider.swift`: `final class SchoolTileProvider:
   UtilityTileProvider { let id: UtilityTileID = .school; let refreshPolicy = …;
   func fetch(settings:) … }`.
2. **Id constant** — `UtilityTile.swift`: `static let school: UtilityTileID = "school"`
   (and add to `defaults` if it should ship on by default).
3. **Gradient token** — `UtilityTileColor.swift`: `static let school: [UInt32] = […]`
   (darken so the lighter stop passes 4.5:1).
4. **Registry entry** — `UtilityTileRegistry.swift`: one `UtilityTileDescriptor(id:
   .school, displayName:, symbol:, gradient: UtilityTileGradient.school, summary:,
   provider: SchoolTileProvider(), settingsEditor: …)`.

`UtilityRowView.swift`, `UtilityCustomizeSheet.swift`, `UtilityTileView.swift`:
**unchanged.** The row renders `model.tiles` via the registry; the sheet renders
`registry.catalog`; both are id-agnostic. (For a realtime `kind`, no migration is
needed — `town_status.kind` is free text.)

## Acceptance checklist

- **Fresh install → defaults render real data quickly:** the row paints instantly
  from the UserDefaults mirror (defaults); garbage/library are local (instant),
  weather/roads fetch with a shimmer → data. ✔ (verified in sim)
- **Airplane mode:** garbage + library are pure-local (correct); weather/roads throw
  → `.failed` → em-dash value, never a crash; a prior loaded value is kept on a
  refresh failure. ✔ (by construction)
- **Change garbage day → updates immediately + survives relaunch:** the sheet's
  weekday picker → `applyDraft` → `prefs.save` (UserDefaults + Supabase) →
  re-fetch garbage. Relaunch reads the UserDefaults mirror. ✔ (by construction)
- **Edit `town_status` roads row → tile updates ~2s while open:** `RealtimeClient`
  on `town_status` → `onAnyChange` → re-fetch (same pipeline as the map). ✔ (by construction)
- **Disable all four → only the Customize tile shows; re-enable works.** ✔ (verified in sim)
- **Extensibility:** see above — no row/sheet edits. ✔

## Accessibility / Dynamic Type

- **VoiceOver:** each tile is one element reading "Name, value, secondary" (or
  "loading"/"unavailable"); the Customize tile is a labelled button; the sheet uses
  standard controls. (Confirmed against the runtime accessibility tree.)
- **Dynamic Type:** tiles use fixed `.system(size:)` fonts to match the Calendar
  bento (per the "same as the calendar box" direction), so they are stable across
  Dynamic Type — they don't clip, but they also don't enlarge with it. If the tiles
  should scale with Dynamic Type, that is a deliberate departure from the bento match.

## Review & hardening

An adversarial multi-agent review (5 dimensions × find-then-refute) confirmed 13
defects; all real ones are fixed:

- **HIGH — RealtimeClient leak:** `start()` re-created subscriptions after
  `teardown()` if the tab was left during the `hydrate()` network window → an
  orphaned websocket + heartbeat forever. Fixed: `guard started, !Task.isCancelled`
  after the await (teardown is authoritative) + `reconcileSubscriptions()`.
- **HIGH — offline data loss:** `hydrate()` overwrote an un-synced offline edit with
  the stale server row. Fixed: a `pendingSync` flag — a failed upsert stays pending,
  and hydrate pushes local (retries) instead of pulling while pending.
- **HIGH — VoiceOver:** the expanded rows + warning badge weren't announced and the
  tile lacked the button trait. Fixed (a11y label now includes them; `.isButton`).
- **MED — garbage holidays hardcoded to 2026:** floating holidays (Memorial/Labor/
  Thanksgiving) now computed per-year by rule; the shift compares by week-offset so
  it's correct for any `firstWeekday` (regression test in a 2028 week).
- **MED — customize toggles unnamed** for VoiceOver → labelled with the tile name.
- **LOW —** `WeatherService` now coalesces concurrent callers (no cache stampede);
  `JSONValue.intValue` is crash-safe on NaN/out-of-range doubles.
- **Accepted by design (documented):** fixed type sizes (no Dynamic Type scaling) to
  match the bento; long-press is the ongoing reconfigure entry after first save.

## Debug launch flags (RootView gate branch, DEBUG only)

`-utility-row-preview` (render the row past auth) · `-utility-expand` (auto-expand the
first tile) · `-utility-customize` (open the sheet) · `-utility-empty` (force zero
tiles → Customize-only state).
