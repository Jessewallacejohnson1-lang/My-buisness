# Harvest ledger — historical logs

**Nothing has moved.** `MAP_BUILD_LOG.md`, `REVIEW.md` and `DECISIONS.md` are byte-identical
to what they were before this file existed, and they stay that way until Jesse approves the
verdicts below. This is a proposal, not a migration: no line has been copied into a rules
leaf, no line has been archived, and nothing has been deleted.

**This is not a complete harvest of the three logs' rules.** It is a complete harvest of what
one regex — a **bolded lead at the head of a bullet**, `^\s*[-*]\s+\*\*([^*]{8,120})\*\*` — can
see on a single line. Eight known blind spots, each verified against the sources:

1. **A literal `*` anywhere inside the lead** kills the match at any length, because the class
   is `[^*]`. `DECISIONS.md:69` — *"**`supabase/migrations/*` is applied history. Never edit it
   retroactively.**"* — is a **live, actionable rule that is not a row below**. Recorded here so
   it is not lost.
2. **A bold lead that wraps across a line break** is invisible to a single-line pattern (example
   in `DECISIONS.md`: the "seven Swift comments that reference `@hygge/core` — keep them" rule;
   that one is already carried by `architecture.md`/`identifiers.md`, so nothing was lost).
3. **Bold in mid-sentence rather than at the bullet head** — where much of the real rule text
   actually sits (e.g. the anti-grayscale and hidden-`poi-label` clauses inside `MAP_BUILD_LOG.md:2168`).
4. **Unbolded sub-bullets and continuation lines** under a matched bullet (e.g. `MAP_BUILD_LOG.md:725`).
5. **Running prose under a heading**, with no bullet at all.
6. **Fenced code and SQL blocks** — applied migrations, style expressions, launch-arg recipes.
7. **Headings** — which is why all 16 `REVIEW.md` rows lead with the identical word `CONFIRMED`.
8. **Leads under 8 or over 120 characters** (e.g. `- **Water**:` at `MAP_BUILD_LOG.md:2162`).

The extractor was left exactly as specified rather than widened, so this ledger mirrors its row
set precisely. A second pass, if wanted, starts from the list above.

`scripts/harvest_candidates.py` extracted the rows — every bolded bullet lead the pattern above
can see. The script decides nothing. Each
`Verdict` and `Destination` below was assigned by reading the bullet and checking the claim
against the current source.

## The verdicts

- **`promote`** — still true, and a reader touching that area needs it before acting. The
  `Destination` names the `docs/rules/*.md` leaf it belongs in.
- **`drop`** — the surface it describes was deleted in the 2026-09-17 strip-down or has since
  been superseded. `docs/GUTTING-LEDGER.md` records what went and how to get it back, so the
  line does not need a second home. (Map-internal retirements — the Living Basemap, `POILayer`,
  the map "+"/`QuickAddSheet`, `SpotFilter` — are recorded in `docs/rules/map.md` rather than
  in the gutting ledger, but the disposition is the same.)
- **`archive`** — true and worth keeping, but it is a record of work done, a measurement, a
  verification note, or something a rules leaf already states. Nobody needs to read it before
  acting.

A rule's *evidence* often names a surface that no longer exists; that does not make the rule
dead. Rows were judged on whether the reader still needs the rule, not on whether a dead thing
is mentioned. Two rows carry that shape explicitly: `MAP_BUILD_LOG.md:1070` (`.regularMaterial`
is appearance-adaptive) reasons from "this app is light-only", which stopped being true when
dark mode landed — but the map canvas is still appearance-fixed, so the trap stands; and
`REVIEW.md:124` (a plain `VStack` in a `ScrollView` builds every child and fires every
child's `.task`) was found in the deleted Activities tab.

## Rows needing Jesse's judgement

One row is marked `promote` with a destination of `?` — `MAP_BUILD_LOG.md:2338`, "Civic full
details can render near-empty". It is an unresolved **content** decision (what a civic spot's
full page holds when Google Places has nothing), not a rule yet. It is recorded as `promote`
rather than `archive` so archiving does not bury it, but its leaf depends on the answer.

## The table

The first three columns are the extractor's output, unchanged. `Verdict` and `Destination`
were filled by hand. **`Section` is added here and is not the extractor's** — it is the
nearest preceding heading in the source file, because a bare lead like `Verified:` or
`CONFIRMED` says nothing about what is being judged (all sixteen `REVIEW.md` rows lead with
the same word). It is context for the approval pass, nothing more.

| Source | Line | Rule lead | Verdict | Destination | Section |
| --- | ---: | --- | --- | --- | --- |
| `MAP_BUILD_LOG.md` | 190 | Selected: | archive |  | Phase 2 — Marker bubbles |
| `MAP_BUILD_LOG.md` | 216 | Recenter: | archive |  | Phase 4 — Chrome |
| `MAP_BUILD_LOG.md` | 221 | Loading/error: | archive |  | Phase 4 — Chrome |
| `MAP_BUILD_LOG.md` | 305 | `Backend/RealtimeClient.swift` | archive |  | Part A — the map updates itself |
| `MAP_BUILD_LOG.md` | 310 | `Features/Map/MapModel.swift` | archive |  | Part A — the map updates itself |
| `MAP_BUILD_LOG.md` | 316 | `Backend/SupabaseConfig.swift` | archive |  | Part A — the map updates itself |
| `MAP_BUILD_LOG.md` | 332 | Admin gate: | drop |  | Part B — quick-add (post from the map) |
| `MAP_BUILD_LOG.md` | 335 | "+" button | drop |  | Part B — quick-add (post from the map) |
| `MAP_BUILD_LOG.md` | 339 | `Features/Map/QuickAddSheet.swift` | drop |  | Part B — quick-add (post from the map) |
| `MAP_BUILD_LOG.md` | 415 | Realtime INSERT → pulse (zero refresh): | archive |  | Independent re-verification (2026-07-05, fresh screenshots on iPhone 17 sim) |
| `MAP_BUILD_LOG.md` | 420 | Realtime DELETE → clears (zero refresh): | archive |  | Independent re-verification (2026-07-05, fresh screenshots on iPhone 17 sim) |
| `MAP_BUILD_LOG.md` | 423 | Non-admin gate — CORRECTION. | archive |  | Independent re-verification (2026-07-05, fresh screenshots on iPhone 17 sim) |
| `MAP_BUILD_LOG.md` | 460 | Porthole detail: | promote | `docs/rules/map.md` | Map intro onboarding screen (2026-07-06) |
| `MAP_BUILD_LOG.md` | 464 | Choreography: | archive |  | Map intro onboarding screen (2026-07-06) |
| `MAP_BUILD_LOG.md` | 468 | Verified: | archive |  | Map intro onboarding screen (2026-07-06) |
| `MAP_BUILD_LOG.md` | 480 | Adversarial review (10-agent workflow) → 4 confirmed fixes: | archive |  | "?" help button + review pass (2026-07-06) |
| `MAP_BUILD_LOG.md` | 488 | Accepted / by-design: | archive |  | "?" help button + review pass (2026-07-06) |
| `MAP_BUILD_LOG.md` | 496 | Basemap coloring | archive |  | Life360-style redesign of the map tab (2026-07-06) |
| `MAP_BUILD_LOG.md` | 500 | Top chrome | drop |  | Life360-style redesign of the map tab (2026-07-06) |
| `MAP_BUILD_LOG.md` | 504 | Floating controls | drop |  | Life360-style redesign of the map tab (2026-07-06) |
| `MAP_BUILD_LOG.md` | 505 | `MapSheet` (new) | archive |  | Life360-style redesign of the map tab (2026-07-06) |
| `MAP_BUILD_LOG.md` | 513 | DEBUG args added: | archive |  | Life360-style redesign of the map tab (2026-07-06) |
| `MAP_BUILD_LOG.md` | 514 | Verified (screenshot loop, iPhone 17): | archive |  | Life360-style redesign of the map tab (2026-07-06) |
| `MAP_BUILD_LOG.md` | 520 | `GeocoderService.town(lat:lon:)` | archive |  | Dynamic town pill — reverse-geocoded map center (2026-07-06) |
| `MAP_BUILD_LOG.md` | 524 | `MapModel.townLabel` | promote | `docs/rules/map.md` | Dynamic town pill — reverse-geocoded map center (2026-07-06) |
| `MAP_BUILD_LOG.md` | 528 | DEBUG arg: | archive |  | Dynamic town pill — reverse-geocoded map center (2026-07-06) |
| `MAP_BUILD_LOG.md` | 530 | Verified: | archive |  | Dynamic town pill — reverse-geocoded map center (2026-07-06) |
| `MAP_BUILD_LOG.md` | 536 | Filter chip square (`SJMapView.filterMenu`) | promote | `docs/rules/swift-traps.md` | Filter-chip chrome fix + board de-dup + real-content 5× (2026-07-06, overnight) |
| `MAP_BUILD_LOG.md` | 541 | Board duplicate (`CommunityAPI.getBoardSections`) | archive |  | Filter-chip chrome fix + board de-dup + real-content 5× (2026-07-06, overnight) |
| `MAP_BUILD_LOG.md` | 550 | Content 5× (Supabase, data-only — no Swift) | promote | `docs/rules/map.md` | Filter-chip chrome fix + board de-dup + real-content 5× (2026-07-06, overnight) |
| `MAP_BUILD_LOG.md` | 563 | Note (two-repo rule): | archive |  | Filter-chip chrome fix + board de-dup + real-content 5× (2026-07-06, overnight) |
| `MAP_BUILD_LOG.md` | 573 | Supabase (applied to the live project): | archive |  | Onboarding — community profile (name · interests · avatar → Supabase) — 2026-07-07 |
| `MAP_BUILD_LOG.md` | 578 | Backend: | archive |  | Onboarding — community profile (name · interests · avatar → Supabase) — 2026-07-07 |
| `MAP_BUILD_LOG.md` | 584 | Taxonomy: | archive |  | Onboarding — community profile (name · interests · avatar → Supabase) — 2026-07-07 |
| `MAP_BUILD_LOG.md` | 586 | Imagery (hybrid): | promote | `docs/rules/design.md` | Onboarding — community profile (name · interests · avatar → Supabase) — 2026-07-07 |
| `MAP_BUILD_LOG.md` | 594 | DEBUG launch args: | drop |  | Onboarding — community profile (name · interests · avatar → Supabase) — 2026-07-07 |
| `MAP_BUILD_LOG.md` | 596 | Verified in-sim (iPhone 17): | archive |  | Onboarding — community profile (name · interests · avatar → Supabase) — 2026-07-07 |
| `MAP_BUILD_LOG.md` | 611 | Detents (`metrics(H)`): | promote | `docs/rules/map.md` | Sheet detents — three stops + a live peek ("the sheet is the app") — 2026-07-13 |
| `MAP_BUILD_LOG.md` | 616 | Peek = one line (`peekLine`), not a list. | archive |  | Sheet detents — three stops + a live peek ("the sheet is the app") — 2026-07-13 |
| `MAP_BUILD_LOG.md` | 622 | Line ⇄ list cross-fade. | promote | `docs/rules/map.md` | Sheet detents — three stops + a live peek ("the sheet is the app") — 2026-07-13 |
| `MAP_BUILD_LOG.md` | 625 | Momentum snap (`snap`). | archive |  | Sheet detents — three stops + a live peek ("the sheet is the app") — 2026-07-13 |
| `MAP_BUILD_LOG.md` | 635 | Verified in-sim (iPhone 17): | archive |  | Sheet detents — three stops + a live peek ("the sheet is the app") — 2026-07-13 |
| `MAP_BUILD_LOG.md` | 664 | Time-of-day | drop |  | Living Basemap — time-of-day + weather + season (2026-07-13) |
| `MAP_BUILD_LOG.md` | 672 | What changes | drop |  | Living Basemap — time-of-day + weather + season (2026-07-13) |
| `MAP_BUILD_LOG.md` | 711 | Selection flips ONE feature-state | drop |  | Map pin hierarchy — recede the many, surface the few (2026-07-13) |
| `MAP_BUILD_LOG.md` | 720 | Labels rendered nothing. | promote | `docs/rules/map.md` | Map pin hierarchy — recede the many, surface the few (2026-07-13) |
| `MAP_BUILD_LOG.md` | 724 | Two warnings | archive |  | Map pin hierarchy — recede the many, surface the few (2026-07-13) |
| `MAP_BUILD_LOG.md` | 794 | Labels were mispositioned, not just "close." | archive |  | Living Basemap retired + pin badges redrawn to the Life360 reference (2026-07-13) |
| `MAP_BUILD_LOG.md` | 801 | Roads/road-labels were silently not recoloring. | promote | `docs/rules/map.md` | Living Basemap retired + pin badges redrawn to the Life360 reference (2026-07-13) |
| `MAP_BUILD_LOG.md` | 811 | `if live && !selected { PulseRing() }` had silently lost its `!selected` | archive |  | Living Basemap retired + pin badges redrawn to the Life360 reference (2026-07-13) |
| `MAP_BUILD_LOG.md` | 814 | Pin tap targets shrank from a guaranteed ≥44×44pt to a bare 28×28pt | promote | `docs/rules/map.md` | Living Basemap retired + pin badges redrawn to the Life360 reference (2026-07-13) |
| `MAP_BUILD_LOG.md` | 817 | `let labelInk = "#5E5D56"` | archive |  | Living Basemap retired + pin badges redrawn to the Life360 reference (2026-07-13) |
| `MAP_BUILD_LOG.md` | 821 | `PinDisplay.selected` was dead | archive |  | Living Basemap retired + pin badges redrawn to the Life360 reference (2026-07-13) |
| `MAP_BUILD_LOG.md` | 832 | Known, not fixed: | archive |  | Living Basemap retired + pin badges redrawn to the Life360 reference (2026-07-13) |
| `MAP_BUILD_LOG.md` | 852 | `MapModel.pinsExpanded` | promote | `docs/rules/map.md` | Pins shrink/expand with zoom — space-efficient labels (2026-07-14) |
| `MAP_BUILD_LOG.md` | 858 | Threshold reused from the old (deleted) pin-hierarchy's tuning | archive |  | Pins shrink/expand with zoom — space-efficient labels (2026-07-14) |
| `MAP_BUILD_LOG.md` | 860 | `MapPinBadge` gained an `expanded: Bool` | archive |  | Pins shrink/expand with zoom — space-efficient labels (2026-07-14) |
| `MAP_BUILD_LOG.md` | 883 | Data model + category map. | archive |  | Food & business POI markers — clustered Mapbox layer + Supabase seed (2026-07-15) |
| `MAP_BUILD_LOG.md` | 891 | Supabase `places` table | archive |  | Food & business POI markers — clustered Mapbox layer + Supabase seed (2026-07-15) |
| `MAP_BUILD_LOG.md` | 897 | The layer (`POILayer`). | drop |  | Food & business POI markers — clustered Mapbox layer + Supabase seed (2026-07-15) |
| `MAP_BUILD_LOG.md` | 905 | Tap → detail. | drop |  | Food & business POI markers — clustered Mapbox layer + Supabase seed (2026-07-15) |
| `MAP_BUILD_LOG.md` | 930 | `Theme/Motion.swift` (new) | promote | `docs/rules/design.md` | Map premium-feel pass — quantified motion/haptics/material spec (2026-07-15) |
| `MAP_BUILD_LOG.md` | 937 | `Support/Haptics.swift` | promote | `docs/rules/design.md` | Map premium-feel pass — quantified motion/haptics/material spec (2026-07-15) |
| `MAP_BUILD_LOG.md` | 941 | Marker select (`SJMapView`) | archive |  | Map premium-feel pass — quantified motion/haptics/material spec (2026-07-15) |
| `MAP_BUILD_LOG.md` | 947 | Camera "pin above the card" (§12.2, the headline) | promote | `docs/rules/map.md` | Map premium-feel pass — quantified motion/haptics/material spec (2026-07-15) |
| `MAP_BUILD_LOG.md` | 959 | POI layer | drop |  | Map premium-feel pass — quantified motion/haptics/material spec (2026-07-15) |
| `MAP_BUILD_LOG.md` | 964 | Reduce Motion | promote | `docs/rules/map.md` | Map premium-feel pass — quantified motion/haptics/material spec (2026-07-15) |
| `MAP_BUILD_LOG.md` | 1006 | `POICluster` | promote | `docs/rules/map.md` | 2026-07-18 — Map UI overhaul, Phase A: POI clustering snap → glide |
| `MAP_BUILD_LOG.md` | 1016 | `POIMarkers` | promote | `docs/rules/map.md` | 2026-07-18 — Map UI overhaul, Phase A: POI clustering snap → glide |
| `MAP_BUILD_LOG.md` | 1021 | `SJMapView+POIClustering` | archive |  | 2026-07-18 — Map UI overhaul, Phase A: POI clustering snap → glide |
| `MAP_BUILD_LOG.md` | 1043 | `RootView` | archive |  | 2026-07-19 — Map UI overhaul, Phase B: one continuous bottom glass |
| `MAP_BUILD_LOG.md` | 1049 | `MapSheet` | archive |  | 2026-07-19 — Map UI overhaul, Phase B: one continuous bottom glass |
| `MAP_BUILD_LOG.md` | 1053 | `SJMapView` | archive |  | 2026-07-19 — Map UI overhaul, Phase B: one continuous bottom glass |
| `MAP_BUILD_LOG.md` | 1065 | Basemap green | archive |  | 2026-07-19 — Map UI overhaul, Phase C: colour + marker polish |
| `MAP_BUILD_LOG.md` | 1070 | Cluster bubbles | promote | `docs/rules/swift-traps.md` | 2026-07-19 — Map UI overhaul, Phase C: colour + marker polish |
| `MAP_BUILD_LOG.md` | 1075 | Dominant category | archive |  | 2026-07-19 — Map UI overhaul, Phase C: colour + marker polish |
| `MAP_BUILD_LOG.md` | 1079 | Size-by-count | promote | `docs/rules/map.md` | 2026-07-19 — Map UI overhaul, Phase C: colour + marker polish |
| `MAP_BUILD_LOG.md` | 1085 | Town-label occlusion | promote | `docs/rules/map.md` | 2026-07-19 — Map UI overhaul, Phase C: colour + marker polish |
| `MAP_BUILD_LOG.md` | 1094 | POI label de-confliction | promote | `docs/rules/map.md` | 2026-07-19 — Map UI overhaul, Phase C: colour + marker polish |
| `MAP_BUILD_LOG.md` | 1126 | Intermittent unstyled basemap. | promote | `docs/rules/map.md` | Final pass (2026-07-19) — fresh Design Director + fresh code audit |
| `MAP_BUILD_LOG.md` | 1178 | De-confliction now reserves the app's own floating chrome | promote | `docs/rules/map.md` | Post-final-pass fixes (2026-07-19) |
| `MAP_BUILD_LOG.md` | 1184 | Cluster fill no longer cool. | archive |  | Post-final-pass fixes (2026-07-19) |
| `MAP_BUILD_LOG.md` | 1190 | Town label at the default zoom | archive |  | Post-final-pass fixes (2026-07-19) |
| `MAP_BUILD_LOG.md` | 1193 | A civic REST DOT can still graze the town name at z12. | archive |  | Post-final-pass fixes (2026-07-19) |
| `MAP_BUILD_LOG.md` | 1198 | A POI badge occludes the Sacred Heart Chapel civic landmark at z15/z16 | archive |  | Post-final-pass fixes (2026-07-19) |
| `MAP_BUILD_LOG.md` | 1202 | Sheet glass transmits green / bleaches warm backdrops | archive |  | Post-final-pass fixes (2026-07-19) |
| `MAP_BUILD_LOG.md` | 1208 | Civic landmarks now actually win z-order. | promote | `docs/rules/map.md` | The last three open items — fixed (2026-07-19) |
| `MAP_BUILD_LOG.md` | 1214 | One marker family. | archive |  | The last three open items — fixed (2026-07-19) |
| `MAP_BUILD_LOG.md` | 1222 | Sheet glass no longer prints park shapes. | promote | `docs/rules/map.md` | The last three open items — fixed (2026-07-19) |
| `MAP_BUILD_LOG.md` | 1234 | One clustering input set below `pinExpandZoom`. | promote | `docs/rules/map.md` | 2026-07-23 — Issue 1: civic landmarks join clusters; cluster-first labels |
| `MAP_BUILD_LOG.md` | 1240 | Selection and live state. | promote | `docs/rules/map.md` | 2026-07-23 — Issue 1: civic landmarks join clusters; cluster-first labels |
| `MAP_BUILD_LOG.md` | 1244 | Cluster-first collision geometry. | promote | `docs/rules/map.md` | 2026-07-23 — Issue 1: civic landmarks join clusters; cluster-first labels |
| `MAP_BUILD_LOG.md` | 1250 | Continuous merge/split. | promote | `docs/rules/map.md` | 2026-07-23 — Issue 1: civic landmarks join clusters; cluster-first labels |
| `MAP_BUILD_LOG.md` | 1294 | Backend: | archive |  | 2026-07-23 — Brand logos on POI pins (`feat/poi-logos`) |
| `MAP_BUILD_LOG.md` | 1302 | Curation pipeline: | archive |  | 2026-07-23 — Brand logos on POI pins (`feat/poi-logos`) |
| `MAP_BUILD_LOG.md` | 1410 | Browse state preserved. | archive |  | Follow-up fixes (post-review, 2026-07-23) |
| `MAP_BUILD_LOG.md` | 1414 | Camera reserve content-driven. | promote | `docs/rules/map.md` | Follow-up fixes (post-review, 2026-07-23) |
| `MAP_BUILD_LOG.md` | 1418 | Degenerate distance suppressed. | archive |  | Follow-up fixes (post-review, 2026-07-23) |
| `MAP_BUILD_LOG.md` | 1421 | X-close animated | archive |  | Follow-up fixes (post-review, 2026-07-23) |
| `MAP_BUILD_LOG.md` | 1499 | `TownRainPhysics` | promote | `docs/rules/architecture.md` | Town rain — the town's brand marks drop when you press "Saint Joseph" |
| `MAP_BUILD_LOG.md` | 1501 | `TownRainField` | promote | `docs/rules/map.md` | Town rain — the town's brand marks drop when you press "Saint Joseph" |
| `MAP_BUILD_LOG.md` | 1506 | `TownRainRoster` | archive |  | Town rain — the town's brand marks drop when you press "Saint Joseph" |
| `MAP_BUILD_LOG.md` | 1545 | A short burst per press | archive |  | Town rain, revised — one ball, a closed field, and a bubble on the press |
| `MAP_BUILD_LOG.md` | 1549 | The field is closed. | archive |  | Town rain, revised — one ball, a closed field, and a bubble on the press |
| `MAP_BUILD_LOG.md` | 1553 | The floor is the sheet's live top edge. | promote | `docs/rules/map.md` | Town rain, revised — one ball, a closed field, and a bubble on the press |
| `MAP_BUILD_LOG.md` | 1558 | Drift is now two-directional. | archive |  | Town rain, revised — one ball, a closed field, and a bubble on the press |
| `MAP_BUILD_LOG.md` | 1562 | `townPillBubble` | archive |  | Town rain, revised — one ball, a closed field, and a bubble on the press |
| `MAP_BUILD_LOG.md` | 1583 | One mark per press, but they accumulate. | archive |  | Town rain, revised — one ball, a closed field, and a bubble on the press |
| `MAP_BUILD_LOG.md` | 1590 | Local businesses only. | promote | `docs/rules/map.md` | Town rain, revised — one ball, a closed field, and a bubble on the press |
| `MAP_BUILD_LOG.md` | 1633 | `MonoMarkerPalette.swift` | promote | `docs/rules/map.md` | 2026-08-13 — Map polish Phase 1: cluster bubbles go ink (plan 2026-08-13-map-tab-ui-polish) |
| `MAP_BUILD_LOG.md` | 1641 | `POIMarkers.swift` | archive |  | 2026-08-13 — Map polish Phase 1: cluster bubbles go ink (plan 2026-08-13-map-tab-ui-polish) |
| `MAP_BUILD_LOG.md` | 1678 | `SJMapView.swift` | archive |  | 2026-08-13 — Map polish Phase 2: search replaces the top-right "+"; "+" relocates (plan 2026-08-13-map-tab-ui… |
| `MAP_BUILD_LOG.md` | 1689 | `MapSearch.swift` | promote | `docs/rules/swift-traps.md` | 2026-08-13 — Map polish Phase 2: search replaces the top-right "+"; "+" relocates (plan 2026-08-13-map-tab-ui… |
| `MAP_BUILD_LOG.md` | 1698 | `UserLocation.swift` | archive |  | 2026-08-13 — Map polish Phase 2: search replaces the top-right "+"; "+" relocates (plan 2026-08-13-map-tab-ui… |
| `MAP_BUILD_LOG.md` | 1703 | `SJMapView+POIClustering.swift` | archive |  | 2026-08-13 — Map polish Phase 2: search replaces the top-right "+"; "+" relocates (plan 2026-08-13-map-tab-ui… |
| `MAP_BUILD_LOG.md` | 1707 | `App/RootView.swift` | promote | `docs/rules/swift-traps.md` | 2026-08-13 — Map polish Phase 2: search replaces the top-right "+"; "+" relocates (plan 2026-08-13-map-tab-ui… |
| `MAP_BUILD_LOG.md` | 1713 | DEBUG flags | archive |  | 2026-08-13 — Map polish Phase 2: search replaces the top-right "+"; "+" relocates (plan 2026-08-13-map-tab-ui… |
| `MAP_BUILD_LOG.md` | 1759 | (a) metadata pills | archive |  | 2026-08-13 — Map polish Phase 3: the Flighty-anatomy pin detail sheet (glass-bar morph retired) |
| `MAP_BUILD_LOG.md` | 1770 | (e) status card | archive |  | 2026-08-13 — Map polish Phase 3: the Flighty-anatomy pin detail sheet (glass-bar morph retired) |
| `MAP_BUILD_LOG.md` | 1781 | (f) "View full details ›" | archive |  | 2026-08-13 — Map polish Phase 3: the Flighty-anatomy pin detail sheet (glass-bar morph retired) |
| `MAP_BUILD_LOG.md` | 1785 | (g) action bar | archive |  | 2026-08-13 — Map polish Phase 3: the Flighty-anatomy pin detail sheet (glass-bar morph retired) |
| `MAP_BUILD_LOG.md` | 2148 | `landuse` filter widened | archive |  | 2026-08-14 — Map polish round 2, Phase B: the basemap goes colorful (Jesse's Subway reference) |
| `MAP_BUILD_LOG.md` | 2153 | `landuse` fill-color is a per-class `match` | archive |  | 2026-08-14 — Map polish round 2, Phase B: the basemap goes colorful (Jesse's Subway reference) |
| `MAP_BUILD_LOG.md` | 2160 | `national-park` | archive |  | 2026-08-14 — Map polish round 2, Phase B: the basemap goes colorful (Jesse's Subway reference) |
| `MAP_BUILD_LOG.md` | 2168 | Unchanged | archive |  | 2026-08-14 — Map polish round 2, Phase B: the basemap goes colorful (Jesse's Subway reference) |
| `MAP_BUILD_LOG.md` | 2222 | `RootView.swift` | archive |  | 2026-08-14 — Map polish round 2, Phase C: the tab bar attaches identically on all four tabs |
| `MAP_BUILD_LOG.md` | 2227 | `MapSheet.swift` | archive |  | 2026-08-14 — Map polish round 2, Phase C: the tab bar attaches identically on all four tabs |
| `MAP_BUILD_LOG.md` | 2332 | Full-details photo box renders blank | promote | `docs/rules/design.md` | 2026-08-14 — Map polish round 2, Phase D: compact quiet card + flaw-hunt sweep |
| `MAP_BUILD_LOG.md` | 2338 | Civic full details can render near-empty | promote | ? | 2026-08-14 — Map polish round 2, Phase D: compact quiet card + flaw-hunt sweep |
| `REVIEW.md` | 50 | CONFIRMED | archive |  | [1] A REST-layer 401 (server-revoked/rejected token) never invalidates AuthStore's session or forces re-login |
| `REVIEW.md` | 56 | CONFIRMED | archive |  | [2] Stale join()/receiveLoop() Task from a cancelled connection attempt is never cancellation-checked, so a b… |
| `REVIEW.md` | 64 | CONFIRMED | archive |  | [3] Reminders.parseTime silently mis-schedules "Midnight"-labeled events (falls back to noon) |
| `REVIEW.md` | 70 | CONFIRMED | archive |  | [4] confidentPhoto cache key omits coordinate — shared venue-name strings leak a wrong-venue confidence result |
| `REVIEW.md` | 76 | CONFIRMED | drop |  | [5] CalendarExport.addDay swallows per-event save failures and still reports success once one event lands |
| `REVIEW.md` | 82 | CONFIRMED | archive |  | [6] GooglePlacesService caches have no in-flight de-duplication, undermining the file's own cost-discipline goal |
| `REVIEW.md` | 88 | CONFIRMED | archive |  | [7] MapSheet stays collapsed at peek height when a spot is preselected at mount |
| `REVIEW.md` | 94 | CONFIRMED | archive |  | [8] Live-glow / 'Now' badges go stale because nothing drives a re-render off wall-clock time |
| `REVIEW.md` | 100 | CONFIRMED | drop |  | [9] Optimistic RSVP can be silently reverted by a concurrent load() |
| `REVIEW.md` | 106 | CONFIRMED | drop |  | [10] RollCallSection and QuestSection show a false empty/zero state on every Home-tab revisit, unlike the Tod… |
| `REVIEW.md` | 112 | CONFIRMED | drop |  | [11] Explore feed silently rebrands network failures as "nothing here yet" |
| `REVIEW.md` | 118 | CONFIRMED | drop |  | [12] Club join/leave has no in-flight guard — out-of-order requests can leave local state opposite the server |
| `REVIEW.md` | 124 | CONFIRMED | promote | `docs/rules/swift-traps.md` | [13] Explore feed uses a plain VStack (not lazy) so every card — and every trail's geocode network call — ren… |
| `REVIEW.md` | 130 | CONFIRMED | drop |  | [14] Onboarding/profile hydration is device-session-scoped, not per-user — a second account on the same devic… |
| `REVIEW.md` | 136 | CONFIRMED | archive |  | [15] Weekly-repeat event posting has no rollback or idempotency — a mid-loop failure leaves partial events li… |
| `REVIEW.md` | 142 | CONFIRMED | promote | `docs/rules/swift-traps.md` | [16] VenuePhoto shows a stale (wrong-venue) photo when its inputs change under a reused view identity |
| `DECISIONS.md` | 180 | Dark mode. | drop |  | 5. Deferred / out of scope for this rebrand |
| `DECISIONS.md` | 182 | A single accent colour — IMPLEMENTED. | archive |  | 5. Deferred / out of scope for this rebrand |
| `DECISIONS.md` | 193 | App Store distribution work. | archive |  | 5. Deferred / out of scope for this rebrand |
| `DECISIONS.md` | 197 | App icon pixels. | archive |  | 5. Deferred / out of scope for this rebrand |
| `DECISIONS.md` | 252 | Superseded test note: | archive |  | 5. Deferred / out of scope for this rebrand |
| `DECISIONS.md` | 308 | Status-card tint is one token — RESOLVED 2026-08-14: the BP mark's orange. | archive |  | 6. Decided 2026-08-13 — map pin-detail sheet (map polish Phase 3) |
| `DECISIONS.md` | 318 | The sheet's action bar is a PILL — a deliberate brand exception. | archive |  | 6. Decided 2026-08-13 — map pin-detail sheet (map polish Phase 3) |
| `DECISIONS.md` | 355 | The plus is ink, not white. | archive |  | The two places the reference could not be followed |
| `DECISIONS.md` | 359 | The bell is a bare mark, not a disc. | archive |  | The two places the reference could not be followed |
| `DECISIONS.md` | 366 | Create is not a fifth `Tab` case. | archive |  | Structural calls |
| `DECISIONS.md` | 369 | The tab bar's height did not change. | archive |  | Structural calls |
| `DECISIONS.md` | 372 | Search and the bell open a reserved screen, not a dead tap. | promote | `docs/rules/architecture.md` | Structural calls |
| `DECISIONS.md` | 379 | Glyph weight. | archive |  | Left open, deliberately |
| `DECISIONS.md` | 383 | The map disc in Dark Mode | promote | `docs/rules/design.md` | Left open, deliberately |
