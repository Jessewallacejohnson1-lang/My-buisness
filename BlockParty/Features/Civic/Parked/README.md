# Parked — the utility tile row

**This code is not dead. It is waiting for the Civic tab.**

It was removed from the Today tab on 2026-08-09 when Today became a daily-edition
feed. Nothing here was rewritten; it moved as a unit, intact, and it still
compiles and still has its tests. Do not delete it, and do not "clean it up"
because it looks unreferenced — it is unreferenced *on purpose*, for now.

## What's here

15 files, ~2,138 lines, moved verbatim from `Features/Home/Utility/`:

- `UtilityTile.swift` — the `UtilityTileProvider` protocol, tile content/state
  model, and the `UtilityRefreshPolicy` (`.computed` / `.cached(ttl:)` /
  `.live(staleAfter:)`).
- `UtilityTileRegistry.swift` — the catalog. Four descriptors: weather, garbage,
  roads, library. Adding a tile is a provider + an id + a gradient + one entry.
- `UtilityRowView.swift` — `UtilityRowModel` plus the horizontal row.
- `UtilityTileView.swift` — the tap-to-expand tile.
- `UtilityCustomizeSheet.swift` — toggle / drag-reorder / per-tile settings.
- `UtilityPrefsStore.swift` — UserDefaults mirror + Supabase sync.
- `UtilityTileColor.swift` — **the app's one full-colour exception.** Gradients
  plus the WCAG contrast math that verifies them.
- `UtilityRowEntrance.swift`, `UtilityFormat.swift`, and `Providers/` (weather,
  garbage + schedule math, library + hours, roads).

## What deliberately did NOT move

These stay where the house pattern puts them, and the Civic tab will need them:

- `Backend/UtilityPrefsAPI.swift` — PostgREST client for `user_utility_prefs`.
- `Backend/TownStatusAPI.swift` — `town_status` reads; used only by
  `RoadsTileProvider`, and the table's `kind` column is deliberately open-ended
  so other civic content can share it.
- `Theme/Motion.swift` — `bentoExpand` / `tilePress` / `tileEntrance` are shared
  with the Calendar Insights bento boxes. **Do not move or delete them.**
- `Features/Home/WeatherService.swift` — shared with the almanac and greeting.
  The weather tile is a consumer, not the owner.

## Live user data — read this before rebuilding

`user_utility_prefs` (Supabase) and the `utility.*` UserDefaults keys still hold
real per-user configuration: which tiles are enabled, their order, and the
garbage pickup weekday.

Per Jesse's 2026-08-09 decision, `UtilityPrefsStore` is **disconnected for now** —
Today no longer mounts the row or hydrates prefs. The rows were not deleted. When
the Civic tab is built it should re-hydrate them rather than start from defaults,
or a user who customised their tiles will silently lose that.

`docs/adr/ADR-001-utility-tile-persistence.md` treats reachability of the
Customize sheet as a load-bearing invariant. Re-read it before redesigning.

## Still verifiable

The DEBUG flag `-utility-row-preview` still renders the row full-screen,
bypassing the auth gate (`RootView`). Use it to confirm this code still works
before wiring it into Civic. Its tests also still run in `BlockPartyTests`:
`UtilityRowMotionTests`, `UtilityContrastTests`, `UtilityPrefsCodecTests`,
`UtilityProviderTests`, `UtilityRowModelTests`, `UtilityTileVisualTests`,
`UtilityCustomizeSheetSeedTests`, `GarbageScheduleTests`, `LibraryHoursTests`.

See `Features/Civic/CivicTabDestination.swift` for the destination stub.
