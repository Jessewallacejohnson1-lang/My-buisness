# St. Joe Map UI Overhaul — Design Spec

**Date:** 2026-07-18
**Branch / worktree:** `feat/map-poi-markers` in `~/Documents/hygge-poi`
**Owner:** Jesse (non-technical) — pause at every phase gate with before/after screenshots + plain summary.

## Quality bar
Apple Maps / Airbnb-level premium: no snapping, no orphaned pins, no visual clutter, one continuous bottom glass, greens matching Apple Maps.

## Process
Lead engineer (Opus) orchestrates. Each phase runs a **design-match loop**: build → screenshot the simulator → a *fresh* QA agent + a *fresh* Design Director agent grade against this spec → fix → rebuild → repeat until pass → **STOP for Jesse**. The agent that writes code never reviews its own work. Phases are strictly gated: A → stop → B → stop → C → stop → final pass. Commit each phase and record it in `MAP_BUILD_LOG.md`.

**References:** self-sourced — capture "before" from the simulator, color-match green against a real Apple Maps light-mode screenshot.

## Confirmed current state (grounding)
- Two marker systems: six civic landmarks are already SwiftUI `MapViewAnnotation`s (premium); the 52 food/business POIs are Mapbox built-in GeoJSON clustering (`POILayer.swift`, `src.cluster = true`, `clusterRadius = 44`, `clusterMaxZoom = 13`) → `CircleLayer`s that redraw instantly. This IS the snap; the fixed radius strands the gold/gray/green pins.
- Current basemap green `#D6E8C4` (sage); water `#9EDAF3`; land `#F4F3EC` (`BasemapPalette.swift`).
- iOS deployment target 26.5 → Liquid Glass (`GlassEffectContainer`/`glassEffectID`) is first-class, not a fallback.
- Bottom = `MapSheet` (peek/medium/full detents) stacked above the global `HyggeTabBar` = the "two boxes" problem.

## Phase A — Animated clustering
- Replace the POI circle-layer cluster rendering with **SwiftUI view annotations** for every POI and cluster bubble, animated with springs (~0.35–0.5s, gentle overshoot).
- **Engine:** let Mapbox compute clusters (query children/expansion-zoom from the clustered source) and animate the drawing in SwiftUI — satisfies "known parent-child so nothing is stranded" with lower risk than a full Supercluster port. **Spike first** to prove the feel before the polished build.
- Merge (zoom out): children fly to parent centroid, scale down + fade; bubble scales up. Split: exact reverse. Count animates (roll/cross-fade), never a hard cut.
- Straggler fix: membership from parent-child data; verify zero orphans at multiple zooms (re-check gold/gray/green).
- Occlusion fix: town/street labels get priority; markers dodge, never cover, "St. Joseph".
- **Scope:** the six civic landmarks stay always-on-top and do NOT dissolve into clusters. Only the 52 POIs cluster/animate.

## Phase B — One continuous bottom glass
- Merge `MapSheet` collapsed state INTO the tab bar as one Liquid Glass shape (`GlassEffectContainer` + `glassEffectID`), same width/insets/material, growing upward via `presentationDetents`.
- Collapsed = tab bar (optional slim handle). Expanded = grows upward, material + radius continuous (tab bar stretching up, not a second panel).
- Relocate/auto-hide the "?" and locate buttons so they never collide as the sheet expands.
- Remove clipped orphan slivers; fix layout overflow.
- Rewrite empty-state copy — never "nothing on the map" while pins show. Draft: title "St. Joe today"; body "No events or activity posted yet today — but all your local spots are on the map. Tap a pin to explore."

## Phase C — Color + marker polish
- Brighten green `#D6E8C4` → ≈`#B8E6A0`, tuned live against a real Apple Maps screenshot (stay in the pale Scandinavian palette; nudge, don't go neon). Water/land already on target.
- Restyle cluster bubbles: light glass + subtle depth (soft shadow + translucent fill) instead of flat charcoal; add category hinting (thin colored ring / dominant-category tint).
- Size scaling by count (a "2" clearly smaller than a "42"); number legible at every size.
- Unify rest dots, awake glyph markers, cluster bubbles into one family tied by coral `#FF6B57` + category colors; awake pins keep Apple-style glyph markers.

## Done criteria
Zero orphaned pins; nothing snaps; one continuous glass bottom with no clipped bits; no cluster covers the town label; greens match Apple Maps — verified at multiple zooms with the bottom piece collapsed and expanded.
