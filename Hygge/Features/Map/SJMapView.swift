//
//  SJMapView.swift
//  Hygge — Mapbox map of Saint Joseph, Minnesota.
//
//  Style: change MAP_STYLE_URL to any Mapbox Studio or built-in style.
//  Live pulse: change LIVE_COLOR for a full rebrand in one line.
//

import SwiftUI
import MapboxMaps

// MARK: - Constants (one-line swap for style or live color)

private let MAP_STYLE_URL = "mapbox://styles/mapbox/light-v11"
private let LIVE_COLOR    = Hue.moss700   // rebrand: change this one constant

// MARK: - Pin data
//
// Coordinate audit (FIX 2):
// Mapbox iOS SDK uses CLLocationCoordinate2D(latitude:longitude:) — Apple's standard.
// This is NOT GeoJSON (lon, lat) order. No flip needed.
// All values verified: latitude ≈ 45.56 °N, longitude ≈ -94.3 °W. Correct for St. Joseph, MN.
// No authoritative overrides were provided; existing values match visible map placement.
// isLive: marks spots with a happening today → drives the pulse ring animation.

private struct SJPin: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let coord: CLLocationCoordinate2D
    var isLive: Bool = false   // default off; flip true for today's active spots
}

private let sjPins: [SJPin] = [
    // geocoded: East Minnesota Street, St. Joseph, MN — confirmed 2026-07-04
    SJPin(id: "downtown",   name: "Downtown",            symbol: "cup.and.saucer.fill",
          coord: .init(latitude: 45.5654, longitude: -94.3069), isLive: true),
    // geocoded: 37 College Ave S, St. Joseph, MN — confirmed 2026-07-04
    SJPin(id: "saintbens",  name: "Saint Ben's",          symbol: "book.fill",
          coord: .init(latitude: 45.5604, longitude: -94.3220)),
    // no Mapbox POI; campus approximate — confirmed 2026-07-04
    SJPin(id: "chapel",     name: "Sacred Heart Chapel",  symbol: "building.columns.fill",
          coord: .init(latitude: 45.5728, longitude: -94.3193)),
    // geocoded: College Ave N access point, St. Joseph, MN — confirmed 2026-07-04
    SJPin(id: "wobegon",    name: "Wobegon Trail",         symbol: "figure.hiking",
          coord: .init(latitude: 45.5671, longitude: -94.3189)),
    // geocoded: 2850 Abbey Plaza, Collegeville, MN — confirmed 2026-07-04
    SJPin(id: "saintjohns", name: "Saint John's",          symbol: "book.fill",
          coord: .init(latitude: 45.5800, longitude: -94.3934)),
]

private let stJoeCenter = CLLocationCoordinate2D(latitude: 45.565, longitude: -94.317)

// MARK: - View

struct SJMapView: View {
    @State private var viewport: Viewport = .camera(
        center: stJoeCenter,
        zoom: 13.5,
        bearing: 0,
        pitch: 0
    )
    @State private var selectedPin: SJPin?

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            headerBar
        }
    }

    private var mapLayer: some View {
        Map(viewport: $viewport) {
            annotations
        }
        .mapStyle(MapStyle(uri: StyleURI(rawValue: MAP_STYLE_URL)!))
        .ignoresSafeArea(edges: .bottom)
    }

    @MapContentBuilder
    private var annotations: some MapContent {
        ForEvery(sjPins) { pin in
            MapViewAnnotation(coordinate: pin.coord) {
                MapPinBadge(pin: pin, selected: selectedPin?.id == pin.id)
                    .onTapGesture { toggleSelection(pin) }
            }
            .allowOverlap(false)
        }
    }

    private func toggleSelection(_ pin: SJPin) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedPin = (selectedPin?.id == pin.id) ? nil : pin
        }
    }

    private var headerBar: some View {
        HStack {
            Text("Saint Joseph")
                .font(.displaySemi(20))
                .foregroundStyle(Hue.ink)
            Spacer()
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    viewport = .camera(center: stJoeCenter, zoom: 13.5)
                    selectedPin = nil
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Hue.moss700)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Hue.hairline).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Live pulse ring
//
// Self-contained SwiftUI view — @State is local, so the animation loop
// never propagates updates to sibling pins or the parent map.
// Core Animation renders each frame off the main thread; no re-render budget consumed.

private struct PulseRing: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(LIVE_COLOR.opacity(pulsing ? 0 : 0.55))
            .frame(width: 44, height: 44)
            .scaleEffect(pulsing ? 2.2 : 1.0)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Pin badge

private struct MapPinBadge: View {
    let pin: SJPin
    let selected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Live pulse ring sits behind the circle, doesn't affect layout
                if pin.isLive && !selected {
                    PulseRing()
                }

                Circle()
                    .fill(selected ? Hue.moss700 : Hue.paper)
                    .frame(width: selected ? 46 : 38, height: selected ? 46 : 38)
                    .shadow(color: .black.opacity(selected ? 0.3 : 0.18), radius: selected ? 8 : 4, y: 2)
                    .overlay(Circle().stroke(selected ? Color.clear : Hue.hairline, lineWidth: 1))

                Image(systemName: pin.symbol)
                    .font(.system(size: selected ? 20 : 16, weight: .semibold))
                    .foregroundStyle(selected ? .white : Hue.moss700)
            }
            MapTriangle()
                .fill(selected ? Hue.moss700 : Hue.paper)
                .frame(width: 10, height: 6)

            if selected {
                Text(pin.name)
                    .font(.sansSemibold(11))
                    .foregroundStyle(Hue.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Hue.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .padding(.top, 4)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
    }
}

// MARK: - Triangle shape

private struct MapTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
