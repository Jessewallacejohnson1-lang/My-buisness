//
//  SJMapView.swift
//  Hygge — Mapbox map of Saint Joseph, Minnesota.
//
//  Life360-clean visual system. DISCIPLINE: Hue.accent (coral) appears ONLY
//  on live indicators and primary tappable elements. Everything else is
//  surface (white), gray, grayLight, or mapInk.
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

/// The custom tab bar (drawn on top by MainTabsView) sits over the map's bottom
/// edge. Both the floating controls and the bottom card add this much clearance
/// so their primary actions never hide behind it.
private let TAB_BAR_CLEARANCE: CGFloat = 56

// MARK: - Main view

struct SJMapView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = MapModel()

    @State private var viewport: Viewport = .camera(
        center: MapSpots.center,
        zoom: 13.5,
        bearing: 0,
        pitch: 0
    )
    @State private var selectedSpot: Spot?
    @State private var quickAdding = false

    private var isAdmin: Bool {
        // DEBUG-only: `-force-nonadmin` launch arg forces the non-admin branch so
        // simulator verification can screenshot the gated map without a second
        // account. No effect in release builds or without the flag.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-force-nonadmin") { return false }
        #endif
        return Admin.isAdmin(auth.email)
    }

    /// Real events at this spot today — searches title AND location so an event
    /// like "Independence Day Parade" at location "Downtown" still matches.
    private func events(at spot: Spot) -> [TimelineEvent] {
        model.todayEvents.filter { ev in
            let haystack = [ev.title, ev.location].compactMap { $0 }.joined(separator: " ").lowercased()
            return spot.keywords.contains { haystack.contains($0) }
        }
    }

    /// Events that actually resolve to a pin (light a marker / open in a card).
    /// The header counts only these — an approved event at a venue not in the
    /// curated catalogue is real but shows nowhere on the map, so counting it in
    /// "N happening today" would overstate what the user can see or tap.
    private var mappedEventCount: Int {
        model.todayEvents.filter { ev in
            let haystack = [ev.title, ev.location].compactMap { $0 }.joined(separator: " ").lowercased()
            return MapSpots.all.contains { $0.keywords.contains { haystack.contains($0) } }
        }.count
    }

    /// A spot glows only while one of its events is actually happening.
    private func isLive(_ spot: Spot) -> Bool {
        events(at: spot).contains { DateHelpers.isLiveNow($0.startTime) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            topHeader
            floatingControls
            bottomCardLayer
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
    }

    // MARK: Map

    private var mapLayer: some View {
        MapReader { proxy in
            Map(viewport: $viewport) {
                annotations
            }
            .mapStyle(MapStyle(uri: StyleURI(rawValue: MAP_STYLE_URL)!))
            .onStyleLoaded { _ in
                guard let map = proxy.map else { return }
                // Water — blue
                try? map.setLayerProperty(for: "water",          property: "fill-color", value: "#4A90D9")
                try? map.setLayerProperty(for: "waterway",       property: "line-color", value: "#4A90D9")
                // Grass / parks — green
                for id in ["landuse", "national-park", "landcover", "park"] {
                    try? map.setLayerProperty(for: id, property: "fill-color", value: "#7AB870")
                }
                // Buildings — grey
                try? map.setLayerProperty(for: "building",       property: "fill-color",         value: "#B8B8B8")
                try? map.setLayerProperty(for: "building",       property: "fill-outline-color",  value: "#B8B8B8")
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Spot + liveness snapshot. The id changes when liveness flips so ForEvery
    /// rebuilds the annotation view — Mapbox doesn't re-render an annotation
    /// whose element identity is unchanged, which left stale badges after
    /// today's events loaded (or a Realtime change flipped a spot live).
    private struct PinState: Identifiable {
        let spot: Spot
        let live: Bool
        var id: String { "\(spot.id)-\(live)" }
    }

    @MapContentBuilder
    private var annotations: some MapContent {
        // A tap on the open map (not a pin, not a pan) dismisses the card.
        // Fires only when no annotation/layer handled the tap.
        TapInteraction { _ in
            closeCard()
            return true
        }

        ForEvery(MapSpots.all.map { PinState(spot: $0, live: isLive($0)) }) { state in
            MapViewAnnotation(coordinate: state.spot.coordinate) {
                MapPinBadge(spot: state.spot, live: state.live,
                            selected: selectedSpot?.id == state.spot.id,
                            a11yLabel: accessibilityLabel(for: state.spot, live: state.live))
                    .onTapGesture { selectSpot(state.spot) }
            }
            // Six curated pins — never cull; culling hid downtown (and its live
            // glow) behind the nearby chapel pin.
            .allowOverlap(true)
        }
    }

    // MARK: Header — title + honest today status

    private var topHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Saint Joseph")
                .font(.displaySemi(20))
                .foregroundStyle(Hue.mapInk)
            MapStatusLine(state: model.state,
                          count: mappedEventCount,
                          onRetry: { model.retry() })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Hue.mapHairline).frame(height: 1), alignment: .bottom)
    }

    // MARK: Floating controls — admin "+" stacked above recenter, bottom-right

    private var floatingControls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    if isAdmin { quickAddButton }
                    recenterButton
                }
                .padding(.trailing, 16)
            }
            // Clear the custom tab bar plus a gap, so both stacked controls sit
            // fully above it.
            .padding(.bottom, TAB_BAR_CLEARANCE + 20)
        }
    }

    private var quickAddButton: some View {
        Button {
            Haptics.light()
            quickAdding = true
        } label: {
            chromeCircle(icon: "plus")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add an event")
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

    /// The shared chrome bubble — 44px white circle, hairline, ink line icon.
    private func chromeCircle(icon: String) -> some View {
        Circle()
            .fill(Hue.surface)
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(Hue.mapHairline, lineWidth: 1))
            .mapFloatShadow()
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Hue.mapInk)
            )
    }

    // MARK: Bottom card

    private var bottomCardLayer: some View {
        VStack {
            Spacer()
            if let spot = selectedSpot {
                MapBottomCard(spot: spot, happenings: events(at: spot)) {
                    closeCard()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selectedSpot?.id)
    }

    // MARK: Actions

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

// MARK: - Today status line (loading / count / quiet / error / offline)

private struct MapStatusLine: View {
    let state: MapModel.LoadState
    let count: Int
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .loading:
            SkeletonBar()
        case .loaded, .empty:
            // Count only events that resolve to a spot; when none map, it's a
            // quiet day even if unlisted-venue events exist. Numbers are mono.
            if count > 0 {
                Text("\(count) happening today")
                    .font(.mono(13))
                    .foregroundStyle(Hue.gray)
                    .monospacedDigit()
            } else {
                Text("A quiet day — nothing on the map yet")
                    .font(.sans(13))
                    .foregroundStyle(Hue.grayLight)
            }
        case .offline:
            // Recoverable without backgrounding the app — offer the same retry
            // affordance as the error state.
            Button(action: onRetry) {
                HStack(spacing: 5) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 11, weight: .medium))
                    Text("Offline — tap to retry")
                }
                .font(.sans(13))
                .foregroundStyle(Hue.grayLight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Offline. Tap to retry")
        case .error:
            Button(action: onRetry) {
                HStack(spacing: 5) {
                    Text("Couldn't load today")
                    Text("Retry").foregroundStyle(Hue.accent)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Hue.accent)
                }
                .font(.sans(13))
                .foregroundStyle(Hue.gray)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Couldn't load today. Retry")
        }
    }
}

/// A calm loading skeleton — a soft bar with a slow highlight sweep, never a
/// spinner on white. Static under Reduce Motion.
private struct SkeletonBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        Capsule()
            .fill(Hue.mapHairline)
            .frame(width: 128, height: 11)
            .overlay(
                GeometryReader { geo in
                    if !reduceMotion {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [.clear, Hue.surface.opacity(0.85), .clear],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * 0.55)
                            .offset(x: phase * geo.size.width)
                    }
                }
            )
            .clipShape(Capsule())
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    phase = 1.25
                }
            }
            .accessibilityLabel("Loading today's happenings")
    }
}

// MARK: - Live pulse ring
//
// Self-contained — @State is local so the animation loop never propagates
// updates to sibling pins or the parent map. Core Animation renders each frame
// off the main thread. Coral, opacity 0.35 → 0, scale 1 → 2.2, 1.5 s loop.
// Static under Reduce Motion (no pulse; the badge dot still marks "live").

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
// Live:     2px accent border, accent icon, 10px accent dot badge top-right
//           with 2px white ring. Pulse ring: coral 0.35→0, scale 1→2.2, 1.5s.
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

// MARK: - Accent pill button style

private struct AccentPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Hue.accentPressed : Hue.accent,
                in: Capsule()
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Bottom card
//
// White sheet, top-only 20pt radius, sheet shadow (upward), grabber pill.
// Spot name (title 20 semibold mapInk) + one-line blurb (caption grayLight).
// Happenings: accent dot • name (15 medium) left, time (13 gray) right, 13pt gap.
// Directions pill: full-width 50pt height, accent fill, accentPressed on tap.

private struct MapBottomCard: View {
    let spot: Spot
    let happenings: [TimelineEvent]
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    /// VoiceOver text for a happening row — includes "happening now" when live.
    private static func happeningLabel(_ h: TimelineEvent) -> String {
        let base = "\(h.title), \(h.startTime ?? "all day")"
        return DateHelpers.isLiveNow(h.startTime) ? base + ", happening now" : base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Capsule()
                    .fill(Hue.mapHairline)
                    .frame(width: 36, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(spot.name)
                    .font(.displaySemi(20))
                    .foregroundStyle(Hue.mapInk)
                    .lineLimit(1)

                if let blurb = spot.blurb {
                    Text(blurb)
                        .font(.sans(13))
                        .foregroundStyle(Hue.grayLight)
                        .lineLimit(1)
                }
            }
            .padding(.top, 16)

            // Today's happenings — real events only; accent dot only while live.
            if !happenings.isEmpty {
                VStack(spacing: 13) {
                    ForEach(happenings) { h in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(DateHelpers.isLiveNow(h.startTime) ? Hue.accent : Hue.grayLight)
                                .frame(width: 6, height: 6)
                            Text(h.title)
                                .font(.sansMedium(15))
                                .foregroundStyle(Hue.mapInk)
                                .lineLimit(1)
                            Spacer()
                            Text(h.startTime ?? "all day")
                                .font(.sans(13))
                                .foregroundStyle(Hue.gray)
                        }
                        // Live state is a coral dot for sighted users; spell it
                        // out for VoiceOver so it isn't color-only (WCAG 1.4.1).
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Self.happeningLabel(h))
                    }
                }
                .padding(.top, 16)
            }

            Button {
                let lat = spot.coordinate.latitude
                let lon = spot.coordinate.longitude
                if let url = URL(string: "maps://?daddr=\(lat),\(lon)&dirflg=d") {
                    openURL(url)
                }
            } label: {
                Text("Directions")
                    .font(.sansSemibold(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(AccentPillStyle())
            .padding(.top, 20)
            // Lift the primary action above the tab bar; the card background still
            // bleeds to the bottom edge behind it.
            .padding(.bottom, TAB_BAR_CLEARANCE + 20)
            .accessibilityLabel("Directions to \(spot.name)")
        }
        .padding(.horizontal, 20)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: Radius.xl,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: Radius.xl,
                style: .continuous
            )
            .fill(Hue.surface)
            .ignoresSafeArea(edges: .bottom)
            .mapSheetShadow()
        }
    }
}
