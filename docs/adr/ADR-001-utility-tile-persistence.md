# ADR-001 — Utility tile persistence: the catalog is the source of truth

**Date:** 2026-08-03
**Status:** Accepted
**Branch:** `fix/today-utility-entry-point`
**Supersedes the persistence work specified in the Today-tab build brief.**

> First ADR in this repo. No prior ADRs and no existing numbering scheme were found
> (`find . -iname "*adr*"`, excluding DerivedData), so this establishes one:
> `docs/adr/ADR-NNN-kebab-slug.md`, zero-padded to three digits, numbered in the order
> decisions are accepted.

---

## Context

A user's Utility Row was stuck at two tiles with no way to restore the other two.
Reinstalling the app did not fix it, which ruled out a corrupt local mirror: the row's
state also lives in Supabase (`user_utility_prefs`) and is pulled back down on the next
sign-in.

The reported symptom looked like a persistence one-way door — tiles disabled once and
then dropped from storage permanently, unrecoverable without a data change. The brief
specified the matching fix: persist every catalog tile with an explicit `isEnabled`
flag, add a schema-version key to the stored payload, and write a migration to convert
existing rows.

That fix was investigated and deliberately **not** built. The premise was wrong.

## Investigation

**The catalog cannot run out of tiles.** `UtilityTileRegistry.catalog` is a hardcoded
compile-time array of four descriptors, constructed fresh in `init()` on every launch.
It is not persisted, not derived from prefs, and nothing in the app can trim it.

**The sheet already seeds from the catalog, not from what is enabled.**
`UtilityCustomizeSheet.seed(saved:catalog:)`:

```swift
nonisolated static func seed(saved: [UtilityTileID],
                             catalog: [UtilityTileID]) -> (order: [UtilityTileID],
                                                           enabled: Set<UtilityTileID>) {
    let enabled = Set(saved)
    let disabled = catalog.filter { !enabled.contains($0) }
    return (order: saved + disabled, enabled: enabled)
}
```

Saved tiles first in their saved order, then **every remaining catalog tile**, listed
but off. A disabled tile is always present in the sheet, at any prior state, so it can
always be turned back on. There is no door to be one-way.

**Per-tile settings were never filtered either.** `UtilityRowView`'s save drops disabled
ids from `tiles` (`order.filter { enabled.contains($0) }`) but writes `settings`
untouched, so the garbage tile's pickup weekday survives a disable → re-enable round
trip. The config the migration was meant to protect was never at risk.

Storage is sound. The stuck row was a UI dead end.

## The actual defect

`UtilityRowView.swift`, one line:

```swift
var showCustomizeTile: Bool { !prefs.hasSavedOnce || tiles.isEmpty }
```

After the first save with at least one tile enabled, both terms go false and the row
removes the trailing Customize tile — its only visible way into the sheet. The sole
remaining path was a `.contextMenu` long-press on a tile, which is not an affordance a
user can discover. The data was intact the whole time; the user simply had nothing to
tap.

**Why it survived testing.** The shipped acceptance check in `docs/UTILITY_ROW.md`
tested *"disable all four"*. That makes `tiles.isEmpty` true, which brings the Customize
tile back, so the check passed. Disabling *some* — the ordinary case, and the only
broken one — was never exercised. The transferable lesson: an acceptance check written
against the extreme value can pass over a defect that only exists in the middle of the
range. Test the partial case, not just the empty one.

## Decision

1. **The catalog stays the single source of truth for what CAN be shown.**
   `utility.tiles` stores only what IS shown, in order. Nothing else.
2. **The entry point into the Customize sheet is permanent.** `showCustomizeTile` is
   `true` at every tile count. It reads "Add quick info" when nothing is enabled and
   "Customize" otherwise.
3. **No schema-version key. No migration. No `isEnabled` persistence.** The stored
   shape is unchanged.

The invariant — no sequence of toggles and reorders may make a catalog tile unreachable
from the sheet — is now pinned by a randomized property test over ~200 replayable
operation sequences (`BlockPartyTests/UtilityCustomizeSheetSeedTests.swift`), run
against the real persistence path so a "relaunch" is a genuine second store reading
genuinely written bytes.

## Why the specified migration was rejected

It would have changed a live `jsonb` contract that has no version arbitration in it.

- The client upserts the whole row (`on_conflict=user_id`,
  `resolution=merge-duplicates`). Sync is **whole-row last-write-wins** — no version, no
  etag, no field-level merge.
- `updated_at` is dead. It is set at INSERT, no trigger bumps it, the client never sends
  it, and the decoded `UtilityPrefsRow.updatedAt` is never read. Confirmed against the
  live database. There is nothing to arbitrate on.

So an app version writing the new shape and an app version writing the old one would
overwrite each other with no way to tell which was newer. That is real risk, taken on
behalf of a defect that did not exist. Affected accounts recover by opening the sheet
and turning tiles back on; no data change was required, and none was made.

`supabase/migrations/20260724120100_user_utility_prefs.sql` is untouched — applied
history is never edited.

## Consequences

**Positive**

- No migration risk, and no change to a live sync contract that cannot arbitrate.
- Affected users recover in-app. No reinstall, no support step, no data edit.
- The fix is one line of behavior plus copy, instead of a schema change across two
  storage layers.
- The reachability invariant is now covered by a property test rather than a single
  hand-picked case, which is what let the original defect through.

**Negative**

- **Relative order among disabled tiles is not preserved.** Disabling a tile drops it
  from `utility.tiles` entirely; on the next open it re-lists in catalog order, not
  where the user last had it. Acceptable at a four-tile catalog; worth revisiting if the
  catalog grows.
- **`hasSavedOnce` still exists.** It no longer gates the entry point, only the
  first-run caption (`showCaption`). A key that means less than its name suggests is a
  future reading hazard. It stays because the `utility.*` UserDefaults keys are never
  renamed — renaming logs users out.
- **The row must keep exactly one permanent affordance.** That is now a load-bearing
  constraint on any future redesign of the Utility Row, not a stylistic preference. A
  redesign that hides the Customize tile behind a gesture or a scroll position
  reintroduces this defect.

## Open

Whole-row last-write-wins can still silently drop one of two concurrent device edits:
two phones save different tile sets, the later upsert wins outright, and the earlier
edit is gone with no signal. Untouched by this decision — the sync contract is exactly
as it was. It deserves its own ADR, and any fix for it is the natural place to introduce
a version field, since that change has to reckon with arbitration anyway.
