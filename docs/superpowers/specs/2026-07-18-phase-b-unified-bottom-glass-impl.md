# Phase B — Unified Bottom Glass: Implementation Spec

**Branch/worktree:** `feat/map-poi-markers` in `~/Documents/hygge-poi`. Build clean (0 warnings) + verified in simulator.

## Goal
Merge the map's `MapSheet` and the global `HyggeTabBar` into ONE continuous Liquid Glass piece: the tab bar IS the collapsed state, and pulling up grows the SAME glass upward into the sheet — same width/insets/material/corner-radius. Plus: relocate/auto-hide the ?/locate buttons so they never collide, remove clipped slivers, and rewrite the empty-state copy.

## Grounded current state
- `HyggeTabBar` (`Hygge/App/RootView.swift:394`): a floating Liquid Glass pill — `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))`, `.padding(.horizontal, 20)`, `.padding(.bottom, 4)`; 4 tab buttons, coral `matchedGeometryEffect` pill. Placed in `MainTabsView` body (`RootView.swift:235`) as the top ZStack sibling over the tab content.
- `MapSheet` (`Hygge/Features/Map/MapSheet.swift`): a HAND-ROLLED draggable sheet (GeometryReader + `DragGesture` + 3 detents `peek`120 / `medium`~50% / `full`; momentum snap; VoiceOver adjustable). Background = OPAQUE `Hue.surface` + `mapSheetShadow()`; FULL-WIDTH (edge-to-edge); floats `tabBarClearance = 56`pt above the bottom. NOT glass, NOT inset. Lives inside `SJMapView`'s ZStack (`SJMapView.swift:251`).
- So sheet (in `SJMapView`) + tab bar (in `MainTabsView`) are SEPARATE view trees, stacked → the "two boxes."
- Map floating ?/locate buttons: `SJMapView.floatingControls`, padded `tabBarClearance + peekHeight + 12` above the bottom (just above the sheet peek).

## KEY DECISION — do NOT use `presentationDetents`
The overhaul prompt suggested `presentationDetents`. Rejected: a native detent sheet renders in a SEPARATE presentation layer, which cannot share a `GlassEffectContainer` with the tab bar → it could never morph into one continuous shape. Instead **keep the existing in-tree custom draggable sheet** (its detent/drag/snap logic is good and in the same view tree) and co-locate it with the tab bar in ONE `GlassEffectContainer`, using `glassEffect` + `glassEffectID` (shared `@Namespace`) so they read/morph as a single shape.

## Approach
1. **Co-locate the sheet + tab bar for the MAP TAB in one `GlassEffectContainer`.** The map's bottom sheet glass should grow down INTO / flush WITH the tab bar so they morph as one shape. Concretely: on the map tab, present the sheet flush atop the tab bar within a shared container (lift the sheet's glass presentation to sit with the tab bar; the sheet's content/state/callbacks stay owned by the map — `SJMapView`/`MapModel`). Keep the plain `HyggeTabBar` UNCHANGED for the other 3 tabs.
2. **Restyle the sheet glass:** replace the opaque `Hue.surface` background with `.glassEffect(.regular, in: <UnevenRoundedRectangle, top corners continuous>)` — the SAME material + corner radius as the tab bar. Match the tab bar's side insets (`.padding(.horizontal, 20)`) — the sheet is NO LONGER edge-to-edge.
3. **Continuous shape:** collapsed = the tab bar with a slim drag handle / peek lip above it (one shape, no 56pt gap — the sheet's bottom MEETS the tab bar). Expanded = the glass grows upward via the existing detents; material + radius stay continuous so it reads as the tab bar STRETCHING UP, not a second panel appearing.
4. **?/locate buttons:** when the sheet grows past peek, fade/slide them out (or move above the sheet's top edge) so they NEVER collide as it expands. Re-anchor their resting spot to the new unified bottom.
5. **Remove clipped orphan slivers** (the partial circle bottom-left + blue sliver bottom-right that peek from behind the tab bar) — fix the layout overflow so nothing pokes out.
6. **Empty-state copy** — must NEVER say "nothing on the map" while pins are visible (the map ALWAYS shows permanent venues; the sheet is about TODAY's live activity). Update the peek line + list empty state: peek primary when quiet → "St. Joe today"; empty list → "No events or activity posted yet today — but all your local spots are on the map. Tap a pin to explore." (Fit the existing `peekPrimary`/`peekSecondary`/`emptyState` structure; keep it warm/neighborly per the app voice.)

## Preserve (do not regress)
All sheet functionality: 3 detents + drag + momentum snap + VoiceOver `accessibilityAdjustableAction`; Today⇄Places toggle; spot detail (blurb, happenings, save, Directions); realtime; `SavedStore`; every debug flag (`-map-detent`, `-map-sheet`, `-map-open`, …). The other 3 tabs' tab bar must look/behave EXACTLY as before. Target iOS 26.5 — `.glassEffect`/`GlassEffectContainer`/`glassEffectID` are already available (the tab bar uses them); no availability shim needed for those.

## Verify (rest states — settle before capture)
Build 0 warnings. Screenshot the map bottom at collapsed(peek) / medium / full — confirm ONE continuous glass piece (tab bar + sheet: same width, insets, material, radius; no gap; not a second panel), ?/locate never colliding, no clipped slivers, and the new copy. Screenshot a NON-map tab to confirm its tab bar is UNCHANGED. Fresh QA + Design Director review before the gate.

## Done
One continuous glass bottom collapsed AND expanded; same width/insets/material as the tab bar; no clipped bits; buttons never collide; corrected copy; other tabs unaffected; build clean. Then STOP for Jesse with before/after.
