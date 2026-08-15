//
//  SJMapView.swift
//  Block Party — Mapbox map of Saint Joseph, Minnesota.
//
//  Life360-style layout: floating top chrome (help "?" top-left · town pill ·
//  search top-right, with the filter chip row beneath — MapFilterChips, map
//  polish Phase 4), one static warm basemap (BasemapPalette — no time/season/
//  weather modulation), a persistent draggable bottom sheet (MapSheet), and
//  coral reserved for live indicators + primary/tappable elements. Soft paper
//  edge fades top and bottom seat the chrome (round 2); recenter floats alone
//  bottom-right. The map has NO compose entry — event creation lives on the
//  other tabs (round 2, Jesse's call; QuickAddSheet deleted with it).
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
// `@_spi(Restricted)`: the ONE restricted symbol used is `LogoViewOptions.visibility`,
// which hides the Mapbox wordmark (Jesse's 2026-08-14 call — see ornament notes below).
@_spi(Restricted) import MapboxMaps

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
            // The detail sheet's CATEGORY pill wants the specific subtype
            // ("Coffee Shop"), not the broad family word; fall back to the
            // family when Google supplied no primaryType.
            if let t = poi.primaryType, !t.isEmpty {
                return t.replacingOccurrences(of: "_", with: " ").capitalized
            }
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

// The map's filter (the chip row under the town pill) lives in
// MapFilterChips.swift — `MapFilter` spans both catalogs (civic spots + POIs).

// MARK: - Main view

struct SJMapView: View {
    /// The source of truth lives in MainTabsView so the shell can hide the tab
    /// bar under the detail sheet and clear the selection on a tab change.
    @Binding var mapDetail: MapPlaceDetail?
    /// Real happenings for the selected civic spot, matched from this view's
    /// `MapModel` and fed to the detail sheet. Always empty for POIs or no
    /// selection. Local state now — the tab shell no longer renders detail.
    @State private var mapDetailHappenings: [TimelineEvent] = []
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase
    /// Container-level Reduce Motion (the self-contained pin animations read their own;
    /// this one gates the camera flys + the card/selection springs — spec §11 / §12.6).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Not `private`: the POI-clustering + autozoom methods in SJMapView+POIClustering.swift
    // read `model` and drive `viewport`, and Swift `private` is file-scoped.
    @StateObject var model = MapModel()

    /// Latest laid-out map height, so a pin-select can reserve the detail sheet
    /// as camera padding and land the pin above it. Updated off the layout pass.
    @State private var containerH: CGFloat = 0
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
    /// The chip row's selection (MapFilterChips). Survives camera moves by
    /// construction — nothing camera-driven ever writes it.
    @State private var filter = MapFilter.initial()

    // MARK: Search state (map polish Phase 2 — the top-right chrome slot)

    /// Whether the magnifier has expanded into the search field. Not `private`:
    /// `chromeRects` (SJMapView+POIClustering.swift) reads it to reserve the
    /// expanded band so pin labels never draw under active search UI.
    @State var searchActive = false
    /// The top chrome's bottom edge (field + results panel) in the map's own
    /// coordinate space, measured live. Read by `chromeRects` while search is up.
    @State var searchChromeBottom: CGFloat = 0
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool
    /// One-shot user position for search-row distances. Nil (denied, unavailable,
    /// fix failed) simply renders no distance — no nagging, no error state.
    @State private var userLocation: CLLocation?
    /// Guards concurrent fetches. The permission ask itself lands on the FIRST
    /// search expansion; iOS shows the system alert only once per install, so
    /// re-running on a later expansion resolves instantly from the decided status.
    @State private var locatingUser = false

    /// Names the map container's coordinate space, so the chrome measurement and
    /// the label pass's reservations agree on an origin.
    static let mapSpaceName = "SJMapView.container"

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Client-side matches over what the map already holds — no network.
    private var searchResults: [MapSearchResult] {
        MapSearch.results(query: trimmedSearchQuery,
                          spots: MapSpots.all,
                          pois: model.pois,
                          events: model.todayEvents,
                          spotFor: { spot(for: $0) })
    }

    // MARK: Client-side POI clustering (replaces the retired POILayer)
    //
    // The chip-filtered POIs (`filteredPOIs` — all 52 on the All chip) mount as view
    // annotations (POIClusterMarker); this state is
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

    /// DEBUG-only: `-map-open-poi [name-substring | id]` opens a POI's detail
    /// sheet once `places` loads. With no value, it deterministically uses the first
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

    #if DEBUG
    /// DEBUG-only: `-town-rain` fires one town-rain burst once the POIs land, so the
    /// drop can be screen-recorded headlessly — there is no tap automation in this
    /// setup, and the press that normally starts it is a real touch on the town pill.
    static let debugTownRain = ProcessInfo.processInfo.arguments.contains("-town-rain")

    /// Long enough for the logo prefetch to have filled the cache after `pois` land.
    private static let debugRainDelay: TimeInterval = 1.2

    /// DEBUG-only search drivers (mirrors the -explore-search family):
    /// `-map-search-open` expands the search field on appear (keyboard up);
    /// `-map-search <query>` also types the query so the results list renders;
    /// `-map-search-committed <query>` programmatically commits the FIRST result —
    /// fly + pin open — for headless verification of the result-tap path.
    static let debugSearchOpen = ProcessInfo.processInfo.arguments.contains("-map-search-open")

    static func debugSearchQuery() -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-map-search"), i + 1 < a.count,
              !a[i + 1].hasPrefix("-") else { return nil }
        return a[i + 1]
    }

    static func debugSearchCommitted() -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-map-search-committed"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    #endif

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

    @State private var showingHelp = false
    /// Browse state lives above the conditionally mounted sheet so a place-detail
    /// interlude cannot reset the user's chosen face or detent.
    @State private var browseMode = MapSheet.initialMode()
    @State private var browseDetent = MapSheet.initialDetent()
    /// How far the bottom sheet has grown past its peek (0 = collapsed, 1 = at/above
    /// medium), published by `MapSheet` via `SheetExpansionKey`. Drives the fade-out of
    /// the floating compass/recenter controls (bottom-right — the "?" lives in the
    /// top-left chrome) so they never collide with the rising sheet.
    @State private var sheetExpansion: CGFloat = 0

    /// Bumped by `flyHome()`; every change drops one burst of town-rain. An Int rather
    /// than a Bool so back-to-back presses each start a fresh burst.
    @State private var rainTrigger = 0

    /// The map sheet's live top edge — the surface the town rain lands on. `.infinity`
    /// until the sheet publishes, which the field reads as "use the resting floor".
    @State private var sheetTop: CGFloat = .infinity

    /// Bumped on each town-pill press; drives the bubble that blooms out of the pill.
    @State private var bubbleNonce = 0
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

    /// Bottom margin (from the map's bottom edge) for the Mapbox ⓘ attribution
    /// button — an 8pt sliver above the collapsed glass, as low as it can sit while
    /// still resting ABOVE the peek sheet rather than hidden behind it (the
    /// expanding sheet occludes it; it's clearly visible at the collapsed rest,
    /// tucked under the bottom edge fade). The wordmark LOGO is hidden outright —
    /// Jesse's explicit 2026-08-14 decision (map polish round 2), superseding the
    /// earlier "repositioned but not removed" stance: Mapbox's ToS wants the logo
    /// visible and its `visibility` is an SPI-restricted knob, and Jesse accepted
    /// that risk (recorded in plans/2026-08-14-map-polish-round-2.md). The ⓘ stays:
    /// it is legally required attribution and carries the telemetry opt-out.
    private static let ornamentBottomMargin: CGFloat =
        MapSheet.tabBarReserve + MapSheet.peekHeight + 8

    /// The hidden-wordmark options (see `ornamentBottomMargin`'s note — Jesse's
    /// 2026-08-14 call). `visibility` is not part of the public initializer, so
    /// it's set on a mutable copy.
    private static var hiddenLogoOptions: LogoViewOptions {
        var options = LogoViewOptions()
        options.visibility = .hidden
        return options
    }

    /// Not `private`: the shared cluster + label pass consumes this exact filtered set.
    /// Events resolves through the same today/live rule the pins use (`events(at:)`
    /// + `isLive`, DEBUG forces included); Saved reads the shared device-local store.
    var filteredSpots: [Spot] {
        MapSpots.all.filter {
            filter.includesSpot(category: $0.category,
                                hasEventToday: !events(at: $0).isEmpty || isLive($0),
                                isSaved: isSavedSpot($0))
        }
    }

    /// The POIs the chip row leaves visible — the exact set that mounts as
    /// annotations AND feeds `recomputeClusters`, so the cluster bubbles recount
    /// to the filtered map. Not `private`: the clustering extension reads it.
    var filteredPOIs: [POI] {
        model.pois.filter { filter.includesPOI(family: $0.family, isSaved: isSavedPOI($0)) }
    }

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

    /// Whether the viewer has saved this POI — the same store the detail sheet's
    /// bookmark toggles (`detail.saveID` is the POI id), same DEBUG force.
    private func isSavedPOI(_ poi: POI) -> Bool {
        #if DEBUG
        if Self.debugSavedIds().contains(poi.id) { return true }
        #endif
        return saved.isSaved(poi.id)
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            // While a pin's detail sheet is up, the map dims slightly — a wash
            // that keeps the basemap legible (subtle, not modal-dark), matching
            // Flighty. Plain black, not `Hue.ink`: the canvas is light in both
            // appearances. Non-interactive, so map taps still dismiss the sheet.
            if mapDetail != nil {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            mapBottomFade
            mapTopFade
            topChrome
            // UNMOUNTED (not faded) under the detail sheet: these are glass
            // circles, and extracted glass ignores an ancestor's `.opacity` —
            // they would ghost through the card.
            if mapDetail == nil {
                floatingControls
                    .transition(.opacity)
            }
            // Pressing "Saint Joseph" (or recenter) rains the town's own brand marks
            // past the chrome. Sits UNDER the sheet on purpose: the balls' floor is
            // the sheet's peek edge, so at peek they bounce on its visible top, and a
            // raised sheet simply hides them instead of letting them bounce over its
            // content. Non-interactive, so it never intercepts a map gesture.
            TownRainField(trigger: rainTrigger, pois: model.pois, floorY: sheetTop)
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
            // The Flighty-anatomy pin detail sheet (map polish Phase 3). It
            // supersedes the retired tab-bar glass morph; the tab bar hides
            // while it is up (MainTabsView), so the card owns the bottom zone.
            if let detail = mapDetail {
                PinDetailSheet(
                    detail: detail,
                    happenings: mapDetailHappenings,
                    isLive: detail.spot.map(isLive) ?? false,
                    distanceLabel: detailDistanceLabel(detail),
                    height: detailSheetHeight,
                    onClose: { closeCard() }
                )
                // Fresh @State (open-now, drag, full-details) per place — a
                // civic→POI hand-off must not inherit the previous card's state.
                .id(detail.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                // The card sits on the physical bottom edge; its own bottom
                // padding floats the action bar above the home indicator.
                .ignoresSafeArea(edges: .bottom)
                .transition(reduceMotion
                    ? .opacity
                    : .move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        // Name the container's space so the top chrome can measure its own bottom
        // edge in the same coordinates `chromeRects` reserves in.
        .coordinateSpace(name: Self.mapSpaceName)
        // The search field must not shove the map / sheet / chrome upward when the
        // keyboard rises — the field sits at the TOP, and the results panel is
        // height-capped to stay clear of the keyboard on its own. Collapsing the
        // search must restore the chrome exactly, so nothing here ever moves.
        .ignoresSafeArea(.keyboard)
        // Track the map's HEIGHT (a pin-select lifts the pin above the detail sheet) and its full
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
        .onPreferenceChange(SheetTopKey.self) { sheetTop = $0 }
        .onAppear {
            model.start(auth: auth)
            Haptics.prepare()
            #if DEBUG
            // `-town-rain`: play the town-pill press headlessly — bubble AND drop —
            // because there is no tap automation here. Fired on appear rather than on
            // `pois` landing: signed out, `pois` never lands, and the bubble is worth
            // recording even when there is nothing to rain.
            if SJMapView.debugTownRain {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.debugRainDelay) {
                    bubbleNonce += 1
                    rainTrigger += 1
                }
            }
            // `-map-search…`: drive the search chrome headlessly.
            if SJMapView.debugSearchOpen || SJMapView.debugSearchQuery() != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    expandSearch()
                    if let q = SJMapView.debugSearchQuery() { searchQuery = q }
                }
            }
            if let q = SJMapView.debugSearchCommitted() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    searchQuery = q
                    debugCommitSearch(attempts: 8)
                }
            }
            #endif
            syncMapDetailHappenings()
            if mapDetail != nil { fetchLocationIfAuthorized() }
            // A spot preselected at mount (deep link, or the DEBUG -map-open flag) frames
            // above the detail sheet, exactly as a direct pin tap would. Deferred one
            // runloop so `containerH` has been measured — the lift is proportional now.
            if let s = selectedSpot {
                DispatchQueue.main.async {
                    viewport = liftedViewport(s.coordinate, zoom: Self.selectZoom)
                }
            }
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
        .onChange(of: mapDetail?.id) { _, id in
            syncMapDetailHappenings()
            // The sheet's DISTANCE pill: read an existing fix or take one
            // silently. Never prompts (see fetchLocationIfAuthorized).
            if id != nil { fetchLocationIfAuthorized() }
        }
        .onChange(of: model.todayEvents) { _, _ in syncMapDetailHappenings() }
        // A tapped POI or civic pin opens the PinDetailSheet card mounted above —
        // the one detail presentation shared by both catalogs (Phase 3).
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
                // cluster zooms in to split. Only the chip row's filtered set mounts —
                // the same set recomputeClusters counts, so pins and bubbles agree.
                ForEvery(filteredPOIs) { poi in
                    let markerID = ClusterMarkerID.poi(poi.id)
                    let isSelected = selectedClusterMarkerID == markerID
                    // While any detail is open, every OTHER pin calms down (its
                    // label drops) so the selected pin owns the moment (Phase 5).
                    let calmed = mapDetail != nil && !isSelected
                    MapViewAnnotation(coordinate: poi.coordinate) {
                        POIClusterMarker(
                            poi: poi,
                            assignment: markerAssignments[markerID]
                                ?? POIAssignment(anchor: poi.coordinate, clustered: false),
                            expanded: model.pinsExpanded,
                            selected: isSelected,
                            showsLabel: model.pinsExpanded && !calmed
                                && labelledMarkers.contains(markerID),
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
                    // While any detail is open, every OTHER pin calms down (label
                    // drops, live pulse rests — static ring stays) — Phase 5.
                    let calmed = mapDetail != nil && !isSelected
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
                                calmed: calmed,
                                expanded: isSelected || model.pinsExpanded,
                                showsLabel: model.pinsExpanded && !calmed
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
            // Ornaments: wordmark hidden, ⓘ attribution kept and lifted to just above
            // the collapsed unified glass so it's never clipped into a sliver behind
            // the bottom bar (Jesse's 2026-08-14 wordmark call — see
            // `ornamentBottomMargin`'s note). The scale bar stays hidden (it was
            // never wanted on this civic map). This is a Map-specific modifier, so it
            // must precede the standard .onChange modifiers below (those erase the
            // concrete Map type).
            .ornamentOptions(OrnamentOptions(
                scaleBar: ScaleBarViewOptions(visibility: .hidden),
                // Suppress the built-in compass: its needle is coral (the monochrome brand
                // deletes that hue) and its 0.3s fade / bearing-only tap aren't the spec. Our
                // own `MapCompass` overlay replaces it (adaptive, 0.25s fade, resets bearing
                // AND pitch). Without this the SDK's default `.adaptive` compass would surface
                // at top-trailing the moment rotation is enabled.
                compass: CompassViewOptions(visibility: .hidden),
                logo: Self.hiddenLogoOptions,
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
            // A chip change ticks a selection haptic. If it hides the place whose
            // detail is open (civic or POI), the stale selection drops so the sheet
            // doesn't linger over a pin that's gone.
            .onChange(of: filter) { _, _ in
                Haptics.selection()
                dismissDetailIfFiltered()
                // The filter changes both cluster membership and the shared label pass.
                recomputeClusters(proxy.map)
            }
            // Saving/unsaving changes Saved-chip membership live (the detail
            // sheet's bookmark is tappable while the chip is active) — recount
            // and drop a now-hidden detail. A no-op on every other chip.
            .onChange(of: saved.ids) { _, _ in
                guard filter == .saved else { return }
                dismissDetailIfFiltered()
                recomputeClusters(proxy.map)
            }
            // Selection changes cluster membership immediately: the selected marker is
            // removed from its aggregate before the camera begins lifting toward it.
            .onChange(of: selectedClusterMarkerID) { _, _ in
                recomputeClusters(proxy.map)
            }
            // A live civic landmark is absorbed below the threshold, with liveness carried
            // by the cluster ring. Keep that aggregate status current without requiring a pan.
            // Both changes can also flip Events-chip membership (an event landing, ending,
            // or expiring past the live window) — drop a detail the chip no longer shows,
            // exactly as a chip change would, so the card can't linger over a vanished pin.
            .onChange(of: model.todayEvents) { _, _ in
                dismissDetailIfFiltered()
                recomputeClusters(proxy.map)
            }
            .onChange(of: model.clockTick) { _, _ in
                dismissDetailIfFiltered()
                recomputeClusters(proxy.map)
            }
            // The top chrome (chip row at rest; expanded search field + results
            // panel while active) reserves a measured top band in the label pass
            // (`chromeRects`) — recompute when it appears, grows, or collapses,
            // so no pin label draws under chrome.
            .onChange(of: searchActive) { _, _ in
                recomputeClusters(proxy.map)
            }
            .onChange(of: searchChromeBottom) { _, _ in
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

    // MARK: Top chrome — help "?" · town pill · search, with the chip row beneath

    private var topChrome: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // The "?" and town pill fade out while search is active (Q8) and
                // are restored on collapse — both are untouched at rest.
                if !searchActive {
                    // The "?" moved up here from the bottom stack (round 2, Jesse):
                    // it mirrors the trailing 44pt search circle, so it also keeps
                    // the town pill screen-centered — the slot the retired
                    // SpotFilter Menu held (a clear balancer since Phase 4).
                    helpButton
                        .transition(.opacity)
                    Spacer(minLength: 8)
                    townPill
                        .transition(.opacity)
                    Spacer(minLength: 8)
                }
                searchControl
            }
            .padding(.horizontal, 16)
            // The filter chip row (map polish Phase 4), under the pill. It fades
            // with the pill while search is active, so the results panel lands
            // directly beneath the field.
            if !searchActive {
                MapFilterChips(selection: $filter)
                    .transition(.opacity)
            }
            if searchActive && !trimmedSearchQuery.isEmpty {
                MapSearchResultsPanel(
                    results: searchResults,
                    emptyText: MapSearch.emptySentence(town: model.townLabel),
                    distanceFor: { searchDistanceLabel($0) },
                    onPick: { commitSearchResult($0) }
                )
                .padding(.horizontal, 16)
                .transition(.opacity)
            }
        }
        .padding(.top, 8)
        .animation(Motion.smooth, value: trimmedSearchQuery.isEmpty)
        // Measure the chrome's bottom edge (field + results panel) so the label
        // pass can reserve the whole active-search band — see `chromeRects`.
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { searchChromeBottom = g.frame(in: .named(Self.mapSpaceName)).maxY }
                    .onChange(of: g.frame(in: .named(Self.mapSpaceName)).maxY) { _, y in
                        searchChromeBottom = y
                    }
            }
        )
    }

    /// GOAL A — the top-right chrome slot: a magnifier at rest, spring-expanding
    /// into a glass search field on the SAME chrome material, so the circle
    /// visibly becomes the field. The "X" collapses it back to the icon and
    /// clears the query. The "?" and pill fade while it's expanded, so the field
    /// owns the full row width.
    private var searchControl: some View {
        HStack(spacing: 6) {
            Button {
                expandSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Hue.ink)
                    .frame(width: searchActive ? 30 : 44, height: 44)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!searchActive)
            .accessibilityLabel("Search places and events")

            if searchActive {
                TextField("Search places and events", text: $searchQuery)
                    .font(.sans(15))
                    .foregroundStyle(Hue.ink)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { commitFirstSearchResult() }
                    .transition(.opacity)

                Button {
                    collapseSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Hue.inkSecondary)
                        .frame(width: 34, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
                .transition(.opacity)
            }
        }
        .padding(.leading, searchActive ? 8 : 0)
        .padding(.trailing, searchActive ? 4 : 0)
        .frame(maxWidth: searchActive ? .infinity : 44)
        // A 44pt-high capsule at width 44 IS the chromeCircle recipe — same glass,
        // same ink icon — so the rest state matches its chrome siblings exactly.
        .glassEffect(.regular, in: Capsule())
    }

    /// The town-name pill. Names whatever town the camera is over (reverse-geocoded);
    /// now TAPPABLE — a quick "take me back to Saint Joseph" that flies home when you've
    /// panned off over a neighboring town. The whole thing is one control, so the label
    /// spells the action out for VoiceOver.
    private var townPill: some View {
        Button {
            bubbleNonce += 1        // acknowledge the press at the instant of the tap
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
            // Liquid Glass, the same material as the sheet + tab bar, so the map's
            // chrome reads as one system. Glass carries its own floating shadow.
            .glassEffect(.regular, in: Capsule())
            .contentShape(Capsule())
            .townPillBubble(nonce: bubbleNonce)
        }
        .buttonStyle(.plain)
        .animation(Motion.smooth, value: model.townLabel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.townLabel). Tap to return to Saint Joseph.")
        .accessibilityAddTraits(.isButton)
    }

    /// A soft frosted dissolve over the map's bottom band. Every other tab sits over
    /// the calm canvas, but the map is a busy backdrop — without this, map detail
    /// bleeds through the floating glass tab bar and shows in the strip beneath it.
    /// Two layers on one top→bottom mask:
    ///   1. `.ultraThinMaterial` — the same material language as the glass chrome —
    ///      blurs the live map (labels/roads/pins) into softness color-agnostically,
    ///      so it reads right over land, water AND parks.
    ///   2. a paper wash (`Hue.paper`, the basemap's own land tone) — a bare material
    ///      goes cold-grey over the warm map, so this keeps the frost warm and seals
    ///      the home-indicator strip.
    /// A dissolve (invisible top → present at the bottom), never a bar.
    /// Non-interactive; taps pass through to the map.
    private var mapBottomFade: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear,               location: 0.0),
                            .init(color: .black.opacity(0.85), location: 0.72),
                            .init(color: .black,               location: 1.0),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            LinearGradient(
                stops: [
                    .init(color: Hue.paper.opacity(0),    location: 0.0),
                    .init(color: Hue.paper.opacity(0.32), location: 0.55),
                    .init(color: Hue.paper.opacity(0.82), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(height: 172)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }

    /// The top twin of `mapBottomFade` (round 2, Jesse's edge-fade ask): a soft
    /// paper wash from the physical top edge dying out through the pill row, so the
    /// status bar and floating chrome sit on a gently faded edge (Apple Maps /
    /// Subway store-finder read) instead of raw cartography. Colour only — no
    /// material: pin labels legitimately pass under this band (it is NOT chrome and
    /// deliberately joins no `chromeRects`), and a blur would smear them where a
    /// light wash keeps them readable. `Hue.paper` is dynamic, so dark mode fades
    /// to the dark page exactly like the bottom band. Non-interactive.
    private var mapTopFade: some View {
        LinearGradient(
            stops: [
                .init(color: Hue.paper.opacity(0.85), location: 0.0),
                .init(color: Hue.paper.opacity(0.45), location: 0.4),
                .init(color: Hue.paper.opacity(0),    location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 150)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    // MARK: Floating controls — compass + recenter (bottom-right)

    private var floatingControls: some View {
        VStack(spacing: 12) {
            Spacer()
            // Compass rides in its OWN fixed 44pt slot above recenter, so it can
            // fade in/out as the map rotates without ever reflowing the control
            // beneath it. Right-aligned to sit over the column. Hidden (no
            // reflow) at north.
            HStack {
                Spacer()
                MapCompass(heading: compass, reduceMotion: reduceMotion, onReset: resetNorth)
            }
            .frame(height: 44)
            HStack {
                Spacer()
                recenterButton
            }
        }
        .padding(.horizontal, 16)
        // Stack ABOVE the map's ⓘ attribution (which sits just above the collapsed
        // glass) so the two never collide; fade + lift out of the way as the sheet
        // grows so they never collide with it either.
        .padding(.bottom, MapSheet.tabBarReserve + MapSheet.peekHeight + 96)
        .offset(y: -sheetExpansion * 10)
        .opacity(Double(1 - min(1, sheetExpansion * 1.3)))
        .allowsHitTesting(sheetExpansion < 0.12)
        .animation(.easeOut(duration: 0.18), value: sheetExpansion)
    }

    /// The "?" — reopens the map intro. Lives in the top-left chrome slot (round 2,
    /// Jesse's call), mirroring the top-right search circle.
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

    /// The shared chrome bubble — 44px circle, ink line icon, real Liquid Glass
    /// (the SAME material as the sheet + tab bar, so the map's controls read as
    /// one system; glass carries its own floating shadow). The old solid-accent
    /// "active filter" variant left with the SpotFilter Menu — an active filter
    /// now reads off the chip row itself (the ink-filled chip).
    private func chromeCircle(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Hue.ink)
            .frame(width: 44, height: 44)
            .glassEffect(.regular, in: Circle())
    }

    // MARK: Actions

    private func syncMapDetailHappenings() {
        guard let spot = selectedSpot else {
            mapDetailHappenings = []
            return
        }
        mapDetailHappenings = events(at: spot)
    }

    /// A camera viewport centered on `coord` with the detail sheet's zone reserved
    /// as bottom padding, so the selected pin lands centered in the visible strip
    /// of map ABOVE the card rather than hiding behind it. The reserve tracks the
    /// sheet's own proportional height (the 180 floor covers the first frame,
    /// before `containerH` is measured).
    private func liftedViewport(_ coord: CLLocationCoordinate2D, zoom: CGFloat) -> Viewport {
        liftedCoord = coord
        var vp = Viewport.camera(center: coord, zoom: zoom)
        let lift = max(180, containerH * PinDetailSheet.heightFraction)
        vp.padding = EdgeInsets(top: 0, leading: 0, bottom: lift, trailing: 0)
        return vp
    }

    /// The compact detail card's height — `PinDetailSheet.heightFraction` of the
    /// map (Flighty proportions), with a floor for the pre-measurement frame.
    private var detailSheetHeight: CGFloat {
        max(360, (containerH > 0 ? containerH : 720) * PinDetailSheet.heightFraction)
    }

    /// "0.3 mi" from the user's one-shot fix to the open place — nil without a
    /// fix, and the sheet's DISTANCE pill simply doesn't render.
    private func detailDistanceLabel(_ detail: MapPlaceDetail) -> String? {
        guard let userLocation else { return nil }
        let pin = CLLocation(latitude: detail.coordinate.latitude,
                             longitude: detail.coordinate.longitude)
        return MapDistance.label(meters: pin.distance(from: userLocation))
    }

    /// Take a location fix for the detail sheet's DISTANCE pill — but only when
    /// access is ALREADY authorized. It never prompts: the when-in-use ask
    /// deliberately lives on the first search expansion (Phase 2), so opening a
    /// pin can't interrupt the moment with a system alert.
    private func fetchLocationIfAuthorized() {
        guard userLocation == nil, !locatingUser, LocationPermission.isAuthorized else { return }
        locatingUser = true
        Task {
            userLocation = await UserLocation.oneShot()
            locatingUser = false
        }
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
        rainTrigger += 1        // the town's brand marks drop while the camera flies
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
    /// spot may be off-screen — spec §4 0.9–1.2s band) and open its detail sheet,
    /// landing the pin above the card.
    private func focus(_ spot: Spot) {
        Haptics.light()
        let move = { viewport = liftedViewport(spot.coordinate, zoom: Self.selectZoom) }
        if reduceMotion { move() } else { withViewportAnimation(.fly(duration: 1.0)) { move() } }
        withAnimation(reduceMotion ? Motion.smooth : Motion.card) {
            mapDetail = .spot(spot)
        }
    }

    /// A direct pin tap: pop the selection (Motion.select) and, when ENTERING a selection,
    /// EASE the camera toward the pin — offset upward so it stays visible above the
    /// sheet (spec: easeOut, never a fly, for the on-open move). Toggling the
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
        else { withViewportAnimation(.easeOut(duration: 0.5)) { move() } }
    }

    /// Open a tapped food/business POI's detail (resolved from the tapped feature's
    /// `id` property). The enum makes civic/POI mutually exclusive in one assignment,
    /// then eases the POI above the shared detail sheet (easeOut, matching selectSpot).
    private func selectPOI(id: String) {
        guard let poi = model.pois.first(where: { $0.id == id }) else { return }
        Haptics.light()
        withAnimation(reduceMotion ? Motion.smooth : Motion.card) {
            mapDetail = .poi(poi)
        }
        let move = { viewport = liftedViewport(poi.coordinate, zoom: Self.selectZoom) }
        if reduceMotion { move() } else { withViewportAnimation(.easeOut(duration: 0.5)) { move() } }
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

    // MARK: Search actions (map polish Phase 2)

    /// Expand the magnifier into the field: spring width, keyboard up, focused.
    /// The FIRST expansion is also where the when-in-use permission ask lands.
    private func expandSearch() {
        guard !searchActive else { return }
        Haptics.light()
        withAnimation(reduceMotion ? Motion.smooth : Motion.card) { searchActive = true }
        // Focus once the field is mounted — a same-transaction focus can be dropped.
        DispatchQueue.main.async { searchFocused = true }
        fetchUserLocationIfNeeded()
    }

    /// The "X" (and a committed result): collapse back to the icon, clear the
    /// query, drop the keyboard. The town pill fades back in with the collapse.
    private func collapseSearch() {
        searchFocused = false
        searchQuery = ""
        withAnimation(reduceMotion ? Motion.smooth : Motion.card) { searchActive = false }
    }

    /// One-shot: ask for when-in-use access (a real prompt only the very first
    /// time — see LocationPermission.request) and take a single position fix.
    /// Denied / unavailable leaves `userLocation` nil and distances just don't
    /// render; nothing retries in a loop, nothing nags.
    private func fetchUserLocationIfNeeded() {
        guard userLocation == nil, !locatingUser else { return }
        locatingUser = true
        Task {
            if await LocationPermission.request() {
                userLocation = await UserLocation.oneShot()
            }
            locatingUser = false
        }
    }

    /// Distance from the user's one-shot fix to a result's pin — nil without a
    /// fix or for an event with no pin. Same formatter as the detail sheet's
    /// DISTANCE pill.
    private func searchDistanceLabel(_ result: MapSearchResult) -> String? {
        guard let userLocation, let coordinate = result.coordinate else { return nil }
        let pin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return MapDistance.label(meters: pin.distance(from: userLocation))
    }

    /// A tapped result: keyboard down, search collapsed, camera FLIES to the pin
    /// and the pin OPENS — the same selection + detail path a direct tap takes.
    /// Events resolve to their spot's pin.
    private func commitSearchResult(_ result: MapSearchResult) {
        collapseSearch()
        Haptics.light()
        switch result.target {
        case .spot(let spot):
            openFromSearch(.spot(spot), at: spot.coordinate)
        case .poi(let poi):
            openFromSearch(.poi(poi), at: poi.coordinate)
        case .event(_, let pin):
            if let pin {
                openFromSearch(.spot(pin), at: pin.coordinate)
            } else {
                // Spot-less fallback: an event at an unlisted venue has no pin to
                // open, so the camera just flies home rather than inventing one.
                let home = { viewport = .camera(center: MapSpots.center, zoom: 13.5) }
                if reduceMotion { home() } else { withViewportAnimation(.fly(duration: 1.0)) { home() } }
            }
        }
    }

    /// The keyboard's Search key — commit the top match, if there is one.
    private func commitFirstSearchResult() {
        guard let first = searchResults.first else { return }
        commitSearchResult(first)
    }

    /// Fly-and-open shared by every committed result — the same 1.0s fly +
    /// liftedViewport + Motion.card open that `focus(_:)` uses for row taps.
    /// Search intent wins over the chip row: a chip that hides the committed
    /// place resets to All FIRST (MapFilter.afterSearchCommit), so the card
    /// never opens over a map with no pin for it underneath.
    private func openFromSearch(_ detail: MapPlaceDetail, at coordinate: CLLocationCoordinate2D) {
        filter = filter.afterSearchCommit(showsTarget: filterShowsSearchTarget(detail))
        withAnimation(reduceMotion ? Motion.smooth : Motion.card) { mapDetail = detail }
        let move = { viewport = liftedViewport(coordinate, zoom: Self.selectZoom) }
        if reduceMotion { move() } else { withViewportAnimation(.fly(duration: 1.0)) { move() } }
    }

    #if DEBUG
    /// `-map-search-committed`: the POIs load async, so keep trying briefly until
    /// the query yields a result, then commit the first — fly + pin open.
    private func debugCommitSearch(attempts: Int) {
        if let first = searchResults.first {
            commitSearchResult(first)
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                debugCommitSearch(attempts: attempts - 1)
            }
        }
    }
    #endif

    // Client-side POI clustering (recompute trigger, reclustering, bubble lifecycle) and
    // the DEBUG autozoom demo live in SJMapView+POIClustering.swift.

    private func closeCard() {
        guard mapDetail != nil else { return }
        withAnimation(reduceMotion ? Motion.smooth : Motion.card) {
            mapDetail = nil
        }
    }

    /// Whether the active chip leaves this place on the map — the same
    /// membership `dismissDetailIfFiltered` checks, asked BEFORE a committed
    /// search result opens so the filter can yield to the search intent.
    private func filterShowsSearchTarget(_ detail: MapPlaceDetail) -> Bool {
        switch detail {
        case .spot(let spot): return filteredSpots.contains { $0.id == spot.id }
        case .poi(let poi):   return filteredPOIs.contains { $0.id == poi.id }
        }
    }

    /// A chip change (or an unsave while the Saved chip is active) can hide the
    /// place whose detail is open — close the card rather than leave it
    /// describing a pin that is no longer on the map.
    private func dismissDetailIfFiltered() {
        if let s = selectedSpot, !filteredSpots.contains(where: { $0.id == s.id }) { closeCard() }
        if let p = selectedPOI, !filteredPOIs.contains(where: { $0.id == p.id }) { closeCard() }
    }

    /// Spoken pin summary — the same complete sentences the sheet uses
    /// (MapSheetCopy), so eyes and ears hear one voice.
    private func accessibilityLabel(for spot: Spot, live: Bool) -> String {
        let n = events(at: spot).count
        var parts = ["\(spot.name)."]
        parts.append(n == 0 ? "Nothing happening yet today."
                            : MapSheetCopy.todayCountSentence(n))
        if live { parts.append("Happening now.") }
        return parts.joined(separator: " ")
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

// MARK: - Selected pulse ring (map polish Phase 5)
//
// The "you opened this" ring under the detail sheet — PulseRing's recipe, but
// INK (plum stays live-only), slower and quieter: selection is confirmation,
// not urgency (2.4s vs live's 1.5s; 0.22 vs 0.35; 1.9× vs 2.2×). Shared by the
// selected civic badge and the selected-POI overlay. Under Reduce Motion it
// renders as a STATIC ink ring instead — the live-ring discipline: meaning
// survives as geometry when motion is suppressed.

private struct SelectedPulseRing: View {
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        if reduceMotion {
            Circle()
                .stroke(MarkerRole.selectedRing.opacity(0.35), lineWidth: 1.5)
                .frame(width: diameter + 12, height: diameter + 12)
        } else {
            Circle()
                .fill(MarkerRole.selectedRing.opacity(pulsing ? 0 : 0.22))
                .frame(width: diameter, height: diameter)
                .scaleEffect(pulsing ? 1.9 : 1.0)
                .onAppear {
                    withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                        pulsing = true
                    }
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
// selected: scale 1.25 (Motion.select), lifted marker shadow, always expanded, plus
//           a slow quiet INK pulse ring (SelectedPulseRing) while the detail is open.
// calmed:   while ANOTHER place's detail is open the rest of the map rests — this
//           badge keeps its static signals (live ring, saved corner) but stops its
//           live pulse; its label is withheld at the call site via `showsLabel`.
// Motion:   wake = opacity 0→1 + scale 0.6→1.0 spring on first appear (Motion.select);
//           expand/shrink = Motion.card on diameter + icon/label crossfade; select bump =
//           Motion.select; tint change = Motion.smooth. Reduce Motion drops every
//           scale/spring to a simple opacity/colour crossfade (never removed — §11).

private struct MapPinBadge: View {
    let spot: Spot
    let base: PinDisplay      // rest | saved | live — the coloring (selection ignored)
    let selected: Bool
    let calmed: Bool          // a DIFFERENT place's detail is open — rest the pulse
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
            // The selection's own quiet ink pulse (static ring under Reduce
            // Motion) — drawn first so every static signal sits above it.
            if selected { SelectedPulseRing(diameter: diameter) }

            // Suppressed once selected — the selected ring above (plus scale +
            // label) is the "you tapped this" cue; two pulses read as noise. Also
            // rested while `calmed` (another place's detail is open) so the open
            // card owns the moment — the static live ring below still carries
            // "happening now". Kept even compact otherwise — the one live signal
            // worth keeping glanceable zoomed all the way out.
            if live && !selected && !calmed { PulseRing(diameter: diameter) }

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
            // The selection's quiet ink pulse (static ring under Reduce Motion) —
            // the same ring the selected civic badge shows, sized to the 34pt badge.
            SelectedPulseRing(diameter: 34)

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
