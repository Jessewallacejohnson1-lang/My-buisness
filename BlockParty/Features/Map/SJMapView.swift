//
//  SJMapView.swift
//  Block Party — Mapbox map of Saint Joseph, Minnesota.
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
//  liveness + "today's happenings" come only from real events. Live ink is routed
//  through MonoMarkerPalette's role table.
//

import SwiftUI
import UIKit
import MapboxMaps

// MARK: - Constants

private let MAP_STYLE_URL = "mapbox://styles/mapbox/light-v11"

// Basemap cartography lives in BasemapPalette (Features/Map/BasemapPalette.swift) —
// one static palette, pixel-matched to the Life360 reference. No modulation.

// MARK: - Shared place selection

/// The map's single selected-place value, owned by `MainTabsView` and carried into
/// both this map and the global bottom shell. Each case stores the source model itself,
/// so marker selection, camera framing, labels, directions, and save state cannot drift
/// across duplicated view models.
enum MapPlaceDetail: Identifiable, Hashable {
    case spot(Spot)
    case poi(POI)

    var id: String {
        switch self {
        case .spot(let spot): return "spot:\(spot.id)"
        case .poi(let poi):   return "poi:\(poi.id)"
        }
    }

    var name: String {
        switch self {
        case .spot(let spot): return spot.name
        case .poi(let poi):   return poi.name
        }
    }

    var glyph: String {
        switch self {
        case .spot(let spot): return spot.category.filledSymbol
        case .poi(let poi):   return poi.glyph
        }
    }

    var categoryLabel: String {
        switch self {
        case .spot(let spot):
            switch spot.category {
            case .trail:    return "Trail"
            case .park:     return "Park"
            case .downtown: return "Downtown"
            case .coffee:   return "Coffee"
            case .fitness:  return "Fitness"
            case .college:  return "Campus"
            case .chapel:   return "Landmark"
            case .default:  return "Place"
            }
        case .poi(let poi):
            return poi.family.label
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .spot(let spot): return spot.coordinate
        case .poi(let poi):   return poi.coordinate
        }
    }

    var spot: Spot? {
        guard case .spot(let spot) = self else { return nil }
        return spot
    }

    var poi: POI? {
        guard case .poi(let poi) = self else { return nil }
        return poi
    }

    var saveID: String {
        switch self {
        case .spot(let spot): return spot.id
        case .poi(let poi):   return poi.id
        }
    }

    /// Neither source model currently carries Google price level. Keep the optional
    /// seam explicit so the badge can add it when real data exists; never synthesize it.
    var priceLabel: String? { nil }

    var distanceLabel: String? {
        let origin = CLLocation(
            latitude: MapSpots.center.latitude,
            longitude: MapSpots.center.longitude
        )
        let destination = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        let meters = destination.distance(from: origin)
        guard meters >= 30 else { return nil }
        let miles = meters / 1_609.344

        if miles < 0.1 {
            let roundedFeet = Int((meters * 3.28084 / 50).rounded()) * 50
            return "\(max(50, roundedFeet)) ft"
        }
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }
        return "\(Int(miles.rounded())) mi"
    }

    var badgeLabel: String {
        [categoryLabel, distanceLabel, priceLabel]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var groupAccessibilityLabel: String {
        let distance = distanceLabel.map { ", \($0) from downtown" } ?? ""
        let price = priceLabel.map { ", \($0)" } ?? ""
        return "\(name). \(categoryLabel)\(distance)\(price)."
    }

    var directionsURL: URL? {
        switch self {
        case .spot(let spot):
            return URL(
                string: "maps://?daddr=\(spot.coordinate.latitude),\(spot.coordinate.longitude)&dirflg=d"
            )
        case .poi(let poi):
            let query = poi.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "http://maps.apple.com/?q=\(query)&ll=\(poi.lat),\(poi.lon)")
        }
    }

    /// DEBUG-only civic preselection used by the screenshot route. A POI cannot be
    /// resolved until its async catalogue arrives, so that flag is handled in SJMapView.
    static func debugInitialDetail() -> MapPlaceDetail? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-map-open"), index + 1 < arguments.count,
           let spot = MapSpots.all.first(where: { $0.id == arguments[index + 1] }) {
            return .spot(spot)
        }
        #endif
        return nil
    }
}

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
    /// The source of truth lives in MainTabsView so the global tab shell can morph.
    @Binding var mapDetail: MapPlaceDetail?
    /// Real happenings for the selected civic spot, projected out of this view's
    /// `MapModel` for the global tab shell. Always empty for POIs or no selection.
    @Binding var mapDetailHappenings: [TimelineEvent]
    /// Non-admins tap the top-right "+" into the global composer (admins get the
    /// map's own QuickAddSheet). Injected by MainTabsView, like HomeView.
    var onCompose: (() -> Void)? = nil

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase
    /// Container-level Reduce Motion (the self-contained pin animations read their own;
    /// this one gates the camera flys + the card/selection springs — spec §11 / §12.6).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Not `private`: the POI-clustering + autozoom methods in SJMapView+POIClustering.swift
    // read `model` and drive `viewport`, and Swift `private` is file-scoped.
    @StateObject var model = MapModel()

    /// Latest laid-out map height, so a pin-select can reserve the morphed detail shell
    /// as camera padding and land the pin above it. Updated off the layout pass.
    @State private var containerH: CGFloat = 0
    /// The compact detail grows with its two-line title and Dynamic Type. Scale the
    /// two-line baseline reserve with that content, still bounded in `liftedViewport`.
    @ScaledMetric(relativeTo: .title3) private var detailCameraReserve =
        BlockPartyTabBar.detailCameraReserve
    /// The coordinate the camera is currently lifted onto (non-nil while a selection holds
    /// the bottom padding). Used to settle the camera back to no-padding on dismiss so the
    /// map isn't left mis-framed with a half-screen inset once the sheet collapses.
    @State private var liftedCoord: CLLocationCoordinate2D?
    /// The zoom a tapped/focused spot settles at — above the 14.5 awake threshold so its
    /// label shows. Shared by direct pin taps and Today/Places row taps.
    private static let selectZoom: CGFloat = 15
    /// Device-local saved set (shared with Explore). Observed so saving a place from
    /// the sheet updates its pin to the Saved state live.
    @ObservedObject private var saved = SavedStore.shared

    @State var viewport: Viewport = .camera(
        center: SJMapView.debugInitialCenter() ?? MapSpots.center,
        zoom: SJMapView.debugInitialZoom() ?? 13.5,
        bearing: SJMapView.debugInitialBearing() ?? 0,
        pitch: SJMapView.debugInitialPitch() ?? 0
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

    /// DEBUG-only: `-map-bearing <deg>` / `-map-pitch <deg>` start the camera already rotated
    /// / tilted, so the compass-visible state and the tilted horizon can be screenshotted
    /// headlessly (the sim has no two-finger gesture automation). No effect in release.
    private static func debugInitialBearing() -> Double? {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-map-bearing"), i + 1 < a.count { return Double(a[i + 1]) }
        #endif
        return nil
    }

    private static func debugInitialPitch() -> Double? {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-map-pitch"), i + 1 < a.count { return Double(a[i + 1]) }
        #endif
        return nil
    }

    private var selectedSpot: Spot? { mapDetail?.spot }
    private var selectedPOI: POI? { mapDetail?.poi }
    @State private var filter: SpotFilter = .all

    // MARK: Client-side POI clustering (replaces the retired POILayer)
    //
    // The 52 POIs are all mounted as view annotations (POIClusterMarker); this state is
    // the recomputed layout that drives their merge/split glide. Recomputed on zoom-step
    // changes + at camera idle (never every frame — mirrors how Mapbox only reclusters at
    // zoom steps), off the LIVE projection via proxy.map.point(for:).

    // These drive the clusterer that lives in SJMapView+POIClustering.swift, so they are
    // not `private` (Swift `private` is file-scoped and the extension is another file).

    /// Namespaced POI/civic id → where it should sit (its cluster seed, or itself when
    /// solo). Every leaf reads its own entry; a flip animates that leaf's spring.
    @State var markerAssignments: [ClusterMarkerID: POIAssignment] = [:]
    /// The cluster bubbles to draw, including ones currently fading out (a split keeps a
    /// dissolving bubble mounted a beat so it fades rather than pops).
    @State var renderedClusters: [POIClusterRender] = []
    /// Namespaced marker ids whose name label has room at the current layout (see
    /// `POICluster.labelledMarkers`). Everything else shows its badge but withholds text.
    @State var labelledMarkers: Set<ClusterMarkerID> = []
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

    /// Annotation draw order. Mapbox draws view annotations by `priority`, NOT declaration
    /// order. Higher wins. The current spatial hierarchy is cluster > selected > any
    /// unselected pin; civic status no longer grants an always-on-top exception.
    static let poiPriority = 0
    static let civicPriority = 0
    static let selectedPriority = 10
    static let clusterPriority = 20

    /// DEBUG-only: `-map-open-poi [name-substring | id]` opens a POI's tab-shell
    /// detail once `places` loads. With no value, it deterministically uses the first
    /// loaded POI so the documented screenshot command stays self-contained.
    private static func debugOpenPOI(in pois: [POI]) -> POI? {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-map-open-poi") {
            guard i + 1 < a.count, !a[i + 1].hasPrefix("-") else { return pois.first }
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
    /// Browse state lives above the conditionally mounted sheet so a place-detail
    /// interlude cannot reset the user's chosen face or detent.
    @State private var browseMode = MapSheet.initialMode()
    @State private var browseDetent = MapSheet.initialDetent()
    /// How far the bottom sheet has grown past its peek (0 = collapsed, 1 = at/above
    /// medium), published by `MapSheet` via `SheetExpansionKey`. Drives the fade-out of
    /// the floating ?/locate controls so they never collide with the rising sheet.
    @State private var sheetExpansion: CGFloat = 0
    /// The map view's own size, measured in the view layer (the SDK's `MapboxMap.size` is
    /// internal). Feeds the label pass's floating-chrome reservation. Not `private`: the
    /// clustering extension reads it.
    @State var mapSize: CGSize = .zero

    /// Live camera heading (bearing/pitch) + last center/zoom, updated every camera frame so
    /// the compass needle tracks rotation 1:1. Held as `@State` (a stable reference), NOT
    /// `@StateObject`: `@State` does not subscribe to the object's publisher, so mutating its
    /// `@Published` bearing re-renders only `MapCompass` (which observes it) and never this
    /// whole map view — the isolation that keeps per-frame rotation at 120 Hz.
    @State private var compass = CompassHeading()

    /// Bottom margin (from the map's bottom edge) for the Mapbox logo + attribution
    /// button. Mapbox's Terms of Service REQUIRE both to stay visible — they may be
    /// repositioned but not removed, and the logo may not be restyled (the ⓘ is already
    /// the smallest-footprint attribution and carries the required telemetry opt-out).
    /// So "minimize screen space" = tuck them to just an 8pt sliver above the collapsed
    /// glass (was +40, floating well into the map) — as low as they can sit while still
    /// resting ABOVE the peek sheet rather than hidden behind it. The expanding sheet
    /// occludes them (drawn on top); they're clearly visible at the collapsed/peek rest.
    private static let ornamentBottomMargin: CGFloat =
        MapSheet.tabBarReserve + MapSheet.peekHeight + 8

    private var isAdmin: Bool {
        // DEBUG-only: `-force-nonadmin` launch arg forces the non-admin branch so
        // simulator verification can screenshot the gated map without a second
        // account. No effect in release builds or without the flag.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-force-nonadmin") { return false }
        #endif
        return Admin.isAdmin(auth.email)
    }

    /// Not `private`: the shared cluster + label pass consumes this exact filtered set.
    var filteredSpots: [Spot] { MapSpots.all.filter { filter.matches($0.category) } }

    /// The one marker clustering must exclude. Selection is mutually exclusive across
    /// catalogs, so one namespaced id fully represents the exception.
    var selectedClusterMarkerID: ClusterMarkerID? {
        if let selectedSpot { return .civic(selectedSpot.id) }
        if let selectedPOI { return .poi(selectedPOI.id) }
        return nil
    }

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
    func isLive(_ spot: Spot) -> Bool {
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
            if mapDetail == nil {
                MapSheet(
                    events: model.todayEvents,
                    state: model.state,
                    spots: filteredSpots,
                    happenings: { events(at: $0) },
                    spotFor: { spot(for: $0) },
                    onSelectSpot: { focus($0) },
                    onRetry: { model.retry() },
                    mode: $browseMode,
                    detent: $browseDetent
                )
                // Liquid Glass surfaces are extracted for container compositing, so
                // opacity alone can leave child text visible. Removing the browse sheet
                // guarantees detail is the sole bottom element; lifted state restores it.
                .transition(.identity)
            }
        }
        // Track the map's HEIGHT (a pin-select lifts the pin above the detail shell) and its full
        // SIZE (the label pass's chrome reservation — `MapboxMap.size` is internal to the
        // SDK, so measure the view instead). One reader feeds both; written at layout and
        // again only on a real size change (rotation / multitasking), never per frame.
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { containerH = g.size.height; mapSize = g.size }
                    .onChange(of: g.size) { _, new in containerH = new.height; mapSize = new }
            }
        )
        // The sheet publishes how far it's grown past peek; the floating controls fade
        // off it (see `floatingControls`).
        .onPreferenceChange(SheetExpansionKey.self) { sheetExpansion = $0 }
        .onAppear {
            model.start(auth: auth)
            Haptics.prepare()
            syncMapDetailHappenings()
            // A spot preselected at mount (deep link, or the DEBUG -map-open flag) frames
            // above the morphed detail shell, exactly as a direct pin tap would.
            if let s = selectedSpot { viewport = liftedViewport(s.coordinate, zoom: Self.selectZoom) }
        }
        // Map is "ready" once the data has resolved AND the basemap has painted —
        // otherwise the cover would lift onto a blank grey map. But if the data
        // errored/went offline, lift immediately (show that surface; don't wait for
        // tiles that also won't load). `styleLoaded` also flips on a style-load error
        // below, and `TabLoadingHost` has a hard timeout, so the cover can't hang.
        .tabReady(model.state != .loading
                  && (model.styleLoaded || model.state == .error || model.state == .offline))
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:     model.onForeground()
            case .background: model.onBackground()
            default:          break
            }
        }
        // When the last selection clears (X or map-background tap), release the camera's
        // bottom padding so the map re-settles level instead of staying jammed upward.
        .onChange(of: selectedSpot?.id) { _, id in if id == nil { releaseCameraLift() } }
        .onChange(of: selectedPOI?.id) { _, id in if id == nil { releaseCameraLift() } }
        .onChange(of: mapDetail?.id) { _, _ in syncMapDetailHappenings() }
        .onChange(of: model.todayEvents) { _, _ in syncMapDetailHappenings() }
        .sheet(isPresented: $quickAdding) {
            QuickAddSheet(spots: MapSpots.all)
        }
        // A tapped POI no longer opens a modal or sheet detail. Its compact content
        // lives in the one global tab-shell morph shared with civic spots.
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
                // cluster zooms in to split.
                ForEvery(model.pois) { poi in
                    let markerID = ClusterMarkerID.poi(poi.id)
                    let isSelected = selectedClusterMarkerID == markerID
                    MapViewAnnotation(coordinate: poi.coordinate) {
                        POIClusterMarker(
                            poi: poi,
                            assignment: markerAssignments[markerID]
                                ?? POIAssignment(anchor: poi.coordinate, clustered: false),
                            expanded: model.pinsExpanded,
                            selected: isSelected,
                            showsLabel: model.pinsExpanded && labelledMarkers.contains(markerID),
                            proxy: proxy,
                            onTap: { selectPOI(id: poi.id) }
                        )
                    }
                    // Never cull — merged markers stack on their seed and must not vanish.
                    .allowOverlap(true)
                    .priority(isSelected ? Self.selectedPriority : Self.poiPriority)
                }
                ForEvery(renderedClusters) { cluster in
                    MapViewAnnotation(coordinate: cluster.coordinate) {
                        POIClusterBubbleView(count: cluster.count,
                                             active: cluster.active,
                                             containsLive: cluster.containsLive,
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
                // Every curated spot remains mounted at its real coordinate. Below
                // pinExpandZoom the shared leaf moves it into its assigned cluster; above
                // that threshold its solo assignment glides it back to this anchor.
                ForEvery(filteredSpots) { spot in
                    // Computed once and reused below — isLive(spot) scans today's events,
                    // no need to repeat that scan for the badge tint and the a11y label.
                    let spotIsLive = isLive(spot)
                    let markerID = ClusterMarkerID.civic(spot.id)
                    let isSelected = selectedClusterMarkerID == markerID
                    MapViewAnnotation(coordinate: spot.coordinate) {
                        CivicClusterMarker(
                            coordinate: spot.coordinate,
                            assignment: markerAssignments[markerID]
                                ?? POIAssignment(anchor: spot.coordinate, clustered: false),
                            proxy: proxy
                        ) {
                            MapPinBadge(
                                spot: spot,
                                base: PinDisplay.resolve(
                                    isLive: spotIsLive,
                                    isSaved: isSavedSpot(spot)
                                ),
                                selected: isSelected,
                                expanded: isSelected || model.pinsExpanded,
                                showsLabel: model.pinsExpanded
                                    && labelledMarkers.contains(markerID),
                                a11yLabel: accessibilityLabel(for: spot, live: spotIsLive)
                            )
                            .onTapGesture { selectSpot(spot) }
                        }
                    }
                    // Never cull; clustered leaves must stay mounted to complete their glide.
                    .allowOverlap(true)
                    .priority(isSelected ? Self.selectedPriority : Self.civicPriority)
                }
                // A tapped POI gets an on-map selected treatment (spec §2): a haloed,
                // enlarged (1.25×) family badge overlaid at its coordinate — the same
                // SwiftUI-annotation approach the civic pins use for selection, so we
                // stay clear of clustered-source feature-state. Cleared with the sheet.
                if let poi = selectedPOI {
                    MapViewAnnotation(coordinate: poi.coordinate) {
                        POISelectedMarker(poi: poi)
                    }
                    .allowOverlap(true)
                    .priority(Self.selectedPriority)
                }
            }
            .mapStyle(MapStyle(uri: StyleURI(rawValue: MAP_STYLE_URL)!))
            // Apple-Maps-grade rotate + tilt. The label de-confliction pass is bearing/pitch
            // agnostic in practice: it projects every marker through the LIVE camera
            // (`map.point(for:)`) and re-runs 0.13s after the camera settles (rotation included,
            // via `.onCameraChanged`), so a rotated frame re-deconflicts correctly; and every
            // pin/cluster/label is a SwiftUI `MapViewAnnotation`, which stays screen-upright
            // rather than rotating with the basemap. `focalPoint` is left nil so rotate + zoom
            // pivot around the two-finger centroid (Apple's focal behavior). Rotation hysteresis
            // is the SDK's built-in engage threshold, gated further by
            // `simultaneousRotateAndPinchZoomEnabled` so a pinch-zoom doesn't drift into a
            // rotation. `panDecelerationFactor` (velocity × factor per ms during the release
            // glide) defaults to `UIScrollView.DecelerationRate.normal` ≈ 0.998 — set explicitly
            // so it's one of the tunable feel knobs.
            .gestureOptions(GestureOptions(rotateEnabled: true,
                                           simultaneousRotateAndPinchZoomEnabled: true,
                                           pitchEnabled: true,
                                           panDecelerationFactor: 0.998))
            // Lift the required Mapbox logo + attribution to just above the collapsed
            // unified glass so they're never clipped into slivers behind the bottom bar.
            // The scale bar stays hidden (it was never wanted on this civic map). This
            // is a Map-specific modifier, so it must precede the standard .onChange
            // modifiers below (those erase the concrete Map type).
            .ornamentOptions(OrnamentOptions(
                scaleBar: ScaleBarViewOptions(visibility: .hidden),
                // Suppress the built-in compass: its needle is coral (the monochrome brand
                // deletes that hue) and its 0.3s fade / bearing-only tap aren't the spec. Our
                // own `MapCompass` overlay replaces it (adaptive, 0.25s fade, resets bearing
                // AND pitch). Without this the SDK's default `.adaptive` compass would surface
                // at top-trailing the moment rotation is enabled.
                compass: CompassViewOptions(visibility: .hidden),
                logo: LogoViewOptions(
                    position: .bottomLeading,
                    margins: CGPoint(x: 16, y: Self.ornamentBottomMargin)),
                attributionButton: AttributionButtonOptions(
                    position: .bottomTrailing,
                    margins: CGPoint(x: 14, y: Self.ornamentBottomMargin))
            ))
            // ProMotion: let the renderer run up to 120 Hz (floor 80) so rotate/tilt/pan
            // inertia is buttery on 120 Hz devices. `preferred: 120` targets the ceiling;
            // the SwiftUI facade maps this to `MapView.preferredFrameRateRange`.
            .frameRate(range: 80...120, preferred: 120)
            .onStyleLoaded { _ in
                recolorBasemap(proxy.map)
                clampPitch(proxy.map)
                // POILayer.install is GONE — Phase A retired the Mapbox clustered layer for
                // client-side clustering, so the POIs mount as view annotations instead.
                recomputeClusters(proxy.map)   // POIs may still be loading — pois-change reclusters
                model.markStyleLoaded()
            }
            // Re-apply once the map reports fully loaded. `onStyleLoaded` alone was a ONE-SHOT
            // application and it intermittently lost the race: a launch would occasionally
            // render a complete but UNRECOLOURED map — default Mapbox grey land, grey parks —
            // instead of the town's palette. (Caught by histogram, not by eye: the frame is
            // fully drawn, so it looks like a finished render, just the wrong one.)
            // `recolor` is pure `setLayerProperty` calls, so a second application is
            // idempotent and costs nothing when the first one already landed.
            .onMapLoaded { _ in BasemapPalette.recolor(proxy.map) }
            // If the basemap can't load (offline first run, bad token), treat the map
            // as "painted" so the loading cover lifts to reveal the map's own state
            // rather than hanging on a screen that will never finish.
            .onMapLoadingError { _ in model.markStyleLoaded() }
            // Name whatever town the map is panned over, shrink/expand pins to fit the
            // zoom (both debounced in the model — never the view's @State here), and
            // recluster on zoom steps / at idle so merges + splits glide.
            .onCameraChanged {
                model.updateTown(center: $0.cameraState.center)
                model.updateZoom($0.cameraState.zoom)
                scheduleClusterRecompute(zoom: $0.cameraState.zoom, map: proxy.map)
                // Feed the live heading to the compass. `update` only touches @Published when
                // bearing/pitch actually change, so a pure pan/zoom (bearing 0) doesn't churn
                // the compass every frame.
                compass.update(cameraState: $0.cameraState)
            }
            // Toggling the category filter ticks a selection haptic (spec §10 / §12.5 —
            // the native Menu supplies none we control). If the change hides the selected
            // spot, drop the stale selection so the tab-shell detail doesn't linger.
            .onChange(of: filter) { _, _ in
                Haptics.selection()
                if let s = selectedSpot, !filteredSpots.contains(where: { $0.id == s.id }) { closeCard() }
                // The filter changes both cluster membership and the shared label pass.
                recomputeClusters(proxy.map)
            }
            // Selection changes cluster membership immediately: the selected marker is
            // removed from its aggregate before the camera begins lifting toward it.
            .onChange(of: selectedClusterMarkerID) { _, _ in
                recomputeClusters(proxy.map)
            }
            // A live civic landmark is absorbed below the threshold, with liveness carried
            // by the cluster ring. Keep that aggregate status current without requiring a pan.
            .onChange(of: model.todayEvents) { _, _ in
                recomputeClusters(proxy.map)
            }
            .onChange(of: model.clockTick) { _, _ in
                recomputeClusters(proxy.map)
            }
            // POIs load async (once) after the style — recompute the layout when they land.
            .onChange(of: model.pois) { _, pois in
                recomputeClusters(proxy.map)
                #if DEBUG
                if mapDetail == nil, let poi = SJMapView.debugOpenPOI(in: pois) {
                    mapDetail = .poi(poi)
                    viewport = liftedViewport(poi.coordinate, zoom: Self.selectZoom)
                }
                // Kick the autozoom demo only ONCE the POIs exist (they load a few seconds
                // after launch) — otherwise the merge sweep would run over an empty map.
                if !pois.isEmpty { startAutozoomIfNeeded() }
                #endif
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Apply the shared static palette once after light-v11 finishes loading.
    private func recolorBasemap(_ map: MapboxMap?) {
        BasemapPalette.recolor(map)
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

    /// The town-name pill. Names whatever town the camera is over (reverse-geocoded);
    /// now TAPPABLE — a quick "take me back to Saint Joseph" that flies home when you've
    /// panned off over a neighboring town. The whole thing is one control, so the label
    /// spells the action out for VoiceOver.
    private var townPill: some View {
        Button {
            flyHome()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                Text(model.townLabel)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Hue.surface, in: Capsule())
            .overlay(Capsule().stroke(Hue.hairline, lineWidth: 1))
            .mapFloatShadow()
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(Motion.smooth, value: model.townLabel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.townLabel). Tap to return to Saint Joseph")
        .accessibilityAddTraits(.isButton)
    }

    private var composeButton: some View {
        Button {
            Haptics.light()
            if isAdmin { quickAdding = true } else { onCompose?() }
        } label: {
            chromeCircle(icon: "plus")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAdmin ? "Add an event" : "Open add menu")
    }

    // MARK: Floating controls — help (bottom-left) + recenter (bottom-right)

    private var floatingControls: some View {
        VStack(spacing: 12) {
            Spacer()
            // Compass rides in its OWN fixed 44pt slot directly above the recenter control, so
            // it can fade in/out as the map rotates without ever reflowing the help/recenter
            // row beneath it. Right-aligned to sit over recenter. Hidden (no reflow) at north.
            HStack {
                Spacer()
                MapCompass(heading: compass, reduceMotion: reduceMotion, onReset: resetNorth)
            }
            .frame(height: 44)
            HStack(alignment: .bottom) {
                helpButton
                Spacer()
                recenterButton
            }
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
            flyHome()   // §11: flyHome honors Reduce Motion (no fly, instant set)
        } label: {
            chromeCircle(icon: "location")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter map")
    }

    /// The shared chrome bubble — 44px circle, hairline, ink line icon.
    /// Active INVERTS to a solid ACCENT fill with a white icon — "active filter" is
    /// one of the brand's meaning-scoped accent seams, and a legible "filter is on"
    /// signal (a weight step alone isn't): a user who can't see the filter is active
    /// reads the hidden pins as missing data.
    private func chromeCircle(icon: String, active: Bool = false) -> some View {
        Circle()
            .fill(active ? Hue.accent : Hue.surface)
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(active ? Hue.accent : Hue.hairline, lineWidth: 1))
            .mapFloatShadow()
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 16, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? Hue.surface : Hue.ink)
            )
    }

    // MARK: Actions

    private func syncMapDetailHappenings() {
        guard let spot = selectedSpot else {
            mapDetailHappenings = []
            return
        }
        mapDetailHappenings = events(at: spot)
    }

    /// A camera viewport centered on `coord` with the compact morphed detail shell
    /// reserved as bottom padding. This replaces the old half-screen/medium-sheet lift:
    /// the pin stays comfortably above the actual element that now owns place detail.
    private func liftedViewport(_ coord: CLLocationCoordinate2D, zoom: CGFloat) -> Viewport {
        liftedCoord = coord
        var vp = Viewport.camera(center: coord, zoom: zoom)
        let lift = min(
            detailCameraReserve,
            max(160, containerH * 0.36)
        )
        vp.padding = EdgeInsets(top: 0, leading: 0, bottom: lift, trailing: 0)
        return vp
    }

    /// Drop the camera's bottom padding once nothing is selected, settling on the last-lifted
    /// spot with a plain (unpadded) camera — otherwise Mapbox keeps the ~half-screen inset and
    /// the map stays jammed to the top after the sheet collapses. Guarded so a civic→POI (or
    /// POI→civic) hand-off, which momentarily clears one selection, doesn't fight the new lift.
    private func releaseCameraLift() {
        guard mapDetail == nil, let c = liftedCoord else { return }
        liftedCoord = nil
        let settle = { viewport = .camera(center: c, zoom: Self.selectZoom) }   // zero padding
        if reduceMotion { settle() } else { withViewportAnimation(.easeInOut(duration: 0.35)) { settle() } }
    }

    /// Fly the camera home to Saint Joseph and dismiss any open detail. Clears `liftedCoord`
    /// FIRST: `closeCard()` nils the selection, which fires `.onChange` → `releaseCameraLift`
    /// on the next update — and that would re-target the pin that WAS open (at selectZoom),
    /// stomping this home fly. With `liftedCoord` already nil, `releaseCameraLift` no-ops and
    /// the home fly wins. Shared by the tappable town pill and the recenter control.
    private func flyHome() {
        Haptics.light()
        liftedCoord = nil
        closeCard()
        let home = { viewport = .camera(center: MapSpots.center, zoom: 13.5) }
        if reduceMotion { home() } else { withViewportAnimation(.fly(duration: 0.8)) { home() } }
    }

    /// Tap-compass action: ease the camera back to due north AND level (bearing 0, pitch 0),
    /// keeping the current center + zoom, over 0.4s easeOut. Once bearing reaches 0 the compass
    /// fades itself out (its visibility is adaptive on bearing). Honors Reduce Motion with an
    /// instant set. `compass.center/zoom` hold the last camera frame, so the map only rotates
    /// level — it doesn't recenter.
    private func resetNorth() {
        Haptics.light()
        let level = {
            viewport = .camera(center: compass.center, zoom: compass.zoom, bearing: 0, pitch: 0)
        }
        if reduceMotion { level() } else { withViewportAnimation(.easeOut(duration: 0.4)) { level() } }
    }

    /// Clamp the tilt gesture to 0–70° (past ~70° the horizon smears and labels pile up).
    /// Applied once on style load. `setCameraBounds` throws, so catch + log rather than a
    /// silent `try?` — the repo's 0-warning bar wants the intent explicit.
    private func clampPitch(_ map: MapboxMap?) {
        guard let map else { return }
        do {
            try map.setCameraBounds(with: CameraBoundsOptions(maxPitch: 70, minPitch: 0))
        } catch {
            print("[SJMapView] setCameraBounds(pitch 0–70) failed: \(error)")
        }
    }

    /// A Today/Places row tap: fly to the spot (a longer, deliberate 1.0s fly since the
    /// spot may be off-screen — spec §4 0.9–1.2s band) and open its detail in the
    /// morphing tab shell, landing the pin above that compact panel.
    private func focus(_ spot: Spot) {
        Haptics.light()
        let move = { viewport = liftedViewport(spot.coordinate, zoom: Self.selectZoom) }
        if reduceMotion { move() } else { withViewportAnimation(.fly(duration: 1.0)) { move() } }
        withAnimation(reduceMotion ? Motion.smooth : Motion.card) {
            mapDetail = .spot(spot)
        }
    }

    /// A direct pin tap: pop the selection (Motion.select) and, when ENTERING a selection,
    /// ease-recenter the pin above the detail in the same gesture (spec §12.2). Toggling the
    /// same pin off fires NO haptic and no recenter (spec §2 — deselect is silent).
    private func selectSpot(_ spot: Spot) {
        let entering = selectedSpot?.id != spot.id
        if entering { Haptics.light() }
        withAnimation(reduceMotion ? Motion.smooth : Motion.select) {
            mapDetail = entering ? .spot(spot) : nil
        }
        guard entering else { return }
        let move = { viewport = liftedViewport(spot.coordinate, zoom: Self.selectZoom) }
        if reduceMotion { move() }              // §11: instant set, no ease, under Reduce Motion
        else { withViewportAnimation(.easeInOut(duration: 0.45)) { move() } }
    }

    /// Open a tapped food/business POI's detail (resolved from the tapped feature's
    /// `id` property). The enum makes civic/POI mutually exclusive in one assignment,
    /// then eases the POI above the same compact tab-shell detail.
    private func selectPOI(id: String) {
        guard let poi = model.pois.first(where: { $0.id == id }) else { return }
        Haptics.light()
        withAnimation(reduceMotion ? Motion.smooth : Motion.card) {
            mapDetail = .poi(poi)
        }
        let move = { viewport = liftedViewport(poi.coordinate, zoom: Self.selectZoom) }
        if reduceMotion { move() } else { withViewportAnimation(.easeInOut(duration: 0.45)) { move() } }
    }

    /// A tapped cluster eases in (0.4s easeInOut — spec §7) to ~15.5, above the 14.5 awake
    /// threshold so the cluster splits into individual glyph markers. (clusterMaxZoom is 13,
    /// so this reliably breaks any cluster apart; easing to exact leaf bounds would need the
    /// async cluster-expansion-zoom API — a nicety not worth the async tap handler here.)
    private func zoomToCluster(_ coord: CLLocationCoordinate2D) {
        Haptics.light()
        let move = { viewport = .camera(center: coord, zoom: 15.5) }
        if reduceMotion { move() } else { withViewportAnimation(.easeInOut(duration: 0.4)) { move() } }
    }

    // Client-side POI clustering (recompute trigger, reclustering, bubble lifecycle) and
    // the DEBUG autozoom demo live in SJMapView+POIClustering.swift.

    private func closeCard() {
        guard mapDetail != nil else { return }
        withAnimation(reduceMotion ? Motion.smooth : Motion.card) {
            mapDetail = nil
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
            .fill(MarkerRole.liveRing.opacity(pulsing ? 0 : 0.35))
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
// selected: scale 1.25 (Motion.select), lifted marker shadow, always expanded.
// Motion:   wake = opacity 0→1 + scale 0.6→1.0 spring on first appear (Motion.select);
//           expand/shrink = Motion.card on diameter + icon/label crossfade; select bump =
//           Motion.select; tint change = Motion.smooth. Reduce Motion drops every
//           scale/spring to a simple opacity/colour crossfade (never removed — §11).

private struct MapPinBadge: View {
    let spot: Spot
    let base: PinDisplay      // rest | saved | live — the coloring (selection ignored)
    let selected: Bool
    let expanded: Bool        // zoom-driven (or forced by `selected`) — see SJMapView
    let showsLabel: Bool      // granted by the shared cluster-first collision pass
    let a11yLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private static let expandedDiameter: CGFloat = 28
    private static let compactDiameter: CGFloat = 14
    private static let iconSize: CGFloat = 13

    private var diameter: CGFloat { expanded ? Self.expandedDiameter : Self.compactDiameter }
    private var live: Bool  { base == .live }
    private var saved: Bool { base == .saved }
    private var labelVisible: Bool { expanded && showsLabel }
    /// Badge fill, routed through `MarkerRole` so the monochrome skin swaps in
    /// without branching here (see MonoMarkerPalette.swift).
    private var tint: Color { live ? MarkerRole.liveFill : MarkerRole.civicFill(spot.category) }

    var body: some View {
        badge
            .scaleEffect(appeared ? (selected && !reduceMotion ? 1.25 : 1.0) : (reduceMotion ? 1.0 : 0.6))
            // Selection pop (scale + the shadow lift below). Under Reduce Motion the scale
            // is suppressed above, but the shadow/label change still crossfades (Motion.smooth)
            // — meaning-carrying motion becomes a cross-fade, not nothing (§11).
            .animation(reduceMotion ? Motion.smooth : Motion.select, value: selected)
            // A spot going live/saved (a real event starting, a save toggled) crossfades
            // its tint instead of snapping — the annotation view persists across these
            // transitions (Mapbox reuses it by the spot's stable id), so without this the
            // color change would be the only unanimated state change on the badge. A colour
            // fade aids comprehension, so it stays under Reduce Motion too.
            .animation(Motion.smooth, value: base)
            // Shrink/expand — Motion.card so six pins settling to a new size on a pinch
            // feels like one physical move, not a snap. Reduce Motion still crossfades
            // (Motion.smooth + the opacity below), just without the size spring.
            .animation(reduceMotion ? Motion.smooth : Motion.card, value: expanded)
            // The name label attaches AFTER scaleEffect, as an overlay rather than a
            // ZStack sibling of the circle — so it (a) reads its position off badge's
            // un-scaled layout frame via `.overlay(alignment: .leading)` + leading
            // padding (a ZStack-centered frame + `.offset()` looks similar but is wrong:
            // the centering happens BEFORE the offset is applied, so the offset would
            // need to also account for the label's own width, which varies per name),
            // and (b) never grows 1.15x with the selected scale bump the way the circle
            // does — labels stayed a constant size in the pre-redesign badge too.
            .overlay(alignment: .leading) {
                HaloText(spot.name, color: MarkerRole.label(base: tint))
                    .frame(width: 100, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Self.expandedDiameter + 6)
                    .allowsHitTesting(false)
                    // Never animate in from scale(0) — a barely-visible starting shape
                    // reads as natural, a point-source doesn't (emil-design-eng).
                    .scaleEffect(reduceMotion ? 1 : (labelVisible ? 1 : 0.9), anchor: .leading)
                    .opacity(labelVisible ? 1 : 0)
            }
            .animation(Motion.smooth, value: showsLabel)
            .opacity(appeared ? 1 : (reduceMotion ? 1 : 0))
            // Enlarge the invisible tap target to Apple's ≥44×44pt HIG minimum
            // regardless of the current visual size — centered the same as the
            // visual circle, so the annotation's map-coordinate anchor doesn't move.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .onAppear {
                withAnimation(reduceMotion ? Motion.smooth : Motion.select) {
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

            // STATIC live ring. The pulse alone cannot carry "happening now" for three
            // separate reasons: it is suppressed while selected; Reduce Motion renders it
            // as a same-size disc fully occluded by the opaque badge above; and in any
            // still frame it may be caught mid-cycle at zero opacity. Coral used to be the
            // real signal — without it a Reduce Motion user could not tell a live spot from
            // a dormant one at all. This ring is GEOMETRY, not colour, so it survives every
            // one of those cases, and it is deliberately NOT gated on `expanded`: a compact
            // dot is exactly where a glanceable live cue matters most.
            //
            // Routed through MarkerRole so the pending accent colour (live events are on its
            // shortlist) lands in ONE place rather than here.
            if live {
                Circle()
                    .stroke(MarkerRole.liveStaticRing, lineWidth: 2)
                    .frame(width: diameter + 7, height: diameter + 7)
            }

            Circle()
                .fill(tint)
                .frame(width: diameter, height: diameter)
                .mapMarkerShadow(selected: selected)   // tighter than a button; lifts on select (§8)
                // Civic pins are ink-filled (dark), so the keyline stays the white lift —
                // `isLightFill: false`. Routed through MarkerRole so the skin owns the value.
                .overlay(Circle().stroke(MarkerRole.pinStroke(isLightFill: false), lineWidth: 1.5))

            Image(systemName: spot.category.filledSymbol)
                .font(.system(size: Self.iconSize, weight: .semibold))
                .foregroundStyle(MarkerRole.civicGlyph)
                .opacity(expanded ? 1 : 0)   // too cramped on a 14pt compact dot

            if saved {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(MarkerRole.savedGlyph)
                    .frame(width: 12, height: 12)
                    .background(Circle().fill(MarkerRole.savedBadgeFill))
                    .overlay(Circle().stroke(MarkerRole.savedBadgeStroke, lineWidth: 1))
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
                label.foregroundStyle(MarkerRole.labelHalo).offset(x: o.0, y: o.1)
            }
            label.foregroundStyle(color)
        }
    }

    private var label: some View {
        Text(text)
            .font(.sansSemibold(12))   // spec §9: marker label is semibold, not bold
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }
}

// MARK: - Selected POI marker (on-map overlay for a tapped food/business POI)
//
// The POIs live in a clustered Mapbox style layer (POILayer); rather than wire
// clustered-source feature-state + promoteId for a selected size bump, the tapped POI
// gets a SwiftUI annotation overlaid at its coordinate — the same approach the civic
// pins use for selection. Spec §2: scale to ~1.25, a lifted marker shadow, and a soft
// halo faded in beneath it. Reduce Motion drops the pop to a plain fade.

private struct POISelectedMarker: View {
    let poi: POI
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @ObservedObject private var logoCache = POILogoCache.shared

    var body: some View {
        // A resolved brand logo swaps the fill to the light tier (a mark can't sit on
        // mid grey); ring, halo and lifted shadow keep carrying the selection emphasis.
        let hasLogo = logoCache.resolvedImage(for: poi) != nil
        ZStack {
            // Halo — a soft family-tinted disc that reads as elevation under the marker.
            Circle()
                .fill(MarkerRole.selectedPOIHalo(poi.family).opacity(0.22))
                .frame(width: 54, height: 54)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)

            // The enlarged badge — 34pt, sized to match a SELECTED CIVIC pin (28pt × 1.25 ≈ 35pt)
            // for on-map parity, rather than 1.25× the POI's own ~20pt awake dot; white-ringed,
            // lifted shadow. The halo carries the extra emphasis a bare 1.25× wouldn't.
            Circle()
                .fill(hasLogo ? MarkerRole.selectedPOILogoFill : MarkerRole.selectedPOIFill(poi.family))
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(MarkerRole.pinStroke(isLightFill: hasLogo), lineWidth: 2))
                .mapMarkerShadow(selected: true)

            Image(systemName: poi.glyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MarkerRole.selectedPOIGlyph)

            POILogoCircle(poi: poi, diameter: 31)
        }
        .frame(width: 54, height: 54)
        // Never animate in from a point-source — start just under full size (emil-design-eng).
        .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(Motion.select) { appeared = true } }
        }
        // Taps are handled by the underlying POI style layer + the map's tap interaction.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
