//
//  SJMapView.swift
//  Hygge — Mapbox map of Saint Joseph, Minnesota.
//
//  Life360-style layout: floating top chrome (filter · town pill · compose), a
//  warm Google-style basemap, a persistent draggable bottom sheet (MapSheet), and
//  coral reserved for live indicators + primary/tappable elements.
//
//  Pin hierarchy (see docs/superpowers/specs/2026-07-13-map-pin-hierarchy-design.md):
//  most pins RECEDE to a small dot; a few STAND OUT. State is resolved once by
//  `PinDisplay` (precedence selected > live > saved > rest) and rendered across
//  three tiers so labels get real Mapbox collision:
//    • `CircleLayer`  — the recessive 6pt rest dot for every pin, at all zooms.
//    • `SymbolLayer`  — awake pins' name labels, with text-collision + sort-key +
//                       a zoom-threshold crossfade (T = 14.5).
//    • SwiftUI overlay — the full badge for saved/live/selected (shadow, wake
//                       spring, live pulse). Selection flips ONE feature-state
//                       property; it never re-diffs the source.
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

/// Style ids for the pin source + layers (imperatively installed on the base map).
private let PIN_SOURCE  = "hygge-pins"
private let DOT_LAYER   = "hygge-pin-dots"
private let LABEL_LAYER = "hygge-pin-labels"

/// The pin-hierarchy tuning in one place — the values the spec left me to choose.
private enum PinTuning {
    static let dotRadius: Double        = 3      // circle-radius 3 → 6pt DIAMETER
    static let dotOpacity: Double       = 0.65   // recessive; NOT coral (coral == live)
    static let dotStrokeWidth: Double   = 0.5    // contrasting hairline, survives any basemap
    static let labelThreshold: Double   = 14.5   // T — labels fade in by here
    static let labelHideBelow: Double   = 14.3   // T − 0.2 — soft band (anti-strobe)
    static let hitTarget: CGFloat       = 44     // rest dot's invisible ≥44×44 tap target
    static let labelSize: Double        = 12
    static let labelHaloWidth: Double   = 1.3
}

// Basemap cartography now lives in BasemapPalette (Features/Map/Atmosphere): the
// Living Basemap modulates land/green/water/building by time · season · weather.
// The summer·noon·clear anchor reproduces the original warm Life360 hexes exactly.

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
    /// The Living Basemap's environment (time-of-day · season · weather). Drives the
    /// basemap palette, the time wash, the precip layer, and the town-pill whisper.
    /// Independent of MapModel (events/realtime) — a clean seam.
    @StateObject private var atmosphere = AtmosphereModel()
    /// Held so recolorBasemap can re-apply when the atmosphere changes, not only
    /// once on style load.
    @State private var mapRef: MapboxMap?

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

    /// DEBUG-only: `-map-zoom <z>` starts the camera at a given zoom so each pin
    /// hierarchy state (z12 all-rest · z14 threshold · z16 labels-on) can be
    /// screenshotted headlessly. No effect in release / without the flag.
    private static func debugInitialZoom() -> Double? {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-map-zoom"), i + 1 < a.count { return Double(a[i + 1]) }
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

    /// The single resolver — one enum, one place. Selection is included here (for the
    /// overlay); the SOURCE uses the base state (selection ignored), see pinFeatures().
    private func display(for spot: Spot) -> PinDisplay {
        PinDisplay.resolve(isSelected: selectedSpot?.id == spot.id,
                           isLive: isLive(spot),
                           isSaved: isSavedSpot(spot))
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            // Living Basemap ambience — above the map, below all chrome/sheet so
            // pins + controls stay crisp. Both are non-interactive.
            TimeWashOverlay(atmosphere: atmosphere.current)
            WeatherParticles(atmosphere: atmosphere.current)
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
        .onAppear { model.start(auth: auth); atmosphere.start() }
        .onDisappear { model.stop(); atmosphere.stop() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:     model.onForeground(); atmosphere.onForeground()
            case .background: model.onBackground()
            default:          break
            }
        }
        // Re-apply the basemap cartography when the atmosphere shifts (time / season
        // / weather). The recolor otherwise only runs once, on style load.
        .onChange(of: atmosphere.current) { _, _ in recolorBasemap(mapRef) }
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
                // A tap on the map (not a badge): select the nearest rest dot within
                // the 44pt hit target, else dismiss the detail.
                TapInteraction { context in
                    handleMapTap(point: context.point, map: proxy.map)
                    return true
                }
                // The few pins that stand out — the full badge for saved/live/selected.
                // Rest pins are the dots in the circle layer (no overlay view).
                ForEvery(awakePins) { pin in
                    MapViewAnnotation(coordinate: pin.spot.coordinate) {
                        MapPinBadge(spot: pin.spot, base: pin.base, selected: pin.selected,
                                    a11yLabel: accessibilityLabel(for: pin.spot, live: pin.base == .live))
                            .onTapGesture { selectSpot(pin.spot) }
                    }
                    // Never cull; the badge must always beat its own dot / neighbors.
                    .allowOverlap(true)
                }
            }
            .mapStyle(MapStyle(uri: StyleURI(rawValue: MAP_STYLE_URL)!))
            .onStyleLoaded { _ in
                mapRef = proxy.map
                recolorBasemap(proxy.map)
                installPins(proxy.map)
            }
            // Name whatever town the map is panned over (debounced in the model).
            .onCameraChanged { model.updateTown(center: $0.cameraState.center) }
            // Rebuild the source when membership / liveness / saves change (cheap: 6
            // features). Selection is NOT here — it's a feature-state flip.
            .onChange(of: pinSignature) { _, _ in updatePins(proxy.map) }
            .onChange(of: selectedSpot?.id) { _, _ in applySelectionState(proxy.map) }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// A value that changes whenever the pin SOURCE should rebuild — filter, the
    /// per-minute liveness tick, today's events, and the saved set. (Selection is
    /// excluded; it rides feature-state.)
    private var pinSignature: Int {
        var h = Hasher()
        h.combine(filter)
        h.combine(model.clockTick)
        h.combine(model.todayEvents.count)
        h.combine(saved.ids)
        return h.finalize()
    }

    // MARK: Pin style layers (imperative — installed on the base map)

    /// The GeoJSON features for the current filter, carrying the BASE state
    /// (selection ignored — selection is layered on via feature-state so it never
    /// re-diffs the source).
    private func pinFeatures() -> FeatureCollection {
        let feats: [Feature] = filteredSpots.map { spot in
            var f = Feature(geometry: .point(Point(spot.coordinate)))
            f.identifier = .string(spot.id)   // so setFeatureState can target it
            let base = PinDisplay.resolve(isSelected: false,
                                          isLive: isLive(spot),
                                          isSaved: isSavedSpot(spot))
            f.properties = [
                "state":   .string(base.rawValue),
                "sortKey": .number(base.labelSortKey),   // lower wins collision
                "name":    .string(spot.name)
            ]
            return f
        }
        return FeatureCollection(features: feats)
    }

    /// text-opacity for the label layer: selected → 0 (the overlay draws its
    /// always-on label, above collision + zoom); everyone else crossfades in across
    /// the T−0.2…T band. feature-state is paint-only, so this lives here, not layout.
    private func labelOpacityExpression() -> Exp {
        // Mapbox requires `zoom` at the TOP LEVEL of a property expression — nesting it
        // inside `case` throws on addLayer (silently, via our catch → no labels). So the
        // crossfade is the OUTER interpolate, and the selected-hide rides each stop's
        // output: selected → 0 always (the overlay draws its always-on label); everyone
        // else fades in across the T−0.2…T band.
        func hideIfSelected(_ shown: Double) -> Exp {
            Exp(.switchCase) {
                Exp(.boolean) { Exp(.featureState) { "selected" }; false }
                0.0
                shown
            }
        }
        return Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            PinTuning.labelHideBelow; hideIfSelected(0.0)
            PinTuning.labelThreshold; hideIfSelected(1.0)
        }
    }

    /// Install (or refresh) the pin source + dot layer + label layer. Idempotent —
    /// onStyleLoaded can fire again on a style reload. Best-effort like recolorBasemap.
    private func installPins(_ map: MapboxMap?) {
        guard let map else { return }

        var dots = CircleLayer(id: DOT_LAYER, source: PIN_SOURCE)
        dots.circleRadius      = .constant(PinTuning.dotRadius)
        dots.circleColor       = .constant(StyleColor(UIColor(Hue.mapInk)))
        dots.circleOpacity     = .constant(PinTuning.dotOpacity)
        dots.circleStrokeColor = .constant(StyleColor(UIColor.white))
        dots.circleStrokeWidth = .constant(PinTuning.dotStrokeWidth)

        var labels = SymbolLayer(id: LABEL_LAYER, source: PIN_SOURCE)
        labels.textField       = .expression(Exp(.get) { "name" })
        labels.textSize        = .constant(PinTuning.labelSize)
        labels.textColor       = .constant(StyleColor(UIColor(Hue.mapInk)))
        labels.textHaloColor   = .constant(StyleColor(UIColor.white))
        labels.textHaloWidth   = .constant(PinTuning.labelHaloWidth)
        labels.textOffset      = .constant([0, 2.4])     // clear the 44pt badge, then hang below
        labels.textAnchor      = .constant(.top)
        labels.textAllowOverlap = .constant(false)       // ← the non-negotiable collision
        labels.symbolSortKey   = .expression(Exp(.get) { "sortKey" })
        labels.filter          = Exp(.neq) { Exp(.get) { "state" }; "rest" }  // rest has no label
        labels.textOpacity     = .expression(labelOpacityExpression())

        do {
            if map.sourceExists(withId: PIN_SOURCE) {
                map.updateGeoJSONSource(withId: PIN_SOURCE, geoJSON: .featureCollection(pinFeatures()))
            } else {
                var src = GeoJSONSource(id: PIN_SOURCE)
                src.data = .featureCollection(pinFeatures())
                try map.addSource(src)
            }
            if !map.layerExists(withId: DOT_LAYER)   { try map.addLayer(dots) }
            if !map.layerExists(withId: LABEL_LAYER) { try map.addLayer(labels) }
        } catch {
            // Best-effort: a missing layer id in a given style version shouldn't crash.
        }
        applySelectionState(map)
    }

    /// Push the current features into the existing source (state / liveness / saves
    /// changed). No-ops until the source is installed.
    private func updatePins(_ map: MapboxMap?) {
        guard let map, map.sourceExists(withId: PIN_SOURCE) else { return }
        map.updateGeoJSONSource(withId: PIN_SOURCE, geoJSON: .featureCollection(pinFeatures()))
        applySelectionState(map)   // a data update can drop feature-state; re-assert it
    }

    /// Selection = flip ONE feature-state property per pin. The label layer's
    /// text-opacity reads it (paint), and the overlay draws the selected badge.
    private func applySelectionState(_ map: MapboxMap?) {
        guard let map, map.sourceExists(withId: PIN_SOURCE) else { return }
        for spot in filteredSpots {
            let sel = (selectedSpot?.id == spot.id)
            map.setFeatureState(sourceId: PIN_SOURCE, featureId: spot.id, state: ["selected": sel]) { _ in }
        }
    }

    /// Warm the flat light-v11 basemap toward the Life360 reference: beige ground,
    /// sage parks, soft-blue water, light-gray buildings. Each set is best-effort
    /// (try?) since a given layer id may not exist in every style version.
    private func recolorBasemap(_ map: MapboxMap?) {
        guard let map else { return }
        let p = BasemapPalette.make(for: atmosphere.current)
        // Ground / land (background-type layers)
        for id in ["land", "background"] {
            try? map.setLayerProperty(for: id, property: "background-color", value: p.land)
        }
        // Parks / grass / woods (fill layers)
        for id in ["landuse", "landcover", "national-park", "park", "pitch", "grass"] {
            try? map.setLayerProperty(for: id, property: "fill-color", value: p.green)
        }
        // Water
        try? map.setLayerProperty(for: "water",    property: "fill-color", value: p.water)
        try? map.setLayerProperty(for: "waterway", property: "line-color", value: p.water)
        // Buildings — grey
        try? map.setLayerProperty(for: "building", property: "fill-color",         value: p.building)
        try? map.setLayerProperty(for: "building", property: "fill-outline-color", value: p.building)
    }

    /// The awake pins (saved / live / selected) that get a full badge in the overlay.
    /// `base` is the coloring (rest/saved/live, selection ignored); `selected` drives
    /// the scale / raised shadow / always-on label.
    private var awakePins: [AwakePin] {
        filteredSpots.compactMap { spot in
            let d = display(for: spot)
            guard d.isAwake else { return nil }
            let base = PinDisplay.resolve(isSelected: false,
                                          isLive: isLive(spot),
                                          isSaved: isSavedSpot(spot))
            return AwakePin(spot: spot, base: base, selected: d == .selected)
        }
    }

    /// Tap on the open map: pick the nearest curated spot within a 44pt target
    /// (projecting each spot to the screen), else dismiss. This gives rest dots a
    /// ≥44×44 hit area without an extra layer; awake badges handle their own taps.
    private func handleMapTap(point: CGPoint, map: MapboxMap?) {
        guard let map else { return }
        var best: (spot: Spot, dist: CGFloat)?
        for spot in filteredSpots {
            let p = map.point(for: spot.coordinate)
            let dist = hypot(p.x - point.x, p.y - point.y)
            if best == nil || dist < best!.dist { best = (spot, dist) }
        }
        if let best, best.dist <= PinTuning.hitTarget / 2 {
            if selectedSpot?.id != best.spot.id { selectSpot(best.spot) }
        } else {
            closeCard()
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
        // When weather resolves, the pill grows a second line; animate the row so the
        // flanking chrome circles settle smoothly instead of snapping (cold-open only).
        .animation(.easeInOut(duration: 0.35), value: atmosphere.current.resolvedAt != nil)
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
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Hue.accent)
                Text(model.townLabel)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.mapInk)
                    .lineLimit(1)
            }
            // The quiet "why" — weather + time. Muted ink, never coral; hidden
            // until weather resolves, then expands the pill's second line in.
            AtmosphereWhisper(atmosphere: atmosphere.current)
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

// MARK: - Awake pin (overlay item)

/// A pin that earns a full badge. `id` folds in state so ForEvery rebuilds the
/// annotation when a pin's weight changes (Mapbox doesn't re-render an annotation
/// whose element identity is unchanged).
private struct AwakePin: Identifiable {
    let spot: Spot
    let base: PinDisplay      // rest | saved | live — the coloring
    let selected: Bool
    var id: String { "\(spot.id)-\(base.rawValue)-\(selected)" }
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

// MARK: - Marker bubble (awake pins only: saved / live / selected)
//
// Base:     44px white circle, 1px mapHairline border, standard float shadow,
//           centered 20px line icon in mapInk, weight .medium.
// Saved:    ink `bookmark.fill` mini-badge top-right (coral stays live-only here).
// Live:     2px accent border, accent icon, 10px accent dot badge top-right + pulse.
// Selected: scale 1.15, deeper shadow, always-on name label below.
// Motion:   wake = opacity 0→1 + scale 0.6→1.0 spring (~220ms); Reduce Motion =
//           opacity crossfade only, no scale.

private struct MapPinBadge: View {
    let spot: Spot
    let base: PinDisplay      // rest | saved | live
    let selected: Bool
    let a11yLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var live: Bool  { base == .live }
    private var saved: Bool { base == .saved }

    var body: some View {
        ZStack {
            badge
                .scaleEffect(selected && !reduceMotion ? 1.15 : 1.0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
            if selected {
                // The selected label — always on, ignores T, above collision (it's
                // drawn here, not in the symbol layer). Hangs below the badge without
                // shifting its center (offset is post-layout).
                Text(spot.name)
                    .font(.sansSemibold(13))
                    .foregroundStyle(Hue.mapInk)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Hue.surface, in: Capsule())
                    .overlay(Capsule().stroke(Hue.mapHairline, lineWidth: 1))
                    .mapFloatShadow()
                    .fixedSize()
                    .offset(y: 36)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        // Wake: scale 0.6→1.0 + fade in (spring); Reduce Motion → fade only.
        .scaleEffect(appeared ? 1.0 : (reduceMotion ? 1.0 : 0.6))
        .opacity(appeared ? 1 : (reduceMotion ? 1 : 0))
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
            } else if saved {
                // Ink bookmark mini-badge — reads "yours" while keeping coral == live.
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Hue.mapInk)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Hue.surface))
                    .overlay(Circle().stroke(Hue.mapHairline, lineWidth: 1))
                    .offset(x: 16, y: -16)
            }
        }
    }
}
