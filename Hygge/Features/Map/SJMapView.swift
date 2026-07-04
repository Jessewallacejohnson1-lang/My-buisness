//
//  SJMapView.swift
//  Hygge — Mapbox map of Saint Joseph, Minnesota.
//
//  Life360-clean visual system. DISCIPLINE: Hue.accent (coral) appears ONLY
//  on live indicators and primary tappable elements. Everything else is
//  surface (white), gray, grayLight, or mapInk.
//
//  One-line rebrand: change LIVE_COLOR below.
//

import SwiftUI
import MapboxMaps

// MARK: - Constants

private let MAP_STYLE_URL = "mapbox://styles/mapbox/light-v11"
private let LIVE_COLOR    = Hue.accent   // warm coral — change here to rebrand

// MARK: - Pin category → SF Symbol
//
// Icon mapping table (Lucide analogue → SF Symbol):
//   trail    → TreePine        → figure.hiking
//   park     → Trees           → tree
//   downtown → Store           → storefront
//   coffee   → Coffee          → cup.and.saucer
//   fitness  → Dumbbell        → dumbbell
//   college  → GraduationCap   → graduationcap
//   chapel   → Building        → building.columns
//   default  → MapPin          → mappin

private enum PinCategory {
    case trail, park, downtown, coffee, fitness, college, chapel, `default`

    var symbol: String {
        switch self {
        case .trail:    return "figure.hiking"
        case .park:     return "tree"
        case .downtown: return "storefront"
        case .coffee:   return "cup.and.saucer"
        case .fitness:  return "dumbbell"
        case .college:  return "graduationcap"
        case .chapel:   return "building.columns"
        case .default:  return "mappin"
        }
    }
}

// MARK: - Data types

private struct SJPin: Identifiable {
    let id: String
    let name: String
    let category: PinCategory
    let coord: CLLocationCoordinate2D
    /// lowercase keywords matched against real events' location strings
    let kw: [String]
    var description: String? = nil
}

// MARK: - Pin data
//
// Coordinates: CLLocationCoordinate2D(latitude:longitude:) — Apple/Mapbox standard.
// NOT GeoJSON order. Verified 2026-07-04 against OpenStreetMap building
// footprints + published street addresses (Mapbox geocoding had put Downtown
// ~900 m east and the chapel ~1 km north — see MAP_BUILD_LOG.md FIX 5).
//
// isLive and "today's happenings" are NEVER hardcoded here — they come from
// real events (CommunityAPI.getTodayEvents) matched to a pin by keyword, and
// a pin only glows while an event is actually happening (start ≤ now ≤ +2 h).

private let sjPins: [SJPin] = [
    SJPin(
        id: "downtown",
        name: "Downtown",
        category: .downtown,
        coord: .init(latitude: 45.5648, longitude: -94.3183), // Minnesota St W at College Ave (The Local Blend block)
        kw: ["downtown", "minnesota st", "local blend", "krewe", "bad habit", "college ave", "church of st"],
        description: "Shops & cafés on Minnesota St"
    ),
    SJPin(
        id: "saintbens",
        name: "Saint Ben's",
        category: .college,
        coord: .init(latitude: 45.5604, longitude: -94.3218), // Gorecki Center, CSB campus
        kw: ["saint ben", "st. ben", "st ben", "csb", "benedict", "gorecki"],
        description: "College of Saint Benedict"
    ),
    SJPin(
        id: "chapel",
        name: "Sacred Heart Chapel",
        category: .chapel,
        coord: .init(latitude: 45.5631, longitude: -94.3189), // the chapel building itself (OSM footprint)
        kw: ["chapel", "sacred heart", "monastery"],
        description: "The monastery & its dome"
    ),
    SJPin(
        id: "wobegon",
        name: "Wobegon Trail",
        category: .trail,
        coord: .init(latitude: 45.5665, longitude: -94.3161), // trailhead park, 605 1st Ave NE (water tower)
        kw: ["wobegon", "trailhead"],
        description: "Bike, walk & run the trail"
    ),
    SJPin(
        id: "millstream",
        name: "Millstream Park",
        category: .park,
        coord: .init(latitude: 45.5701, longitude: -94.3287), // 725 CR-75 W, NW edge of town
        kw: ["millstream"],
        description: "Shelter, disc golf & the stream"
    ),
    SJPin(
        id: "saintjohns",
        name: "Saint John's",
        category: .college,
        coord: .init(latitude: 45.5800, longitude: -94.3923), // Abbey church, Collegeville
        kw: ["saint john", "st. john", "st john", "sju", "abbey", "collegeville"],
        description: "The Abbey in Collegeville"
    ),
]

private let stJoeCenter = CLLocationCoordinate2D(latitude: 45.565, longitude: -94.317)

// MARK: - Main view

struct SJMapView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var viewport: Viewport = .camera(
        center: stJoeCenter,
        zoom: 13.5,
        bearing: 0,
        pitch: 0
    )
    @State private var selectedPin: SJPin?
    @State private var todayEvents: [TimelineEvent] = []

    private var api: CommunityAPI { CommunityAPI(auth: auth) }

    /// Real events at this pin today — searches title AND location so an event
    /// like "Independence Day Parade" at location "Downtown" (or nil) still matches.
    private func events(at pin: SJPin) -> [TimelineEvent] {
        todayEvents.filter { ev in
            let haystack = [ev.title, ev.location].compactMap { $0 }.joined(separator: " ").lowercased()
            return pin.kw.contains { haystack.contains($0) }
        }
    }

    /// A pin glows only while one of its events is actually happening.
    private func isLive(_ pin: SJPin) -> Bool {
        events(at: pin).contains { DateHelpers.isLiveNow($0.startTime) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            topHeader

            // Recenter button — fixed 16pt above safe-area bottom (tab bar), right edge
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    recenterButton.padding(.trailing, 16)
                }
                .padding(.bottom, 16)
            }

            // Bottom card — slides up from bottom edge
            VStack {
                Spacer()
                if let pin = selectedPin {
                    MapBottomCard(pin: pin, happenings: events(at: pin)) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            selectedPin = nil
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selectedPin?.id)
        }
        .task {
            todayEvents = (try? await api.getTodayEvents()) ?? []
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
                try? map.setLayerProperty(for: "water",    property: "fill-color", value: "#B0CAE0")
                try? map.setLayerProperty(for: "park",     property: "fill-color", value: "#BACFB5")
                try? map.setLayerProperty(for: "building", property: "fill-color", value: "#C8C8C8")
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Pin + liveness snapshot. The id changes when liveness flips so ForEvery
    /// rebuilds the annotation view — Mapbox doesn't re-render an annotation
    /// whose element identity is unchanged, which left stale non-live badges
    /// after today's events finished loading.
    private struct PinState: Identifiable {
        let pin: SJPin
        let live: Bool
        var id: String { "\(pin.id)-\(live)" }
    }

    @MapContentBuilder
    private var annotations: some MapContent {
        ForEvery(sjPins.map { PinState(pin: $0, live: isLive($0)) }) { state in
            MapViewAnnotation(coordinate: state.pin.coord) {
                MapPinBadge(pin: state.pin, live: state.live, selected: selectedPin?.id == state.pin.id)
                    .onTapGesture { selectPin(state.pin) }
            }
            // Six curated pins — never cull; culling was hiding downtown
            // (and its live glow) behind the nearby chapel pin.
            .allowOverlap(true)
        }
    }

    // MARK: Header — title only; recenter moved to floating button

    private var topHeader: some View {
        HStack {
            Text("Saint Joseph")
                .font(.displaySemi(20))
                .foregroundStyle(Hue.mapInk)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Hue.mapHairline).frame(height: 1), alignment: .bottom)
    }

    // MARK: Recenter — 44px white pill, ink location icon

    private var recenterButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                viewport = .camera(center: stJoeCenter, zoom: 13.5)
                selectedPin = nil
            }
        } label: {
            Circle()
                .fill(Hue.surface)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Hue.mapHairline, lineWidth: 1))
                .mapFloatShadow()
                .overlay(
                    Image(systemName: "location")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Hue.mapInk)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func selectPin(_ pin: SJPin) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            selectedPin = (selectedPin?.id == pin.id) ? nil : pin
        }
    }
}

// MARK: - Live pulse ring
//
// Self-contained — @State is local so the animation loop never propagates
// updates to sibling pins or the parent map. Core Animation renders each
// frame off the main thread; no SwiftUI re-render budget consumed.
// Coral, opacity 0.35 → 0, scale 1 → 2.2, 1.5 s loop.

private struct PulseRing: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(LIVE_COLOR.opacity(pulsing ? 0 : 0.35))
            .frame(width: 44, height: 44)
            .scaleEffect(pulsing ? 2.2 : 1.0)
            .onAppear {
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
// No pointer tail — anchor is at bubble center over the coordinate.

private struct MapPinBadge: View {
    let pin: SJPin
    let live: Bool
    let selected: Bool

    var body: some View {
        ZStack {
            // Pulse ring behind bubble — live only, hidden when selected
            if live && !selected {
                PulseRing()
            }

            // Bubble
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

            // Icon — line weight, no fill, ink or accent when live
            Image(systemName: pin.category.symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(live ? LIVE_COLOR : Hue.mapInk)

            // Live badge dot — top-right corner of 44px circle
            // Offset: (44/2 − 10/2) = 17pt from center → edge of circle
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
// Spot name (title 20 semibold mapInk) + one-line description (caption grayLight).
// Happenings: accent dot • name (15 medium) left, time (13 gray) right, 13pt gap.
// Directions pill: full-width 50pt height, accent fill, accentPressed on tap.

private struct MapBottomCard: View {
    let pin: SJPin
    let happenings: [TimelineEvent]
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Grabber pill — 36×4, centered, 8pt from top
            HStack {
                Capsule()
                    .fill(Hue.mapHairline)
                    .frame(width: 36, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            // Name + description
            VStack(alignment: .leading, spacing: 3) {
                Text(pin.name)
                    .font(.displaySemi(20))
                    .foregroundStyle(Hue.mapInk)
                    .lineLimit(1)

                if let desc = pin.description {
                    Text(desc)
                        .font(.sans(13))
                        .foregroundStyle(Hue.grayLight)
                        .lineLimit(1)
                }
            }
            .padding(.top, 16)

            // Today's happenings — real events only; accent dot only while live
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
                    }
                }
                .padding(.top, 16)
            }

            // Directions — full-width accent pill, 50pt height
            Button {
                let lat = pin.coord.latitude
                let lon = pin.coord.longitude
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
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
        .background {
            // Background extends behind home indicator; content stays above it.
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
