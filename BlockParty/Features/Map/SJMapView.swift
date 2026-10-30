//
//  SJMapView.swift
//  Block Party — the Town's map: today's events, and nothing else.
//
//  Presented full screen from the Town bar's yellow disc. Jesse's map reset (BP app
//  references/map-reset, 2026-10-30): the map shows only today's events, one glass photo
//  bubble per real spot (TodayBubbles.swift), sized by the zoom; a tap raises Airbnb's map
//  card (MapEventCard), and the card opens the Event page on the map's own stack, so Back
//  comes back to the map. Bubbles that touch on screen (tags included) merge into one, whose card pages
//  through all their events. The chrome is two circles, close and recenter, the compass
//  once the map is turned, and one pill that says the day is over or the read failed.
//  Business pins, chips, search, the help button, the town pill and the bottom sheet went
//  with the reset; Search has the businesses.
//
//  One static basemap (BasemapPalette, Uber's colours), Mapbox's wordmark hidden and its
//  ⓘ attribution kept (Jesse's 2026-08-14 call), rotate and tilt 0–70°, 120 Hz.
//

import SwiftUI
import UIKit
// `@_spi(Restricted)`: the ONE restricted symbol used is `LogoViewOptions.visibility`,
// which hides the Mapbox wordmark (Jesse's 2026-08-14 call).
@_spi(Restricted) import MapboxMaps

private let MAP_STYLE_URL = "mapbox://styles/mapbox/light-v11"

struct SJMapView: View {
    /// Leaves the map; nil draws no close circle.
    var onClose: (() -> Void)?

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TownFeed.self) private var townFeed
    @StateObject private var model = MapModel()

    /// The zoom the map opens at: downtown and Saint Ben's fill the screen, so their bubbles
    /// don't pile up (Jesse at Check-in 1).
    static let openZoom: Double = 14.6

    @State private var viewport: Viewport = .camera(
        center: SJMapView.debugCenter() ?? MapSpots.center,
        zoom: SJMapView.debugZoom() ?? SJMapView.openZoom,
        bearing: SJMapView.debugDouble(.mapBearing) ?? 0,
        pitch: SJMapView.debugDouble(.mapPitch) ?? 0
    )
    /// The bearing and pitch for the compass, the zoom for the bubbles: each observed only
    /// by what draws it, so a pinch or a twist never redraws the whole map.
    @State private var compass = CompassHeading()
    @State private var zoom = MapZoom()
    /// Today's bubbles as drawn: merged where they touch at the zoom the camera last settled at.
    @State private var shown: [TodayBubble] = []
    @State private var selectedID: String?
    @State private var page = 0
    @State private var path: [FeedCardItem] = []
    @State private var mapSize: CGSize = .zero

    private var selected: TodayBubble? { shown.first { $0.id == selectedID } }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                MapReader { proxy in mapLayer(proxy) }
                chrome
                if let bubble = selected {
                    MapEventCard(events: bubble.events, page: $page,
                                 onOpen: { open($0) }, onClose: { select(nil) })
                        .id(bubble.id)
                        .padding(.horizontal, MapEventCard.sideInset)
                        .padding(.bottom, MapEventCard.bottomInset)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0 }
            .toolbar(.hidden, for: .navigationBar)
            .background { SwipeBack().frame(width: 0, height: 0) }
            .navigationDestination(for: FeedCardItem.self) { FeedEventDetailDestination(item: $0) }
        }
        .onAppear {
            model.start(auth: auth, feed: townFeed)
            Haptics.prepare()
        }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:     model.onForeground()
            case .background: model.onBackground()
            default:          break
            }
        }
        .onChange(of: townFeed.cards) { _, cards in model.show(cards) }
    }

    // MARK: Map

    private func mapLayer(_ proxy: MapProxy) -> some View {
        Map(viewport: $viewport) {
            ForEvery(shown) { bubble in
                MapViewAnnotation(coordinate: bubble.coordinate) {
                    TodayEventBubble(bubble: bubble, zoom: zoom, selected: bubble.id == selectedID) {
                        select(bubble)
                    }
                }
                .allowOverlap(true)
                // The tapped one sits on top.
                .priority(bubble.id == selectedID ? 1 : 0)
            }
            // A tap on the map itself, past any bubble, closes the card.
            TapInteraction { _ in
                if selectedID != nil { select(nil) }
                return false
            }
        }
        .mapStyle(MapStyle(uri: StyleURI(rawValue: MAP_STYLE_URL)!))
        // Rotate and tilt pivot around the two fingers; a pinch doesn't drift into a turn.
        .gestureOptions(GestureOptions(rotateEnabled: true,
                                       simultaneousRotateAndPinchZoomEnabled: true,
                                       pitchEnabled: true,
                                       panDecelerationFactor: 0.998))
        // Wordmark hidden, ⓘ attribution kept top left under close (the card covers the bottom),
        // scale bar and Mapbox's own compass off (`MapCompass` replaces it: our ink, and it
        // levels the tilt too).
        .ornamentOptions(OrnamentOptions(
            scaleBar: ScaleBarViewOptions(visibility: .hidden),
            compass: CompassViewOptions(visibility: .hidden),
            logo: Self.hiddenLogoOptions,
            attributionButton: AttributionButtonOptions(position: .topLeading,
                                                        margins: CGPoint(x: 26, y: 62))
        ))
        .frameRate(range: 80...120, preferred: 120)
        .onStyleLoaded { _ in
            BasemapPalette.recolor(proxy.map)
            clampPitch(proxy.map)
            relayout(proxy.map)
        }
        // A second recolour: `onStyleLoaded` alone sometimes lost the race and left the map
        // Mapbox's grey; `recolor` is idempotent.
        .onMapLoaded { _ in BasemapPalette.recolor(proxy.map) }
        .onCameraChanged {
            compass.update(cameraState: $0.cameraState)
            zoom.update(Double($0.cameraState.zoom))
        }
        // Merges and splits wait for the camera to settle, then glide.
        .onMapIdle { _ in relayout(proxy.map) }
        .onChange(of: model.today.events) { _, _ in relayout(proxy.map) }
        .onChange(of: model.today.spots.count) { _, _ in relayout(proxy.map) }
        .onChange(of: model.clockTick) { _, _ in relayout(proxy.map) }
        .ignoresSafeArea()
    }

    /// Today's bubbles at this camera: ended events off, touching bubbles merged. A card whose
    /// bubble is gone closes; one merged into another stays open on the merged bubble.
    private func relayout(_ map: MapboxMap?) {
        let now = TodayBubbleClock.now()
        let bubbles = model.today.bubbles(now: now)
        let merged = map.map { map in
            // Closer than a bead and a half: their time tags would run into each other.
            TodayPlaces.merge(bubbles, at: bubbles.map { map.point(for: $0.coordinate) },
                              within: zoom.bead * 1.5, now: now)
        } ?? bubbles
        let wasOpen = selected
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) { shown = merged }
        #if DEBUG
        debugOpenBubble()
        #endif
        guard let wasOpen, selected == nil else { return }
        if let into = merged.first(where: { $0.events.contains { $0.id == wasOpen.event.id } }) {
            selectedID = into.id
        } else {
            select(nil)
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if let onClose {
                    Button {
                        Haptics.light()
                        onClose()
                    } label: { chromeCircle("xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close the map")
                }
                Spacer(minLength: 8)
                pill
                Spacer(minLength: 8)
                Button { flyHome() } label: { chromeCircle("location") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Recenter map")
            }
            HStack {
                Spacer()
                MapCompass(heading: compass, reduceMotion: reduceMotion, onReset: resetNorth)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// The one pill: a read failed with nothing to show (tap to try again, as the Town bar's
    /// pill words it), or every one of today's events is over ("Nothing today" on a day with none).
    @ViewBuilder
    private var pill: some View {
        let _ = model.clockTick
        if townFeed.entries == nil && townFeed.failed || model.spotsFailed {
            Button {
                Haptics.light()
                model.readAgain()
            } label: {
                pillText(FeedStateCopy.offline)
                    .frame(height: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(FeedStateCopy.retryAction)
        } else if townFeed.entries != nil, model.today.dayIsOver(now: TodayBubbleClock.now()) {
            pillText(model.today.events.isEmpty ? "Nothing today" : "Nothing else today")
        }
    }

    private func pillText(_ words: String) -> some View {
        Text(words)
            .font(.sansSemibold(15))
            .foregroundStyle(Hue.ink.onLightCanvas)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .glassEffect(.regular, in: Capsule())
            .transition(.opacity)
    }

    /// A 44 pt glass circle with an ink glyph, the map's chrome.
    private func chromeCircle(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.sansMedium(16))
            .foregroundStyle(Hue.ink)
            .frame(width: 44, height: 44)
            .glassEffect(.regular, in: Circle())
    }

    // MARK: Actions

    /// Open a bubble's card and lift the bubble into the map above it; nil closes the card and
    /// lets the map settle level again.
    private func select(_ bubble: TodayBubble?) {
        let center = bubble?.coordinate ?? compass.center
        var camera = Viewport.camera(center: center, zoom: compass.zoom)
        if bubble != nil {
            Haptics.light()
            let photo = (mapSize.width - 2 * MapEventCard.sideInset) * 198.6 / 352.7
            camera.padding = EdgeInsets(top: 110, leading: 0,
                                        bottom: photo + 110 + MapEventCard.bottomInset, trailing: 0)
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
            selectedID = bubble?.id
            page = 0
        }
        if bubble != nil || selectedID == nil {
            if reduceMotion { viewport = camera } else { withViewportAnimation(.easeOut(duration: 0.45)) { viewport = camera } }
        }
    }

    private func open(_ item: FeedCardItem) {
        Haptics.light()
        path.append(item)
    }

    /// Back to the opening view over the Town, card closed.
    private func flyHome() {
        Haptics.light()
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) { selectedID = nil }
        let home = { viewport = .camera(center: MapSpots.center, zoom: Self.openZoom) }
        if reduceMotion { home() } else { withViewportAnimation(.fly(duration: 0.8)) { home() } }
    }

    /// The compass's tap: face north and level, in place.
    private func resetNorth() {
        Haptics.light()
        let level = { viewport = .camera(center: compass.center, zoom: compass.zoom, bearing: 0, pitch: 0) }
        if reduceMotion { level() } else { withViewportAnimation(.easeOut(duration: 0.4)) { level() } }
    }

    /// Tilt stops at 70°: past it the horizon smears. `setCameraBounds` throws, so the failure
    /// is logged rather than swallowed.
    private func clampPitch(_ map: MapboxMap?) {
        guard let map else { return }
        do {
            try map.setCameraBounds(with: CameraBoundsOptions(maxPitch: 70, minPitch: 0))
        } catch {
            print("[SJMapView] setCameraBounds(pitch 0–70) failed: \(error)")
        }
    }

    /// The wordmark hidden (Jesse's 2026-08-14 call). `visibility` isn't in the public
    /// initializer, so it's set on a copy.
    private static var hiddenLogoOptions: LogoViewOptions {
        var options = LogoViewOptions()
        options.visibility = .hidden
        return options
    }

    // MARK: DEBUG camera and card

    /// `-map-center <lat>,<lon>` and `-map-zoom <z>` start the camera elsewhere,
    /// `-map-bearing <deg>` and `-map-pitch <deg>` turned or tilted, for screenshots.
    private static func debugCenter() -> CLLocationCoordinate2D? {
        #if DEBUG
        let parts = (LaunchFlags.value(.mapCenter) ?? "").split(separator: ",").compactMap { Double($0) }
        if parts.count == 2 { return CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1]) }
        #endif
        return nil
    }

    private static func debugZoom() -> Double? { debugDouble(.mapZoom) }

    private static func debugDouble(_ flag: LaunchFlags.Flag) -> Double? {
        #if DEBUG
        return LaunchFlags.value(flag).flatMap(Double.init)
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// `-map-open-bubble <n>` opens the card of the nth bubble (0 the soonest) once there is
    /// one, for screenshots of the card.
    private func debugOpenBubble() {
        guard selectedID == nil, !Self.debugOpened,
              let n = LaunchFlags.value(.mapOpenBubble).flatMap(Int.init), shown.indices.contains(n) else { return }
        Self.debugOpened = true
        select(shown[n])
    }
    private static var debugOpened = false
    #endif
}
