//
//  SJMapView.swift
//  Hygge — Mapbox map of Saint Joseph, Minnesota.
//
//  Life360-style layout: floating top chrome (filter · town pill · compose), one
//  static warm basemap (BasemapPalette — no time/season/weather modulation), a
//  persistent draggable bottom sheet (MapSheet), and coral reserved for live
//  indicators + primary/tappable elements.
//
//  Pins: every curated spot always shows a small badge — a solid category-color
//  circle (green parks/trails, honey downtown/coffee/fitness, sky campus) with a
//  white glyph, plus a halo'd name label beside it — matching the Life360/Mobbin
//  reference (small icon + text, never a big bulky badge). `PinDisplay` still
//  resolves state (selected > live > saved > rest); live/saved/selected layer an
//  accent on top of the same small badge rather than swapping to a different
//  visual language. Pure SwiftUI overlay (`MapViewAnnotation`) — at six curated
//  spots there's no need for a separate Mapbox collision layer.
//
//  Live pipeline: MapModel owns a Realtime subscription on club_events. A new /
//  ended / deleted happening re-syncs the map with no manual refresh — the pin
//  lights or goes quiet on its own. Spots come from the curated MapSpots catalog;
//  liveness + "today's happenings" come only from real events. One-line rebrand:
//  change LIVE_COLOR below.
//

import SwiftUI
import UIKit
import MapboxMaps

// MARK: - Constants

private let MAP_STYLE_URL = "mapbox://styles/mapbox/light-v11"
private let LIVE_COLOR    = Hue.accent   // warm coral — change here to rebrand

// Basemap cartography lives in BasemapPalette (Features/Map/BasemapPalette.swift) —
// one static palette, pixel-matched to the Life360 reference. No modulation.

// MARK: - Spot filter (top-left chip)

/// The map's category chip. Groups the curated categories into the few buckets a
/// neighbor actually thinks in; `.all` shows every pin.
enum SpotFilter: CaseIterable, Hashable {
    case all, downtown, outdoors, campus

    var title: String {
        switch self {
        case .all:      return "Everything"
        case .downtown: return "Downtown"
        case .outdoors: return "Parks & trails"
        case .campus:   return "Campus"
        }
    }

    func matches(_ c: SpotCategory) -> Bool {
        switch self {
        case .all:      return true
        case .downtown: return c == .downtown || c == .coffee
        case .outdoors: return c == .park || c == .trail
        case .campus:   return c == .college || c == .chapel
        }
    }
}

// MARK: - Main view

struct SJMapView: View {
    /// Non-admins tap the top-right "+" into the global composer (admins get the
    /// map's own QuickAddSheet). Injected by MainTabsView, like HomeView.
    var onCompose: (() -> Void)? = nil

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase
    // Not `private`: the POI-clustering + autozoom methods in SJMapView+POIClustering.swift
    // read `model` and drive `viewport`, and Swift `private` is file-scoped.
    @StateObject var model = MapModel()
    /// Device-local saved set (shared with Explore). Observed so saving a place from
    /// the sheet updates its pin to the Saved state live.
    @ObservedObject private var saved = SavedStore.shared

    @State var viewport: Viewport = .camera(
        center: SJMapView.debugInitialCenter() ?? MapSpots.center,
        zoom: SJMapView.debugInitialZoom() ?? 13.5,
        bearing: 0,
        pitch: 0
    )

    /// DEBUG-only: `-map-center <lat>,<lon>` starts the camera elsewhere so the
    /// town pill's reverse-geocoding can be screenshotted over another city. No
    /// effect in release / without the flag.
    private static func debugInitialCenter() -> CLLocationCoordinate2D? {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-map-center"), i + 1 < a.count {
            let parts = a[i + 1].split(separator: ",")
            if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
        #endif
        return nil
    }

    /// DEBUG-only: `-map-zoom <z>` starts the camera at a given zoom for
    /// screenshotting the basemap/pins at a consistent framing. No effect in
    /// release / without the flag.
    private static func debugInitialZoom() -> Double? {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-map-zoom"), i + 1 < a.count { return Double(a[i + 1]) }
        #endif
        return nil
    }

    @State private var selectedSpot: Spot? = SJMapView.debugSelectedSpot()
    /// A tapped food/business POI marker (mutually exclusive with `selectedSpot`).
    @State private var selectedPOI: POI?
    @State private var filter: SpotFilter = .all

    // MARK: Client-side POI clustering (replaces the retired POILayer)
    //
    // The 52 POIs are all mounted as view annotations (POIClusterMarker); this state is
    // the recomputed layout that drives their merge/split glide. Recomputed on zoom-step
    // changes + at camera idle (never every frame — mirrors how Mapbox only reclusters at
    // zoom steps), off the LIVE projection via proxy.map.point(for:).

    // These drive the clusterer that lives in SJMapView+POIClustering.swift, so they are
    // not `private` (Swift `private` is file-scoped and the extension is another file).

    /// POI id → where it should sit (its cluster seed, or itself when solo). Every leaf
    /// reads its own entry; a flip animates that leaf's spring.
    @State var poiAssignments: [String: POIAssignment] = [:]
    /// The cluster bubbles to draw, including ones currently fading out (a split keeps a
    /// dissolving bubble mounted a beat so it fades rather than pops).
    @State var renderedClusters: [POIClusterRender] = []
    /// POI ids whose name label has room to draw at the current layout (see
    /// `POICluster.labelledPOIs`). Everything else shows its badge but withholds its text,
    /// so a dense block reads as a clean map instead of a pile of overlapping names.
    @State var labelledPOIs: Set<String> = []
    /// Last zoom we reclustered at — so we only recompute on a real zoom step, not on
    /// every camera frame.
    @State var lastClusterZoom: Double = .nan
    /// Debounced "camera settled" recompute (cancelled + rescheduled while moving).
    @State var clusterSettle: DispatchWorkItem?
    #if DEBUG
    /// Guards the `-map-autozoom` demo so it fires only once per launch.
    @State var autozoomStarted = false
    #endif

    /// Recompute once the zoom has moved at least this much since the last cluster pass —
    /// small enough that a continuous zoom glides through intermediate cluster states, and
    /// tight enough that seed screen-distances can't drift far enough between recomputes for
    /// two bubbles to converge and overlap mid-zoom (0.1 zoom ⇒ ≤7% distance drift). The
    /// per-zoom grouping distance itself lives in POICluster.clusterRadius(zoom:).
    static let clusterZoomStep: Double = 0.1

    /// Annotation draw order. Mapbox draws view annotations by `priority`, NOT by declaration
    /// order — which is why the six civic landmarks, declared last, were still being covered
    /// by POI badges. Higher wins. Civic landmarks are the map's anchors and sit on top of
    /// everything; a cluster bubble outranks the individual pins it stands for.
    static let poiPriority = 0
    static let clusterPriority = 10
    static let civicPriority = 20

    /// DEBUG-only: `-map-open <spotid>` preselects a spot so its detail card can be
    /// screenshotted headlessly. No effect in release / without the flag.
    private static func debugSelectedSpot() -> Spot? {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-map-open"), i + 1 < a.count {
            return MapSpots.all.first { $0.id == a[i + 1] }
        }
        #endif
        return nil
    }

    /// DEBUG-only: `-map-open-poi <name-substring | id>` opens a POI's detail sheet
    /// once `places` loads, so the sheet can be screenshotted headlessly. No effect
    /// in release / without the flag.
    private static func debugOpenPOI(in pois: [POI]) -> POI? {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-map-open-poi"), i + 1 < a.count {
            let key = a[i + 1].lowercased()
            return pois.first { $0.id == a[i + 1] || $0.name.lowercased().contains(key) }
        }
        #endif
        return nil
    }

    /// DEBUG-only: `-map-save <spotid>` (repeatable) forces a spot into the Saved
    /// state, and `-map-force-live <spotid>` (repeatable) forces it Live, so those
    /// pin states render headlessly without a real save / live event. No effect in
    /// release / without the flag.
    private static func debugSavedIds() -> Set<String> {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        return Set(zip(a, a.dropFirst()).filter { $0.0 == "-map-save" }.map { $0.1 })
        #else
        return []
        #endif
    }
    private static func debugForceLiveIds() -> Set<String> {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        return Set(zip(a, a.dropFirst()).filter { $0.0 == "-map-force-live" }.map { $0.1 })
        #else
        return []
        #endif
    }

    @State private var quickAdding = false
    @State private var showingHelp = false
    /// How far the bottom sheet has grown past its peek (0 = collapsed, 1 = at/above
    /// medium), published by `MapSheet` via `SheetExpansionKey`. Drives the fade-out of
    /// the floating ?/locate controls so they never collide with the rising sheet.
    @State private var sheetExpansion: CGFloat = 0
    /// The map view's own size, measured in the view layer (the SDK's `MapboxMap.size` is
    /// internal). Feeds the label pass's floating-chrome reservation. Not `private`: the
    /// clustering extension reads it.
    @State var mapSize: CGSize = .zero

    /// Bottom margin (from the map's bottom edge) that lifts the required Mapbox logo +
    /// attribution button to rest just above the collapsed unified glass, so they're no
    /// longer clipped into slivers behind it. The expanding sheet occludes them (drawn
    /// on top) — they're clearly visible at the collapsed/peek rest state.
    private static let ornamentBottomMargin: CGFloat =
        MapSheet.tabBarReserve + MapSheet.peekHeight + 40

    private var isAdmin: Bool {
        // DEBUG-only: `-force-nonadmin` launch arg forces the non-admin branch so
        // simulator verification can screenshot the gated map without a second
        // account. No effect in release builds or without the flag.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-force-nonadmin") { return false }
        #endif
        return Admin.isAdmin(auth.email)
    }

    /// Not `private`: the label de-confliction pass in SJMapView+POIClustering.swift
    /// reserves these civic badges/labels first (they're the map's anchors).
    var filteredSpots: [Spot] { MapSpots.all.filter { filter.matches($0.category) } }

    /// Real events at this spot today — searches title AND location so an event
    /// like "Independence Day Parade" at location "Downtown" still matches.
    private func events(at spot: Spot) -> [TimelineEvent] {
        model.todayEvents.filter { ev in
            let haystack = [ev.title, ev.location].compactMap { $0 }.joined(separator: " ").lowercased()
            return spot.keywords.contains { haystack.contains($0) }
        }
    }

    /// The pin an event resolves to (first curated spot whose keyword it matches),
    /// so a Today row can fly you there. nil for an unlisted venue.
    private func spot(for ev: TimelineEvent) -> Spot? {
        let haystack = [ev.title, ev.location].compactMap { $0 }.joined(separator: " ").lowercased()
        return MapSpots.all.first { $0.keywords.contains { haystack.contains($0) } }
    }

    /// A spot glows only while one of its events is actually happening.
    private func isLive(_ spot: Spot) -> Bool {
        #if DEBUG
        if Self.debugForceLiveIds().contains(spot.id) { return true }
        #endif
        return events(at: spot).contains { DateHelpers.isLiveNow($0.startTime) }
    }

    /// Whether the viewer has saved this place (device-local; the map's Saved pin).
    private func isSavedSpot(_ spot: Spot) -> Bool {
        #if DEBUG
        if Self.debugSavedIds().contains(spot.id) { return true }
        #endif
        return saved.isSaved(spot.id)
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            topChrome
            floatingControls
            MapSheet(
                events: model.todayEvents,
                state: model.state,
                spots: filteredSpots,
                selected: $selectedSpot,
                happenings: { events(at: $0) },
                spotFor: { spot(for: $0) },
                onSelectSpot: { focus($0) },
                onRetry: { model.retry() }
            )
        }
        // Screen size, for the label pass's chrome reservation (`MapboxMap.size` is internal
        // to the SDK, so measure the view instead). Written once at layout, and again only on
        // a real size change (rotation / multitasking) — not per frame.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { mapSize = geo.size }
                    .onChange(of: geo.size) { _, new in mapSize = new }
            }
        )
        // The sheet publishes how far it's grown past peek; the floating controls fade
        // off it (see `floatingControls`).
        .onPreferenceChange(SheetExpansionKey.self) { sheetExpansion = $0 }
        .onAppear { model.start(auth: auth) }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:     model.onForeground()
            case .background: model.onBackground()
            default:          break
            }
        }
        .sheet(isPresented: $quickAdding) {
            QuickAddSheet(spots: MapSpots.all)
        }
        // A tapped POI marker opens its detail (name, category, address, Open in Maps,
        // and live Google hours/website/phone/photo). POI is Identifiable by its row id.
        .sheet(item: $selectedPOI) { poi in
            POIDetailSheet(poi: poi)
        }
        // The "?" chrome button reopens the map intro any time — full-bleed, so it
        // gets its own cover. `instant` skips the first-run bloom so the reference
        // is readable immediately on every open.
        .fullScreenCover(isPresented: $showingHelp) {
            MapIntroView(ctaTitle: "Got it", instant: true) { showingHelp = false }
        }
    }

    // MARK: Map

    private var mapLayer: some View {
        MapReader { proxy in
            Map(viewport: $viewport) {
                // POIs now cluster client-side and render as SwiftUI view annotations that
                // GLIDE on merge/split (POIClusterMarker + POIClusterBubbleView) — the old
                // Mapbox POI style layers + their layer taps are retired. Taps live on the
                // annotation views themselves (SwiftUI overlays sit above the map, so they
                // resolve before the map-wide closeCard tap): a POI opens its detail, a
                // cluster zooms in to split. Declared BEFORE the civic pins so civic pins
                // always win the z-order (they must never be clustered or covered).
                ForEvery(model.pois) { poi in
                    MapViewAnnotation(coordinate: poi.coordinate) {
                        POIClusterMarker(
                            poi: poi,
                            assignment: poiAssignments[poi.id]
                                ?? POIAssignment(anchor: poi.coordinate, clustered: false),
                            expanded: model.pinsExpanded,
                            showsLabel: labelledPOIs.contains(poi.id),
                            proxy: proxy,
                            onTap: { selectPOI(id: poi.id) }
                        )
                    }
                    // Never cull — merged markers stack on their seed and must not vanish.
                    .allowOverlap(true)
                    // Explicit draw order. Declaration order does NOT control it — a POI badge
                    // was rendering OVER the Sacred Heart Chapel landmark and stealing its
                    // name label, despite civic being declared last. `priority` is the actual
                    // knob: POIs < cluster bubbles < civic landmarks, which must never be
                    // covered (see the header + CLAUDE.md).
                    .priority(Self.poiPriority)
                }
                ForEvery(renderedClusters) { cluster in
                    MapViewAnnotation(coordinate: cluster.coordinate) {
                        POIClusterBubbleView(count: cluster.count,
                                             active: cluster.active,
                                             family: cluster.dominantFamily,
                                             maxDiameter: cluster.maxDiameter) {
                            zoomToCluster(cluster.coordinate)
                        }
                    }
                    .allowOverlap(true)
                    .priority(Self.clusterPriority)
                }
                // A tap on the open map (not a badge/marker) just dismisses the detail —
                // every curated spot owns a real tappable badge, so there's no
                // nearest-neighbor hit-testing to do here.
                TapInteraction { _ in
                    closeCard()
                    return true
                }
                // Every curated spot always shows its small badge (see MapPinBadge) —
                // live/saved/selected layer an accent on top of the same badge.
                ForEvery(filteredSpots) { spot in
                    // Computed once and reused below — isLive(spot) scans today's events,
                    // no need to repeat that scan for the badge tint and the a11y label.
                    let spotIsLive = isLive(spot)
                    MapViewAnnotation(coordinate: spot.coordinate) {
                        // `base` colors the badge (live/saved/rest); `selected` is a
                        // separate scale/shadow accent layered on top, so a selected+live
                        // spot keeps its coral + pulse (see PinDisplay.swift's header).
                        MapPinBadge(spot: spot,
                                    base: PinDisplay.resolve(isLive: spotIsLive, isSaved: isSavedSpot(spot)),
                                    selected: selectedSpot?.id == spot.id,
                                    // A selected pin always shows its label regardless of
                                    // zoom (you asked for it); everyone else expands/shrinks
                                    // with the zoom-driven room the map actually has.
                                    expanded: selectedSpot?.id == spot.id || model.pinsExpanded,
                                    a11yLabel: accessibilityLabel(for: spot, live: spotIsLive))
                            .onTapGesture { selectSpot(spot) }
                    }
                    // Never cull; the selected/live badge must always beat its neighbors.
                    .allowOverlap(true)
                    .priority(Self.civicPriority)
                }
            }
            .mapStyle(MapStyle(uri: StyleURI(rawValue: MAP_STYLE_URL)!))
            // Lift the required Mapbox logo + attribution to just above the collapsed
            // unified glass so they're never clipped into slivers behind the bottom bar.
            // The scale bar stays hidden (it was never wanted on this civic map). This
            // is a Map-specific modifier, so it must precede the standard .onChange
            // modifiers below (those erase the concrete Map type).
            .ornamentOptions(OrnamentOptions(
                scaleBar: ScaleBarViewOptions(visibility: .hidden),
                logo: LogoViewOptions(
                    position: .bottomLeading,
                    margins: CGPoint(x: 16, y: Self.ornamentBottomMargin)),
                attributionButton: AttributionButtonOptions(
                    position: .bottomTrailing,
                    margins: CGPoint(x: 14, y: Self.ornamentBottomMargin))
            ))
            .onStyleLoaded { _ in
                recolorBasemap(proxy.map)
                recomputeClusters(proxy.map)   // POIs may still be loading — pois-change reclusters
            }
            // Re-apply once the map reports fully loaded. `onStyleLoaded` alone was a ONE-SHOT
            // application and it intermittently lost the race: a launch would occasionally
            // render a complete but UNRECOLOURED map — default Mapbox grey land, grey parks,
            // no cream — instead of the town's palette. (Caught by histogram, not by eye: the
            // frame is fully drawn, so it looks like a finished render, just the wrong one.)
            // `recolorBasemap` is pure `setLayerProperty` calls, so a second application is
            // idempotent and costs nothing when the first one already landed.
            .onMapLoaded { _ in recolorBasemap(proxy.map) }
            // Name whatever town the map is panned over, shrink/expand pins to fit the
            // zoom (both debounced in the model — never the view's @State here), and
            // recluster on zoom steps / at idle so merges + splits glide.
            .onCameraChanged {
                model.updateTown(center: $0.cameraState.center)
                model.updateZoom($0.cameraState.zoom)
                scheduleClusterRecompute(zoom: $0.cameraState.zoom, map: proxy.map)
            }
            // If a filter change hides the selected spot, drop the stale selection so the
            // detail sheet doesn't linger over a pin that's no longer on the map.
            .onChange(of: filter) { _, _ in
                if let s = selectedSpot, !filteredSpots.contains(where: { $0.id == s.id }) { closeCard() }
                // The label de-confliction pass reserves the CIVIC badges/labels first, and
                // the filter changes which of those are on the map — so a filter change can
                // free up (or take away) room for POI names. Recompute now rather than
                // leaving stale grants until the next camera move.
                recomputeClusters(proxy.map)
            }
            // POIs load async (once) after the style — recompute the layout when they land.
            .onChange(of: model.pois) { _, pois in
                recomputeClusters(proxy.map)
                #if DEBUG
                if selectedPOI == nil, let poi = SJMapView.debugOpenPOI(in: pois) { selectedPOI = poi }
                // Kick the autozoom demo only ONCE the POIs exist (they load a few seconds
                // after launch) — otherwise the merge sweep would run over an empty map.
                if !pois.isEmpty { startAutozoomIfNeeded() }
                #endif
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Warm the flat light-v11 basemap to the static Life360-reference palette
    /// (BasemapPalette — no modulation). Layer ids are verified against light-v11's
    /// actual style JSON (`GET styles/v1/mapbox/light-v11`) — it's a much simpler
    /// style than Mapbox Streets (one consolidated `land`/`road-simple`/`road-label-simple`
    /// layer apiece, no per-class road/motorway split), so don't reach for Streets'
    /// layer names here without checking. Each set is still best-effort (try?) since
    /// a given layer id may not exist in every style version.
    private func recolorBasemap(_ map: MapboxMap?) {
        guard let map else { return }
        let p = BasemapPalette.self
        try? map.setLayerProperty(for: "land", property: "background-color", value: p.land)
        // Parks / grass / woods (fill layers) — light-v11 only has these two.
        for id in ["landuse", "national-park"] {
            try? map.setLayerProperty(for: id, property: "fill-color", value: p.green)
        }
        try? map.setLayerProperty(for: "water",    property: "fill-color", value: p.water)
        try? map.setLayerProperty(for: "waterway", property: "line-color", value: p.water)
        try? map.setLayerProperty(for: "building", property: "fill-color",         value: p.building)
        try? map.setLayerProperty(for: "building", property: "fill-outline-color", value: p.building)
        // Roads — one consolidated layer in light-v11 (width-differentiated by class,
        // not color; see BasemapPalette.road's comment).
        try? map.setLayerProperty(for: "road-simple", property: "line-color", value: p.road)
        // Labels — the reference's road/place names read as a bold, dark charcoal,
        // not the style default's light grey. Reuse Hue.ink2 rather than duplicate
        // its hex (it's a near-exact match for the reference's sampled label ink,
        // #555553).
        let labelInk = Hue.ink2.hexString
        for id in ["road-label-simple", "settlement-major-label", "settlement-minor-label", "settlement-subdivision-label"] {
            try? map.setLayerProperty(for: id, property: "text-color", value: labelInk)
        }
        // Move the SETTLEMENT (town/city) names DOWN, out from under the cluster bubbles.
        // A town's POI cluster necessarily sits on the town centroid — exactly where Mapbox
        // anchors the town name — so the biggest bubble always landed on "St. Joseph" (the
        // overhaul spec's "no cluster covers the town label"). Mapbox's own label collision
        // can't help: these bubbles are SwiftUI view annotations drawn above the map canvas,
        // so the style never sees them.
        //
        // Anchoring the text to its TOP and pushing it below the point clears the bubble while
        // keeping every name on the map. (Hiding the layers instead would kill Collegeville,
        // Saint Wendel, Five Points and St. Cloud too — the town pill only reverse-geocodes
        // the viewport CENTRE, so it can't name the towns around it, and a nameless map at
        // z11 is worse than the collision ever was.)
        //
        // The offset is in ems of the label's own text size, which light-v11 interpolates to
        // ~14–24pt by zoom and `symbolrank`. It must clear the LARGEST bubble radius — the
        // overlap cap tops out at 44pt across ⇒ 22pt — so 2.4em (≈34–58pt) clears with room.
        // 1.4em was measurably short: the z11 "69" bubble still clipped "St. Joseph".
        //
        // Both layers also carry a `text-radial-offset`, which takes precedence over
        // `text-offset` where it is non-zero. light-v11 steps it to 0 at z ≥ 8 and this map
        // lives at z11–15, so `text-offset` is the one that applies here.
        for id in ["settlement-major-label", "settlement-minor-label"] {
            try? map.setLayerProperty(for: id, property: "text-anchor", value: "top")
            try? map.setLayerProperty(for: id, property: "text-offset", value: [0.0, 2.4])
        }
        // Above z13 the town name stops earning its space: you are unambiguously INSIDE one
        // town and the top pill already names it. Capping matches what light-v11 already does
        // to `settlement-minor-label` (maxzoom 13), so majors and minors retire together.
        // Below z13 — the regional view, where naming Collegeville / Saint Wendel / Rockville
        // is the whole point — the offset label stays and clears the bubbles.
        //
        // KNOWN LIMIT, deliberately not chased further: at z12 a civic REST DOT can still
        // graze the first glyphs of the name. The offset dodges the cluster bubble (which is
        // centred on the town centroid) but the civic spots trail just south of it, which is
        // where the offset puts the text. Anchoring ABOVE instead was measured and is WORSE —
        // the label lands squarely behind the 61-bubble. The remaining options both cost more
        // than the defect: a larger offset detaches the name from its own dot, and our pins
        // can't dodge because they sit at real coordinates while the label is Mapbox's.
        try? map.setLayerProperty(for: "settlement-major-label", property: "maxzoom", value: 13.0)
    }

    // MARK: Top chrome — filter · town pill · compose (replaces the title header)

    private var topChrome: some View {
        HStack(spacing: 10) {
            filterMenu
            Spacer(minLength: 8)
            townPill
            Spacer(minLength: 8)
            composeButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $filter) {
                ForEach(SpotFilter.allCases, id: \.self) { f in Text(f.title).tag(f) }
            }
        } label: {
            chromeCircle(icon: "slider.horizontal.3", active: filter != .all)
        }
        // Strip the default menu/glass control background so only the chrome
        // circle shows — matches the sibling Button chrome (which use .plain).
        .buttonStyle(.plain)
        .accessibilityLabel("Filter places")
    }

    private var townPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Hue.accent)
            Text(model.townLabel)
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.mapInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Hue.surface, in: Capsule())
        .overlay(Capsule().stroke(Hue.mapHairline, lineWidth: 1))
        .mapFloatShadow()
        .animation(.easeInOut(duration: 0.2), value: model.townLabel)
        .accessibilityElement(children: .combine)
    }

    private var composeButton: some View {
        Button {
            Haptics.light()
            if isAdmin { quickAdding = true } else { onCompose?() }
        } label: {
            chromeCircle(icon: "plus")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add an event")
    }

    // MARK: Floating controls — help (bottom-left) + recenter (bottom-right)

    private var floatingControls: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                helpButton
                Spacer()
                recenterButton
            }
            .padding(.horizontal, 16)
            // Stack ABOVE the map's attribution row (logo + info button, which sit just
            // above the collapsed glass) so the two never collide; fade + lift out of the
            // way as the sheet grows so they never collide with it either.
            .padding(.bottom, MapSheet.tabBarReserve + MapSheet.peekHeight + 96)
            .offset(y: -sheetExpansion * 10)
            .opacity(Double(1 - min(1, sheetExpansion * 1.3)))
            .allowsHitTesting(sheetExpansion < 0.12)
            .animation(.easeOut(duration: 0.18), value: sheetExpansion)
        }
    }

    private var helpButton: some View {
        Button {
            Haptics.light()
            showingHelp = true
        } label: {
            chromeCircle(icon: "questionmark")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How the map works")
    }

    private var recenterButton: some View {
        Button {
            withViewportAnimation(.fly(duration: 0.8)) {
                viewport = .camera(center: MapSpots.center, zoom: 13.5)
            }
            closeCard()
        } label: {
            chromeCircle(icon: "location")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter map")
    }

    /// The shared chrome bubble — 44px white circle, hairline (coral when active),
    /// ink line icon.
    private func chromeCircle(icon: String, active: Bool = false) -> some View {
        Circle()
            .fill(Hue.surface)
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(active ? Hue.accent : Hue.mapHairline, lineWidth: active ? 1.5 : 1))
            .mapFloatShadow()
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(active ? Hue.accent : Hue.mapInk)
            )
    }

    // MARK: Actions

    /// A Today/Places row tap: fly to the spot and open its detail in the sheet.
    private func focus(_ spot: Spot) {
        Haptics.light()
        selectedPOI = nil
        withViewportAnimation(.fly(duration: 0.7)) {
            viewport = .camera(center: spot.coordinate, zoom: 15)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            selectedSpot = spot
        }
    }

    private func selectSpot(_ spot: Spot) {
        Haptics.light()
        selectedPOI = nil                       // civic + POI detail are mutually exclusive
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            selectedSpot = (selectedSpot?.id == spot.id) ? nil : spot
        }
    }

    /// Open a tapped food/business POI's detail (resolved from the tapped feature's
    /// `id` property). Closes any civic card first — the two details never coexist.
    private func selectPOI(id: String) {
        guard let poi = model.pois.first(where: { $0.id == id }) else { return }
        Haptics.light()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { selectedSpot = nil }
        selectedPOI = poi
    }

    /// A tapped cluster zooms in to ~15 (above the 14.5 awake threshold), splitting it
    /// into individual glyph markers centered on the tapped area.
    private func zoomToCluster(_ coord: CLLocationCoordinate2D) {
        Haptics.light()
        withViewportAnimation(.fly(duration: 0.6)) {
            viewport = .camera(center: coord, zoom: 15)
        }
    }

    // Client-side POI clustering (recompute trigger, reclustering, bubble lifecycle) and
    // the DEBUG autozoom demo live in SJMapView+POIClustering.swift.

    private func closeCard() {
        guard selectedSpot != nil else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            selectedSpot = nil
        }
    }

    private func accessibilityLabel(for spot: Spot, live: Bool) -> String {
        let n = events(at: spot).count
        let base = n == 0 ? "\(spot.name), nothing today"
                          : "\(spot.name), \(n) happening today"
        return live ? base + ", happening now" : base
    }
}

// MARK: - Live pulse ring
//
// Self-contained — @State is local so the animation loop never propagates updates
// to sibling pins or the parent map. Core Animation renders each frame off the
// main thread. Coral, opacity 0.35 → 0, scale 1 → 2.2, 1.5 s loop. Static under
// Reduce Motion (no pulse; the coral fill still marks "live").

private struct PulseRing: View {
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            // In mono this halo IS the liveness signal — there is no coral left to
            // carry it, so the pin's only "something is happening here" cue is this
            // expanding ink ring plus the always-on name label. Held at 0.35 in both
            // skins: ink at 35% over paper lands close to the coral's weight, so the
            // pulse reads with the same urgency it always did.
            .fill(MarkerRole.liveRing(warm: LIVE_COLOR).opacity(pulsing ? 0 : 0.35))
            .frame(width: diameter, height: diameter)
            .scaleEffect(pulsing ? 2.2 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Marker chip (every curated spot; shrinks/expands with zoom)
//
// Life360/Mobbin-reference pattern: a small SOLID category-color circle with a
// white glyph, plus a bold halo'd name label beside it — never a big bulky badge.
// The circle's ANCHOR stays fixed at the badge's own center regardless of size; the
// label is an overlay that hangs to the right without shifting where the pin
// actually points.
//
// compact (zoomed out / not selected): a plain 14pt tint dot — no icon, no label,
//           so six pins share the map without crowding each other's names.
// expanded (zoomed in enough, or selected): 28pt circle + white glyph + halo'd
//           label beside it, same as before.
// saved:    + a small ink bookmark corner accent (expanded only — too cramped compact).
// live:     coral fill + pulse ring + coral label (live always wins the tint; the
//           pulse still shows compact — it's the one thing worth keeping glanceable
//           at any zoom).
// selected: scale 1.15, deeper shadow, always expanded regardless of zoom.
// Motion:   wake = opacity 0→1 + scale 0.6→1.0 spring (~220ms) on first appear;
//           expand/shrink = spring on diameter + icon/label crossfade; Reduce Motion
//           drops every scale/spring to an instant or simple opacity change.

private struct MapPinBadge: View {
    let spot: Spot
    let base: PinDisplay      // rest | saved | live — the coloring (selection ignored)
    let selected: Bool
    let expanded: Bool        // zoom-driven (or forced by `selected`) — see SJMapView
    let a11yLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private static let expandedDiameter: CGFloat = 28
    private static let compactDiameter: CGFloat = 14
    private static let iconSize: CGFloat = 13

    private var diameter: CGFloat { expanded ? Self.expandedDiameter : Self.compactDiameter }
    private var live: Bool  { base == .live }
    private var saved: Bool { base == .saved }
    /// Badge fill, routed through `MarkerRole` so the monochrome skin swaps in
    /// without branching here (see MonoMarkerPalette.swift).
    private var tint: Color { live ? MarkerRole.liveFill(warm: LIVE_COLOR) : MarkerRole.civicFill(spot.category) }

    var body: some View {
        badge
            .scaleEffect(appeared ? (selected && !reduceMotion ? 1.15 : 1.0) : (reduceMotion ? 1.0 : 0.6))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
            // A spot going live/saved (a real event starting, a save toggled) crossfades
            // its tint instead of snapping — the annotation view persists across these
            // transitions (Mapbox reuses it by the spot's stable id), so without this the
            // color change would be the only unanimated state change on the badge.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: base)
            // Shrink/expand — a spring so six pins settling to a new size on a pinch
            // feels like one physical move, not a snap. Reduce Motion still crossfades
            // (opacity below), just without the size spring.
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.8), value: expanded)
            // The name label attaches AFTER scaleEffect, as an overlay rather than a
            // ZStack sibling of the circle — so it (a) reads its position off badge's
            // un-scaled layout frame via `.overlay(alignment: .leading)` + leading
            // padding (a ZStack-centered frame + `.offset()` looks similar but is wrong:
            // the centering happens BEFORE the offset is applied, so the offset would
            // need to also account for the label's own width, which varies per name),
            // and (b) never grows 1.15x with the selected scale bump the way the circle
            // does — labels stayed a constant size in the pre-redesign badge too.
            .overlay(alignment: .leading) {
                HaloText(spot.name, color: tint)
                    .frame(width: 100, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Self.expandedDiameter + 6)
                    .allowsHitTesting(false)
                    // Never animate in from scale(0) — a barely-visible starting shape
                    // reads as natural, a point-source doesn't (emil-design-eng).
                    .scaleEffect(expanded ? 1 : 0.9, anchor: .leading)
                    .opacity(expanded ? 1 : 0)
            }
            .opacity(appeared ? 1 : (reduceMotion ? 1 : 0))
            // Enlarge the invisible tap target to Apple's ≥44×44pt HIG minimum
            // regardless of the current visual size — centered the same as the
            // visual circle, so the annotation's map-coordinate anchor doesn't move.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.18)
                                           : .spring(response: 0.22, dampingFraction: 0.72)) {
                    appeared = true
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11yLabel)
            .accessibilityAddTraits(.isButton)
    }

    private var badge: some View {
        ZStack {
            // Suppressed once selected — the scale bump + always-visible label is
            // the "you tapped this" cue; a pulsing ring behind it reads as noise.
            // Kept even compact — the one live signal worth keeping glanceable
            // zoomed all the way out.
            if live && !selected { PulseRing(diameter: diameter) }

            // Mono-only: a STATIC ring outside a live badge. Coral used to say "live"
            // without moving; motion alone left liveness invisible in a still frame.
            // Drawn at diameter + 7 so it clears the badge's own 1.5pt white keyline
            // and reads as a separate mark rather than a thick border.
            if live, let ring = MarkerRole.liveStaticRing {
                Circle()
                    .stroke(ring, lineWidth: 2)
                    .frame(width: diameter + 7, height: diameter + 7)
                    .opacity(expanded ? 1 : 0)   // no room around a 14pt compact dot
            }

            Circle()
                .fill(tint)
                .frame(width: diameter, height: diameter)
                .mapFloatShadow(pressed: selected)
                // Civic pins are ink-filled in both skins' terms (dark fill), so the
                // keyline stays the white lift — `isLightFill: false`.
                .overlay(Circle().stroke(MarkerRole.pinStroke(isLightFill: false), lineWidth: 1.5))

            Image(systemName: spot.category.filledSymbol)
                .font(.system(size: Self.iconSize, weight: .semibold))
                .foregroundStyle(MarkerRole.civicGlyph)
                .opacity(expanded ? 1 : 0)   // too cramped on a 14pt compact dot

            if saved {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Hue.mapInk)
                    .frame(width: 12, height: 12)
                    .background(Circle().fill(Hue.surface))
                    .overlay(Circle().stroke(Hue.mapHairline, lineWidth: 1))
                    .offset(x: Self.expandedDiameter / 2 - 3, y: -(Self.expandedDiameter / 2 - 3))
                    .opacity(expanded ? 1 : 0)   // same — no room on the compact dot
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Halo'd map label
//
// A bold colored label with a white outline so it stays legible over any basemap
// fill (park green, water blue, cream ground) without a background pill — matches
// the reference's bare-on-the-map label treatment.

struct HaloText: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) { self.text = text; self.color = color }

    private static let haloOffsets: [(CGFloat, CGFloat)] =
        [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(Self.haloOffsets.enumerated()), id: \.offset) { _, o in
                label.foregroundStyle(.white).offset(x: o.0, y: o.1)
            }
            label.foregroundStyle(color)
        }
    }

    private var label: some View {
        Text(text)
            .font(.sansBold(12))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }
}
