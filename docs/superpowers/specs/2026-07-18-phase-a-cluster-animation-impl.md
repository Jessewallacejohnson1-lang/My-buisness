# Phase A — Animated POI Clustering: Implementation Spec

**Branch/worktree:** `feat/map-poi-markers` in `~/Documents/hygge-poi`. Builds clean (0 warnings) + verified in simulator.

## Goal
Replace the snapping Mapbox built-in GeoJSON clustering of the 52 food/business POIs with **SwiftUI view-annotation markers + client-side clustering**, so pins **glide** (spring) when merging into / splitting out of clusters, with **zero stragglers** and animated cluster counts. Civic pins and everything else stay as-is.

## Proven mechanism (from the spike — `Hygge/Features/Map/_SpikeClusterView.swift`)
- **A `MapViewAnnotation`'s `coordinate` is NOT SwiftUI-animatable.** Animate position with a screen-space `.offset` instead: anchor each marker at its TRUE coordinate, and offset the inner view toward the cluster centroid's projected screen point (`proxy.map.point(for: centroid)` minus `point(for: trueCoord)`). Scale + opacity animate alongside.
- **Isolation is mandatory.** The Mapbox `Map`'s `onCameraChanged`/`onStyleLoaded` write sibling `@State`, and any non-animated write **cancels an in-flight animation**. So each marker's animating state MUST live in its own leaf subview (the same reason `PulseRing` in `SJMapView.swift` isolates its `@State`). Do NOT drive marker animation from `@State` on the map container view.
- Spring: `~response 0.42, dampingFraction 0.72` (lively, gentle overshoot, ~0.35–0.5s). Reduce Motion → instant/opacity-only.

## Clustering engine (client-side, deterministic)
- 52 POIs is tiny — no need to port full Supercluster. Implement a small **greedy distance clusterer** in screen space at the current zoom: project all POIs to screen points, greedily group any within a **cluster radius (~44pt, tunable)** into a cluster at their centroid. Membership by radius ⇒ **every in-range pin joins ⇒ no stragglers by construction** (this is the straggler fix).
- Recompute on **zoom-step changes / camera idle**, NOT every camera frame (avoid re-clustering mid-pinch — mirror how Mapbox only reclusters at zoom steps). Between recomputes the layout is stable; on recompute, animate the transition.
- Output per recompute: a list of render nodes — each is either a **single POI** (id, coord) or a **cluster** (stable id, centroid, count, member POI ids). Provide the mapping so each POI knows its current cluster centroid (target to fly to) — this drives merge/split.

## Rendering (in `SJMapView.mapLayer`, mirroring the civic `ForEvery`)
- Keep ALL 52 POIs mounted as `MapViewAnnotation`s anchored at their true coords (52 is well under the ~100 view-annotation budget). Each POI marker view:
  - **Clustered:** offsets toward its cluster centroid (screen vector), fades opacity → ~0, scales down — animated (spring, isolated leaf state).
  - **Unclustered:** offset 0, full opacity/scale.
  - Marker visual stays roughly current for Phase A (amber = food, indigo = business, white glyph; small rest dot below the awake zoom → glyph marker + de-conflicted label at/above it). **Final marker/bubble polish is Phase C — do not gold-plate here.**
- One **cluster bubble** `MapViewAnnotation` per cluster at its centroid: scales up + fades in as members merge; shows the count. **Count animates** on change (cross-fade or roll — never a hard cut). Bubble styling stays close to current for Phase A (Phase C makes it glass + category-tinted + size-by-count).
- **Retire** `POILayer`'s POI dot/glyph/cluster/count style layers + its `TapInteraction(.layer(...))` hooks (they're the snapping renderer). Keep POI *data* loading (`model.pois`) intact.

## Preserve exactly (do not regress)
- The six **civic `MapViewAnnotation` pins** (`ForEvery(filteredSpots)` + `MapPinBadge`) — unchanged, always on top, never clustered.
- **Taps:** tapping a POI opens `POIDetailSheet` (was `selectPOI(id:)` via layer tap → now the marker view's `onTapGesture`); tapping a cluster **zooms in to split it** (was `zoomToCluster`). Tapping empty map still `closeCard()`.
- Basemap recolor, chrome (filter/town pill/compose), `MapSheet`, realtime pipeline, `SpotFilter`, debug launch flags.
- The `SpotFilter` must also filter POIs if it did before (check current behavior).

## Occlusion (pragmatic — flag at gate)
View annotations render above the whole basemap incl. labels; true collision-dodging vs. style labels isn't natively supported. Goal for Phase A: eliminate the *egregious* case (a big opaque disc smothering the "Saint Joseph" / street labels) via smaller, lighter bubbles and by not letting the town label sit under a fat opaque centroid. Perfect label-dodging is a Phase C styling lever (translucent glass bubbles) — note residual occlusion at the gate rather than over-engineering here.

## Verification (motion is the point)
- Build 0 warnings. Static screenshots at z11/z12/z13/z14/z15: confirm **no orphan dot** sits beside/under any cluster (re-check the gold/gray/green pins), civic pins intact, taps work.
- Motion: add a DEBUG `-map-autozoom` flag that eases the camera zoom (e.g. 15→11→15 over ~6s) so a full merge+split can be frame-sampled; capture ~10 screenshots across it and confirm pins glide (intermediate positions), counts don't hard-cut, nothing snaps.
- Fresh QA + Design Director review the frames against this spec before the phase gate.

## Done (Phase A gate)
No orphaned pins at any zoom; merge/split glides (no snap); count animates; civic pins + taps + sheet all intact; egregious label occlusion gone. Remove the spike (`_SpikeClusterView.swift` + the RootView branch) before committing. Commit + append `MAP_BUILD_LOG.md`. Then STOP for Jesse with before/after.
