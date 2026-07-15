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
    @StateObject private var model = MapModel()
    /// Device-local saved set (shared with Explore). Observed so saving a place from
    /// the sheet updates its pin to the Saved state live.
    @ObservedObject private var saved = SavedStore.shared

    @State private var viewport: Viewport = .camera(
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

    private var isAdmin: Bool {
        // DEBUG-only: `-force-nonadmin` launch arg forces the non-admin branch so
        // simulator verification can screenshot the gated map without a second
        // account. No effect in release builds or without the flag.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-force-nonadmin") { return false }
        #endif
        return Admin.isAdmin(auth.email)
    }

    private var filteredSpots: [Spot] { MapSpots.all.filter { filter.matches($0.category) } }

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
                // A tap on a POI marker opens its detail; a tap on a cluster zooms in
                // to split it. Layer-scoped interactions are evaluated BEFORE the
                // map-wide tap, so these win over closeCard() when a marker/cluster is hit.
                TapInteraction(.layer(POILayer.dotLayerID)) { feature, _ in
                    if let id = feature.properties["id"]??.string { selectPOI(id: id) }
                    return true
                }
                TapInteraction(.layer(POILayer.clusterLayerID)) { _, context in
                    zoomToCluster(context.coordinate)
                    return true
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
                }
            }
            .mapStyle(MapStyle(uri: StyleURI(rawValue: MAP_STYLE_URL)!))
            .onStyleLoaded { _ in
                recolorBasemap(proxy.map)
                if let map = proxy.map { POILayer.install(on: map, pois: model.pois) }
            }
            // Name whatever town the map is panned over, and shrink/expand pins to fit
            // the zoom (both debounced in the model — never the view's @State here).
            .onCameraChanged {
                model.updateTown(center: $0.cameraState.center)
                model.updateZoom($0.cameraState.zoom)
            }
            // If a filter change hides the selected spot, drop the stale selection so the
            // detail sheet doesn't linger over a pin that's no longer on the map.
            .onChange(of: filter) { _, _ in
                if let s = selectedSpot, !filteredSpots.contains(where: { $0.id == s.id }) { closeCard() }
            }
            // POIs load async (once) after the style — push them into the source when they land.
            .onChange(of: model.pois) { _, pois in
                if let map = proxy.map { POILayer.update(on: map, pois: pois) }
                #if DEBUG
                if selectedPOI == nil, let poi = SJMapView.debugOpenPOI(in: pois) { selectedPOI = poi }
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
            // Sit just above the sheet peek, which itself sits above the tab bar.
            .padding(.bottom, MapSheet.tabBarClearance + MapSheet.peekHeight + 12)
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
            .fill(LIVE_COLOR.opacity(pulsing ? 0 : 0.35))
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
    private var tint: Color { live ? LIVE_COLOR : spot.category.tint }

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

            Circle()
                .fill(tint)
                .frame(width: diameter, height: diameter)
                .mapFloatShadow(pressed: selected)
                .overlay(Circle().stroke(Hue.surface, lineWidth: 1.5))

            Image(systemName: spot.category.filledSymbol)
                .font(.system(size: Self.iconSize, weight: .semibold))
                .foregroundStyle(.white)
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

private struct HaloText: View {
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
