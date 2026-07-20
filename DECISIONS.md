# Block Party rebrand — decisions & open questions

Branch: `rebrand/block-party`, cut from `integration/pre-rebrand`
(= `main` + almanac-greeting-glyph + st-joe-community-feed + tab-loading-cover).

This file is the one place "hygge" is allowed to survive. Everything below is
either a deliberate carve-out or an open question for Jesse.

---

## 1. Identifiers deliberately NOT renamed

These are wire-level or persisted identifiers. Renaming them is a behaviour
change, not a reskin, so they keep the old spelling on purpose.

| Identifier | Value | Why it stays |
|---|---|---|
| Bundle identifier | `Jesse.Hygge` | Changing it creates a **new App Store Connect app** and orphans the existing listing, TestFlight builds, and installs. Also the Google Places API key is restricted to this bundle ID in Cloud Console — changing it silently breaks Places lookups. |
| Log subsystem | `Jesse.Hygge` | Deliberately mirrors the bundle ID. Kept in sync with it. |
| Keychain account | `hygge.session` | Renaming logs out **every existing install** on next launch. |
| UserDefaults keys | `hygge.onboarded`, `hygge.onboarded.<uid>`, `hygge.interests`, `hygge.saved.ids`, `hygge.displayName` | Renaming resets onboarding and loses every user's saved items and interests. |
| Realtime topic | `realtime:hygge-<table>` | A wire-level channel name shared with the backend and with app instances already in the field. Changing it puts new builds on a different channel from old ones. |
| Supabase seed data | `hygge_research`, `hygge_curated`, `hygge-stjoe-*` place slugs | **Live rows in the production database**, written by already-applied migrations. No Swift code references them (verified), so they are data-only. Editing the applied migration files would not change the live DB and would falsify migration history. |

**Consequence:** the Phase 1 exit check `grep -ri "hygge"` cannot return empty.
It should return exactly: this file, the bundle ID / log subsystem, the five
storage keys, the realtime topic, and `supabase/migrations/*`. Anything else is
a real miss.

### Open question — bundle ID
Renaming `Jesse.Hygge` → e.g. `Jesse.BlockParty` is possible but it is a
**new app** to the App Store, not a rename of the existing one. The visible app
name on the Store is controlled by the App Store Connect listing and
`CFBundleDisplayName`, both of which now say "Block Party" regardless. Recommend
leaving the bundle ID alone permanently. **Needs Jesse's call if we ever want the
identifier itself to read BlockParty.**

### Open question — storage keys
If the app has never shipped outside Jesse's devices, the five storage keys and
the realtime topic could be renamed freely. Chosen approach assumes there *may*
be real installs. **Revisit if pre-launch is confirmed.**

---

## 2. Untouched by the rebrand

- `supabase/migrations/*.sql` — applied history. Never edited retroactively.
- The Supabase project (`lxdgwhvqjqmqliobwjpi`) also backs an unrelated
  "Hygge Health" wellness app. Any find/replace across `supabase/` risks
  touching another product's config. Left alone.
- App group IDs, keychain access groups, associated domains, URL schemes —
  none exist in this project, so nothing to preserve.
- `DEVELOPMENT_TEAM = 5Z6CXL9QA8` and signing config — unchanged.

## 3. `.gitignore` — secret paths repointed

`.gitignore` ignored `Hygge/Config/MapboxConfig.swift` and
`Hygge/Config/GooglePlacesConfig.swift`. After the folder rename those paths
must become `BlockParty/Config/...`, otherwise the **Mapbox token and Google
Places API key stop being ignored** and are one `git add -A` away from being
committed. Repointed as part of the rename.

---

## 4. Deferred branches

Two branches were NOT merged before the rebrand, by decision, because they
conflict on genuinely divergent map work rather than on anything mechanical:

- `feat/map-poi-markers` — Phases A–C, replaced `POILayer.swift` (Mapbox symbol
  layers) with SwiftUI view annotations (`POICluster`, `POIMarkers`,
  `SJMapView+POIClustering`).
- `feat/upcoming-personal-insights` — the Upcoming "personal town dashboard"
  remake (adds `SpotlightWheel.swift`); an earlier version of this work is
  already in `main` via `7cf6964`. Carries one map commit
  (`cc89eb2` Liquid-Glass chrome) which is the source of most of its conflicts.

Both must now be merged **across the rename**, so their paths will need
repointing. This was the accepted cost of not reconciling divergent map
architectures inside a rebrand task.

### Decided — POI rendering architecture
The **SwiftUI view-annotation rewrite** (`feat/map-poi-markers`) is the intended
future; `main`'s `POILayer.swift` is to be retired.

**Consequence for Phase 3:** the map reskin is deliberately limited to
token/colour changes (cluster fill, pin tint, control borders) that port cleanly
to either architecture. No structural map changes, because that code is being
replaced. Expect to re-apply the ink tokens to `POICluster`/`POIMarkers` when
that branch lands.

---

## 5. Deferred / out of scope for this rebrand

- **Dark mode.** The token set is light-mode only (ink on paper). There is also
  a pre-existing Dark Mode tab-bar contrast bug noted on the map branch.
- **A single optional accent colour.** Phase 1–4 ship pure monochrome; photos
  carry all colour. Adding one accent later is a deliberate, separate decision.
- **App Store listing rename**, marketing assets, screenshots, and the
  App Store description.
- **App icon pixels.** The 1024×1024 `AppIcon.png` has the "Hygge" wordmark
  baked into the image. A grep can never catch this — it is replaced by Jesse's
  `block-party-icon.png` in Phase 4.
- `HyggeTests/` has **no target in the Xcode project** (verified — it is inert
  source, never compiled). It is renamed for consistency but wiring it up as a
  real test target remains a separate task.
