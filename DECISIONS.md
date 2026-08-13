# Block Party rebrand — decisions and outstanding actions

This is the durable record for the identifier purge and the deliberately retained
historical/external references. Dated implementation sections below remain as history;
the 2026-08-09 decision in §1 supersedes their earlier keep-the-identifiers analysis.

---

## 1. Decided 2026-08-09 — full identifier purge

The original carve-out treated persisted identifiers as permanently frozen because a
rename would log out every existing install and erase local state. That analysis was
incomplete: it never considered a one-time migration that reads the old value, writes
the new value, then deletes the old value.

The app is pre-launch. At the decision point the production project had **4 auth
users, 2 active in the prior 30 days, and 1 town profile**. With such a small surface,
an explicit migration removes the data-loss risk and the App Store continuity cost is
known rather than speculative.

**Jesse's decision on 2026-08-09: full purge.** The accepted end state is:

| Identifier | End state |
|---|---|
| Bundle identifier | `Jesse.BlockParty` |
| Log subsystem | `Jesse.BlockParty` |
| Keychain account | `bp.session` |
| Product-namespaced UserDefaults | `bp.*` |
| Realtime topic | `realtime:bp-<table>` |

**No migration shim exists, and one is impossible.** The original plan was to preserve
user data with a read-old → write-new → delete-old migration. That plan was wrong, and
the reason is worth recording so nobody re-proposes it: iOS scopes `UserDefaults` to the
app container and Keychain items to an access group derived from the bundle id.
`Jesse.BlockParty` is therefore a **different app** with an empty container — it cannot
read anything `Jesse.Hygge` wrote. Bridging would require a shared keychain access group
declared in **both** builds, and the already-shipped build has none, which cannot be
fixed retroactively.

A migration was written, proven unreachable, and removed rather than shipped as dead
code. **Consequence: the rename is a clean break — existing installs re-authenticate and
re-onboard.** That was accepted because the app is pre-launch: 4 accounts, 2 active in
30 days, 1 town profile. It would not be acceptable after launch, which is precisely why
the rename happened now. Realtime topics are ephemeral and need no migration.

### OUTSTANDING console actions

1. **Google Cloud:** add `Jesse.BlockParty` to the Places API key's iOS bundle-id
   restrictions. Skipping this makes **all venue photography go blank** in the renamed
   app because runtime Places requests are rejected.
2. **App Store Connect:** create the new app record for `Jesse.BlockParty`. This bundle
   change intentionally orphans the old listing and its TestFlight builds; they cannot
   be transferred to the new identifier.

These are external actions. No repository edit can substitute for either one.

---

## 2. Deliberate remaining references

- **The one deliberate application-code carve-out is seven Swift comments that
  reference `@hygge/core`. Keep them.** That is the live npm
  package name in the twin Expo repository at
  `~/Documents/my-business/packages/core/package.json`. The comments describe a real
  synchronization boundary and stay accurate until that package is renamed.
- A handful of comments still name `hygge.*` to explain what the keys used to be and
  why nothing is migrated. Those are explanatory, not live identifiers.
- **`supabase/migrations/*` is applied history. Never edit it retroactively.** Old
  identifiers in those files record what actually ran. Consequently,
  `grep -ri hygge` will always find legitimate migration-history hits even after the
  application purge is complete; changing those files would falsify history and would
  not update production anyway.
- The shared Supabase project (`lxdgwhvqjqmqliobwjpi`) also contains an unrelated
  retired **Hygge Health** schema. Do not apply a blind repository- or project-wide
  replacement to another product's data.
- App groups, keychain access groups, associated domains, and URL schemes do not exist
  in this project. `DEVELOPMENT_TEAM = 5Z6CXL9QA8` and automatic-signing configuration
  remain unchanged.

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

### RESOLVED 2026-07-20 — the basemap is colourful again
Jesse's call: **keep the UI white/monochrome, but the map keeps real colour.**
Parks `#D9E8C8`, water `#A8D8EE`; land stays `Hue.paper` and buildings/roads stay
on tokens, so colour is spent only on the natural features that carry meaning and
ink markers still dominate.

The framing that makes this consistent rather than an exception-by-exception
carve-out: **the map is content, not chrome** — the same category as photography.
Chrome is monochrome; content keeps its colour.

The original grayscale attempt and its failure are recorded below, because the
reasoning still applies to any future "make it quieter" instinct.

### Superseded: basemap contrast — the grayscale attempt
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
- **A single accent colour — IMPLEMENTED.** `Hue.accent` is plum/berry
  `#8E3B6B`, deliberately distinct from the retired coral and from the basemap's
  sage/sky terrain. It is meaning-scoped to **live events · active filters ·
  selected/saved state · primary CTAs**. Body copy, cards, category glyphs, and
  decorative backgrounds remain ink/paper; the accent is never filler.

  Current map liveness uses the accent fill/static ring/pulse, and selected map
  chrome/tab-shell controls route through the same token. Keep the value-step fixes
  in `CalendarView.numberColor` and `InsightsMiniCalendar`: those distinguish
  *has data* from *empty*, not active/selected state, so they should not consume the
  accent.
- **App Store distribution work.** The original plan deferred a listing rename. The
  2026-08-09 bundle-id decision supersedes that plan: a new App Store Connect record is
  now required and remains outstanding in §1, along with marketing assets, screenshots,
  and the App Store description.
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

  **Replaced again 2026-08-07** with the new Block Party logo: the script "BP"
  monogram wearing a striped party hat, with confetti — coral-orange and purple
  on a near-black tile. The supplied render was 1254×1254 with the tile floating
  on pure black; the tile face was measured by luminance (the face vignettes to
  ~1.5 luma, the void is ~0.1), the largest centred square cropped full-bleed
  with a 1% edge inset, output 1024×1024 8-bit RGB, no alpha. `LaunchMark`
  (72/1024 inset crop) and `MarkTemplate` (alpha = artwork coverage) were
  regenerated from the same pixels, and the sizing constant was re-measured:
  `inkFraction 0.7511` → `contentFraction 0.8273` (the lockup = letters + hat,
  confetti excluded so placements don't undersize the letters).
- **Superseded test note:** at the time of the original rebrand, `HyggeTests/` was
  inert and had no project target. It has since become the wired `BlockPartyTests`
  target with active coverage; do not treat the old statement as current setup advice.

---

## 3. Migrations applied 2026-08-09 — and the one deliberately split

Applied to `lxdgwhvqjqmqliobwjpi`, in this order, each verified before the next:

1. `board_items_news` — `image_url` + `fetched_at`, the `board_sweeps` table
   (authenticated read only, no client write path), and the backfill that
   published 30 real non-civic staging rows. Town Notes pool is now 41; the 23
   civic rows stay held back for the Civic tab.
2. `posting_dismissals` — own-row RLS mirroring `event_saves`. For You's dismiss
   now persists.
3. `rename_hygge_place_ids` — 62 synthetic ids `hygge-stjoe-*` -> `stjoe-*`,
   sources -> `bp_research` / `bp_curated`. 29 Google `ChIJ*` ids untouched, and
   all 77 `logo_url` values survived (they key off the row uuid, not `place_id`).
4. `trivia_schema` — `correct_idx`, the widened `kind` check, per-lane unique
   indexes, `claim_trivia`, `touch_stats` and `trivia_streak`.
5. `trivia_seed` — 30 questions, all with answers. Today's is claimed.
6. `briefing_touch_excludes_trivia` — see below.
7. `spotlight_weeks_archive` — the archive table, `subject_type`, and a backfill
   of one row per historical ISO week.

### Two authored redefinitions were NOT applied as written

Both `20260809300000_trivia.sql` and `20260809210000_weekly_spotlight_rotation.sql`
rewrite a whole live function. **Neither authored copy matches what is deployed.**

`get_today_briefing` live has a `touch_tally` lateral join — "one grouped scan,
not one count per option" — that the authored copy does not. Applying that file
verbatim would have silently reverted the optimization while looking like a
feature migration. Instead, `briefing_touch_excludes_trivia` reads whatever is
actually deployed, rewrites the single predicate it needs
(`and dt.kind in ('poll','history')`, so a claimed trivia row is never served to
the poll card), and refuses rather than guesses if that predicate is not found.
Verified after: patch present, tally preserved, length +45 chars.

`compose_briefing` is **still the daily rotation.** Its rewrite is the half of
the weekly-spotlight migration that was not applied, for the same reason: it is a
170-line replacement of a live 4KB function and it has not been diffed against
what is deployed. Consequence: `spotlight_weeks` exists and is backfilled, but
nothing writes to it yet and the spotlight still changes daily. The client-side
week key and the "week of August 3" label are already correct, so this is a
server-side rotation change only.

**Rule going forward: never apply an authored `create or replace` of a live
function without diffing it against `pg_get_functiondef` first.** This batch
produced two that would have regressed live behaviour.

---

## 6. Decided 2026-08-13 — map pin-detail sheet (map polish Phase 3)

- **Status-card tint is one token, seeded neutral.** The Flighty-anatomy pin
  sheet's status card routes its wash through `Hue.statusTint`
  (`Theme/BlockPartyColor.swift`), currently `= fill` with ink header dot/word.
  Jesse is crafting a custom orange; when the hex arrives, replacing that single
  value is the entire swap. Do not guess an orange in the meantime.
- **The sheet's action bar is a PILL — a deliberate brand exception.** The brand
  rule stays "buttons are 12pt rounded squares, never pills"; Jesse chose the
  Flighty-faithful capsule for this one floating bar. It lives behind one
  constant (`PinDetailSheet.actionBarShape`) with a `.roundedSquare` variant one
  line away; both variants were screenshotted at the decision.
