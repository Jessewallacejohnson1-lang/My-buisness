//
//  SJMapView.swift
//  Hygge — Mapbox map of Saint Joseph, Minnesota.
//
//  Life360-style layout: floating top chrome (filter · town pill · compose), a
//  warm Google-style basemap, a persistent draggable bottom sheet (MapSheet), and
//  coral reserved for live indicators + primary/tappable elements.
//
//  Live pipeline: MapModel owns a Realtime subscription on club_events. A new /
//  ended / deleted happening re-syncs the map with no manual refresh — the pin
//  lights or goes quiet on its own. Spots come from the curated MapSpots catalog;
//  liveness + "today's happenings" come only from real events. One-line rebrand:
//  change LIVE_COLOR below.
//

import SwiftUI
import MapboxMaps

// MARK: - Constants

private let MAP_STYLE_URL = "mapbox://styles/mapbox/light-v11"
private let LIVE_COLOR    = Hue.accent   // warm coral — change here to rebrand

/// Warm Google-/Life360-style basemap cartography — the base-map fill colors (the
/// only raw hexes allowed on the map), kept named so call sites read intent.
private enum MapPalette {
    static let land     = "#F0EBE3"   // warm beige ground
    static let green    = "#C9E0B4"   // soft sage parks / grass
    static let water    = "#A6CBE6"   // soft blue water
    static let building = "#E8E4DC"   // warm light-gray buildings
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
    /// Non-admins tap the top-right "+" into the global composer (admins get the
    /// map's own QuickAddSheet). Injected by MainTabsView, like HomeView.
    var onCompose: (() -> Void)? = nil

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = MapModel()

    @State private var viewport: Viewport = .camera(
        center: SJMapView.debugInitialCenter() ?? MapSpots.center,
        zoom: 13.5,
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
    @State private var selectedSpot: Spot? = SJMapView.debugSelectedSpot()
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
        events(at: spot).contains { DateHelpers.isLiveNow($0.startTime) }
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
                annotations
            }
            .mapStyle(MapStyle(uri: StyleURI(rawValue: MAP_STYLE_URL)!))
            .onStyleLoaded { _ in recolorBasemap(proxy.map) }
            // Name whatever town the map is panned over (debounced in the model).
            .onCameraChanged { model.updateTown(center: $0.cameraState.center) }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Warm the flat light-v11 basemap toward the Life360 reference: beige ground,
    /// sage parks, soft-blue water, light-gray buildings. Each set is best-effort
    /// (try?) since a given layer id may not exist in every style version.
    private func recolorBasemap(_ map: MapboxMap?) {
        guard let map else { return }
        // Ground / land (background-type layers)
        for id in ["land", "background"] {
            try? map.setLayerProperty(for: id, property: "background-color", value: MapPalette.land)
        }
        // Parks / grass / woods (fill layers)
        for id in ["landuse", "landcover", "national-park", "park", "pitch", "grass"] {
            try? map.setLayerProperty(for: id, property: "fill-color", value: MapPalette.green)
        }
        // Water
        try? map.setLayerProperty(for: "water",    property: "fill-color", value: MapPalette.water)
        try? map.setLayerProperty(for: "waterway", property: "line-color", value: MapPalette.water)
        // Buildings — grey
        try? map.setLayerProperty(for: "building", property: "fill-color",         value: MapPalette.building)
        try? map.setLayerProperty(for: "building", property: "fill-outline-color", value: MapPalette.building)
    }

    /// Spot + liveness snapshot. The id changes when liveness flips so ForEvery
    /// rebuilds the annotation view — Mapbox doesn't re-render an annotation whose
    /// element identity is unchanged, which left stale badges after events loaded.
    private struct PinState: Identifiable {
        let spot: Spot
        let live: Bool
        var id: String { "\(spot.id)-\(live)" }
    }

    @MapContentBuilder
    private var annotations: some MapContent {
        // A tap on the open map (not a pin, not a pan) dismisses the detail.
        TapInteraction { _ in
            closeCard()
            return true
        }

        ForEvery(filteredSpots.map { PinState(spot: $0, live: isLive($0)) }) { state in
            MapViewAnnotation(coordinate: state.spot.coordinate) {
                MapPinBadge(spot: state.spot, live: state.live,
                            selected: selectedSpot?.id == state.spot.id,
                            a11yLabel: accessibilityLabel(for: state.spot, live: state.live))
                    .onTapGesture { selectSpot(state.spot) }
            }
            // Never cull; culling hid downtown (and its live glow) behind the
            // nearby chapel pin.
            .allowOverlap(true)
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
        .padding(.vertical, 10)
        .background(Hue.surface, in: Capsule())
        .overlay(Capsule().stroke(Hue.mapHairline, lineWidth: 1))
        .mapFloatShadow()
        .animation(.easeInOut(duration: 0.2), value: model.townLabel)
        .accessibilityLabel(model.townLabel)
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
        withViewportAnimation(.fly(duration: 0.7)) {
            viewport = .camera(center: spot.coordinate, zoom: 15)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            selectedSpot = spot
        }
    }

    private func selectSpot(_ spot: Spot) {
        Haptics.light()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            selectedSpot = (selectedSpot?.id == spot.id) ? nil : spot
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
// Reduce Motion (no pulse; the badge dot still marks "live").

private struct PulseRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(LIVE_COLOR.opacity(pulsing ? 0 : 0.35))
            .frame(width: 44, height: 44)
            .scaleEffect(pulsing ? 2.2 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Marker bubble
//
// Base:     44px white circle, 1px mapHairline border, standard float shadow,
//           centered 20px line icon in mapInk, weight .medium.
// Live:     2px accent border, accent icon, 10px accent dot badge top-right with
//           2px white ring. Pulse ring: coral 0.35→0, scale 1→2.2, 1.5s.
// Selected: scale 1.15, deeper shadow.

private struct MapPinBadge: View {
    let spot: Spot
    let live: Bool
    let selected: Bool
    let a11yLabel: String

    var body: some View {
        ZStack {
            if live && !selected {
                PulseRing()
            }

            Circle()
                .fill(Hue.surface)
                .frame(width: 44, height: 44)
                .mapFloatShadow(pressed: selected)
                .overlay(
                    Circle().stroke(
                        live ? LIVE_COLOR : Hue.mapHairline,
                        lineWidth: live ? 2 : 1
                    )
                )

            Image(systemName: spot.category.symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(live ? LIVE_COLOR : Hue.mapInk)

            if live {
                Circle()
                    .fill(LIVE_COLOR)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Hue.surface, lineWidth: 2))
                    .offset(x: 17, y: -17)
            }
        }
        .scaleEffect(selected ? 1.15 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityAddTraits(.isButton)
    }
}
