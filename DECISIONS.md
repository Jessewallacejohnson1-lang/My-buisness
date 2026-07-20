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

## 4b. Open design questions raised by going monochrome

These are consequences of removing the accent colour. None is a bug; each is
a judgement call for Jesse. **Do not "fix" any of them by reintroducing a
hue** — the fix, if wanted, is weight, size, value, or spacing.

### Basemap contrast — recommend widening
The grayscale ramp is land `#FAFAF7` → parks `#EFEFEC` → water `#E4E4E0`:
about a 6% luminance spread. The Sauk River and the parks are visible but
faint, where before they were sky-blue and sage and read instantly. The map
is the one screen where the background *is* the content, so this is the
weakest point of the monochrome system. Widening to roughly water `#DDDDD8`
and parks `#E9E9E5` stays fully grayscale while letting them work as
landmarks again.

### The Saved pin is the weakest state
Pin state precedence (selected > live > saved > rest) is intact, but Saved
now differs only by a small bookmark corner badge and effectively disappears
in compact mode. Colour used to carry it. Needs a weight/size/fill treatment.

### Accepted, not fixed: POI dots below zoom 14.25
`PlaceCategoryMap.tint` collapses food and business to `Hue.ink` (they were amber
and indigo). Glyphs distinguish them, but glyphs only cross-fade in around the
awake threshold (`POILayer.revealAtAwake`, ~14.25–14.55), so at town-level zoom
the two families are undifferentiated ink dots where colour used to separate them.

Not fixed here on purpose. The only in-place fixes are lowering the awake
threshold — which changes tuned decluttering behaviour, outside a reskin — or
restructuring the Mapbox `circle-color` expression, which is work on
`POILayer.swift`, the file being retired for the SwiftUI-annotation rewrite
(§4). **Carry this into that rewrite:** the new markers need a non-colour way to
separate food from business at low zoom (size, or filled-vs-ring).

### Value now carries what colour used to
Several states are deliberately distinguished by value or weight alone:
- Calendar: days with happenings are `ink`, empty days `inkSecondary`. This
  was a real regression when both were `ink` (fixed in `dc1c467`) — upcoming
  events had become invisible in the grid.
- `InlineAction` success vs error: both `ink`, separated by the check /
  exclamation glyph and bold copy.
- Login success vs error messages: same treatment.
- Destructive actions: the row label loses its red, but the confirmation
  dialog still uses SwiftUI's `.destructive` role, which iOS renders red
  outside our theme — so the warning survives where the decision happens.

## 5. Deferred / out of scope for this rebrand

- **Dark mode.** The token set is light-mode only (ink on paper). There is also
  a pre-existing Dark Mode tab-bar contrast bug noted on the map branch.
- **A single optional accent colour.** Phase 1–4 ship pure monochrome; photos
  carry all colour. Adding one accent later is a deliberate, separate decision.
- **App Store listing rename**, marketing assets, screenshots, and the
  App Store description.
- **App icon pixels.** The old 1024×1024 `AppIcon.png` had the "Hygge" wordmark
  baked into the image — the one rebrand artifact a grep could never catch.
  Replaced in Phase 4 (`4a0fd09`).

  The supplied artwork needed mechanical correction first: it was 1092×1092
  with rounded corners, a drop shadow, and ~200px of outer margin baked in.
  iOS applies its own superellipse mask, so shipping it unmodified would have
  double-rounded the corners and left a shadow ring and grey margin inside the
  tile, shrinking the mark by roughly 15%. It was remapped so the rounded card
  fills the full canvas (mark at 64.6%, centred), output 1024×1024 8-bit RGB
  with no alpha. **If the icon is ever re-exported, export it full-bleed** —
  no rounded corners, no shadow, no transparency.
- `HyggeTests/` has **no target in the Xcode project** (verified — it is inert
  source, never compiled). It is renamed for consistency but wiring it up as a
  real test target remains a separate task.
